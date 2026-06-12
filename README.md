# Sentiment rApp

JAR distributions of the [Sentiment](https://givesentiment.com) rApp — a privacy-preserving survey verification application that runs on the [Reality](https://realitynet.xyz/) network. Surveys + responses are verified locally on each node using WASM and STARK proofs; rewards are paid in **$SENT**.

Running a node makes you a validator on the Sentiment chain. You get a local web UI for creating + answering surveys, on-device response verification (no third-party APIs see the data), and **facilitator rewards** paid by the Reality protocol whenever your node is selected to facilitate an L0 consensus round.

## Quick start

You need **Java 17** and outbound internet. Nothing else. (On Windows, see [Windows (WSL2)](#windows-wsl2) below — `run.sh` is a bash script and won't run in PowerShell.)

```bash
git clone https://github.com/Give-Sentiment/sentiment-rapp-releases.git
cd sentiment-rapp-releases
./run.sh
```

### Windows (WSL2)

`run.sh` needs bash, so on Windows run the node inside WSL2 (Windows Subsystem for Linux). One-time setup in PowerShell (as Administrator), then reboot if prompted:

```powershell
wsl --install -d Ubuntu
```

Then open the **Ubuntu** app and follow the normal quick start:

```bash
sudo apt-get update && sudo apt-get install -y openjdk-17-jdk git
git clone https://github.com/Give-Sentiment/sentiment-rapp-releases.git
cd sentiment-rapp-releases
./run.sh
```

Open <http://127.0.0.1:9010> in your normal Windows browser — WSL2 forwards localhost automatically. All the `./run.sh --status/--logs/--stop` commands below work the same inside Ubuntu. (Git Bash is not supported — the script's process management is unreliable there.)

Mobile hotspots and home NAT are fine: the node only needs outbound internet and joins the network over a relay.

The script downloads + verifies the JAR (~166 MB), generates a unique keystore for your node, writes `config.env`, and launches the node. After about 30–60 seconds you'll see:

```
✓ Node is Ready

  Open in browser: http://127.0.0.1:9010
```

Open that URL — you're on the Sentiment respondent UI.

## What you can do once it's running

| Command | What it does |
|---|---|
| `./run.sh` | Start the node (idempotent — safe to re-run) |
| `./run.sh --status` | Check whether the node is running + L0/L1 state |
| `./run.sh --logs` | Tail the log (Ctrl+C just detaches — the node keeps running) |
| `./run.sh --stop` | Stop the node cleanly |
| `./run.sh --clean` | Wipe local chain state and restart from scratch |

### What's actually running

`./run.sh` boots one JVM that runs both layers of your Sentiment chain validator:

- **L0** binds `127.0.0.1:9000` (public), `:9001` (p2p), `:9002` (cli)
- **L1** binds `127.0.0.1:9010` (public + UI), `:9011` (p2p), `:9012` (cli)

The L1 public port (`9010`) is the local web UI. Other ports are internal HTTP endpoints the cluster uses; nothing on them needs to be exposed.

Your node joins the live Sentiment chain via the testnet writer at `46.101.82.227`. Because that handshake happens over libp2p with the testnet relay, you don't need to forward any ports — typical home NAT is fine.

## Files this creates

After the first run, your local directory contains:

```
sentiment-rapp-releases/
├── run.sh
├── README.md
├── sentiment-reality.jar      # ~166 MB, hash-verified on download
├── operator-l0.p12            # YOUR L0 keystore — back this up if you keep the node
├── operator-l1.p12            # YOUR L1 keystore — distinct identity from L0
├── config.env                 # editable; delete to regenerate defaults
├── sentiment.log              # rolling log
├── sentiment.pid              # PID of the running JVM
├── data/                      # consensus snapshots (auto-grown)
└── aci/                       # ACI database (auto-grown)
```

The keystore is your node's identity. Any rewards your node earns belong to the address derived from this file. Losing it means losing the identity (rewards earned before are still recoverable on-chain, but the node would need a new identity to keep validating).

## Current release

| | |
|---|---|
| Tag | [`v0.1.5-testnet`](https://github.com/Give-Sentiment/sentiment-rapp-releases/releases/tag/v0.1.5-testnet) |
| JAR SHA-256 | `996a3b35d67cd72118571fb1d6eea84e82a67b864dc5d671f0b06955e42f21ac` |
| Reality SDK | build **1095** (commit `608b68dc`) |
| Sentiment chain writer | `46.101.82.227` (Reality testnet) |
| NET L0 anchoring | enabled once the next `DeployAppTransaction` lands on NET L0; `run.sh` leaves `SENTIMENT_RAPP_ADDRESS` commented in `config.env` until then |

## How rewards work

| Recipient | Source | Paid out |
|---|---|---|
| Node operator (you) | Reality protocol facilitator reward | Per L0 round in which your node is selected as a facilitator |
| Survey creator | $SENT `user_reward_pool` (30M cap) | At verified-response milestones: 10 → 25 → 50 → 100 → … → 10 000 (max 70 $SENT / survey) |
| Survey respondent | No direct payout today | Reputation accrues to the respondent's address on every verified response |

The operator stream is a separate protocol-level reward from Reality (not from the $SENT token economy). It's paid in NET, the Reality network's native asset, every time your node is randomly selected to facilitate a round.

## Troubleshooting

### Run `./run.sh --status` first

That tells you whether the JVM is up and what both layers' `/node/info` say. If both report `state:"Ready"`, the node is healthy.

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `Java not found` | Java 17 isn't installed or isn't on PATH | macOS: `brew install openjdk@17`. Ubuntu: `sudo apt-get install -y openjdk-17-jdk`. Other: <https://adoptium.net/temurin/releases/?version=17> |
| `Address already in use` | Another process owns 9000–9012 | `lsof -nP -iTCP:9000` to see who. Stop it or change the ports in `run.sh` (the constant block near the top) |
| `Servers didn't bind within 90s` | Slow first boot, or the JVM crashed | Check `sentiment.log` for the stack trace. `./run.sh --clean` to start over |
| L1 stays at `SessionStarted` | Cluster-join handshake didn't complete | `./run.sh --clean` resolves it 95% of the time |
| Node binds locally but you can't reach the UI | UI is on `127.0.0.1:9010` only — not exposed to your LAN/WAN | Open it from the same machine, or tunnel via SSH: `ssh -L 9010:127.0.0.1:9010 you@host` |

### Reporting an issue

Open one at <https://github.com/Give-Sentiment/sentiment-rapp-releases/issues>. Include:

- The output of `./run.sh --status`
- The last ~50 lines of `sentiment.log`
- Your `config.env` **with any secrets redacted**

## Source

The rApp itself is built from `Give-Sentiment/Sentiment-Survey-Vercel` (currently private; will open to the public alongside testnet launch). This repo only hosts the compiled JAR releases + this launcher.
