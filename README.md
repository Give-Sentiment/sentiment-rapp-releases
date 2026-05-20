# Sentiment rApp Releases

This repository hosts JAR distributions of the [Sentiment rApp](https://givesentiment.com) for [Reality](https://realitynet.xyz/) testnet and (later) mainnet.

## What is it?

The Sentiment rApp is a privacy-preserving survey verification application that runs on the Reality network. Survey responses are verified locally on each operator's node using WASM and STARK proofs; rewards are paid in **$SENT**.

Each node hosting the rApp gets:

- A local UI (port `9010`) where users on that node create surveys and submit responses
- WASM-based on-device verification (no third-party API calls)
- Participation in the Sentiment chain's L0 consensus (block validation, facilitator rewards)
- Optional NET L0 anchoring (the rApp's snapshots periodically anchor to Reality's NET L0)

## Status

| | |
|---|---|
| Reality SDK | build 1078 (`6586bc85`) |
| Testnet writer | live, single-host cluster (Mac mini) |
| `DeployAppTransaction` on NET L0 | **not submitted yet** — once submitted, operators can discover us via NET L0 |
| Third-party operator path | **manual join** (instructions below) until the deploy tx lands |

## Prerequisites

- **Java 17** (OpenJDK / Amazon Corretto / Homebrew `openjdk@17`)
- **~500 MB free disk** (snapshots + ACI DB grow over time)
- **Outbound network access** to the Sentiment chain's L0/L1 hosts
- **Inbound port forwarding** OR libp2p connectivity (operators behind CG-NAT need to set `LIBP2P_RELAY_ADDRESSES` to a relay multiaddr — Reality testnet's relay works)

## 1. Download the JAR

Grab the `sentiment-reality-assembly-*.jar` from the [latest release](https://github.com/Give-Sentiment/sentiment-rapp-releases/releases) and save it somewhere convenient. The rest of this README assumes you've set:

```bash
export JAR_PATH=~/sentiment/sentiment.jar
mkdir -p "$(dirname "$JAR_PATH")"
mkdir -p ~/.sentiment-keys && chmod 700 ~/.sentiment-keys
# ... drop the downloaded JAR at $JAR_PATH ...
```

You can put the JAR anywhere; just substitute `$JAR_PATH` for that location.

**Verify the SHA-256** before running anything. The release page shows the expected hash next to the asset:

```bash
shasum -a 256 "$JAR_PATH"
```

Compare against the hash on the release page. Once we submit the on-chain `DeployAppTransaction`, the canonical `binaryHash` will also be readable from NET L0; cross-check both sources.

> *Alternatively, for scripted/unattended installs:*
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

This is *your* signing key — it identifies your node and receives any facilitator rewards. Keep it safe; if you lose it, your node loses its identity (and any earned $SENT must be recovered via the on-chain receipt).

## 3. Create `config.env`

Save the following to `~/sentiment/config.env` (mode `0600`):

```bash
# Operator-side config — third-party Reality nodes hosting the Sentiment rApp.
# (Sentiment writer nodes have a different config with Supabase credentials —
#  do NOT set SUPABASE_* here. Writer credentials are not for operators.)

# Sentiment RSA public key — encrypts client survey responses so only the
# Sentiment writer (which holds the private key) can decrypt.
SENTIMENT_PUBLIC_KEY=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArXcT7Wr3pv8re1UErPI9q2ZuDs6h87Qj98M1Q3Q2FFna1xnFlOpEyMPROYPxGh5INYfV25vk3ffSOl7coNC3OlPDwCz0fcw9P7dy/2enOFT/A7X8g2LilcBPkl6D+reEga3iex64JfVRCyq6wrTxKyPbegvRHFn9xS2Yg+U2e/9nQ+LksY0d2je0WVTnmda1gF3HUTQqZFSoAYdIJpmkyHvaoST+q8RtR24q8vPXJznAn6geZFPljVfooBVDki/O1RZ3SsyIlRbUFL2st7gcjjA4E8Zs6l7b68Q2ddJTXsnyYFG2eWwaGrYsGipXyqBjqFKDoT1P+ZQ3SGip5FpNTwIDAQAB

NODE_TYPE=validator
APP_IDENTIFIER=sentiment-reality

# Your public IP — peers use this to dial back. Required.
ADVERTISED_IP=<your-public-ip>

# Sentiment chain L0/L1 bootstrap (TBD — will be populated when the writer
# moves to its public host. Until then, this list is empty and operators
# can't join the Sentiment chain externally.)
# L0_INITIAL_HOST=<sentiment-l0-host>
# L0_INITIAL_PUBLIC_PORT=9000
# L1_INITIAL_HOST=<sentiment-l1-host>
# L1_INITIAL_PUBLIC_PORT=9010

# Reality NET L0 testnet (for rApp snapshot anchoring once the rApp is registered)
# SENTIMENT_RAPP_ADDRESS=NET5ovhZRDnnaLK756jEdiR8nE8snz2SDJZ32uQX
# NET_L0_HOST=143.110.227.9
# NET_L0_PUBLIC_PORT=9000
# NET_L0_PEER_ID=0000003264c7c8503da3d03b6021101a57b5eb933d887bb7e3fbf4b2a57c302dfc5008afb522059b1926e8220de1cfa9388183de60b376a7bd93268990d71157

# libp2p relay — required for nodes behind CG-NAT (no inbound port forwarding).
# Reality testnet's relay handles this. Comment out if your node has direct
# inbound connectivity.
LIBP2P_RELAY_ADDRESSES=/ip4/143.110.227.9/tcp/9003/p2p/16Uiu2HAmCRkapTKsQqC1kTPVSEKLNqtiCsumUnf3CAbVuJjGoQB6
```

Then:

```bash
chmod 600 ~/sentiment/config.env
```

## 4. Start the rApp

A turnkey start script for operator nodes (`standalone/start.sh`) ships with the JAR and will be linked from a future release. **Pending — the writer's public host is not finalised, so operators cannot yet bootstrap externally.** Once that lands, the start command will be approximately:

```bash
set -a; source ~/sentiment/config.env; set +a

java --enable-native-access=ALL-UNNAMED \
     -Dtransport.libp2p.relay.addresses="$LIBP2P_RELAY_ADDRESSES" \
     -Djava.net.preferIPv4Stack=true \
     -jar "$JAR_PATH" \
     --l0--command run-validator \
     --l0--env dev \
     --l0--keyalias alias --l0--password password \
     --l0--keystore ~/.sentiment-keys/operator.p12 \
     --l0--ip "$ADVERTISED_IP" \
     --l0--public-port 9000 --l0--p2p-port 9001 --l0--cli-port 9002 \
     --l0--peer-id "$SENTIMENT_GENESIS_L0_PEERID" \
     --l0--l0-ip "$L0_INITIAL_HOST" \
     --l0--startup-port 9000 --l0--collateral 0 \
     --l1--command run-validator \
     --l1--env dev \
     --l1--keyalias alias --l1--password password \
     --l1--keystore ~/.sentiment-keys/operator.p12 \
     --l1--ip "$ADVERTISED_IP" \
     --l1--public-port 9010 --l1--p2p-port 9011 --l1--cli-port 9012 \
     --l1--l0-peer-id "$SENTIMENT_GENESIS_L0_PEERID" \
     --l1--l0-peer-host "$L0_INITIAL_HOST" \
     --l1--l0-peer-port 9000 \
     --l1--collateral 0 --l1--aci-db-path aci
```

After the JVM starts and binds its L0+L1 HTTP servers (~20 s), POST a manual L1 cluster join (the SDK's auto-fire is suppressed for operators — see the troubleshooting section for why):

```bash
cat > /tmp/l1-peer.json <<EOF
{
  "id": "$SENTIMENT_GENESIS_L1_PEERID",
  "ip": "$L1_INITIAL_HOST",
  "p2pPort": "9011"
}
EOF
curl -s -X POST http://127.0.0.1:9012/cluster/join \
     -H 'Content-Type: application/json' \
     -d @/tmp/l1-peer.json
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

A healthy node reports `state=Ready` on both layers, with `clusterSession` matching the rest of the cluster.

## How rewards work

| Recipient | Source | Cadence |
|---|---|---|
| Survey creators | `user_reward_pool` (30M $SENT cap) | At verified-response milestones: 10 → 25 → 50 → 100 → … → 10,000 (max 70 $SENT per survey) |
| Survey respondents | none today (design decision — respondents' incentive is the data being theirs and reputation accrual) | n/a |
| **Node operators (you)** | Reality protocol facilitator rewards | Per L0 consensus round when selected as a facilitator |

## Source code

The full source lives in a separate (currently private) repository: `Give-Sentiment/Sentiment-Survey-Vercel`. The JARs published here are built from that source. The repo will be made public alongside testnet launch; this README will be updated with the link.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Address already in use` on port 9000 | Another rApp / blockchain node is already running | `lsof -nP -iTCP:9000` to find the holder; pick a different port range |
| Node binds but `/node/info` returns no JSON | Started the wrong subcommand (e.g. `run-genesis` instead of `run-validator`) | Operator nodes use `run-validator`. Only the Sentiment writer runs genesis. |
| `L1 join failed: Connection refused` | Genesis L1 isn't reachable, or your config.env's `L1_INITIAL_HOST` is wrong | Verify `L1_INITIAL_HOST:L1_INITIAL_PUBLIC_PORT` is reachable via `curl /node/info` |
| `Cannot start own consensus: Not enough peers` (L1 only, sustained) | L1 join attempt failed; node stuck in `SessionStarted` | Stop the node, wipe `data/snapshot/`, `aci/aci.db/`, restart |
| Node behind CG-NAT, can't accept inbound | No port forwarding available | Ensure `LIBP2P_RELAY_ADDRESSES` is set; libp2p handles relay + hole-punching |
| `InvalidRemoteAddress` on cluster join | Your `ADVERTISED_IP` doesn't match the IP genesis sees on your inbound TCP connection | Set `ADVERTISED_IP` to the actual public IP that genesis observes |

### Why a manual L1 join step?

There's an ordering bug in Reality SDK build 1078: the L1 module fires its cluster-join attempt before the L1 HTTP server has finished binding. Genesis accepts the join, tries to verify the joiner by dialing back to the joiner's p2p port → `Connection refused` (port not LISTEN'ing yet). The joiner transitions to `SessionStarted` and never retries.

We suppress the SDK's auto-fire (`l1GenesisPeer = None` for `NODE_TYPE=validator`) and POST `/cluster/join` manually after the L1 HTTP server is confirmed up. This will be unnecessary once the SDK is patched upstream.

## Reporting issues

Open an issue at <https://github.com/Give-Sentiment/sentiment-rapp-releases/issues> — include the JAR's SHA-256, the relevant log lines, and your `config.env` (with **secrets redacted**).
