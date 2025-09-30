// Copyright (c) 2025, Circle Internet Financial LTD. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! BurnMessage Library
//!
//! Library for formatted BurnMessages used by TokenMessenger.
//!
//! # BurnMessage format:
//!
//! | Field           | Bytes   | Type     | Index |
//! |-----------------|---------|----------|-------|
//! | version         | 4       | uint32   | 0     |
//! | burnToken       | 32      | bytes32  | 4     |
//! | mintRecipient   | 32      | bytes32  | 36    |
//! | amount          | 32      | uint256  | 68    |
//! | messageSender   | 32      | bytes32  | 100   |
//! | maxFee          | 32      | uint256  | 132   |
//! | feeExecuted     | 32      | uint256  | 164   |
//! | expirationBlock | 32      | uint256  | 196   |
//! | hookData        | dynamic | bytes    | 228   |
//!
//! # Fields include:
//! - maxFee
//! - feeExecuted
//! - expirationBlock
//! - hookData
pub mod BurnMessageV2 {
    use core::byte_array::ByteArrayTrait;
    use utils::{
        append_u256_be, append_u32_be, append_zero_u256, extract_bytes_array_dynamic,
        extract_u256_be, extract_u32_be,
    };

    // Field indices
    pub const VERSION_INDEX: usize = 0;
    pub const BURN_TOKEN_INDEX: usize = 4;
    pub const MINT_RECIPIENT_INDEX: usize = 36;
    pub const AMOUNT_INDEX: usize = 68;
    pub const MESSAGE_SENDER_INDEX: usize = 100;
    pub const MAX_FEE_INDEX: usize = 132;
    pub const FEE_EXECUTED_INDEX: usize = 164;
    pub const EXPIRATION_BLOCK_INDEX: usize = 196;
    pub const HOOK_DATA_INDEX: usize = 228;

    pub const EMPTY_FEE_EXECUTED: u256 = 0;
    pub const EMPTY_EXPIRATION_BLOCK: u256 = 0;

    pub mod Errors {
        pub const INVALID_BURN_MESSAGE_TOO_SHORT: felt252 = 'Invalid burn message: too short';
    }

    /// Formats a burn message
    ///
    /// # Arguments
    ///
    /// * `version` - The message body version
    /// * `burn_token` - The burn token address on the source domain, as bytes32
    /// * `mint_recipient` - The mint recipient address as bytes32
    /// * `amount` - The burn amount
    /// * `message_sender` - The message sender
    /// * `max_fee` - The maximum fee to be paid on destination domain
    /// * `hook_data` - Optional hook data for processing on the destination domain.
    ///   NOTE: This field is treated as an opaque byte array and is NOT subject to endianness
    ///   conversion. Integrators must ensure consistent encoding/decoding across chains,
    ///   especially when bridging between Starknet (little-endian) and other chains (typically
    ///   big-endian)
    ///
    /// # Returns
    ///
    /// Formatted message bytes.
    pub fn format_message_for_relay(
        version: u32,
        burn_token: u256,
        mint_recipient: u256,
        amount: u256,
        message_sender: u256,
        max_fee: u256,
        hook_data: ByteArray,
    ) -> ByteArray {
        let mut message: ByteArray = Default::default();

        // Append version (4 bytes, u32)
        append_u32_be(ref message, version);

        // Append burn_token (32 bytes, u256)
        append_u256_be(ref message, burn_token);

        // Append mint_recipient (32 bytes, u256)
        append_u256_be(ref message, mint_recipient);

        // Append amount (32 bytes, u256)
        append_u256_be(ref message, amount);

        // Append message_sender (32 bytes, u256)
        append_u256_be(ref message, message_sender);

        // Append max_fee (32 bytes, u256)
        append_u256_be(ref message, max_fee);

        // Append fee_executed (32 bytes, u256) - empty/zero (optimized)
        append_zero_u256(ref message);

        // Append expiration_block (32 bytes, u256) - empty/zero (optimized)
        append_zero_u256(ref message);

        // Append hook_data (dynamic bytes)
        // Note: hook_data is appended as-is without endianness conversion
        // Integrators must handle endianness consistency across chains
        message.append(@hook_data);

        message
    }

    /// Returns message's version field
    pub fn get_version(message: @ByteArray) -> u32 {
        extract_u32_be(message, VERSION_INDEX)
    }

    /// Returns message's burnToken field
    pub fn get_burn_token(message: @ByteArray) -> u256 {
        extract_u256_be(message, BURN_TOKEN_INDEX)
    }

    /// Returns message's mintRecipient field
    pub fn get_mint_recipient(message: @ByteArray) -> u256 {
        extract_u256_be(message, MINT_RECIPIENT_INDEX)
    }

    /// Returns message's amount field
    pub fn get_amount(message: @ByteArray) -> u256 {
        extract_u256_be(message, AMOUNT_INDEX)
    }

    /// Returns message's messageSender field
    pub fn get_message_sender(message: @ByteArray) -> u256 {
        extract_u256_be(message, MESSAGE_SENDER_INDEX)
    }

    /// Returns message's maxFee field
    pub fn get_max_fee(message: @ByteArray) -> u256 {
        extract_u256_be(message, MAX_FEE_INDEX)
    }

    /// Returns message's feeExecuted field
    pub fn get_fee_executed(message: @ByteArray) -> u256 {
        extract_u256_be(message, FEE_EXECUTED_INDEX)
    }

    /// Returns message's expirationBlock field
    pub fn get_expiration_block(message: @ByteArray) -> u256 {
        extract_u256_be(message, EXPIRATION_BLOCK_INDEX)
    }

    /// Returns message's hookData field
    pub fn get_hook_data(message: @ByteArray) -> ByteArray {
        extract_bytes_array_dynamic(message, HOOK_DATA_INDEX)
    }

    /// Reverts if burn message is malformed or invalid length
    ///
    /// # Arguments
    ///
    /// * `message` - The burn message as ByteArray
    pub fn validate_burn_message_format(message: @ByteArray) {
        let message_len = message.len();
        assert(message_len >= HOOK_DATA_INDEX, Errors::INVALID_BURN_MESSAGE_TOO_SHORT);
    }
}
