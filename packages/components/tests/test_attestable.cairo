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
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

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
        attester: ContractAddress,
    ) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }

        if !attester.is_zero() && !attester_manager.is_zero() {
            self.attestable.initializer(attester_manager, attester);
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_attestable_initializer(
            ref self: ContractState, attester_manager: ContractAddress, attester: ContractAddress,
        ) {
            self.attestable.initializer(attester_manager, attester);
        }

        #[external(v0)]
        fn test_assert_only_attester_manager(self: @ContractState) {
            self.attestable.assert_only_attester_manager();
        }

        #[external(v0)]
        fn test_ownable_initializer(ref self: ContractState, owner: ContractAddress) {
            self.ownable.initializer(owner);
        }
    }
}

// Helper trait for accessing test functions
#[starknet::interface]
trait ITestHelper<TContractState> {
    fn test_attestable_initializer(
        ref self: TContractState, attester_manager: ContractAddress, attester: ContractAddress,
    );
    fn test_assert_only_attester_manager(self: @TContractState);
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_contract(
    owner: ContractAddress, attester_manager: ContractAddress, attester: ContractAddress,
) -> ContractAddress {
    let contract = declare("MockAttestableContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), attester_manager.into(), attester.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_contract() -> ContractAddress {
    let contract = declare("MockAttestableContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![
        zero_address.into(), zero_address.into(), zero_address.into(),
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
    let contract_address = deploy_mock_contract(owner, attester_manager, *attesters.at(0));
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, *attesters.at(0));
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
    let attester0 = *attesters.at(0);
    let attester1 = *attesters.at(1);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(attester1);
    dispatcher.set_signature_threshold(2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.get_signature_threshold() == 2, "Signature threshold should be 1");
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.enable_attester(attester1);
}

#[test]
#[should_panic(expected: ('Invalid attester',))]
fn test_enable_attester_zero_address() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.enable_attester(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('Attester already enabled',))]
fn test_enable_attester_already_enabled() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.disable_attester(attester0);
}

#[test]
#[should_panic(expected: ('Too few enabled attesters',))]
fn test_disable_attester_too_few_enabled_attesters() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
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
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.disable_attester(attester1);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_attester_manager_non_owner() {
    let (owner, attester_manager, attesters, new_attester_manager, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, *attesters.at(0));
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.update_attester_manager(new_attester_manager);
}

#[test]
#[should_panic(expected: ('Invalid attester manager',))]
fn test_update_attester_manager_zero_address() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, *attesters.at(0));
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_attester_manager(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('Manager cannot be the same',))]
fn test_update_attester_manager_same_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, attester_manager, *attesters.at(0));
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_attester_manager(attester_manager);
}

#[test]
#[should_panic(expected: ('Caller not attester manager',))]
fn test_set_signature_threshold_non_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_signature_threshold(2);
}

#[test]
#[should_panic(expected: ('Invalid signature threshold',))]
fn test_set_signature_threshold_invalid_signature_threshold() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(0);
}

#[test]
#[should_panic(expected: ('New threshold too high',))]
fn test_set_signature_threshold_new_threshold_too_high() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(2);
}

#[test]
#[should_panic(expected: ('Same signature threshold',))]
fn test_set_signature_threshold_same_signature_threshold() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let attester0 = *attesters.at(0);
    let contract_address = deploy_mock_contract(owner, attester_manager, attester0);
    let dispatcher = IAttestableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, attester_manager);
    dispatcher.set_signature_threshold(1);
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
    test_dispatcher.test_attestable_initializer(attester_manager, *attesters.at(0));

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
    test_dispatcher.test_attestable_initializer(attester_manager, *attesters.at(0));

    // Try to initialize again
    test_dispatcher.test_attestable_initializer(attester_manager, *attesters.at(0));
}

#[test]
#[should_panic(expected: ('Invalid attester manager',))]
fn test_initialize_zero_attester_manager_address() {
    let (owner, _, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(0.try_into().unwrap(), *attesters.at(0));
}

#[test]
#[should_panic(expected: ('Invalid attester',))]
fn test_initialize_zero_attester_address() {
    let (owner, attester_manager, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, 0.try_into().unwrap());
}

#[test]
fn test_assert_only_attester_manager() {
    let (owner, attester_manager, attesters, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for attestable)
    test_dispatcher.test_ownable_initializer(owner);
    test_dispatcher.test_attestable_initializer(attester_manager, *attesters.at(0));

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
    test_dispatcher.test_attestable_initializer(attester_manager, *attesters.at(0));

    start_cheat_caller_address(contract_address, owner);
    test_dispatcher.test_assert_only_attester_manager();
}
