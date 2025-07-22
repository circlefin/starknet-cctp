#!/bin/bash
set -e

# Start network
yarn start-network

# Deploy contracts
yarn deploy

# Run tests and capture exit code
yarn test
TEST_EXIT_CODE=$?

# Always stop network
yarn stop-network

# Exit with test exit code
exit $TEST_EXIT_CODE