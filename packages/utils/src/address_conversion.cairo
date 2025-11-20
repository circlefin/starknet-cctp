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

use starknet::ContractAddress;

pub mod Errors {
    pub const U256_TO_FELT252_FAILED: felt252 = 'u256 to felt252 failed';
    pub const FELT252_TO_ADDRESS_FAILED: felt252 = 'felt252 to address failed';
}

pub trait AddressConversionTrait {
    fn to_address(self: u256) -> ContractAddress;
    fn to_u256(self: ContractAddress) -> u256;
}

impl AddressConversionTraitImpl of AddressConversionTrait {
    fn to_address(self: u256) -> ContractAddress {
        let value_felt: felt252 = self.try_into().expect(Errors::U256_TO_FELT252_FAILED);
        value_felt.try_into().expect(Errors::FELT252_TO_ADDRESS_FAILED)
    }

    fn to_u256(self: ContractAddress) -> u256 {
        let value_felt: felt252 = self.into();
        value_felt.into()
    }
}
