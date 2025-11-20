# Starknet CCTP Message Package

This package provides Cairo utilities for constructing, parsing, and validating CCTP (Cross-Chain Transfer Protocol) messages on Starknet. It includes functions to encode and decode message fields, verify message formats, and handle message data structures according to the CCTP specification.

## Features

- Build and parse CCTP burn and mint messages as Cairo `ByteArray`s.
- Extract and validate message fields such as version, domains, sender, recipient, amount, and more.
- Utilities for message format validation and dynamic field extraction.
- Designed for use in Starknet smart contracts and CCTP integrations.

## Usage

Import the relevant modules and use the provided functions to construct or validate CCTP messages within your Cairo contracts.
