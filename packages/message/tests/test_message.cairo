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

use core::byte_array::ByteArrayTrait;
use message::Message;

fn get_test_data() -> (u32, u32, u32, u256, u256, u256, u32, ByteArray) {
    let version = 0_u32;
    let source_domain = 1_u32;
    let destination_domain = 2_u32;
    let sender = 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefab_u256;
    let recipient = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321_u256;
    let destination_caller = 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefab_u256;
    let min_finality_threshold = 1_u32;
    let mut message_body: ByteArray = Default::default();
    message_body.append_byte(0x12);
    message_body.append_byte(0x34);
    message_body.append_byte(0x56);

    (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    )
}

#[test]
fn test_format_message_for_relay_basic() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    // Message should have correct minimum length: 151 bytes (fixed fields) + message body length
    assert!(message.len() == 151_usize);
}

#[test]
fn test_all_fields() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body.clone(),
    );

    // Test all getter functions
    assert_eq!(Message::get_version(@message), version);
    assert_eq!(Message::get_source_domain(@message), source_domain);
    assert_eq!(Message::get_destination_domain(@message), destination_domain);
    assert_eq!(Message::get_sender(@message), sender);
    assert_eq!(Message::get_recipient(@message), recipient);
    assert_eq!(Message::get_destination_caller(@message), destination_caller);
    assert_eq!(Message::get_min_finality_threshold(@message), min_finality_threshold);

    // Test message body extraction
    let extracted_message_body = Message::get_message_body(@message);
    assert_eq!(extracted_message_body.len(), message_body.len());
    assert_eq!(extracted_message_body.at(0).unwrap(), 0x12);
    assert_eq!(extracted_message_body.at(1).unwrap(), 0x34);
    assert_eq!(extracted_message_body.at(2).unwrap(), 0x56);
}

#[test]
fn test_empty_message_body() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        _,
    ) =
        get_test_data();
    let empty_message_body: ByteArray = Default::default();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        empty_message_body,
    );

    // Message should have correct length: 148 bytes (no message body)
    assert_eq!(message.len(), 148_usize);

    // Test message body extraction
    let extracted_message_body = Message::get_message_body(@message);
    assert_eq!(extracted_message_body.len(), 0);
}

#[test]
fn test_large_message_body() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        _,
    ) =
        get_test_data();

    // Create large message body (100 bytes)
    let mut large_message_body: ByteArray = Default::default();
    let mut i: u8 = 0;
    while i != 100 {
        large_message_body.append_byte(i);
        i += 1;
    }

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        large_message_body,
    );

    // verify all fields are correct
    assert_eq!(Message::get_version(@message), version);
    assert_eq!(Message::get_source_domain(@message), source_domain);
    assert_eq!(Message::get_destination_domain(@message), destination_domain);
    assert_eq!(Message::get_sender(@message), sender);
    assert_eq!(Message::get_recipient(@message), recipient);
    assert_eq!(Message::get_destination_caller(@message), destination_caller);
    assert_eq!(Message::get_min_finality_threshold(@message), min_finality_threshold);

    // Message should have correct length: 148 bytes (fixed fields) + 100 bytes message body
    assert_eq!(message.len(), 248_usize);

    // Test message body extraction
    let extracted_message_body = Message::get_message_body(@message);
    assert_eq!(extracted_message_body.len(), 100);

    // Verify message body content
    let mut j: u32 = 0;
    while j != 100 {
        assert_eq!(extracted_message_body.at(j).unwrap(), j.try_into().unwrap());
        j += 1;
    }
}

#[test]
fn test_zero_values() {
    let version = 0_u32;
    let source_domain = 0_u32;
    let destination_domain = 0_u32;
    let sender = 0_u256;
    let recipient = 0_u256;
    let destination_caller = 0_u256;
    let min_finality_threshold = 0_u32;
    let message_body: ByteArray = Default::default();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    assert_eq!(Message::get_version(@message), version);
    assert_eq!(Message::get_source_domain(@message), source_domain);
    assert_eq!(Message::get_destination_domain(@message), destination_domain);
    assert_eq!(Message::get_sender(@message), sender);
    assert_eq!(Message::get_recipient(@message), recipient);
    assert_eq!(Message::get_destination_caller(@message), destination_caller);
    assert_eq!(Message::get_min_finality_threshold(@message), min_finality_threshold);
    assert_eq!(Message::get_message_body(@message).len(), 0);
}

#[test]
fn test_max_values() {
    let version = 0xFFFFFFFF_u32;
    let source_domain = 0xFFFFFFFF_u32;
    let destination_domain = 0xFFFFFFFF_u32;
    let sender = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let recipient = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let destination_caller =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256;
    let min_finality_threshold = 0xFFFFFFFF_u32;
    let message_body: ByteArray = Default::default();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    assert_eq!(Message::get_version(@message), version);
    assert_eq!(Message::get_source_domain(@message), source_domain);
    assert_eq!(Message::get_destination_domain(@message), destination_domain);
    assert_eq!(Message::get_sender(@message), sender);
    assert_eq!(Message::get_recipient(@message), recipient);
    assert_eq!(Message::get_destination_caller(@message), destination_caller);
    assert_eq!(Message::get_min_finality_threshold(@message), min_finality_threshold);
    assert_eq!(Message::get_message_body(@message).len(), 0);
}

#[test]
fn test_validate_message_format_valid() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    // Should not panic for valid message
    Message::validate_message_format(@message);
}

#[test]
fn test_validate_message_format_minimum_length() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        _,
    ) =
        get_test_data();
    let empty_message_body: ByteArray = Default::default();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        empty_message_body,
    );

    // Should not panic for minimum valid length (148 bytes)
    Message::validate_message_format(@message);
}

#[test]
#[should_panic(expected: ('Invalid message: too short',))]
fn test_validate_message_format_too_short() {
    let mut short_message: ByteArray = Default::default();
    let mut i: u32 = 0;
    while i != 100 { // Only 100 bytes, should be at least 148
        short_message.append_byte(0);
        i += 1;
    }

    // Should panic for message body length < 148
    Message::validate_message_format(@short_message);
}

#[test]
#[should_panic(expected: ('Byte array too short',))]
fn test_get_message_body_too_short() {
    let mut short_message: ByteArray = Default::default();
    let mut i: u32 = 0;
    while i != 100 { // Only 100 bytes, should be at least 148
        short_message.append_byte(0);
        i += 1;
    }

    Message::get_message_body(@short_message);
}

#[test]
fn test_message_structure_consistency() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    // Test that extracting and reformatting produces the same result
    let extracted_version = Message::get_version(@message);
    let extracted_source_domain = Message::get_source_domain(@message);
    let extracted_destination_domain = Message::get_destination_domain(@message);
    let extracted_sender = Message::get_sender(@message);
    let extracted_recipient = Message::get_recipient(@message);
    let extracted_destination_caller = Message::get_destination_caller(@message);
    let extracted_min_finality_threshold = Message::get_min_finality_threshold(@message);
    let extracted_message_body = Message::get_message_body(@message);

    let rebuilt_message = Message::format_message(
        extracted_version,
        extracted_source_domain,
        extracted_destination_domain,
        extracted_sender,
        extracted_recipient,
        extracted_destination_caller,
        extracted_min_finality_threshold,
        extracted_message_body,
    );

    // Messages should be identical
    assert_eq!(message.len(), rebuilt_message.len());

    let mut i: u32 = 0;
    while i != message.len().into() {
        assert_eq!(message.at(i).unwrap(), rebuilt_message.at(i).unwrap());
        i += 1;
    }
}

#[test]
fn test_field_independence() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    // Test that changing one field doesn't affect others
    let modified_version = version + 1;
    let message = Message::format_message(
        modified_version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    // Only version should be different
    assert_eq!(Message::get_version(@message), modified_version);
    assert_eq!(Message::get_source_domain(@message), source_domain);
    assert_eq!(Message::get_destination_domain(@message), destination_domain);
    assert_eq!(Message::get_sender(@message), sender);
    assert_eq!(Message::get_recipient(@message), recipient);
    assert_eq!(Message::get_destination_caller(@message), destination_caller);
}

#[test]
fn test_message_body_with_zero_bytes() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        _,
    ) =
        get_test_data();

    let mut message_body: ByteArray = Default::default();
    message_body.append_byte(0x00);
    message_body.append_byte(0xFF);
    message_body.append_byte(0x00);
    message_body.append_byte(0xAA);
    message_body.append_byte(0x00);

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    // Test message body extraction
    let extracted_message_body = Message::get_message_body(@message);
    assert_eq!(extracted_message_body.len(), 5);
    assert_eq!(extracted_message_body.at(0).unwrap(), 0x00);
    assert_eq!(extracted_message_body.at(1).unwrap(), 0xFF);
    assert_eq!(extracted_message_body.at(2).unwrap(), 0x00);
    assert_eq!(extracted_message_body.at(3).unwrap(), 0xAA);
    assert_eq!(extracted_message_body.at(4).unwrap(), 0x00);
}

#[test]
fn test_different_message_body_sizes() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        _,
    ) =
        get_test_data();

    let sizes = array![0, 1, 10, 32, 100, 255];
    let mut size_index = 0;

    while size_index != sizes.len() {
        let size = *sizes.at(size_index);
        let mut message_body: ByteArray = Default::default();
        let mut i: u32 = 0;
        while i != size {
            message_body.append_byte((i % 256).try_into().unwrap());
            i += 1;
        }
        let message = Message::format_message(
            version,
            source_domain,
            destination_domain,
            sender,
            recipient,
            destination_caller,
            min_finality_threshold,
            message_body,
        );

        let extracted_message_body = Message::get_message_body(@message);
        assert_eq!(extracted_message_body.len(), size.into());

        let mut j: u32 = 0;
        while j != size {
            assert_eq!(extracted_message_body.at(j).unwrap(), (j % 256).try_into().unwrap());
            j += 1;
        }

        size_index += 1;
    }
}

#[test]
fn test_nonce_always_zero() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    assert_eq!(Message::get_nonce(@message), 0_u256);
}

#[test]
fn test_finality_threshold_executed_always_zero() {
    let (
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    ) =
        get_test_data();

    let message = Message::format_message(
        version,
        source_domain,
        destination_domain,
        sender,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
    );

    assert_eq!(Message::get_finality_threshold_executed(@message), 0_u32);
}
#[test]
#[cairofmt::skip]
fn test_with_real_message_data() {
    // Message from Sonic txHash: 0xc05fbd5c4a86902c4ee8d28a09a745d8e57361df7271de2d88157e205ceb04e0
    let data = array![
        // version
        0, 0, 0, 1,
        // source_domain
        0, 0, 0, 13,
        // destination_domain
        0, 0, 0, 2,
        // nonce
        187, 97, 196, 135, 192, 3, 72, 149, 190, 246, 120, 69, 230, 242, 100, 247,
        27, 44, 54, 208, 145, 63, 108, 165, 188, 122, 204, 31, 84, 157, 233, 150,
        // sender
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 181, 160, 233,
        198, 33, 165, 186, 218, 165, 54, 33, 155, 58, 34, 140, 129, 104, 207, 93,
        // recipient
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 181, 160, 233,
        198, 33, 165, 186, 218, 165, 54, 33, 155, 58, 34, 140, 129, 104, 207, 93,
        // destination_caller
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 176, 67, 132,
        12, 210, 243, 38, 135, 236, 107, 99, 251, 4, 18, 88, 93, 227, 152, 34,
        // min_finality_threshold
        0, 0, 3, 232,
        // finality_threshold_executed
        0, 0, 0, 0,
        // message_body
        0, 0, 0, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41, 33, 157, 212, 0, 242, 191,
        96, 229, 162, 61, 19, 190, 114, 180, 134, 212, 3, 136, 148,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 176, 67, 132, 12, 210, 243,
        38, 135, 236, 107, 99, 251, 4, 18, 88, 93, 227, 152, 34,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 53, 165, 55, 32,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 176, 67, 132, 12, 210, 243,
        38, 135, 236, 107, 99, 251, 4, 18, 88, 93, 227, 152, 34,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
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
    let mut i = 0;
    while i != data.len() {
        message.append_byte(*data.at(i));
        i += 1;
    }
    Message::validate_message_format(@message);
    let message_body = Message::get_message_body(@message);
    let version = Message::get_version(@message);
    let source_domain = Message::get_source_domain(@message);
    let destination_domain = Message::get_destination_domain(@message);
    let nonce = Message::get_nonce(@message);
    let sender = Message::get_sender(@message);
    let recipient = Message::get_recipient(@message);
    let destination_caller = Message::get_destination_caller(@message);
    let min_finality_threshold = Message::get_min_finality_threshold(@message);

    assert_eq!(version, 1);
    assert_eq!(source_domain, 13);
    assert_eq!(destination_domain, 2);
    assert_eq!(nonce, 0xbb61c487c0034895bef67845e6f264f71b2c36d0913f6ca5bc7acc1f549de996);
    assert_eq!(sender, 0x28b5a0e9c621a5badaa536219b3a228c8168cf5d);
    assert_eq!(recipient, 0x28b5a0e9c621a5badaa536219b3a228c8168cf5d);
    assert_eq!(destination_caller, 0x09b043840Cd2F32687eC6b63FB0412585DE39822);
    assert_eq!(min_finality_threshold, 1000);
    assert_eq!(message_body.len(), 388);
}
