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
