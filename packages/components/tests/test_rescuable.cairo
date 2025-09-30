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

use cctp_components::rescuable::{
    IRescuableDispatcher, IRescuableDispatcherTrait, RescuableComponent,
};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use stablecoin::{IFiatTokenDispatcher, IFiatTokenDispatcherTrait};
use starknet::ContractAddress;

// Mock ERC20 contract for testing token rescue functionality
#[starknet::contract]
mod MockERC20Contract {
    use stablecoin::IFiatToken;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        transfer_should_fail: bool,
    }

    #[abi(embed_v0)]
    impl ERC20Impl of IFiatToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Implementation for test purposes
            let to_balance = self.balances.read(to);
            self.balances.write(to, to_balance + amount);
        }

        fn burn(ref self: ContractState, amount: u256) {
            // Implementation for test purposes
            let caller = starknet::get_caller_address();
            let caller_balance = self.balances.read(caller);
            assert!(caller_balance >= amount, "Insufficient balance to burn");
            self.balances.write(caller, caller_balance - amount);
        }

        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
            if self.transfer_should_fail.read() {
                return false;
            }
            // Simple transfer logic for testing
            let caller = starknet::get_caller_address();
            let caller_balance = self.balances.read(caller);
            if caller_balance >= amount {
                self.balances.write(caller, caller_balance - amount);
                let to_balance = self.balances.read(to);
                self.balances.write(to, to_balance + amount);
                true
            } else {
                false
            }
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn total_supply(self: @ContractState) -> u256 {
            // Not needed for tests
            0
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply()
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            // Not needed for these tests
            false
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            self.transfer_from(from, to, amount)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            // Not needed for these tests
            false
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            // Not needed for these tests
            0
        }

        fn version(self: @ContractState) -> u8 {
            // Not needed for these tests
            1_u8
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn set_balance(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.balances.write(account, amount);
        }

        #[external(v0)]
        fn get_balance(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        #[external(v0)]
        fn set_transfer_should_fail(ref self: ContractState, should_fail: bool) {
            self.transfer_should_fail.write(should_fail);
        }
    }
}

#[starknet::interface]
trait IMockERC20TestHelper<TContractState> {
    fn set_balance(ref self: TContractState, account: ContractAddress, amount: u256);
    fn get_balance(self: @TContractState, account: ContractAddress) -> u256;
    fn set_transfer_should_fail(ref self: TContractState, should_fail: bool);
}

// Mock contract that uses both ownable and rescuable components for testing
#[starknet::contract]
mod MockRescuableContract {
    use cctp_components::rescuable::RescuableComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(path: RescuableComponent, storage: rescuable, event: RescuableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl RescuableImpl = RescuableComponent::Rescuable<ContractState>;
    impl RescuableInternalImpl = RescuableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        rescuable: RescuableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        RescuableEvent: RescuableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, rescuer: ContractAddress) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }
        if !rescuer.is_zero() {
            self.rescuable.initializer(rescuer);
        }
    }

    // Expose internal functions for testing
    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_rescuable_initializer(ref self: ContractState, rescuer: ContractAddress) {
            self.rescuable.initializer(rescuer);
        }

        #[external(v0)]
        fn test_assert_only_rescuer(self: @ContractState) {
            self.rescuable.assert_only_rescuer();
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
    fn test_rescuable_initializer(ref self: TContractState, rescuer: ContractAddress);
    fn test_assert_only_rescuer(self: @TContractState);
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_erc20_contract() -> ContractAddress {
    let contract = declare("MockERC20Contract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn deploy_mock_rescuable_contract(
    owner: ContractAddress, rescuer: ContractAddress,
) -> ContractAddress {
    let contract = declare("MockRescuableContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), rescuer.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_rescuable_contract() -> ContractAddress {
    let contract = declare("MockRescuableContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![zero_address.into(), zero_address.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_addresses() -> (
    ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let rescuer: ContractAddress = 456.try_into().unwrap();
    let new_rescuer: ContractAddress = 'new_rescuer'.try_into().unwrap();
    let recipient: ContractAddress = 'recipient'.try_into().unwrap();
    let unauthorized: ContractAddress = 'unauthorized'.try_into().unwrap();
    (owner, rescuer, new_rescuer, recipient, unauthorized)
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initialized_contract_state() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Check that rescuer is set correctly
    assert!(dispatcher.rescuer() == rescuer, "Rescuer should return the correct address");
}

#[test]
fn test_uninitialized_contract_state() {
    let contract_address = deploy_uninitialized_rescuable_contract();
    let dispatcher = IRescuableDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();

    // Check that rescuer is zero when uninitialized
    assert!(dispatcher.rescuer() == zero_address, "Uninitialized rescuer should be zero address");
}

#[test]
fn test_update_rescuer_functionality() {
    let (owner, rescuer, new_rescuer, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Spy on events
    let mut spy = spy_events();

    // Update rescuer as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_rescuer(new_rescuer);
    stop_cheat_caller_address(contract_address);

    // Check that rescuer was updated
    assert!(dispatcher.rescuer() == new_rescuer, "Rescuer should be updated");

    // Verify RescuerChanged event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    RescuableComponent::Event::RescuerChanged(
                        RescuableComponent::RescuerChanged { new_rescuer: new_rescuer },
                    ),
                ),
            ],
        );
}

#[test]
fn test_rescue_erc20_functionality() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Deploy mock ERC20 contract
    let erc20_address = deploy_mock_erc20_contract();
    let erc20_dispatcher = IFiatTokenDispatcher { contract_address: erc20_address };
    let erc20_test_helper = IMockERC20TestHelperDispatcher { contract_address: erc20_address };

    // Set up ERC20 contract with some balance for the rescuable contract
    let rescue_amount: u256 = 1000000;
    erc20_test_helper.set_balance(contract_address, rescue_amount);

    // Verify initial balance
    assert!(
        erc20_dispatcher.balance_of(contract_address) == rescue_amount,
        "Contract should have initial balance",
    );
    assert!(
        erc20_dispatcher.balance_of(recipient) == 0, "Recipient should start with zero balance",
    );

    // Rescue tokens as rescuer
    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address, recipient, rescue_amount);
    stop_cheat_caller_address(contract_address);

    // Verify tokens were rescued
    assert!(erc20_dispatcher.balance_of(contract_address) == 0, "Contract balance should be zero");
    assert!(
        erc20_dispatcher.balance_of(recipient) == rescue_amount, "Recipient should receive tokens",
    );
}

#[test]
fn test_complete_rescuable_workflow() {
    let (owner, rescuer, new_rescuer, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Deploy mock ERC20 contract
    let erc20_address = deploy_mock_erc20_contract();
    let erc20_dispatcher = IFiatTokenDispatcher { contract_address: erc20_address };
    let erc20_test_helper = IMockERC20TestHelperDispatcher { contract_address: erc20_address };

    // 1. Owner updates rescuer
    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_rescuer(new_rescuer);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.rescuer() == new_rescuer, "Rescuer should be updated");

    // 2. Set up tokens for rescue
    let rescue_amount: u256 = 500000;
    erc20_test_helper.set_balance(contract_address, rescue_amount);

    // 3. New rescuer rescues tokens
    start_cheat_caller_address(contract_address, new_rescuer);
    dispatcher.rescue_erc20(erc20_address, recipient, rescue_amount);
    stop_cheat_caller_address(contract_address);

    // Verify final state
    assert!(dispatcher.rescuer() == new_rescuer, "Rescuer should remain updated");
    assert!(
        erc20_dispatcher.balance_of(recipient) == rescue_amount, "Recipient should receive tokens",
    );
}

// ================================
// ERROR HANDLING TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_rescuer_rejects_non_owner() {
    let (owner, rescuer, new_rescuer, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.update_rescuer(new_rescuer);
}

#[test]
#[should_panic(expected: ('Rescuer cannot be zero address',))]
fn test_update_rescuer_rejects_zero_address() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    let zero_address: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_rescuer(zero_address);
}

#[test]
#[should_panic(expected: ('Caller is not the rescuer',))]
fn test_rescue_erc20_rejects_non_rescuer() {
    let (owner, rescuer, _, recipient, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };
    let erc20_address = deploy_mock_erc20_contract();

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.rescue_erc20(erc20_address, recipient, 1000);
}

#[test]
#[should_panic(expected: ('Token cannot be zero address',))]
fn test_rescue_erc20_rejects_zero_token_address() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    let zero_address: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(zero_address, recipient, 1000);
}

#[test]
#[should_panic(expected: ('Recipient cannot be zero',))]
fn test_rescue_erc20_rejects_zero_recipient() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };
    let erc20_address = deploy_mock_erc20_contract();

    let zero_address: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address, zero_address, 1000);
}

#[test]
#[should_panic(expected: ('Amount cannot be zero',))]
fn test_rescue_erc20_rejects_zero_amount() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };
    let erc20_address = deploy_mock_erc20_contract();

    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address, recipient, 0);
}


#[test]
#[should_panic(expected: ('Rescue transfer failed',))]
fn test_rescue_erc20_rejects_failed_transfer() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Deploy mock ERC20 contract and set it to fail transfers
    let erc20_address = deploy_mock_erc20_contract();
    let erc20_test_helper = IMockERC20TestHelperDispatcher { contract_address: erc20_address };

    // Set balance and configure transfer to fail
    let rescue_amount: u256 = 1000;
    erc20_test_helper.set_balance(contract_address, rescue_amount);
    erc20_test_helper.set_transfer_should_fail(true);

    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address, recipient, rescue_amount);
}

#[test]
#[should_panic]
fn test_rescue_erc20_insufficient_balance_fails_on_transfer() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Deploy mock ERC20 contract
    let erc20_address = deploy_mock_erc20_contract();
    let erc20_test_helper = IMockERC20TestHelperDispatcher { contract_address: erc20_address };

    // Set up contract with some balance, but less than what we try to rescue
    let contract_balance: u256 = 500;
    let rescue_amount: u256 = 1000; // More than available balance
    erc20_test_helper.set_balance(contract_address, contract_balance);

    // Try to rescue more tokens than available - transfer will return false
    // and rescue_erc20 will panic with 'Rescue transfer failed'
    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address, recipient, rescue_amount);
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_initializer_functionality() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_rescuable_contract();
    let dispatcher = IRescuableDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for rescuable)
    test_dispatcher.test_ownable_initializer(owner);
    // Initialize rescuable
    test_dispatcher.test_rescuable_initializer(rescuer);

    // Check that rescuer is set
    assert!(dispatcher.rescuer() == rescuer, "Initializer should set the rescuer");
}

#[test]
#[should_panic(expected: ('Rescuer cannot be zero address',))]
fn test_initializer_rejects_zero_address() {
    let (owner, _, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_rescuable_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    test_dispatcher.test_ownable_initializer(owner);
    let zero_address: ContractAddress = 0.try_into().unwrap();
    test_dispatcher.test_rescuable_initializer(zero_address);
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initializer_rejects_already_initialized() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Try to initialize again - should fail
    test_dispatcher.test_rescuable_initializer(rescuer);
}

#[test]
fn test_assert_only_rescuer_functionality() {
    let (owner, rescuer, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Should pass for rescuer
    start_cheat_caller_address(contract_address, rescuer);
    test_dispatcher.test_assert_only_rescuer();
}

#[test]
#[should_panic(expected: ('Caller is not the rescuer',))]
fn test_assert_only_rescuer_fails_for_non_rescuer() {
    let (owner, rescuer, _, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    test_dispatcher.test_assert_only_rescuer();
}

// ================================
// INTEGRATION WITH OWNABLE
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_old_owner_cannot_update_rescuer_after_transfer() {
    let (owner, rescuer, new_rescuer, _, _) = get_test_addresses();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let dispatcher = IRescuableDispatcher { contract_address };

    // Transfer ownership
    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(contract_address);

    // Old owner should not be able to update rescuer
    start_cheat_caller_address(contract_address, owner);
    dispatcher.update_rescuer(new_rescuer);
}

#[test]
fn test_new_owner_can_update_rescuer() {
    let (owner, rescuer, new_rescuer, _, _) = get_test_addresses();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let dispatcher = IRescuableDispatcher { contract_address };

    // Transfer ownership
    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();

    // New owner should be able to update rescuer
    dispatcher.update_rescuer(new_rescuer);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.rescuer() == new_rescuer, "New owner should be able to update rescuer");
}

#[test]
fn test_multiple_rescue_operations() {
    let (owner, rescuer, _, recipient, _) = get_test_addresses();
    let contract_address = deploy_mock_rescuable_contract(owner, rescuer);
    let dispatcher = IRescuableDispatcher { contract_address };

    // Deploy multiple mock ERC20 contracts
    let erc20_address1 = deploy_mock_erc20_contract();
    let erc20_address2 = deploy_mock_erc20_contract();
    let erc20_dispatcher1 = IFiatTokenDispatcher { contract_address: erc20_address1 };
    let erc20_dispatcher2 = IFiatTokenDispatcher { contract_address: erc20_address2 };
    let erc20_test_helper1 = IMockERC20TestHelperDispatcher { contract_address: erc20_address1 };
    let erc20_test_helper2 = IMockERC20TestHelperDispatcher { contract_address: erc20_address2 };

    // Set up balances
    let rescue_amount1: u256 = 100000;
    let rescue_amount2: u256 = 200000;
    erc20_test_helper1.set_balance(contract_address, rescue_amount1);
    erc20_test_helper2.set_balance(contract_address, rescue_amount2);

    // Rescue tokens from both contracts
    start_cheat_caller_address(contract_address, rescuer);
    dispatcher.rescue_erc20(erc20_address1, recipient, rescue_amount1);
    dispatcher.rescue_erc20(erc20_address2, recipient, rescue_amount2);
    stop_cheat_caller_address(contract_address);

    // Verify both rescues succeeded
    assert!(
        erc20_dispatcher1.balance_of(recipient) == rescue_amount1, "First rescue should succeed",
    );
    assert!(
        erc20_dispatcher2.balance_of(recipient) == rescue_amount2, "Second rescue should succeed",
    );
}
