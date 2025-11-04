// Copyright (c) 2025 Circle Internet Group, Inc. All rights reserved.
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

//! Message Library
//!
//! Library for formatted Messages used by Relayer and Receiver.
//!
//! # Message format:
//!
//! | Field                     | Bytes   | Type     | Index |
//! |---------------------------|---------|----------|-------|
//! | version                   | 4       | uint32   | 0     |
//! | sourceDomain              | 4       | uint32   | 4     |
//! | destinationDomain         | 4       | uint32   | 8     |
//! | nonce                     | 32      | bytes32  | 12    |
//! | sender                    | 32      | bytes32  | 44    |
//! | recipient                 | 32      | bytes32  | 76    |
//! | destinationCaller         | 32      | bytes32  | 108   |
//! | minFinalityThreshold      | 4       | uint32   | 140   |
//! | finalityThresholdExecuted | 4       | uint32   | 144   |
//! | messageBody               | dynamic | bytes    | 148   |

pub mod MessageV2 {
    use core::byte_array::ByteArrayTrait;
    use utils::{
        append_u256_be, append_u32_be, append_zero_u256, extract_bytes_array_dynamic,
        extract_u256_be, extract_u32_be,
    };

    // Field indices
    pub const VERSION_INDEX: usize = 0;
    pub const SOURCE_DOMAIN_INDEX: usize = 4;
    pub const DESTINATION_DOMAIN_INDEX: usize = 8;
    pub const NONCE_INDEX: usize = 12;
    pub const SENDER_INDEX: usize = 44;
    pub const RECIPIENT_INDEX: usize = 76;
    pub const DESTINATION_CALLER_INDEX: usize = 108;
    pub const MIN_FINALITY_THRESHOLD_INDEX: usize = 140;
    pub const FINALITY_THRESHOLD_EXECUTED_INDEX: usize = 144;
    pub const MESSAGE_BODY_INDEX: usize = 148;

    pub const EMPTY_FINALITY_THRESHOLD_EXECUTED: u32 = 0;


    pub mod Errors {
        pub const INVALID_MESSAGE_TOO_SHORT: felt252 = 'Invalid message: too short';
    }

    /// Formats a message
    ///
    /// # Arguments
    ///
    /// * `version` - The message body version
    /// * `source_domain` - The source domain
    /// * `destination_domain` - The destination domain
    /// * `sender` - The sender
    /// * `recipient` - The recipient
    /// * `destination_caller` - The destination caller
    /// * `min_finality_threshold` - The minimum finality threshold
    /// * `message_body` - The message body
    ///
    /// # Returns
    ///
    /// The formatted message bytes
    pub fn format_message(
        version: u32,
        source_domain: u32,
        destination_domain: u32,
        sender: u256,
        recipient: u256,
        destination_caller: u256,
        min_finality_threshold: u32,
        message_body: @ByteArray,
    ) -> ByteArray {
        let mut message: ByteArray = Default::default();

        // Append version (4 bytes, u32)
        append_u32_be(ref message, version);

        // Append source_domain (4 bytes, u32)
        append_u32_be(ref message, source_domain);

        // Append destination_domain (4 bytes, u32)
        append_u32_be(ref message, destination_domain);

        // Append nonce (32 bytes, u256) - empty/zero
        append_zero_u256(ref message);

        // Append sender (32 bytes, u256)
        append_u256_be(ref message, sender);

        // Append recipient (32 bytes, u256)
        append_u256_be(ref message, recipient);

        // Append destination_caller (32 bytes, u256)
        append_u256_be(ref message, destination_caller);

        // Append min_finality_threshold (4 bytes, u32)
        append_u32_be(ref message, min_finality_threshold);

        // Append finality_threshold_executed (4 bytes, u32)
        append_u32_be(ref message, EMPTY_FINALITY_THRESHOLD_EXECUTED);

        // Append message_body (dynamic, bytes)
        message.append(message_body);

        message
    }

    /// Reverts if message is malformed or too short
    ///
    /// # Arguments
    ///
    /// * `message` - The message as ByteArray
    pub fn validate_message_format(message: @ByteArray) {
        assert(message.len() >= MESSAGE_BODY_INDEX, Errors::INVALID_MESSAGE_TOO_SHORT);
    }


    /// Returns message's version field
    pub fn get_version(message: @ByteArray) -> u32 {
        extract_u32_be(message, VERSION_INDEX)
    }

    /// Returns message's source domain field
    pub fn get_source_domain(message: @ByteArray) -> u32 {
        extract_u32_be(message, SOURCE_DOMAIN_INDEX)
    }

    /// Returns message's destination domain field
    pub fn get_destination_domain(message: @ByteArray) -> u32 {
        extract_u32_be(message, DESTINATION_DOMAIN_INDEX)
    }

    /// Returns message's nonce field
    pub fn get_nonce(message: @ByteArray) -> u256 {
        extract_u256_be(message, NONCE_INDEX)
    }

    /// Returns message's sender field
    pub fn get_sender(message: @ByteArray) -> u256 {
        extract_u256_be(message, SENDER_INDEX)
    }

    /// Returns message's recipient field
    pub fn get_recipient(message: @ByteArray) -> u256 {
        extract_u256_be(message, RECIPIENT_INDEX)
    }

    /// Returns message's destination caller field
    pub fn get_destination_caller(message: @ByteArray) -> u256 {
        extract_u256_be(message, DESTINATION_CALLER_INDEX)
    }

    /// Returns message's min finality threshold field
    pub fn get_min_finality_threshold(message: @ByteArray) -> u32 {
        extract_u32_be(message, MIN_FINALITY_THRESHOLD_INDEX)
    }

    /// Returns message's finality threshold executed field
    pub fn get_finality_threshold_executed(message: @ByteArray) -> u32 {
        extract_u32_be(message, FINALITY_THRESHOLD_EXECUTED_INDEX)
    }

    /// Returns message's message body field
    pub fn get_message_body(message: @ByteArray) -> ByteArray {
        extract_bytes_array_dynamic(message, MESSAGE_BODY_INDEX)
    }
}
