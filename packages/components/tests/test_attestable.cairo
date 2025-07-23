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

use cctp_components::attestable::{
    AttestableComponent, IAttestableDispatcher, IAttestableDispatcherTrait,
};
use core::array::{Array, ArrayTrait};
use core::serde::Serde;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use test_utils::{hex_string_to_bytes_array, u8_array_to_byte_array};

// Mock contract that uses the ownable component for testing
#[starknet::contract]
mod MockAttestableContract {
    use cctp_components::attestable::AttestableComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(path: AttestableComponent, storage: attestable, event: AttestableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl AttestableImpl = AttestableComponent::Attestable<ContractState>;
    impl AttestableInternalImpl = AttestableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        attestable: AttestableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AttestableEvent: AttestableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        attester_manager: ContractAddress,
        attesters: Array<ContractAddress>,
        signature_threshold: felt252,
    ) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }

        if attesters.len() > 0 && !attester_manager.is_zero() {
            self
                .attestable
                .initializer(attester_manager, attesters, signature_threshold.try_into().unwrap());
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_attestable_initializer(
            ref self: ContractState,
            attester_manager: ContractAddress,
            attesters: Array<ContractAddress>,
            signature_threshold: u64,
        ) {
            self.attestable.initializer(attester_manager, attesters, signature_threshold);
        }

        #[external(v0)]
        fn test_assert_only_attester_manager(self: @ContractState) {
            self.attestable.assert_only_attester_manager();
        }

        #[external(v0)]
        fn test_ownable_initializer(ref self: ContractState, owner: ContractAddress) {
            self.ownable.initializer(owner);
        }

        #[external(v0)]
        fn test_verify_attestation_signatures(
            self: @ContractState, message: ByteArray, attestation: ByteArray,
        ) {
            self.attestable.verify_attestation_signatures(message, attestation);
        }

        #[external(v0)]
        fn test_recover_attester(
            self: @ContractState, digest: u256, attestation: ByteArray, start_index: u32,
        ) -> ContractAddress {
            self.attestable._recover_attester(digest, @attestation, start_index)
        }
    }
}

// Helper trait for accessing test functions
#[starknet::interface]
trait ITestHelper<TContractState> {
    fn test_attestable_initializer(
        ref self: TContractState,
        attester_manager: ContractAddress,
        attesters: Array<ContractAddress>,
        signature_threshold: u64,
    );
    fn test_assert_only_attester_manager(self: @TContractState);
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
    fn test_verify_attestation_signatures(
        self: @TContractState, message: ByteArray, attestation: ByteArray,
    );
    fn test_recover_attester(
        self: @TContractState, digest: u256, attestation: ByteArray, start_index: u32,
    ) -> ContractAddress;
}

fn deploy_mock_contract(
    owner: ContractAddress,
    attester_manager: ContractAddress,
    attesters: Array<ContractAddress>,
    signature_threshold: felt252,
) -> ContractAddress {
    let contract = declare("MockAttestableContract").unwrap().contract_class();
    let mut constructor_calldata = array![];
    Serde::serialize(@owner, ref constructor_calldata);
    Serde::serialize(@attester_manager, ref constructor_calldata);
    Serde::serialize(@attesters, ref constructor_calldata);
    Serde::serialize(@signature_threshold, ref constructor_calldata);
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_contract() -> ContractAddress {
    let contract = declare("MockAttestableContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![
        zero_address.into(), zero_address.into(), zero_address.into(), 0.into(),
    ];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_addresses() -> (
    ContractAddress, ContractAddress, Array<ContractAddress>, ContractAddress, ContractAddress,
) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let attester_manager: ContractAddress = 456.try_into().unwrap();
    let attester0: ContractAddress = 101.try_into().unwrap();
    let attester1: ContractAddress = 102.try_into().unwrap();
    let attester2: ContractAddress = 103.try_into().unwrap();
    let attesters = array![attester0, attester1, attester2];
    let new_attester_manager: ContractAddress = 789.try_into().unwrap();
    let unauthorized: ContractAddress = 999.try_into().unwrap();
    (owner, attester_manager, attesters, new_attester_manager, unauthorized)
}

fn get_test_attesters() -> Array<ContractAddress> {
    let attester1: ContractAddress = 101.try_into().unwrap();
    let attester2: ContractAddress = 102.try_into().unwrap();
    array![attester1, attester2]
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initial_contract_state() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters.clone(), 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    // The attester_manager is set to the deployer address (test caller)
    assert!(dispatcher.get_signature_threshold() == 1, "Signature threshold should be 1");
    assert!(dispatcher.attester_manager() == attester_manager, "Attester manager should be set");
    assert!(dispatcher.is_enabled_attester(*attesters.at(0)), "Attester should be enabled");
}

#[test]
fn test_uninitialized_contract() {
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = IAttestableDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();

    assert!(dispatcher.attester_manager() == zero_address, "Attester manager should be zero");
    assert!(dispatcher.get_signature_threshold() == 0, "Signature threshold should be 0");
}

#[test]
fn test_enable_attester() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let attester2 = *attesters.at(2);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };
    let mut spy = spy_events();

    assert!(dispatcher.get_enabled_attesters().len() == 1, "Attester should be disabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester1);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 2, "Attester should be enabled");
    assert!(dispatcher.is_enabled_attester(attester1), "Attester should be enabled");
    assert!(
        *dispatcher.get_enabled_attesters().at(0) == attester0,
        "Attester should be the second enabled attester",
    );
    assert!(
        *dispatcher.get_enabled_attesters().at(1) == attester1,
        "Attester should be the second enabled attester",
    );

    // verify event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    AttestableComponent::Event::AttesterEnabled(
                        AttestableComponent::AttesterEnabled { attester: attester1 },
                    ),
                ),
            ],
        );

    // enable attester2
    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 3, "Attester should be enabled");
    assert!(dispatcher.is_enabled_attester(attester2), "Attester should be enabled");

    // verify event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    AttestableComponent::Event::AttesterEnabled(
                        AttestableComponent::AttesterEnabled { attester: attester2 },
                    ),
                ),
            ],
        );
}

#[test]
fn test_disable_attester() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let attester2 = *attesters.at(2);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, attester_manager);
    // enable attesters
    dispatcher.enable_attester(attester1);
    dispatcher.enable_attester(attester2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.is_enabled_attester(attester1), "Attester should be enabled");

    start_cheat_caller_address(contract_address, attester_manager);
    // disable attester
    dispatcher.disable_attester(attester1);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 2, "Attester should be disabled");
    assert!(!dispatcher.is_enabled_attester(attester1), "Attester should be disabled");
    assert!(dispatcher.is_enabled_attester(attester2), "Attester should be enabled");

    // verify event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    AttestableComponent::Event::AttesterDisabled(
                        AttestableComponent::AttesterDisabled { attester: attester1 },
                    ),
                ),
            ],
        );

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 1, "Attester should be disabled");
    assert!(!dispatcher.is_enabled_attester(attester2), "Attester should be disabled");

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    AttestableComponent::Event::AttesterDisabled(
                        AttestableComponent::AttesterDisabled { attester: attester2 },
                    ),
                ),
            ],
        );
}

#[test]
fn test_is_enabled_attester() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let attester2 = *attesters.at(2);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    assert!(!dispatcher.is_enabled_attester(attester1), "Attester1 should be disabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester1);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.is_enabled_attester(attester0), "Attester0 should be enabled");
    assert!(dispatcher.is_enabled_attester(attester1), "Attester1 should be enabled");
    assert!(!dispatcher.is_enabled_attester(attester2), "Attester2 should be disabled");
}

#[test]
fn test_get_enabled_attesters() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let attester2 = *attesters.at(2);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    assert!(dispatcher.get_enabled_attesters().len() == 1, "One attester should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(0) == attester0, "Attester0 should be enabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester1);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 2, "Two attester should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(0) == attester0, "Attester0 should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(1) == attester1, "Attester1 should be enabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 3, "Three attesters should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(0) == attester0, "Attester0 should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(1) == attester1, "Attester1 should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(2) == attester2, "Attester2 should be enabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester0);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 2, "Two attester should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(0) == attester2, "Attester1 should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(1) == attester1, "Attester2 should be enabled");

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester1);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_enabled_attesters().len() == 1, "One attesters should be enabled");
    assert!(*dispatcher.get_enabled_attesters().at(0) == attester2, "Attester2 should be enabled");
}

#[test]
fn test_update_attester_manager() {
    let (owner, attester_manager, attesters, new_attester_manager, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_attester_manager(new_attester_manager);
    stop_cheat_caller_address(contract_address);

    assert!(
        dispatcher.attester_manager() == new_attester_manager, "Attester manager should be updated",
    );
}

#[test]
fn test_set_signature_threshold() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_signature_threshold() == 2, "Signature threshold should be 2");
}

// ================================
// ERRORS TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller not attester manager',))]
fn test_enable_attester_non_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.enable_attester(attester1);
}

#[test]
#[should_panic(expected: ('Invalid attester',))]
fn test_enable_attester_zero_address() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('Attester already enabled',))]
fn test_enable_attester_already_enabled() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester0);
    dispatcher.enable_attester(attester0);
}

#[test]
#[should_panic(expected: ('Caller not attester manager',))]
fn test_disable_attester_non_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.disable_attester(attester0);
}

#[test]
#[should_panic(expected: ('Too few enabled attesters',))]
fn test_disable_attester_too_few_enabled_attesters() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester0);
}

#[test]
#[should_panic(expected: ('Signature threshold too low',))]
fn test_disable_attester_signature_threshold_too_low() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester1);
    dispatcher.set_signature_threshold(2);
    dispatcher.disable_attester(attester0);
}

#[test]
#[should_panic(expected: ('Attester is not enabled',))]
fn test_disable_attester_not_enabled() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester1);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_attester_manager_non_owner() {
    let (owner, attester_manager, attesters, new_attester_manager, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.update_attester_manager(new_attester_manager);
}

#[test]
#[should_panic(expected: ('Invalid attester manager',))]
fn test_update_attester_manager_zero_address() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_attester_manager(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('Manager cannot be the same',))]
fn test_update_attester_manager_same_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_attester_manager(attester_manager);
}

#[test]
#[should_panic(expected: ('Caller not attester manager',))]
fn test_set_signature_threshold_non_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_signature_threshold(2);
}

#[test]
#[should_panic(expected: ('Invalid signature threshold',))]
fn test_set_signature_threshold_invalid_signature_threshold() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(0);
}

#[test]
#[should_panic(expected: ('New threshold too high',))]
fn test_set_signature_threshold_new_threshold_too_high() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(2);
}

#[test]
#[should_panic(expected: ('Same signature threshold',))]
fn test_set_signature_threshold_same_signature_threshold() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, array![attester0], 1);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(1);
}

#[test]
#[should_panic(expected: ('Invalid attestation',))]
fn test_verify_attestation_signatures_invalid_attestation() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    let message: ByteArray = "message";
    let attestation = hex_string_to_bytes_array("0x1234");

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
#[should_panic(expected: ('Attester is not enabled',))]
fn test_verify_attestation_signatures_disabled_attester() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // load destination message and attestation data from hash:
    // 0x5fb6eac86e4ea9cadf6f37a1469cf32d7b4b95666addcc507993a4ba8594e41b
    let bytes_array = array![
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        13,
        0,
        0,
        0,
        1,
        124,
        164,
        236,
        114,
        162,
        50,
        74,
        41,
        249,
        153,
        158,
        155,
        158,
        51,
        145,
        229,
        102,
        48,
        9,
        13,
        25,
        61,
        111,
        181,
        216,
        135,
        198,
        81,
        68,
        196,
        239,
        204,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
        232,
        0,
        0,
        7,
        208,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        41,
        33,
        157,
        212,
        0,
        242,
        191,
        96,
        229,
        162,
        61,
        19,
        190,
        114,
        180,
        134,
        212,
        3,
        136,
        148,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        38,
        46,
        16,
        114,
        121,
        87,
        22,
        93,
        186,
        150,
        183,
        232,
        130,
        229,
        78,
        16,
        164,
        63,
        228,
        111,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        34,
        39,
        5,
        176,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        58,
        35,
        249,
        67,
        24,
        20,
        8,
        234,
        196,
        36,
        17,
        106,
        247,
        183,
        121,
        12,
        148,
        203,
        151,
        165,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ];

    let message = u8_array_to_byte_array(@bytes_array);
    let attestation = hex_string_to_bytes_array(
        "0x71a2cb9a1a2ebb617146d2dc5b68f288c825ed2401a47c883a4537ac295184aa507000fd11054198e39d7df39280d365c2e0966d86a4f63280bf8d21b748cc111c2617e687d62726f9c994785be959b52fa01167ca6f8cb118972629847c27bb0a32726cf6df976ccb4f39546fa9379964aadab465a5c2be0c359ed940b80733761b",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid signature order or dupe',))]
fn test_verify_attestation_signatures_invalid_order() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let attesters: Array<ContractAddress> = array![
        // bridge-prod-1
        0x725b06f73ff761ef5390e39315e2bfbf60d33f96.try_into().unwrap(),
        // bridge-prod-2
        0x52ed4cbff8dce6a19748043f3240ec03c834bcef.try_into().unwrap(),
    ];
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // load destination message and attestation data from hash:
    // 0x5fb6eac86e4ea9cadf6f37a1469cf32d7b4b95666addcc507993a4ba8594e41b
    let bytes_array = array![
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        13,
        0,
        0,
        0,
        1,
        124,
        164,
        236,
        114,
        162,
        50,
        74,
        41,
        249,
        153,
        158,
        155,
        158,
        51,
        145,
        229,
        102,
        48,
        9,
        13,
        25,
        61,
        111,
        181,
        216,
        135,
        198,
        81,
        68,
        196,
        239,
        204,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
        232,
        0,
        0,
        7,
        208,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        41,
        33,
        157,
        212,
        0,
        242,
        191,
        96,
        229,
        162,
        61,
        19,
        190,
        114,
        180,
        134,
        212,
        3,
        136,
        148,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        38,
        46,
        16,
        114,
        121,
        87,
        22,
        93,
        186,
        150,
        183,
        232,
        130,
        229,
        78,
        16,
        164,
        63,
        228,
        111,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        34,
        39,
        5,
        176,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        58,
        35,
        249,
        67,
        24,
        20,
        8,
        234,
        196,
        36,
        17,
        106,
        247,
        183,
        121,
        12,
        148,
        203,
        151,
        165,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ];

    let message = u8_array_to_byte_array(@bytes_array);
    let attestation = hex_string_to_bytes_array(
        "0x71a2cb9a1a2ebb617146d2dc5b68f288c825ed2401a47c883a4537ac295184aa507000fd11054198e39d7df39280d365c2e0966d86a4f63280bf8d21b748cc111c2617e687d62726f9c994785be959b52fa01167ca6f8cb118972629847c27bb0a32726cf6df976ccb4f39546fa9379964aadab465a5c2be0c359ed940b80733761b",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid signature order or dupe',))]
fn test_verify_attestation_signatures_dupe_signature() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let attesters: Array<ContractAddress> = array![
        // bridge-prod-1
        0x725b06f73ff761ef5390e39315e2bfbf60d33f96.try_into().unwrap(),
        // bridge-prod-2
        0x52ed4cbff8dce6a19748043f3240ec03c834bcef.try_into().unwrap(),
    ];
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // load destination message and attestation data from hash:
    // 0x5fb6eac86e4ea9cadf6f37a1469cf32d7b4b95666addcc507993a4ba8594e41b
    let bytes_array = array![
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        13,
        0,
        0,
        0,
        1,
        124,
        164,
        236,
        114,
        162,
        50,
        74,
        41,
        249,
        153,
        158,
        155,
        158,
        51,
        145,
        229,
        102,
        48,
        9,
        13,
        25,
        61,
        111,
        181,
        216,
        135,
        198,
        81,
        68,
        196,
        239,
        204,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
        232,
        0,
        0,
        7,
        208,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        41,
        33,
        157,
        212,
        0,
        242,
        191,
        96,
        229,
        162,
        61,
        19,
        190,
        114,
        180,
        134,
        212,
        3,
        136,
        148,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        38,
        46,
        16,
        114,
        121,
        87,
        22,
        93,
        186,
        150,
        183,
        232,
        130,
        229,
        78,
        16,
        164,
        63,
        228,
        111,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        34,
        39,
        5,
        176,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        58,
        35,
        249,
        67,
        24,
        20,
        8,
        234,
        196,
        36,
        17,
        106,
        247,
        183,
        121,
        12,
        148,
        203,
        151,
        165,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ];

    let message = u8_array_to_byte_array(@bytes_array);
    // duplicate attestation signature
    let attestation = hex_string_to_bytes_array(
        "0x71a2cb9a1a2ebb617146d2dc5b68f288c825ed2401a47c883a4537ac295184aa507000fd11054198e39d7df39280d365c2e0966d86a4f63280bf8d21b748cc111c71a2cb9a1a2ebb617146d2dc5b68f288c825ed2401a47c883a4537ac295184aa507000fd11054198e39d7df39280d365c2e0966d86a4f63280bf8d21b748cc111c",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid signature',))]
fn test_verify_attestation_signatures_invalid_signature_s_value() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    let message: ByteArray = "message";
    // invalid attestation signature
    let attestation = hex_string_to_bytes_array(
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid signature',))]
fn test_verify_attestation_signatures_invalid_signature_r_value() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 1);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    let message: ByteArray = "message";
    // invalid attestation signature
    let attestation = hex_string_to_bytes_array(
        "0xc901a511af9b85b6db2b6660d3aeb029129a26944b69a74dd7c26a64e154726fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_initializer_functionality() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = IAttestableDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    // Initialize attestable with attester manager and attester
    test_dispatcher.test_attestable_initializer(attester_manager, attesters.clone(), 1);

    // Check that attester manager is set
    assert!(dispatcher.attester_manager() == attester_manager, "Attester manager should be set");

    // Check that attester is set
    assert!(dispatcher.is_enabled_attester(*attesters.at(0)), "Attester should be enabled");

    assert!(dispatcher.get_signature_threshold() == 1, "Signature threshold should be 1");
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initializer_functionality_already_initialized() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, attesters.clone(), 1);

    // Try to initialize again
    test_dispatcher.test_attestable_initializer(attester_manager, attesters.clone(), 1);
}

#[test]
#[should_panic(expected: ('Invalid attester manager',))]
fn test_initialize_zero_attester_manager_address() {
    let (owner, _, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(0.try_into().unwrap(), attesters.clone(), 1);
}

#[test]
#[should_panic(expected: ('Invalid attesters',))]
fn test_initialize_empty_attesters() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, array![], 1);
}

#[test]
#[should_panic(expected: ('Invalid attester',))]
fn test_initialize_zero_attester_address() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, array![0.try_into().unwrap()], 1);
}

#[test]
fn test_assert_only_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, attesters.clone(), 1);

    start_cheat_caller_address(contract_address, attester_manager);
    test_dispatcher.test_assert_only_attester_manager();
}

#[test]
#[should_panic(expected: ('Caller not attester manager',))]
fn test_assert_only_attester_manager_non_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, attesters.clone(), 1);

    start_cheat_caller_address(contract_address, owner);
    test_dispatcher.test_assert_only_attester_manager();
}

#[test]
fn test_verify_attestation_signatures() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let attesters: Array<ContractAddress> = array![
        // bridge-prod-1
        0x725b06f73ff761ef5390e39315e2bfbf60d33f96.try_into().unwrap(),
        // bridge-prod-2
        0x52ed4cbff8dce6a19748043f3240ec03c834bcef.try_into().unwrap(),
    ];
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // load destination message and attestation data from hash:
    // 0xc05fbd5c4a86902c4ee8d28a09a745d8e57361df7271de2d88157e205ceb04e0
    let bytes_array = array![
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        13,
        0,
        0,
        0,
        2,
        187,
        97,
        196,
        135,
        192,
        3,
        72,
        149,
        190,
        246,
        120,
        69,
        230,
        242,
        100,
        247,
        27,
        44,
        54,
        208,
        145,
        63,
        108,
        165,
        188,
        122,
        204,
        31,
        84,
        157,
        233,
        150,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        9,
        176,
        67,
        132,
        12,
        210,
        243,
        38,
        135,
        236,
        107,
        99,
        251,
        4,
        18,
        88,
        93,
        227,
        152,
        34,
        0,
        0,
        3,
        232,
        0,
        0,
        7,
        208,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        41,
        33,
        157,
        212,
        0,
        242,
        191,
        96,
        229,
        162,
        61,
        19,
        190,
        114,
        180,
        134,
        212,
        3,
        136,
        148,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        9,
        176,
        67,
        132,
        12,
        210,
        243,
        38,
        135,
        236,
        107,
        99,
        251,
        4,
        18,
        88,
        93,
        227,
        152,
        34,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        53,
        165,
        55,
        32,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        9,
        176,
        67,
        132,
        12,
        210,
        243,
        38,
        135,
        236,
        107,
        99,
        251,
        4,
        18,
        88,
        93,
        227,
        152,
        34,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        53,
        165,
        55,
        32,
        33,
        117,
        169,
        251,
        110,
        36,
        228,
        30,
        255,
        204,
        230,
        30,
        146,
        142,
        92,
        159,
        229,
        179,
        219,
        75,
        3,
        104,
        167,
        119,
        150,
        221,
        89,
        247,
        22,
        17,
        203,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        174,
        104,
        183,
        17,
        123,
        224,
        2,
        108,
        189,
        67,
        102,
        48,
        63,
        116,
        238,
        203,
        177,
        158,
        64,
        66,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        53,
        164,
        245,
        87,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        104,
        112,
        69,
        109,
    ];
    let message = u8_array_to_byte_array(@bytes_array);
    let attestation = hex_string_to_bytes_array(
        "0x111a2b4ce084ccc83c8ef18eabf50fc332f603c7cd2ef7e177ea45a1c332f1d97c0fc30429b2c6ce57f7cb6bbcbdabff5d94b487075dff3b09182c25d6e9d98a1cc901a511af9b85b6db2b6660d3aeb029129a26944b69a74dd7c26a64e154726f23bd811da1a90c6ce36a9170785966de2a9280c39042fedb95bbc29bbf301c0d1c",
    );

    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
fn test_verify_attestation_signatures_2() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let attesters: Array<ContractAddress> = array![
        // bridge-prod-1
        0x725b06f73ff761ef5390e39315e2bfbf60d33f96.try_into().unwrap(),
        // bridge-prod-2
        0x52ed4cbff8dce6a19748043f3240ec03c834bcef.try_into().unwrap(),
    ];
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // load destination message and attestation data from hash:
    // 0x5fb6eac86e4ea9cadf6f37a1469cf32d7b4b95666addcc507993a4ba8594e41b
    let bytes_array = array![
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        13,
        0,
        0,
        0,
        1,
        124,
        164,
        236,
        114,
        162,
        50,
        74,
        41,
        249,
        153,
        158,
        155,
        158,
        51,
        145,
        229,
        102,
        48,
        9,
        13,
        25,
        61,
        111,
        181,
        216,
        135,
        198,
        81,
        68,
        196,
        239,
        204,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        40,
        181,
        160,
        233,
        198,
        33,
        165,
        186,
        218,
        165,
        54,
        33,
        155,
        58,
        34,
        140,
        129,
        104,
        207,
        93,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
        232,
        0,
        0,
        7,
        208,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        41,
        33,
        157,
        212,
        0,
        242,
        191,
        96,
        229,
        162,
        61,
        19,
        190,
        114,
        180,
        134,
        212,
        3,
        136,
        148,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        38,
        46,
        16,
        114,
        121,
        87,
        22,
        93,
        186,
        150,
        183,
        232,
        130,
        229,
        78,
        16,
        164,
        63,
        228,
        111,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        34,
        39,
        5,
        176,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        58,
        35,
        249,
        67,
        24,
        20,
        8,
        234,
        196,
        36,
        17,
        106,
        247,
        183,
        121,
        12,
        148,
        203,
        151,
        165,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ];

    let message = u8_array_to_byte_array(@bytes_array);
    let attestation = hex_string_to_bytes_array(
        "0x2617e687d62726f9c994785be959b52fa01167ca6f8cb118972629847c27bb0a32726cf6df976ccb4f39546fa9379964aadab465a5c2be0c359ed940b80733761b71a2cb9a1a2ebb617146d2dc5b68f288c825ed2401a47c883a4537ac295184aa507000fd11054198e39d7df39280d365c2e0966d86a4f63280bf8d21b748cc111c",
    );

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_verify_attestation_signatures(message, attestation);
}

#[test]
fn test_recover_attester() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, attesters, 2);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Test recover attester by match the result of ecrecover, see:
    // https://asecuritysite.com/ecdsa/ecdsa_recpub Test Private key:
    // 33ecc1917ef594d053067651fe2badaadc284b3bbd32d49f2fbbe1078f0e3788 Message to sign: message
    // Hash: c2baf6c66618acd49fb133cebc22f55bd907fe9f0d69a726d45b7539ba6bbe08
    //
    // === Now using Ecrecover ===
    // ECDSA Signature:
    // 6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00
    //   R: 6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23
    //   S: 172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb
    //   V: 00
    //
    // Original public key:
    // 04e194233a607e1ffb9bca8ba248e31968300bd395170b43ed6c12cbe04c5f9e2f22b34e7a28e86ed2124229f1a88ed111ce525699d16d7f10ad771892a8d23beb
    // Recovered public key:
    // 04e194233a607e1ffb9bca8ba248e31968300bd395170b43ed6c12cbe04c5f9e2f22b34e7a28e86ed2124229f1a88ed111ce525699d16d7f10ad771892a8d23beb
    // Public keys match

    let digest: u256 = 0xc2baf6c66618acd49fb133cebc22f55bd907fe9f0d69a726d45b7539ba6bbe08;

    // not sure why, the v value is opposite in this example, so we need to use 01
    let signature: ByteArray = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb01",
    );
    let recovered_attester: ContractAddress = test_dispatcher
        .test_recover_attester(digest, signature, 0);
    assert_eq!(recovered_attester, 0xa9cfcc2fe2a00b4d795c2c8dea60e3e9529252b7.try_into().unwrap());
}
