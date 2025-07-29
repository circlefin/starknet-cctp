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

use utils::{
    append_u256_be, append_u32_be, append_zero_u256, extract_bytes_array_dynamic, extract_u256_be,
    extract_u32_be, pow256, reverse_u256_bytes,
};

#[test]
fn test_append_zero_u256() {
    let mut byte_array: ByteArray = Default::default();
    append_zero_u256(ref byte_array);
    assert_eq!(byte_array.len(), 32);
    assert_eq!(byte_array.at(0).unwrap(), 0);
    assert_eq!(byte_array.at(31).unwrap(), 0);
}

#[test]
fn test_append_u32_be() {
    let mut byte_array: ByteArray = Default::default();
    append_u32_be(ref byte_array, 0x12345678);
    assert_eq!(byte_array.len(), 4);
    assert_eq!(byte_array.at(0).unwrap(), 0x12);
    assert_eq!(byte_array.at(1).unwrap(), 0x34);
    assert_eq!(byte_array.at(2).unwrap(), 0x56);
    assert_eq!(byte_array.at(3).unwrap(), 0x78);
}

#[test]
fn test_append_u256_be() {
    let mut byte_array: ByteArray = Default::default();
    append_u256_be(
        ref byte_array, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
    assert_eq!(byte_array.len(), 32);
    assert_eq!(byte_array.at(0).unwrap(), 0x12);
    assert_eq!(byte_array.at(1).unwrap(), 0x34);
    assert_eq!(byte_array.at(2).unwrap(), 0x56);
    assert_eq!(byte_array.at(3).unwrap(), 0x78);
    assert_eq!(byte_array.at(4).unwrap(), 0x90);
    assert_eq!(byte_array.at(5).unwrap(), 0xab);
    assert_eq!(byte_array.at(6).unwrap(), 0xcd);
    assert_eq!(byte_array.at(7).unwrap(), 0xef);
    assert_eq!(byte_array.at(8).unwrap(), 0x12);
    assert_eq!(byte_array.at(9).unwrap(), 0x34);
    assert_eq!(byte_array.at(10).unwrap(), 0x56);
    assert_eq!(byte_array.at(11).unwrap(), 0x78);
    assert_eq!(byte_array.at(12).unwrap(), 0x90);
    assert_eq!(byte_array.at(13).unwrap(), 0xab);
    assert_eq!(byte_array.at(14).unwrap(), 0xcd);
    assert_eq!(byte_array.at(15).unwrap(), 0xef);
    assert_eq!(byte_array.at(16).unwrap(), 0x12);
    assert_eq!(byte_array.at(17).unwrap(), 0x34);
    assert_eq!(byte_array.at(18).unwrap(), 0x56);
    assert_eq!(byte_array.at(19).unwrap(), 0x78);
    assert_eq!(byte_array.at(20).unwrap(), 0x90);
    assert_eq!(byte_array.at(21).unwrap(), 0xab);
    assert_eq!(byte_array.at(22).unwrap(), 0xcd);
    assert_eq!(byte_array.at(23).unwrap(), 0xef);
    assert_eq!(byte_array.at(24).unwrap(), 0x12);
    assert_eq!(byte_array.at(25).unwrap(), 0x34);
    assert_eq!(byte_array.at(26).unwrap(), 0x56);
    assert_eq!(byte_array.at(27).unwrap(), 0x78);
    assert_eq!(byte_array.at(28).unwrap(), 0x90);
    assert_eq!(byte_array.at(29).unwrap(), 0xab);
    assert_eq!(byte_array.at(30).unwrap(), 0xcd);
    assert_eq!(byte_array.at(31).unwrap(), 0xef);
}

#[test]
fn test_extract_u32_be() {
    let mut byte_array: ByteArray = Default::default();
    append_u32_be(ref byte_array, 0x12345678);
    assert_eq!(extract_u32_be(@byte_array, 0), 0x12345678);
}

#[test]
fn test_extract_u256_be() {
    let mut byte_array: ByteArray = Default::default();
    append_u256_be(
        ref byte_array, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
    assert_eq!(
        extract_u256_be(@byte_array, 0),
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
}

#[test]
fn test_extract_bytes_array_dynamic() {
    let mut byte_array: ByteArray = Default::default();
    append_u256_be(
        ref byte_array, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
    assert_eq!(extract_bytes_array_dynamic(@byte_array, 0), byte_array);
}

#[test]
#[should_panic(expected: ('extract_u256_be OOB',))]
fn test_extract_u256_be_out_of_bounds() {
    let mut byte_array: ByteArray = Default::default();
    append_u256_be(
        ref byte_array, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
    extract_u256_be(@byte_array, 1);
}

#[test]
#[should_panic(expected: ('extract_u32_be OOB',))]
fn test_extract_u32_be_out_of_bounds() {
    let mut byte_array: ByteArray = Default::default();
    append_u32_be(ref byte_array, 0x12345678);
    extract_u32_be(@byte_array, 1);
}

#[test]
#[should_panic(expected: ('Byte array too short',))]
fn test_extract_bytes_array_dynamic_out_of_bounds() {
    let mut byte_array: ByteArray = Default::default();
    append_u256_be(
        ref byte_array, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,
    );
    extract_bytes_array_dynamic(@byte_array, 33);
}

#[test]
#[should_panic(expected: ('pow256 overflow',))]
fn test_pow256_overflow() {
    pow256(32);
}

#[test]
fn test_reverse_u256_bytes() {
    let u256 = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    let reversed = reverse_u256_bytes(u256);
    // reversed: 0xefcdab9078563412efcdab9078563412efcdab9078563412efcdab9078563412
    assert_eq!(reversed, 0xefcdab9078563412efcdab9078563412efcdab9078563412efcdab9078563412);
}
