#!/usr/bin/env bash
# Sentiment rApp — one-command operator launcher.
#
#   ./run.sh             # install if needed + start (foreground tail)
#   ./run.sh --stop      # stop the running node
#   ./run.sh --status    # is it up? what's bound? what's the chain saying?
#   ./run.sh --logs      # tail the log
#   ./run.sh --clean     # wipe local state (data/, aci/, snapshot/) then restart
#
# Re-running ./run.sh is safe: keystore, config, and chain data are preserved.

set -euo pipefail

# ── Constants (release pinning) ──────────────────────────────────────────────
RAPP_VERSION="v0.1.4-testnet"
JAR_URL="https://github.com/Give-Sentiment/sentiment-rapp-releases/releases/download/${RAPP_VERSION}/sentiment-reality-assembly-0.1.0-SNAPSHOT.jar"
JAR_SHA256="9005c5e23991a756c172cdc7567ef27a6cd6f4d42f9fc4e6a562dbd66e6e3b29"

# Sentiment chain (testnet) — where your operator node syncs from.
CHAIN_HOST="46.101.82.227"
CHAIN_L0_PORT=9000
CHAIN_L1_PORT=9010
GENESIS_L0_PEER_ID="c754a46b9c4b3317bfccbe5faf0999005933d3ac1236a02233b531033dec26604d35b12d78a7facb657325ab8f098f47804812a70052f16912660db5870f3cfe"
GENESIS_L1_PEER_ID="f47b97b438e4d65286fea06c617592e51d0ce69e9962ffa787235fc4ab370b272aded409d805042982e2fb2b15def667ab59e3c071041759193e116c8ac5b828"

# Shared response-encryption pubkey (your node encrypts; only Sentiment can decrypt).
SENTIMENT_PUBLIC_KEY="MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArXcT7Wr3pv8re1UErPI9q2ZuDs6h87Qj98M1Q3Q2FFna1xnFlOpEyMPROYPxGh5INYfV25vk3ffSOl7coNC3OlPDwCz0fcw9P7dy/2enOFT/A7X8g2LilcBPkl6D+reEga3iex64JfVRCyq6wrTxKyPbegvRHFn9xS2Yg+U2e/9nQ+LksY0d2je0WVTnmda1gF3HUTQqZFSoAYdIJpmkyHvaoST+q8RtR24q8vPXJznAn6geZFPljVfooBVDki/O1RZ3SsyIlRbUFL2st7gcjjA4E8Zs6l7b68Q2ddJTXsnyYFG2eWwaGrYsGipXyqBjqFKDoT1P+ZQ3SGip5FpNTwIDAQAB"

# Reality testnet libp2p relay — used to receive inbound when behind NAT.
LIBP2P_RELAY="/ip4/143.110.227.9/tcp/9003/p2p/16Uiu2HAmCRkapTKsQqC1kTPVSEKLNqtiCsumUnf3CAbVuJjGoQB6"

# Local port layout (operator binds 9000-9012 on its own machine).
L0_PUBLIC=9000; L0_P2P=9001; L0_CLI=9002
L1_PUBLIC=9010; L1_P2P=9011; L1_CLI=9012

# ── Paths ────────────────────────────────────────────────────────────────────
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="$WORKDIR/sentiment-reality.jar"
KEYSTORE="$WORKDIR/operator.p12"
CONFIG_ENV="$WORKDIR/config.env"
LOG_FILE="$WORKDIR/sentiment.log"
PID_FILE="$WORKDIR/sentiment.pid"

cd "$WORKDIR"

# ── UI helpers ───────────────────────────────────────────────────────────────
c_dim()  { printf '\033[2m%s\033[0m' "$1"; }
c_blue() { printf '\033[36m%s\033[0m' "$1"; }
c_green(){ printf '\033[32m%s\033[0m' "$1"; }
c_red()  { printf '\033[31m%s\033[0m' "$1"; }
c_yellow(){ printf '\033[33m%s\033[0m' "$1"; }
log()    { printf '%s %s\n' "$(c_blue '◆')" "$1"; }
ok()     { printf '%s %s\n' "$(c_green '✓')" "$1"; }
warn()   { printf '%s %s\n' "$(c_yellow '!')" "$1" >&2; }
die()    { printf '%s %s\n' "$(c_red '✗')" "$1" >&2; exit 1; }

# ── Java check ───────────────────────────────────────────────────────────────
require_java() {
    if ! command -v java >/dev/null 2>&1; then
        die "Java not found. Install Java 17 first:
   macOS:  brew install openjdk@17
   Ubuntu: sudo apt-get install -y openjdk-17-jdk
   Other:  https://adoptium.net/temurin/releases/?version=17"
    fi
    local v
    v=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    case "$v" in
      17*|18*|19*|2[0-9]*) ok "Java $v" ;;
      *) warn "Java $v detected — recommended Java 17+. Continuing." ;;
    esac
}

# ── SHA-256 helper (portable mac+linux) ──────────────────────────────────────
sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

# ── JAR download (idempotent) ────────────────────────────────────────────────
ensure_jar() {
    if [ -f "$JAR" ] && [ "$(sha256 "$JAR")" = "$JAR_SHA256" ]; then
        ok "JAR present and verified"
        return
    fi
    log "Downloading rApp $RAPP_VERSION (~166 MB)…"
    curl -fL --progress-bar -o "$JAR" "$JAR_URL" || die "Download failed"
    local got
    got=$(sha256 "$JAR")
    if [ "$got" != "$JAR_SHA256" ]; then
        rm -f "$JAR"
        die "SHA-256 mismatch.
  expected: $JAR_SHA256
  got:      $got"
    fi
    ok "Downloaded + verified"
}

# ── Keystore (idempotent) ────────────────────────────────────────────────────
ensure_keystore() {
    if [ -f "$KEYSTORE" ]; then
        ok "Operator keystore present"
        return
    fi
    log "Generating operator keystore…"
    CL_KEYSTORE="$KEYSTORE" CL_KEYALIAS=alias CL_PASSWORD=password \
        java -cp "$JAR" org.reality.keytool.Main generate >/dev/null
    chmod 600 "$KEYSTORE"
    ok "Operator keystore generated → $KEYSTORE"
    warn "This keystore is your node identity. Back it up if you intend to keep this node long-running."
}

# ── config.env (idempotent — only write if missing) ──────────────────────────
ensure_config() {
    if [ -f "$CONFIG_ENV" ]; then
        ok "config.env present (delete to regenerate)"
        return
    fi
    log "Writing config.env with defaults…"
    cat > "$CONFIG_ENV" <<EOF
# Sentiment rApp operator config — generated by run.sh.
# Safe defaults for a single-machine tester behind NAT.

# Node identity — your keystore is the source of truth.
NODE_TYPE=validator
APP_IDENTIFIER=sentiment-reality
L0_KEYSTORE=$KEYSTORE
L1_KEYSTORE=$KEYSTORE

# Response encryption pubkey (responses your node receives are encrypted with this).
SENTIMENT_PUBLIC_KEY=$SENTIMENT_PUBLIC_KEY

# Your advertised IP. 127.0.0.1 is correct for a NAT'd home machine — libp2p
# routes return traffic via the relay. If you have a public IP and want
# direct HTTP peer dialing, set this to that IP and ensure the cluster ports
# (9000-9012) are reachable.
ADVERTISED_IP=127.0.0.1

# Sentiment chain bootstrap. These point at the testnet writer.
L0_INITIAL_HOST=$CHAIN_HOST
L0_INITIAL_PUBLIC_PORT=$CHAIN_L0_PORT
L1_INITIAL_HOST=$CHAIN_HOST
L1_INITIAL_PUBLIC_PORT=$CHAIN_L1_PORT
GENESIS_ID=$GENESIS_L0_PEER_ID
L1_GENESIS_ID=$GENESIS_L1_PEER_ID

# libp2p relay for NAT traversal.
LIBP2P_RELAY_ADDRESSES=$LIBP2P_RELAY

# Reality NET L0 anchoring — uncomment ONLY after a fresh DeployAppTransaction
# is observed live on NET L0 (operators receive this signal out-of-band).
# Leaving these commented keeps the node working as a Sentiment-chain validator.
# SENTIMENT_RAPP_ADDRESS=...
# NET_L0_HOST=128.199.67.191
# NET_L0_PUBLIC_PORT=9000
# NET_L0_PEER_ID=22222208770d62f27e8cd5b927f9c743ae0acda57f77532bf82be73ed36a59c74240c122dbb725216310f77ade4567d54f2a0361941e27e69571f74cfed326ca
EOF
    chmod 600 "$CONFIG_ENV"
    ok "config.env written → $CONFIG_ENV"
}

# ── State management ────────────────────────────────────────────────────────
wipe_state() {
    log "Wiping local chain state (data/, aci/, snapshot/, *.log)…"
    rm -rf data data-validator-1 data-validator-2 aci aci-validator-1 aci-validator-2 org logs snapshot
    rm -f "$LOG_FILE"
    ok "Wiped"
}

# ── Stop ─────────────────────────────────────────────────────────────────────
stop_node() {
    local stopped=0
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping node (PID $pid)…"
            kill -TERM "$pid" 2>/dev/null || true
            for _ in $(seq 1 10); do
                if ! kill -0 "$pid" 2>/dev/null; then stopped=1; break; fi
                sleep 1
            done
            if [ "$stopped" = 0 ]; then
                warn "Node still running after SIGTERM — sending SIGKILL"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    # Belt-and-suspenders: kill any orphaned JVMs running our JAR.
    pkill -f "sentiment-reality-assembly-0.1.0" 2>/dev/null || true
    ok "Node stopped"
}

# ── Status ──────────────────────────────────────────────────────────────────
show_status() {
    local up=0
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then up=1; fi
    if [ "$up" = 1 ]; then
        echo "Process : $(c_green "running") (PID $(cat "$PID_FILE"))"
    else
        echo "Process : $(c_red "not running")"
    fi
    local probe_state
    probe_state=$(curl -s --max-time 2 "http://127.0.0.1:$L0_PUBLIC/node/info" 2>/dev/null | grep -oE '"state":"[^"]+"' || true)
    echo "L0 :$L0_PUBLIC  : ${probe_state:-no response}"
    probe_state=$(curl -s --max-time 2 "http://127.0.0.1:$L1_PUBLIC/node/info" 2>/dev/null | grep -oE '"state":"[^"]+"' || true)
    echo "L1 :$L1_PUBLIC : ${probe_state:-no response}"
    if [ "$up" = 1 ]; then
        echo "Open    : $(c_blue "http://127.0.0.1:$L1_PUBLIC")"
    fi
}

# ── Launch ──────────────────────────────────────────────────────────────────
launch_node() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Node already running (PID $(cat "$PID_FILE")). Use --stop or --status."
        exit 0
    fi

    # shellcheck disable=SC1090
    set -a; source "$CONFIG_ENV"; set +a

    log "Starting Sentiment rApp node…"

    nohup java --enable-native-access=ALL-UNNAMED \
        -Dtransport.libp2p.relay.addresses="$LIBP2P_RELAY_ADDRESSES" \
        -Djava.net.preferIPv4Stack=true \
        -jar "$JAR" \
        --l0--command run-validator \
        --l0--env dev \
        --l0--requires-libp2p \
        --l0--keyalias alias --l0--password password \
        --l0--keystore "$L0_KEYSTORE" \
        --l0--ip "$ADVERTISED_IP" \
        --l0--public-port "$L0_PUBLIC" --l0--p2p-port "$L0_P2P" --l0--cli-port "$L0_CLI" \
        --l0--peer-id "$GENESIS_ID" \
        --l0--l0-ip "$ADVERTISED_IP" \
        --l0--startup-port "$L0_PUBLIC" --l0--collateral 0 \
        --l1--command run-validator \
        --l1--env dev \
        --l1--requires-libp2p \
        --l1--keyalias alias --l1--password password \
        --l1--keystore "$L1_KEYSTORE" \
        --l1--ip "$ADVERTISED_IP" \
        --l1--public-port "$L1_PUBLIC" --l1--p2p-port "$L1_P2P" --l1--cli-port "$L1_CLI" \
        --l1--l0-peer-id "$GENESIS_ID" \
        --l1--l0-peer-host "$L0_INITIAL_HOST" \
        --l1--l0-peer-port "$L0_INITIAL_PUBLIC_PORT" \
        --l1--collateral 0 --l1--aci-db-path aci \
        > "$LOG_FILE" 2>&1 &

    local pid=$!
    echo $pid > "$PID_FILE"
    log "PID $pid"
    log "Log:  $LOG_FILE"

    # Poll for HTTP server bind (max ~90s)
    log "Waiting for L0 + L1 HTTP servers to bind…"
    local timeout=90 elapsed=0 all_up=0
    while [ $elapsed -lt $timeout ]; do
        if (echo > "/dev/tcp/127.0.0.1/$L0_CLI") 2>/dev/null \
        && (echo > "/dev/tcp/127.0.0.1/$L1_CLI") 2>/dev/null; then
            all_up=1; break
        fi
        sleep 2; elapsed=$((elapsed + 2))
    done
    [ "$all_up" = 1 ] || die "Servers didn't bind within ${timeout}s. Check $LOG_FILE."
    ok "HTTP servers bound"

    # Give the node a moment to settle before posting joins
    sleep 4

    # Post manual L0 + L1 cluster joins (works around an upstream SDK ordering bug)
    log "Joining Sentiment chain (L0)…"
    curl -fsS -X POST "http://127.0.0.1:$L0_CLI/cluster/join" \
        -H 'Content-Type: application/json' \
        -d "{\"id\":\"$GENESIS_ID\",\"ip\":\"$L0_INITIAL_HOST\",\"p2pPort\":\"$L0_P2P\"}" >/dev/null \
        || warn "L0 join returned non-success (often harmless on re-runs)"

    log "Joining Sentiment chain (L1)…"
    curl -fsS -X POST "http://127.0.0.1:$L1_CLI/cluster/join" \
        -H 'Content-Type: application/json' \
        -d "{\"id\":\"$L1_GENESIS_ID\",\"ip\":\"$L1_INITIAL_HOST\",\"p2pPort\":\"$L1_P2P\"}" >/dev/null \
        || warn "L1 join returned non-success (often harmless on re-runs)"

    # Wait for both layers to be Ready
    log "Waiting for cluster handshake…"
    local ready=0
    for _ in $(seq 1 30); do
        local s0 s1
        s0=$(curl -s --max-time 2 "http://127.0.0.1:$L0_PUBLIC/node/info" | grep -oE '"state":"[^"]+"' || true)
        s1=$(curl -s --max-time 2 "http://127.0.0.1:$L1_PUBLIC/node/info" | grep -oE '"state":"[^"]+"' || true)
        if [[ "$s0" == *Ready* && "$s1" == *Ready* ]]; then ready=1; break; fi
        sleep 2
    done

    echo
    if [ "$ready" = 1 ]; then
        ok "Node is $(c_green Ready)"
    else
        warn "Node didn't reach Ready in time. It may still be syncing. Check $(c_dim "./run.sh --status")"
    fi
    echo
    echo "  Open in browser: $(c_blue "http://127.0.0.1:$L1_PUBLIC")"
    echo "  Tail logs:       $(c_dim "./run.sh --logs")"
    echo "  Stop:            $(c_dim "./run.sh --stop")"
    echo
}

tail_logs() {
    [ -f "$LOG_FILE" ] || die "No log file yet — has the node been started?"
    log "Tailing $LOG_FILE — Ctrl+C to detach (node keeps running)"
    tail -F "$LOG_FILE"
}

# ── Main dispatch ───────────────────────────────────────────────────────────
case "${1:-}" in
    --stop)    stop_node ;;
    --status)  show_status ;;
    --logs)    tail_logs ;;
    --clean)   stop_node; wipe_state; require_java; ensure_jar; ensure_keystore; ensure_config; launch_node ;;
    --help|-h) sed -n '2,10p' "$0" | sed 's/^# \?//' ;;
    "")
        require_java
        ensure_jar
        ensure_keystore
        ensure_config
        launch_node
        ;;
    *) die "Unknown argument: $1   (try --help)" ;;
esac
