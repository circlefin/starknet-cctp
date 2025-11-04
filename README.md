# Starknet CCTP

Official implementation of Circle's Cross-Chain Transfer Protocol (CCTP) smart contracts for Starknet.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Overview

Cross-Chain Transfer Protocol (CCTP) is a permissionless on-chain utility that facilitates the transfer of USDC between blockchain networks. This repository contains the official Starknet implementation of CCTP smart contracts, enabling secure and efficient cross-chain USDC transfers between Starknet and other supported blockchains.

### Key Features

- **Native Cross-Chain Transfers**: Burn USDC on the source chain and mint native USDC on the destination chain
- **Permissionless**: Anyone can transfer USDC cross-chain using CCTP
- **Attestation-Based Security**: Leverages Circle's attestation service for secure message verification
- **Composable**: Integrate cross-chain USDC transfers directly into your smart contracts
- **Cairo Implementation**: Built using Cairo, Starknet's native smart contract language

## Architecture

CCTP on Starknet consists of two main contracts:

### 1. Message Transmitter
- Handles cross-chain message transmission and verification
- Manages attestation validation and message replay prevention
- Ensures message authenticity through signature verification

### 2. Token Messenger Minter
- Manages USDC burning on source chains and minting on destination chains
- Controls token pairs between local and remote domains
- Enforces burn limits and transfer controls

## Getting Started

### Prerequisites

- [Git](https://git-scm.com/)
- [Node.js](https://nodejs.org/)
- [Asdf](https://asdf-vm.com/)

### Installation

1. **Install toolchain and dependencies**
   ```bash
   ./setup.sh
   ```

## Usage

### Building Contracts

```bash
# Build all contracts
scarb build --workspace

# Build with release profile
yarn release
```

### Testing

```bash
# Run contract tests
snforge test

# Run end-to-end tests
yarn test:e2e
```

### Local Development

1. **Start local Starknet network**
   ```bash
   yarn start-network
   ```

2. **Deploy contracts**
   ```bash
   yarn deploy
   ```

3. **Run tests**
   ```bash
   yarn test
   ```

4. **Stop network**
   ```bash
   yarn stop-network
   ```

## Examples

Check out the [examples](examples/) directory for practical demonstrations of CCTP usage:

```bash
# Bridge from Starknet to EVM
npm run bridge-v2 strk2evm -- --amount 100 --fastBurn true

# Bridge from EVM to Starknet
npm run bridge-v2 evm2strk -- --amount 100
```

## Project Structure

```
starknet-cctp/
├── packages/
│   ├── components/          # Reusable Cairo components
│   ├── interfaces/          # Contract interfaces
│   ├── message/            # Message construction and parsing utilities
│   ├── message_transmitter/ # Message Transmitter contract
│   ├── token_messenger_minter/ # Token Messenger Minter contract
│   └── utils/              # Shared utilities
├── scripts/                # Deployment and management scripts
├── examples/               # Usage examples
├── e2e/                   # End-to-end tests
└── tests/                 # Unit tests
```

## Security

Security is our top priority. If you discover a security vulnerability, please follow our [Security Policy](SECURITY.md).

## Resources

- [CCTP Documentation](https://developers.circle.com/cctp)
- [Circle Developer Hub](https://developers.circle.com/)
- [Starknet Documentation](https://docs.starknet.io/)
- [Cairo Documentation](https://book.cairo-lang.org/)

## License

This project is licensed under the Apache License, Version 2.0 - see the [LICENSE](LICENSE) file for details.
