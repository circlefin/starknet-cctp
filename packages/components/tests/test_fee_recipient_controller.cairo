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

use cctp_components::fee_recipient_controller::{
    FeeRecipientControllerComponent, IFeeRecipientControllerDispatcher,
    IFeeRecipientControllerDispatcherTrait,
};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Mock contract that uses both ownable and fee_recipient_controller components for testing
#[starknet::contract]
mod MockFeeRecipientControllerContract {
    use cctp_components::fee_recipient_controller::FeeRecipientControllerComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(
        path: FeeRecipientControllerComponent,
        storage: fee_recipient_controller,
        event: FeeRecipientControllerEvent,
    );
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl FeeRecipientControllerImpl =
        FeeRecipientControllerComponent::FeeRecipientController<ContractState>;
    impl FeeRecipientControllerInternalImpl =
        FeeRecipientControllerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        fee_recipient_controller: FeeRecipientControllerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        FeeRecipientControllerEvent: FeeRecipientControllerComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, fee_recipient: ContractAddress,
    ) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }
        if !fee_recipient.is_zero() {
            self.fee_recipient_controller.initializer(fee_recipient);
        }
    }

    // Expose internal functions for testing
    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_fee_recipient_controller_initializer(
            ref self: ContractState, fee_recipient: ContractAddress,
        ) {
            self.fee_recipient_controller.initializer(fee_recipient);
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
    fn test_fee_recipient_controller_initializer(
        ref self: TContractState, fee_recipient: ContractAddress,
    );
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_contract(owner: ContractAddress, fee_recipient: ContractAddress) -> ContractAddress {
    let contract = declare("MockFeeRecipientControllerContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), fee_recipient.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_contract() -> ContractAddress {
    let contract = declare("MockFeeRecipientControllerContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![zero_address.into(), zero_address.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_values() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let unauthorized: ContractAddress = 456.try_into().unwrap();
    let fee_recipient: ContractAddress = 789.try_into().unwrap();
    let fee_recipient2: ContractAddress = 999.try_into().unwrap();
    (owner, unauthorized, fee_recipient, fee_recipient2)
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initialized_contract_state() {
    let (owner, _, fee_recipient, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };

    // Check that fee recipient set correctly
    assert!(
        dispatcher.fee_recipient() == fee_recipient,
        "Fee recipient should be set to the correct value",
    );
}

#[test]
fn test_uninitialized_contract_state() {
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();

    // Check that fee recipient is zero
    assert!(
        dispatcher.fee_recipient() == zero_address,
        "Uninitialized fee recipient should be zero address",
    );
}

#[test]
fn test_set_fee_recipient_functionality() {
    let (owner, _, fee_recipient, fee_recipient2) = get_test_values();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };

    // Spy on events
    let mut spy = spy_events();

    // Set fee recipient as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_fee_recipient(fee_recipient2);

    // Check that fee recipient is set
    assert!(
        dispatcher.fee_recipient() == fee_recipient2,
        "Fee recipient should be set to the correct value",
    );

    // Verify FeeRecipientSet event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    FeeRecipientControllerComponent::Event::FeeRecipientSet(
                        FeeRecipientControllerComponent::FeeRecipientSet {
                            fee_recipient: fee_recipient2,
                        },
                    ),
                ),
            ],
        );
}

// ================================
// ERROR HANDLING TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_fee_recipient_rejects_non_owner() {
    let (owner, unauthorized, fee_recipient, fee_recipient2) = get_test_values();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };
    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.set_fee_recipient(fee_recipient2);
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_set_fee_recipient_rejects_zero_address() {
    let (owner, _, fee_recipient, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_fee_recipient(zero_address);
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_initializer_functionality() {
    let (owner, _, fee_recipient, _) = get_test_values();
    let contract_address = deploy_uninitialized_contract();
    let fee_recipient_controller_dispatcher = IFeeRecipientControllerDispatcher {
        contract_address,
    };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for fee_recipient_controller)
    test_dispatcher.test_ownable_initializer(owner);
    // Initialize fee_recipient_controller with fee recipient
    test_dispatcher.test_fee_recipient_controller_initializer(fee_recipient);

    // Check that fee recipient is set
    assert!(
        fee_recipient_controller_dispatcher.fee_recipient() == fee_recipient,
        "Fee recipient should be set to the correct value",
    );
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_initializer_rejects_zero_address() {
    let (owner, _, _, _) = get_test_values();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for fee_recipient_controller)
    test_dispatcher.test_ownable_initializer(owner);
    let zero_address: ContractAddress = 0.try_into().unwrap();
    // Initialize fee_recipient_controller with zero address
    test_dispatcher.test_fee_recipient_controller_initializer(zero_address);
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initializer_rejects_already_initialized() {
    let (owner, _, fee_recipient, _) = get_test_values();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Try to initialize again - should fail
    test_dispatcher.test_fee_recipient_controller_initializer(fee_recipient);
}

// ================================
// INTEGRATION WITH OWNABLE
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_old_owner_cannot_set_fee_recipient_after_transfer() {
    let (owner, _, fee_recipient, fee_recipient2) = get_test_values();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, fee_recipient);
    let fee_recipient_controller_dispatcher = IFeeRecipientControllerDispatcher {
        contract_address,
    };
    let ownable_dispatcher = IOwnableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(contract_address);

    // Old owner should not be able to set fee recipient
    start_cheat_caller_address(contract_address, owner);
    fee_recipient_controller_dispatcher.set_fee_recipient(fee_recipient2);
}
