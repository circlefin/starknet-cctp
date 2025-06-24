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

# Setup git hooks
git config core.hooksPath .githooks