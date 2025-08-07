# starknet-cctp-private

Official repository for Starknet smart contracts used by the Cross-Chain Transfer Protocol

## Development

### Install Toolchain

```bash
git clone git@github.com:circlefin/starknet-cctp-private.git
cd starknet-cctp-private
./setup.sh
```

## Common Commands

```bash
# Analyze and report errors
scarb check
# Perform test
snforge test
# Test with coverage report
./coverage.sh
```

## E2E Test

Run All tests

```bash
yarn test:e2e
```

Focus on a single test

```bash
# Start starknet-devnet
yarn start-network
# Deploy contracts
yarn deploy
# Change "it" to "fit" to focus on single test(s)
# Then run the test as much as you want
yarn test
# Stop starknet-devnet which also cleans up all states
yarn stop-network
```
