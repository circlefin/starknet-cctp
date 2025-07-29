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

use starknet::ContractAddress;
use utils::AddressConversionTrait;

#[test]
fn test_to_address() {
    let address = 0x1234567890123456789012345678901234567890.to_address();
    assert_eq!(address, 0x1234567890123456789012345678901234567890.try_into().unwrap());
}

#[test]
fn test_to_u256() {
    let address: ContractAddress = 0x1234_felt252.try_into().unwrap();
    let address_u256: u256 = address.to_u256();
    assert_eq!(address_u256, 0x1234);
}

#[test]
#[should_panic(expected: ('u256 to felt252 failed',))]
fn test_to_address_overflow() {
    // Test with a u256 value that's too large to fit in a felt252
    // felt252 max is approximately 2^251 - 17*2^192 + 1
    let too_large: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    too_large.to_address();
}

#[test]
fn test_round_trip_conversion() {
    // Test that converting back and forth works correctly
    let original_u256: u256 = 0xabcdef1234567890;
    let address = original_u256.to_address();
    let back_to_u256 = address.to_u256();
    assert_eq!(original_u256, back_to_u256);
}
