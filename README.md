# Sentiment rApp Releases

This repository hosts JAR distributions of the [Sentiment rApp](https://givesentiment.com) for [Reality](https://reality.network/) testnet and mainnet.

## What is it?

The Sentiment rApp is a privacy-preserving survey verification application that runs on the Reality network. Survey responses are verified locally on each operator's node using WASM and SNARKs; rewards are paid in $SENT.

## For Reality node operators

If you are running a Reality node and want to host the Sentiment rApp:

1. Download the latest `sentiment-reality-assembly-*.jar` from [Releases](https://github.com/Give-Sentiment/sentiment-rapp-releases/releases)
2. Verify the SHA-256 matches the `binaryHash` declared in the on-chain `DeployAppTransaction`
3. Follow the operator setup instructions documented inside the JAR's `standalone/` resources

## Source code

The full source lives in a separate (private) repository. The JARs published here are reproducibly built from that source.
