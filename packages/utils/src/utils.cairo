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

use core::panic_with_felt252;
pub mod Errors {
    pub const BYTE_ARRAY_TOO_SHORT: felt252 = 'Byte array too short';
    pub const EXTRACT_U32_BE_OOB: felt252 = 'extract_u32_be OOB';
    pub const EXTRACT_U256_BE_OOB: felt252 = 'extract_u256_be OOB';
}

// Helper functions for big-endian encoding/decoding

/// Append 32 zero bytes efficiently (optimized for fee_executed and expiration_block)
pub fn append_zero_u256(ref byte_array: ByteArray) {
    let mut i: u32 = 0;
    while i != 32 {
        byte_array.append_byte(0);
        i += 1;
    };
}

/// Append u32 as big-endian bytes to ByteArray
pub fn append_u32_be(ref byte_array: ByteArray, value: u32) {
    byte_array.append_byte(((value / 0x1000000) & 0xFF).try_into().unwrap());
    byte_array.append_byte(((value / 0x10000) & 0xFF).try_into().unwrap());
    byte_array.append_byte(((value / 0x100) & 0xFF).try_into().unwrap());
    byte_array.append_byte((value & 0xFF).try_into().unwrap());
}

/// Append u256 as big-endian bytes (32 bytes) to ByteArray
pub fn append_u256_be(ref byte_array: ByteArray, value: u256) {
    let mut i: u32 = 0;
    while i != 32 {
        let byte_position = 31 - i; // byte position from right (0-31)
        let byte_val = ((value / pow256(byte_position)) & 0xFF).try_into().unwrap();
        byte_array.append_byte(byte_val);
        i += 1;
    };
}

/// Extract u32 from ByteArray at given index (big-endian)
pub fn extract_u32_be(byte_array: @ByteArray, index: usize) -> u32 {
    assert(index + 3 < byte_array.len(), Errors::EXTRACT_U32_BE_OOB);

    let b0: u32 = byte_array.at(index).unwrap().into();
    let b1: u32 = byte_array.at(index + 1).unwrap().into();
    let b2: u32 = byte_array.at(index + 2).unwrap().into();
    let b3: u32 = byte_array.at(index + 3).unwrap().into();

    (b0 * 0x1000000) + (b1 * 0x10000) + (b2 * 0x100) + b3
}

/// Extract u256 from ByteArray at given index (big-endian, 32 bytes)
pub fn extract_u256_be(byte_array: @ByteArray, index: usize) -> u256 {
    assert(index + 31 < byte_array.len(), Errors::EXTRACT_U256_BE_OOB);

    let mut result: u256 = 0;
    let mut i: u32 = 0;

    while i != 32 {
        let byte_val: u256 = byte_array.at(index + i.into()).unwrap().into();
        let byte_position = 31 - i; // byte position from right (0-31)
        result += byte_val * pow256(byte_position);
        i += 1;
    }

    result
}

/// Extract bytes array from ByteArray at given index (dynamic)
pub fn extract_bytes_array_dynamic(byte_array: @ByteArray, index: usize) -> ByteArray {
    let byte_array_len = byte_array.len();
    assert(byte_array_len >= index, Errors::BYTE_ARRAY_TOO_SHORT);

    let mut body: ByteArray = Default::default();
    let mut i = index;

    while i != byte_array_len {
        let byte_opt = byte_array.at(i);
        match byte_opt {
            Option::Some(byte_val) => { body.append_byte(byte_val); },
            Option::None => { break; },
        }
        i += 1;
    }
    body
}

/// Helper function to calculate 256^exponent using optimized pattern matching
pub fn pow256(exponent: u32) -> u256 {
    match exponent {
        0 => 0x1_u256, // 256^0
        1 => 0x100_u256, // 256^1
        2 => 0x10000_u256, // 256^2
        3 => 0x1000000_u256, // 256^3
        4 => 0x100000000_u256, // 256^4
        5 => 0x10000000000_u256, // 256^5
        6 => 0x1000000000000_u256, // 256^6
        7 => 0x100000000000000_u256, // 256^7
        8 => 0x10000000000000000_u256, // 256^8
        9 => 0x1000000000000000000_u256, // 256^9
        10 => 0x100000000000000000000_u256, // 256^10
        11 => 0x10000000000000000000000_u256, // 256^11
        12 => 0x1000000000000000000000000_u256, // 256^12
        13 => 0x100000000000000000000000000_u256, // 256^13
        14 => 0x10000000000000000000000000000_u256, // 256^14
        15 => 0x1000000000000000000000000000000_u256, // 256^15
        16 => 0x100000000000000000000000000000000_u256, // 256^16
        17 => 0x10000000000000000000000000000000000_u256, // 256^17
        18 => 0x1000000000000000000000000000000000000_u256, // 256^18
        19 => 0x100000000000000000000000000000000000000_u256, // 256^19
        20 => 0x10000000000000000000000000000000000000000_u256, // 256^20
        21 => 0x1000000000000000000000000000000000000000000_u256, // 256^21
        22 => 0x100000000000000000000000000000000000000000000_u256, // 256^22
        23 => 0x10000000000000000000000000000000000000000000000_u256, // 256^23
        24 => 0x1000000000000000000000000000000000000000000000000_u256, // 256^24
        25 => 0x100000000000000000000000000000000000000000000000000_u256, // 256^25
        26 => 0x10000000000000000000000000000000000000000000000000000_u256, // 256^26
        27 => 0x1000000000000000000000000000000000000000000000000000000_u256, // 256^27
        28 => 0x100000000000000000000000000000000000000000000000000000000_u256, // 256^28
        29 => 0x10000000000000000000000000000000000000000000000000000000000_u256, // 256^29
        30 => 0x1000000000000000000000000000000000000000000000000000000000000_u256, // 256^30
        31 => 0x100000000000000000000000000000000000000000000000000000000000000_u256, // 256^31
        _ => panic_with_felt252('pow256 overflow'),
    }
}

/// Reverse bytes of a u256 (little-endian to big-endian or vice versa)
pub fn reverse_u256_bytes(value: u256) -> u256 {
    // Step 1: Convert u256 to 32 bytes
    let mut bytes: ByteArray = Default::default();
    append_u256_be(ref bytes, value);

    // Step 2: Reverse the bytes
    let mut reversed_bytes: ByteArray = Default::default();
    let mut i = 32;
    while i != 0 {
        reversed_bytes.append_byte(bytes.at(i - 1).unwrap());
        i -= 1;
    }

    // Step 3: Convert the reversed bytes back to u256
    extract_u256_be(@reversed_bytes, 0)
}
