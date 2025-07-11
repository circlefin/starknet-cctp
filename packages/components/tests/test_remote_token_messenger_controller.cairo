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

use cctp_components::remote_token_messenger_controller::{
    IRemoteTokenMessengerControllerDispatcher, IRemoteTokenMessengerControllerDispatcherTrait,
    RemoteTokenMessengerControllerComponent,
};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Mock contract that uses both ownable and remote_token_messenger_controller components for testing
#[starknet::contract]
mod MockRemoteTokenMessengerControllerContract {
    use cctp_components::remote_token_messenger_controller::RemoteTokenMessengerControllerComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(
        path: RemoteTokenMessengerControllerComponent,
        storage: remote_token_messenger_controller,
        event: RemoteTokenMessengerControllerEvent,
    );
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl RemoteTokenMessengerControllerImpl =
        RemoteTokenMessengerControllerComponent::RemoteTokenMessengerController<ContractState>;
    impl RemoteTokenMessengerControllerInternalImpl =
        RemoteTokenMessengerControllerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        remote_token_messenger_controller: RemoteTokenMessengerControllerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        RemoteTokenMessengerControllerEvent: RemoteTokenMessengerControllerComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }
    }

    // Expose internal functions for testing
    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_assert_only_remote_token_messenger(
            self: @ContractState, domain: u32, token_messenger: u256,
        ) {
            self
                .remote_token_messenger_controller
                .assert_only_remote_token_messenger(domain, token_messenger);
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
    fn test_assert_only_remote_token_messenger(
        self: @TContractState, domain: u32, token_messenger: u256,
    );
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_contract(owner: ContractAddress) -> ContractAddress {
    let contract = declare("MockRemoteTokenMessengerControllerContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_values() -> (ContractAddress, ContractAddress, u256, u256) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let unauthorized: ContractAddress = 456.try_into().unwrap();
    let token_messenger1: u256 = 789_u256;
    let token_messenger2: u256 = 999_u256;
    (owner, unauthorized, token_messenger1, token_messenger2)
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initialized_contract_state() {
    let (owner, _, _, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };

    // Check that remote token messenger controller is zero initially
    assert!(
        dispatcher.remote_token_messenger(1) == 0,
        "Remote token messenger should be zero initially",
    );
}

#[test]
fn test_add_and_remove_remote_token_messenger_functionality() {
    let (owner, _, token_messenger1, token_messenger2) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    let domain2: u32 = 2_u32;

    // Spy on events
    let mut spy = spy_events();

    // Add remote token messenger as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_remote_token_messenger(domain1, token_messenger1);

    // Check that remote token messenger was set correctly
    assert!(
        dispatcher.remote_token_messenger(domain1) == token_messenger1,
        "Remote token messenger should be set correctly",
    );
    assert!(
        dispatcher.remote_token_messenger(domain2) == 0,
        "Other domain should have zero remote token messenger",
    );

    // Verify RemoteTokenMessengerAdded event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    RemoteTokenMessengerControllerComponent::Event::RemoteTokenMessengerAdded(
                        RemoteTokenMessengerControllerComponent::RemoteTokenMessengerAdded {
                            domain: domain1, token_messenger: token_messenger1,
                        },
                    ),
                ),
            ],
        );

    // Add remote token messenger for second domain
    dispatcher.add_remote_token_messenger(domain2, token_messenger2);

    // check both domains have correct remote token messenger
    assert!(
        dispatcher.remote_token_messenger(domain1) == token_messenger1,
        "First domain remote token messenger should remain unchanged",
    );
    assert!(
        dispatcher.remote_token_messenger(domain2) == token_messenger2,
        "Second domain remote token messenger should be set correctly",
    );

    // Remove remote token messenger for first domain
    dispatcher.remove_remote_token_messenger(domain1);

    // check first domain has zero remote token messenger
    assert!(
        dispatcher.remote_token_messenger(domain1) == 0,
        "First domain remote token messenger should be zero",
    );

    // check second domain has correct remote token messenger
    assert!(
        dispatcher.remote_token_messenger(domain2) == token_messenger2,
        "Second domain remote token messenger should remain unchanged",
    );

    // Verify RemoteTokenMessengerRemoved event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    RemoteTokenMessengerControllerComponent::Event::RemoteTokenMessengerRemoved(
                        RemoteTokenMessengerControllerComponent::RemoteTokenMessengerRemoved {
                            domain: domain1, token_messenger: token_messenger1,
                        },
                    ),
                ),
            ],
        );

    // Remove remote token messenger for second domain
    dispatcher.remove_remote_token_messenger(domain2);

    // check both domains have zero remote token messenger
    assert!(
        dispatcher.remote_token_messenger(domain1) == 0,
        "First domain remote token messenger should be zero",
    );
    assert!(
        dispatcher.remote_token_messenger(domain2) == 0,
        "Second domain remote token messenger should be zero",
    );
}

// ================================
// ERROR HANDLING TESTS
// ================================
#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_add_remote_token_messenger_rejects_non_owner() {
    let (owner, unauthorized, token_messenger1, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.add_remote_token_messenger(domain1, token_messenger1);
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_add_remote_token_messenger_rejects_zero_address() {
    let (owner, _, _, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    let zero_address: u256 = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_remote_token_messenger(domain1, zero_address);
}

#[test]
#[should_panic(expected: ('Token messenger already set',))]
fn test_add_remote_token_messenger_rejects_already_set() {
    let (owner, _, token_messenger1, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_remote_token_messenger(domain1, token_messenger1);
    dispatcher.add_remote_token_messenger(domain1, token_messenger1);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_remove_remote_token_messenger_rejects_non_owner() {
    let (owner, unauthorized, _, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.remove_remote_token_messenger(domain1);
}

#[test]
#[should_panic(expected: ('No token messenger set',))]
fn test_remove_remote_token_messenger_rejects_no_token_messenger_set() {
    let (owner, _, _, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };
    let domain1: u32 = 1_u32;
    start_cheat_caller_address(contract_address, owner);
    dispatcher.remove_remote_token_messenger(domain1);
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_assert_only_remote_token_messenger_functionality() {
    let (owner, _, token_messenger1, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let remote_token_messenger_controller_dispatcher = IRemoteTokenMessengerControllerDispatcher {
        contract_address,
    };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    let domain1: u32 = 1_u32;
    start_cheat_caller_address(contract_address, owner);

    assert!(
        remote_token_messenger_controller_dispatcher.remote_token_messenger(domain1) == 0,
        "First domain remote token messenger should be zero",
    );
    // add remote token messenger
    remote_token_messenger_controller_dispatcher
        .add_remote_token_messenger(domain1, token_messenger1);

    // check remote token messenger is set correctly
    assert!(
        remote_token_messenger_controller_dispatcher
            .remote_token_messenger(domain1) == token_messenger1,
        "First domain remote token messenger should be set correctly",
    );

    // check internal function works
    test_dispatcher.test_assert_only_remote_token_messenger(domain1, token_messenger1);

    // remove remote token messenger
    remote_token_messenger_controller_dispatcher.remove_remote_token_messenger(domain1);
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_assert_only_remote_token_messenger_rejects_zero_address() {
    let (owner, _, _, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let domain1: u32 = 1_u32;

    start_cheat_caller_address(contract_address, owner);
    test_dispatcher.test_assert_only_remote_token_messenger(domain1, 0);
}

#[test]
#[should_panic(expected: ('Remote token messenger invalid',))]
fn test_assert_only_remote_token_messenger_rejects_invalid_remote_token_messenger() {
    let (owner, _, token_messenger1, token_messenger2) = get_test_values();
    let contract_address = deploy_mock_contract(owner);
    let remote_token_messenger_controller_dispatcher = IRemoteTokenMessengerControllerDispatcher {
        contract_address,
    };
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let domain1: u32 = 1_u32;

    start_cheat_caller_address(contract_address, owner);
    remote_token_messenger_controller_dispatcher
        .add_remote_token_messenger(domain1, token_messenger1);
    test_dispatcher.test_assert_only_remote_token_messenger(domain1, token_messenger2);
}

// ================================
// INTEGRATION WITH OWNABLE
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_old_owner_cannot_set_remote_token_messenger_after_transfer() {
    let (owner, _, token_messenger1, _) = get_test_values();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner);
    let remote_token_messenger_controller_dispatcher = IRemoteTokenMessengerControllerDispatcher {
        contract_address,
    };
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let domain1: u32 = 1_u32;

    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(contract_address);

    // Old owner should not be able to set remote token messenger
    start_cheat_caller_address(contract_address, owner);
    remote_token_messenger_controller_dispatcher
        .add_remote_token_messenger(domain1, token_messenger1);
}
