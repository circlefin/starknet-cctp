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

use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use token_messenger_minter::{ITokenMessengerMinterDispatcher, ITokenMessengerMinterDispatcherTrait};

fn deploy_contract() -> ContractAddress {
    let contract = declare("TokenMessengerMinter").unwrap().contract_class();
    let constructor_calldata = array![];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

#[test]
fn test_add_two_numbers() {
    let contract_address = deploy_contract();
    let dispatcher = ITokenMessengerMinterDispatcher { contract_address };

    let result = dispatcher.add_two_numbers(5, 10);
    assert!(result == 15, "5 + 10 should equal 15");
}
