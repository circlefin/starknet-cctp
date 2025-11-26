# Starknet Denylist Bypass PoC

This folder contains the scripts required to reproduce the denylist bypass on a local Starknet devnet instance.

## Prerequisites
- Docker (default runtime used by `e2e/cmd/start_network.sh`)
- `corepack` (Yarn) and `node` to run the scripts

## One-shot Reproduction
Run the combined script to build contracts, deploy them to the dockerized devnet, execute the PoC, and capture artifacts:

```bash
cd /path/to/starknet-cctp
repros/denylist_poc/run_all.sh
```

The script will automatically start the devnet container, compile contracts, deploy the CCTP stack, and call the PoC runner. On completion, the devnet is stopped automatically.

## PoC Runner
`repros/denylist_poc/run.ts` can also be executed independently if the devnet is already running and contracts are deployed:

```bash
corepack yarn tsx repros/denylist_poc/run.ts
```

This script:
1. Links the remote token pair if necessary and ensures the Starknet recipient is denylisted.
2. Crafts a signed burn message (using local attester keys) that names the denylisted recipient.
3. Relays the message through `MessageTransmitter.receive_message`.
4. Confirms minting via the resulting `MintAndWithdraw` event and Starknet balance changes.
5. Stores structured evidence (calldata, attestation, receipts, events, balances) under `repros/denylist_poc/artifacts/<timestamp>/summary.json`.

## Artifacts
Each PoC execution produces a JSON summary under `repros/denylist_poc/artifacts` containing:
- Contract addresses and tx hashes
- Burn message, relay message, and attestation payloads (hex)
- MintAndWithdraw event details
- Before/after balances for the denylisted recipient

These artifacts serve as the on-chain evidence requested in the disclosure review.
