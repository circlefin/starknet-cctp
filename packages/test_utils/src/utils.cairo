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

/// Convert u8 array to byte array
pub fn u8_array_to_byte_array(u8_array: @Array<u8>) -> ByteArray {
    let mut byte_array: ByteArray = Default::default();
    let mut i = 0;
    while i != u8_array.len() {
        byte_array.append_byte(*u8_array.at(i));
        i += 1;
    }
    byte_array
}

// Convert hex string to byte array
pub fn hex_string_to_bytes_array(hex: ByteArray) -> ByteArray {
    let mut result: ByteArray = Default::default();
    let len = hex.len();
    let mut i = 0;

    // Skip "0x" or "0X" prefix if present
    if len >= 2 {
        let c0 = hex.at(0).unwrap();
        let c1 = hex.at(1).unwrap();
        if c0 == '0' && (c1 == 'x' || c1 == 'X') {
            i = 2;
        }
    }

    let hex_len = len - i;
    // If odd length, prepend a '0' nibble
    if hex_len % 2 != 0 {
        let lo: felt252 = hex.at(i).unwrap().into();
        result.append_byte(hex_char_to_nibble(lo).try_into().unwrap());
        i += 1;
    }

    while i + 1 != len && i != len {
        let hi: felt252 = hex.at(i).unwrap().into();
        let lo: felt252 = hex.at(i + 1).unwrap().into();
        let byte = hex_char_to_nibble(hi) * 16 + hex_char_to_nibble(lo);
        result.append_byte(byte.try_into().unwrap());
        i += 2;
    }

    result
}

fn hex_char_to_nibble(c: felt252) -> felt252 {
    if c == '0' {
        0
    } else if c == '1' {
        1
    } else if c == '2' {
        2
    } else if c == '3' {
        3
    } else if c == '4' {
        4
    } else if c == '5' {
        5
    } else if c == '6' {
        6
    } else if c == '7' {
        7
    } else if c == '8' {
        8
    } else if c == '9' {
        9
    } else if c == 'a' || c == 'A' {
        10
    } else if c == 'b' || c == 'B' {
        11
    } else if c == 'c' || c == 'C' {
        12
    } else if c == 'd' || c == 'D' {
        13
    } else if c == 'e' || c == 'E' {
        14
    } else if c == 'f' || c == 'F' {
        15
    } else {
        panic!("Invalid hex character")
    }
}
