# Sentiment rApp Releases

This repository hosts JAR distributions of the [Sentiment rApp](https://givesentiment.com) for [Reality](https://realitynet.xyz/) testnet and (later) mainnet.

## What is it?

The Sentiment rApp is a privacy-preserving survey verification application that runs on the Reality network. Survey responses are verified locally on each operator's node using WASM and STARK proofs; rewards are paid in **$SENT**.

Each node hosting the rApp gets:

- A local UI (port `9010`) where users on that node create surveys and submit responses
- WASM-based on-device verification (no third-party API calls)
- Participation in the Sentiment chain's L0 consensus (block validation, **facilitator rewards** paid by the Reality protocol)
- Optional NET L0 anchoring (the rApp's snapshots periodically anchor to Reality's NET L0)

You run a full Sentiment validator alongside whatever else you host. It is *not* a passive snapshot-relay setup; you process responses and earn block-validation rewards.

## Status

| | |
|---|---|
| Reality SDK | build **1092** (`0da02f77`) — earlier builds lack the libp2p init gate fix |
| Latest JAR | `sentiment-reality-assembly-0.1.0-SNAPSHOT.jar` (release `v0.1.2-testnet`) — SHA-256 `c1033306a5e39cf9ee8b58923b42cf3a40fd6827d5df220597ffb4f823841e46` |
| Testnet writer | live on the public testnet, 3-node cluster at `167.253.65.37` |
| Inbound transport | **libp2p** (relay + hole-punching) — no port forwarding required for operators |
| Keystore wiring | **You MUST set `L0_KEYSTORE` + `L1_KEYSTORE`** in `config.env` (see step 3). Without them the node loads a hardcoded built-in keystore path instead of yours, signs with the wrong key, and dies in an `L0PeerDiscovery 401` loop. |
| `DeployAppTransaction` on NET L0 | submitted; NET L1 → NET L0 anchoring is subject to Reality testnet block-inclusion timing. Once the rApp is registered on NET L0, anchoring lights up automatically. |

## Prerequisites

- **Java 17** (OpenJDK / Amazon Corretto / Homebrew `openjdk@17`)
- **~500 MB free disk** (snapshots + ACI DB grow over time)
- **Outbound network access** to the Sentiment chain's writer at `167.253.65.37` (initial bootstrap) and the libp2p relay (so your node can register for inbound traffic)
- **No inbound port forwarding required** — libp2p handles NAT traversal via relay + hole-punching. If you happen to have a public-routable host with port forwarding, the node will use direct HTTP too; otherwise libp2p alone is sufficient.

## 1. Download the JAR

Grab the `sentiment-reality-assembly-*.jar` from the [latest release](https://github.com/Give-Sentiment/sentiment-rapp-releases/releases) and save it somewhere convenient. The rest of this README assumes you've set:

```bash
export JAR_PATH=~/sentiment/sentiment.jar
mkdir -p "$(dirname "$JAR_PATH")"
mkdir -p ~/.sentiment-keys && chmod 700 ~/.sentiment-keys
# ... drop the downloaded JAR at $JAR_PATH ...
```

**Verify the SHA-256** before running anything:

```bash
shasum -a 256 "$JAR_PATH"
# expected: c1033306a5e39cf9ee8b58923b42cf3a40fd6827d5df220597ffb4f823841e46
```

Once the `DeployAppTransaction` lands on NET L0, the same `binaryHash` will also be readable from NET L0 — cross-check both sources.

> *Alternatively, for scripted installs:*
> ```bash
> curl -L -o "$JAR_PATH" \
>   https://github.com/Give-Sentiment/sentiment-rapp-releases/releases/latest/download/sentiment-reality-assembly-0.1.0-SNAPSHOT.jar
> ```

## 2. Generate your own validator keystore

Each operator runs with their own EC keystore. The Reality keytool is bundled inside the same JAR:

```bash
CL_KEYSTORE=~/.sentiment-keys/operator.p12 \
CL_KEYALIAS=alias \
CL_PASSWORD=password \
  java -cp "$JAR_PATH" org.reality.keytool.Main generate
chmod 600 ~/.sentiment-keys/operator.p12
```

This is *your* signing key — it identifies your node and receives any facilitator rewards. Keep it safe; if you lose it, your node loses its identity (and any earned rewards must be recovered via the on-chain receipt).

## 3. Create `config.env`

Save the following to `~/sentiment/config.env` (mode `0600`):

```bash
# Operator-side config — third-party Reality nodes hosting the Sentiment rApp.
# (Sentiment writer nodes have a different config with Supabase credentials —
#  do NOT set SUPABASE_* here. Writer credentials are not for operators.)

# Sentiment RSA public key — encrypts survey responses your node receives so
# only the off-cluster Sentiment admin service (which holds the private key)
# can decrypt them. Your node never sees plaintext after this is applied.
SENTIMENT_PUBLIC_KEY=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArXcT7Wr3pv8re1UErPI9q2ZuDs6h87Qj98M1Q3Q2FFna1xnFlOpEyMPROYPxGh5INYfV25vk3ffSOl7coNC3OlPDwCz0fcw9P7dy/2enOFT/A7X8g2LilcBPkl6D+reEga3iex64JfVRCyq6wrTxKyPbegvRHFn9xS2Yg+U2e/9nQ+LksY0d2je0WVTnmda1gF3HUTQqZFSoAYdIJpmkyHvaoST+q8RtR24q8vPXJznAn6geZFPljVfooBVDki/O1RZ3SsyIlRbUFL2st7gcjjA4E8Zs6l7b68Q2ddJTXsnyYFG2eWwaGrYsGipXyqBjqFKDoT1P+ZQ3SGip5FpNTwIDAQAB

# Operator-style node — joins the Sentiment chain as a validator.
# (The startup will log "Unknown NODE_TYPE, defaulting to genesis" — that's
#  expected and harmless. NODE_TYPE=validator suppresses the SDK's broken L1
#  auto-join while keeping the default 9000-9012 port layout.)
NODE_TYPE=validator
APP_IDENTIFIER=sentiment-reality

# Your advertised IP — used for outbound libp2p registration. If you're behind
# CG-NAT or otherwise can't accept inbound HTTP, 127.0.0.1 is fine; libp2p
# routes return traffic via the relay.
ADVERTISED_IP=127.0.0.1

# Sentiment chain L0/L1 bootstrap. Operators dial these to fetch the initial
# peer info; once libp2p is registered with the relay, all subsequent gossip
# rides libp2p directly.
L0_INITIAL_HOST=167.253.65.37
L0_INITIAL_PUBLIC_PORT=9000
L1_INITIAL_HOST=167.253.65.37
L1_INITIAL_PUBLIC_PORT=9010

# Sentiment-chain genesis peerIds — derived from the Sentiment writer's L0 and
# L1 keystores. Your validator dials these to join the cluster.
GENESIS_ID=c754a46b9c4b3317bfccbe5faf0999005933d3ac1236a02233b531033dec26604d35b12d78a7facb657325ab8f098f47804812a70052f16912660db5870f3cfe
L1_GENESIS_ID=f47b97b438e4d65286fea06c617592e51d0ce69e9962ffa787235fc4ab370b272aded409d805042982e2fb2b15def667ab59e3c071041759193e116c8ac5b828

# YOUR keystore paths — REQUIRED. The app loads the L0 and L1 signing keys from
# these env vars. If you leave them unset, the node falls back to a hardcoded
# built-in path (keys/l{0,1}-initial-validator-key.p12) that does NOT exist on
# your machine and does NOT match your advertised identity — the L1 layer then
# can't verify the L0's signed responses and the node dies in a repeating
# `L0PeerDiscovery$L0PeerDiscoveryError$ ... 401 Unauthorized for GET
# http://127.0.0.1:9000/cluster/info` loop. Point BOTH at your operator keystore:
L0_KEYSTORE=/home/youruser/.sentiment-keys/operator.p12
L1_KEYSTORE=/home/youruser/.sentiment-keys/operator.p12

# Reality NET L0 anchoring — uncomment once the DeployAppTransaction lands on
# NET L0 (see "Status" above). Until then, leave commented — your node still
# works as a full Sentiment validator; only NET L0 anchoring is gated.
# SENTIMENT_RAPP_ADDRESS=NET5ovhZRDnnaLK756jEdiR8nE8snz2SDJZ32uQX
# NET_L0_HOST=128.199.67.191
# NET_L0_PUBLIC_PORT=9000
# NET_L0_PEER_ID=22222208770d62f27e8cd5b927f9c743ae0acda57f77532bf82be73ed36a59c74240c122dbb725216310f77ade4567d54f2a0361941e27e69571f74cfed326ca

# libp2p relay — Reality testnet's relay. With SDK build 1088+, libp2p is
# always on; nodes behind CG-NAT use this relay for inbound traffic.
LIBP2P_RELAY_ADDRESSES=/ip4/143.110.227.9/tcp/9003/p2p/16Uiu2HAmCRkapTKsQqC1kTPVSEKLNqtiCsumUnf3CAbVuJjGoQB6
```

Then:

```bash
chmod 600 ~/sentiment/config.env
```

## 4. Start the rApp

Load the env, then launch:

```bash
set -a; source ~/sentiment/config.env; set +a

java --enable-native-access=ALL-UNNAMED \
     -Dtransport.libp2p.relay.addresses="$LIBP2P_RELAY_ADDRESSES" \
     -Djava.net.preferIPv4Stack=true \
     -jar "$JAR_PATH" \
     --l0--command run-validator \
     --l0--env dev \
     --l0--requires-libp2p \
     --l0--keyalias alias --l0--password password \
     --l0--keystore ~/.sentiment-keys/operator.p12 \
     --l0--ip "$ADVERTISED_IP" \
     --l0--public-port 9000 --l0--p2p-port 9001 --l0--cli-port 9002 \
     --l0--peer-id "$GENESIS_ID" \
     --l0--l0-ip "$ADVERTISED_IP" \
     --l0--startup-port 9000 --l0--collateral 0 \
     --l1--command run-validator \
     --l1--env dev \
     --l1--requires-libp2p \
     --l1--keyalias alias --l1--password password \
     --l1--keystore ~/.sentiment-keys/operator.p12 \
     --l1--ip "$ADVERTISED_IP" \
     --l1--public-port 9010 --l1--p2p-port 9011 --l1--cli-port 9012 \
     --l1--l0-peer-id "$GENESIS_ID" \
     --l1--l0-peer-host "$L0_INITIAL_HOST" \
     --l1--l0-peer-port 9000 \
     --l1--collateral 0 --l1--aci-db-path aci &

NODE_PID=$!
```

**Wait for the L0 and L1 HTTP servers to bind** before posting the cluster joins. The SDK doesn't gate the join phase on this, so a hardcoded `sleep` will race intermittently — poll instead:

```bash
echo "Waiting for L0 + L1 HTTP servers to bind..."
for port in 9001 9002 9011 9012; do
    for _ in $(seq 1 60); do
        if (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
            echo "  :$port up"; break
        fi
        sleep 1
    done
done
sleep 5
```

Then post **both** cluster-join requests — L0 first, then L1. The SDK's auto-join is suppressed for `NODE_TYPE=validator` (see [Troubleshooting](#troubleshooting) for why); these manual POSTs do the work:

```bash
# Join the Sentiment chain's L0 cluster
cat > /tmp/l0-peer.json <<EOF
{ "id": "$GENESIS_ID", "ip": "$L0_INITIAL_HOST", "p2pPort": "9001" }
EOF
curl -s -X POST http://127.0.0.1:9002/cluster/join \
     -H 'Content-Type: application/json' -d @/tmp/l0-peer.json

# Join the Sentiment chain's L1 cluster
cat > /tmp/l1-peer.json <<EOF
{ "id": "$L1_GENESIS_ID", "ip": "$L1_INITIAL_HOST", "p2pPort": "9011" }
EOF
curl -s -X POST http://127.0.0.1:9012/cluster/join \
     -H 'Content-Type: application/json' -d @/tmp/l1-peer.json
```

## 5. Verify your node is up

Once running, your node exposes a few HTTP endpoints locally:

```bash
# L0 health
curl http://127.0.0.1:9000/node/info

# L1 health
curl http://127.0.0.1:9010/node/info

# Sentiment-specific node info (your address + peerId)
curl http://127.0.0.1:9010/sentiment/node-info

# The local UI — open this in your browser
open http://127.0.0.1:9010
```

A healthy node reports `state=Ready` on both layers, with `clusterSession` matching the writer's. The UI lets local users on your machine create and respond to surveys; their responses are encrypted with `SENTIMENT_PUBLIC_KEY` on submission and only the off-cluster admin service can decrypt.

## How rewards work

| Recipient | Source | Cadence |
|---|---|---|
| Survey creators | `user_reward_pool` (30M $SENT cap) | At verified-response milestones: 10 → 25 → 50 → 100 → … → 10,000 (max 70 $SENT per survey) |
| Survey respondents | none today (design decision — respondents' incentive is the data being theirs and reputation accrual) | n/a |
| **Node operators (you)** | Reality protocol facilitator rewards | Per L0 consensus round when selected as a facilitator |

The operator stream is the protocol-level block-validation reward that Reality pays every facilitator in any L0 consensus. Hosting Sentiment puts your node into the Sentiment-chain L0 consensus, so this stream is what you earn for hosting. It's separate from the $SENT economy above.

## Source code

The full source lives in a separate (currently private) repository: `Give-Sentiment/Sentiment-Survey-Vercel`. The JARs published here are built from that source. The repo will be made public alongside testnet launch; this README will be updated with the link.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Address already in use` on port 9000 | Another rApp / blockchain node is already running | `lsof -nP -iTCP:9000` to find the holder; pick a different port range |
| Node binds but `/node/info` returns no JSON | Started the wrong subcommand (e.g. `run-genesis` instead of `run-validator`) | Operator nodes use `run-validator`. Only the Sentiment writer runs genesis. |
| `L1 join failed: Connection refused` | Genesis L1 isn't reachable, or `L1_INITIAL_HOST`/`L1_INITIAL_PUBLIC_PORT` is wrong | Verify with `curl http://$L1_INITIAL_HOST:$L1_INITIAL_PUBLIC_PORT/node/info` |
| `Cannot start own consensus: Not enough peers` (L1 only, sustained) | L1 join attempt failed; node stuck in `SessionStarted` | Stop the node, wipe `data/snapshot/`, `aci/`, restart |
| Node behind CG-NAT, can't accept inbound | No port forwarding available | Ensure `LIBP2P_RELAY_ADDRESSES` is set; libp2p handles relay + hole-punching |
| `InvalidRemoteAddress` on cluster join | Your `ADVERTISED_IP` doesn't match the IP genesis sees on your inbound TCP connection | Set `ADVERTISED_IP` to the actual public IP that genesis observes |
| Startup log says `Unknown NODE_TYPE, defaulting to genesis` | Expected — `NODE_TYPE=validator` is the operator value | Harmless. It selects the default 9000-9012 port layout AND suppresses the SDK's L1 auto-join (which is what you want as an operator). |
| Repeating `L0PeerDiscovery$L0PeerDiscoveryError$ ... 401 Unauthorized for ... GET http://127.0.0.1:9000/cluster/info`, then the JVM exits during L1 boot | `L0_KEYSTORE` / `L1_KEYSTORE` not set, so the node loaded the hardcoded built-in keystore path instead of yours — L0 signs responses with a key whose peerId doesn't match what it advertises, and L1's verify of those responses fails with a synthetic 401 | Set `L0_KEYSTORE` and `L1_KEYSTORE` in `config.env` (step 3) to the absolute path of your operator keystore, wipe `data/`, restart. Cross-check `SdkServices.make` in the logs: the reported `nodeId` must equal the peerId your keystore derives to. |

### Why a manual L1 join step?

There's an ordering bug in Reality SDK build 1088: the L1 module fires its cluster-join attempt before the L1 HTTP server has finished binding. Genesis accepts the join, tries to verify the joiner by dialing back to the joiner's p2p port → `Connection refused` (port not LISTEN'ing yet). The joiner transitions to `SessionStarted` and never retries.

We suppress the SDK's auto-fire (`l1GenesisPeer = None` for any `NODE_TYPE` starting with `validator`) and POST `/cluster/join` manually after the L1 HTTP server is confirmed bound. This will be unnecessary once the SDK is patched upstream.

## Reporting issues

Open an issue at <https://github.com/Give-Sentiment/sentiment-rapp-releases/issues> — include the JAR's SHA-256, the relevant log lines, and your `config.env` (with **secrets redacted**).
