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