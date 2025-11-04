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

use core::byte_array::ByteArrayTrait;
use message::BurnMessageV2;

fn get_test_data() -> (u32, u256, u256, u256, u256, u256, ByteArray) {
    let version = 2_u32;
    let burn_token = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef_u256;
    let mint_recipient = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321_u256;
    let amount = 1000000_u256;
    let message_sender = 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefab_u256;
    let max_fee = 50000_u256;
    let mut hook_data: ByteArray = Default::default();
    hook_data.append_byte(0x12);
    hook_data.append_byte(0x34);
    hook_data.append_byte(0x56);

    (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data)
}

#[test]
fn test_format_message_for_relay_basic() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // Message should have correct minimum length: 228 bytes (fixed fields) + hook data length
    let expected_min_length = 228_usize + 3; // 3 bytes of hook data
    assert!(message.len() >= expected_min_length);
}

#[test]
fn test_round_trip_all_fields() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // Test all getter functions
    assert_eq!(BurnMessageV2::get_version(@message), version);
    assert_eq!(BurnMessageV2::get_burn_token(@message), burn_token);
    assert_eq!(BurnMessageV2::get_mint_recipient(@message), mint_recipient);
    assert_eq!(BurnMessageV2::get_amount(@message), amount);
    assert_eq!(BurnMessageV2::get_message_sender(@message), message_sender);
    assert_eq!(BurnMessageV2::get_max_fee(@message), max_fee);

    // fee_executed and expiration_block should be zero (empty values)
    assert_eq!(BurnMessageV2::get_fee_executed(@message), 0);
    assert_eq!(BurnMessageV2::get_expiration_block(@message), 0);

    // Test hook data extraction
    let extracted_hook_data = BurnMessageV2::get_hook_data(@message);
    assert_eq!(extracted_hook_data.len(), hook_data.len());
    assert_eq!(extracted_hook_data.at(0).unwrap(), 0x12);
    assert_eq!(extracted_hook_data.at(1).unwrap(), 0x34);
    assert_eq!(extracted_hook_data.at(2).unwrap(), 0x56);
}

#[test]
fn test_empty_hook_data() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, _) = get_test_data();
    let empty_hook_data: ByteArray = Default::default();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @empty_hook_data,
    );

    // Message should have exactly 228 bytes (no hook data)
    assert_eq!(message.len(), 228);

    let extracted_hook_data = BurnMessageV2::get_hook_data(@message);
    assert_eq!(extracted_hook_data.len(), 0);
}

#[test]
fn test_large_hook_data() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, _) = get_test_data();

    // Create large hook data (100 bytes)
    let mut large_hook_data: ByteArray = Default::default();
    let mut i: u8 = 0;
    while i != 100 {
        large_hook_data.append_byte(i);
        i += 1;
    }

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @large_hook_data,
    );

    // Verify all fields are correct
    assert_eq!(BurnMessageV2::get_version(@message), version);
    assert_eq!(BurnMessageV2::get_burn_token(@message), burn_token);
    assert_eq!(BurnMessageV2::get_mint_recipient(@message), mint_recipient);
    assert_eq!(BurnMessageV2::get_amount(@message), amount);
    assert_eq!(BurnMessageV2::get_message_sender(@message), message_sender);
    assert_eq!(BurnMessageV2::get_max_fee(@message), max_fee);

    let extracted_hook_data = BurnMessageV2::get_hook_data(@message);
    assert_eq!(extracted_hook_data.len(), 100);

    // Verify hook data content
    let mut j: u32 = 0;
    while j != 100 {
        assert_eq!(extracted_hook_data.at(j).unwrap(), j.try_into().unwrap());
        j += 1;
    }
}

#[test]
fn test_edge_values() {
    // Test with edge values (zeros and max values)
    let version = 0_u32;
    let burn_token = 0_u256;
    let mint_recipient = 0_u256;
    let amount = 0_u256;
    let message_sender = 0_u256;
    let max_fee = 0_u256;
    let hook_data: ByteArray = Default::default();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    assert_eq!(BurnMessageV2::get_version(@message), 0);
    assert_eq!(BurnMessageV2::get_burn_token(@message), 0);
    assert_eq!(BurnMessageV2::get_mint_recipient(@message), 0);
    assert_eq!(BurnMessageV2::get_amount(@message), 0);
    assert_eq!(BurnMessageV2::get_message_sender(@message), 0);
    assert_eq!(BurnMessageV2::get_max_fee(@message), 0);
}

#[test]
fn test_max_values() {
    // Test with maximum values
    let version = 0xFFFFFFFF_u32;
    let burn_token = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let mint_recipient = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let amount = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let message_sender = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let max_fee = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let hook_data: ByteArray = Default::default();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    assert_eq!(BurnMessageV2::get_version(@message), version);
    assert_eq!(BurnMessageV2::get_burn_token(@message), burn_token);
    assert_eq!(BurnMessageV2::get_mint_recipient(@message), mint_recipient);
    assert_eq!(BurnMessageV2::get_amount(@message), amount);
    assert_eq!(BurnMessageV2::get_message_sender(@message), message_sender);
    assert_eq!(BurnMessageV2::get_max_fee(@message), max_fee);
}

#[test]
fn test_validate_burn_message_format_valid() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // Should not panic for valid message
    BurnMessageV2::validate_burn_message_format(@message);
}

#[test]
fn test_validate_burn_message_format_minimum_length() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, _) = get_test_data();
    let empty_hook_data: ByteArray = Default::default();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @empty_hook_data,
    );

    // Should not panic for minimum valid length (228 bytes)
    BurnMessageV2::validate_burn_message_format(@message);
}

#[test]
#[should_panic(expected: ('Invalid burn message: too short',))]
fn test_validate_burn_message_format_too_short() {
    // Create a message that's too short (less than 228 bytes)
    let mut short_message: ByteArray = Default::default();
    let mut i: u32 = 0;
    while i != 100 { // Only 100 bytes, should be at least 228
        short_message.append_byte(0);
        i += 1;
    }

    BurnMessageV2::validate_burn_message_format(@short_message);
}

#[test]
#[should_panic(expected: ('Byte array too short',))]
fn test_get_hook_data_too_short() {
    // Create a message that's too short
    let mut short_message: ByteArray = Default::default();
    let mut i: u32 = 0;
    while i != 200 { // Less than HOOK_DATA_INDEX (228)
        short_message.append_byte(0);
        i += 1;
    }

    BurnMessageV2::get_hook_data(@short_message);
}

#[test]
fn test_message_structure_consistency() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // Test that extracting and reformatting produces the same result
    let extracted_version = BurnMessageV2::get_version(@message);
    let extracted_burn_token = BurnMessageV2::get_burn_token(@message);
    let extracted_mint_recipient = BurnMessageV2::get_mint_recipient(@message);
    let extracted_amount = BurnMessageV2::get_amount(@message);
    let extracted_message_sender = BurnMessageV2::get_message_sender(@message);
    let extracted_max_fee = BurnMessageV2::get_max_fee(@message);
    let extracted_hook_data = BurnMessageV2::get_hook_data(@message);

    let rebuilt_message = BurnMessageV2::format_message_for_relay(
        extracted_version,
        extracted_burn_token,
        extracted_mint_recipient,
        extracted_amount,
        extracted_message_sender,
        extracted_max_fee,
        @extracted_hook_data,
    );

    // Messages should be identical
    assert_eq!(message.len(), rebuilt_message.len());

    let mut i: u32 = 0;
    while i != message.len() {
        assert_eq!(message.at(i).unwrap(), rebuilt_message.at(i).unwrap());
        i += 1;
    }
}

#[test]
fn test_field_independence() {
    // Test that changing one field doesn't affect others
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    // Create message with modified version
    let modified_version = version + 1;
    let message = BurnMessageV2::format_message_for_relay(
        modified_version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // Only version should be different
    assert_eq!(BurnMessageV2::get_version(@message), modified_version);
    assert_eq!(BurnMessageV2::get_burn_token(@message), burn_token);
    assert_eq!(BurnMessageV2::get_mint_recipient(@message), mint_recipient);
    assert_eq!(BurnMessageV2::get_amount(@message), amount);
    assert_eq!(BurnMessageV2::get_message_sender(@message), message_sender);
    assert_eq!(BurnMessageV2::get_max_fee(@message), max_fee);
}

#[test]
fn test_fee_executed_always_zero() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // fee_executed should always be zero in formatted messages
    assert_eq!(BurnMessageV2::get_fee_executed(@message), 0);
}

#[test]
fn test_expiration_block_always_zero() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, hook_data) =
        get_test_data();

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    // expiration_block should always be zero in formatted messages
    assert_eq!(BurnMessageV2::get_expiration_block(@message), 0);
}

#[test]
fn test_hook_data_with_zero_bytes() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, _) = get_test_data();

    // Create hook data with zero bytes mixed in
    let mut hook_data: ByteArray = Default::default();
    hook_data.append_byte(0x00);
    hook_data.append_byte(0xFF);
    hook_data.append_byte(0x00);
    hook_data.append_byte(0xAA);
    hook_data.append_byte(0x00);

    let message = BurnMessageV2::format_message_for_relay(
        version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
    );

    let extracted_hook_data = BurnMessageV2::get_hook_data(@message);
    assert_eq!(extracted_hook_data.len(), 5);
    assert_eq!(extracted_hook_data.at(0).unwrap(), 0x00);
    assert_eq!(extracted_hook_data.at(1).unwrap(), 0xFF);
    assert_eq!(extracted_hook_data.at(2).unwrap(), 0x00);
    assert_eq!(extracted_hook_data.at(3).unwrap(), 0xAA);
    assert_eq!(extracted_hook_data.at(4).unwrap(), 0x00);
}

#[test]
fn test_different_hook_data_sizes() {
    let (version, burn_token, mint_recipient, amount, message_sender, max_fee, _) = get_test_data();

    // Test various hook data sizes
    let sizes = array![0, 1, 10, 32, 100, 255];
    let mut size_index = 0;

    while size_index != sizes.len() {
        let size = *sizes.at(size_index);
        let mut hook_data: ByteArray = Default::default();

        let mut i: u32 = 0;
        while i != size {
            hook_data.append_byte((i % 256).try_into().unwrap());
            i += 1;
        }

        let message = BurnMessageV2::format_message_for_relay(
            version, burn_token, mint_recipient, amount, message_sender, max_fee, @hook_data,
        );

        let extracted_hook_data = BurnMessageV2::get_hook_data(@message);
        assert_eq!(extracted_hook_data.len(), size);

        // Verify correct extraction of all hook data
        let mut j: u32 = 0;
        while j != size {
            assert_eq!(extracted_hook_data.at(j).unwrap(), (j % 256).try_into().unwrap());
            j += 1;
        }

        size_index += 1;
    }
}
#[test]
#[cairofmt::skip]
fn test_with_real_burn_message() {
    // Burn Message from Sonic txHash:
    // 0xc05fbd5c4a86902c4ee8d28a09a745d8e57361df7271de2d88157e205ceb04e0
    let data = array![
        // version
        0, 0, 0, 1,
        // burn_token
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41, 33, 157, 212, 0, 242, 191,
        96, 229, 162, 61, 19, 190, 114, 180, 134, 212, 3, 136, 148,
        // mintRecipient
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 176, 67, 132, 12, 210, 243,
        38, 135, 236, 107, 99, 251, 4, 18, 88, 93, 227, 152, 34,
        // amount
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 53, 165, 55, 32,
        // message_sender
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 176, 67, 132, 12, 210, 243,
        38, 135, 236, 107, 99, 251, 4, 18, 88, 93, 227, 152, 34,
        // max_fee
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        // fee_executed
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        // expiration_block
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        // hook_data
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 53, 165, 55, 32, 33,
        117, 169, 251, 110, 36, 228, 30, 255, 204, 230, 30, 146, 142, 92, 159, 229,
        179, 219, 75, 3, 104, 167, 119, 150, 221, 89, 247, 22, 17, 203, 3, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 174, 104, 183, 17,
        123, 224, 2, 108, 189, 67, 102, 48, 63, 116, 238, 203, 177, 158, 64, 66,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 53, 164, 245, 87,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 104, 112, 69, 109,
    ];

    let mut message: ByteArray = Default::default();
    let mut i: u32 = 0;
    while i != data.len() {
        message.append_byte(*data.at(i));
        i += 1;
    }

    BurnMessageV2::validate_burn_message_format(@message);

    let version = BurnMessageV2::get_version(@message);
    let burn_token = BurnMessageV2::get_burn_token(@message);
    let mint_recipient = BurnMessageV2::get_mint_recipient(@message);
    let amount = BurnMessageV2::get_amount(@message);
    let message_sender = BurnMessageV2::get_message_sender(@message);
    let max_fee = BurnMessageV2::get_max_fee(@message);
    let fee_executed = BurnMessageV2::get_fee_executed(@message);
    let expiration_block = BurnMessageV2::get_expiration_block(@message);
    let hook_data = BurnMessageV2::get_hook_data(@message);

    assert_eq!(version, 1);
    assert_eq!(burn_token, 0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    assert_eq!(mint_recipient, 0x00000000000000000000000009B043840CD2F32687EC6B63FB0412585DE39822);
    assert_eq!(amount, 900020000);
    assert_eq!(message_sender, 0x09b043840Cd2F32687eC6b63FB0412585DE39822);
    assert_eq!(max_fee, 1);
    assert_eq!(fee_executed, 0);
    assert_eq!(expiration_block, 0);
    assert_eq!(hook_data.len(), 160);
}
