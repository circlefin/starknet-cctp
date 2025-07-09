#!/bin/bash

set -e

# Install asdf and plugins
brew install asdf lcov
asdf plugin add cairo-coverage
asdf plugin add cairo-profiler
asdf plugin add scarb
asdf plugin add starknet-foundry
asdf plugin add starknet-devnet
asdf install
curl -L https://raw.githubusercontent.com/software-mansion/universal-sierra-compiler/master/scripts/install.sh | sh

# Setup git hooks
git config core.hooksPath .githooks