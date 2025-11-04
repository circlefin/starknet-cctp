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

use cctp_components::min_fee_controller::{
    IMinFeeControllerDispatcher, IMinFeeControllerDispatcherTrait, MinFeeControllerComponent,
};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Mock contract that uses both ownable and min_fee_controller components for testing
#[starknet::contract]
mod MockMinFeeControllerContract {
    use cctp_components::min_fee_controller::MinFeeControllerComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(
        path: MinFeeControllerComponent, storage: min_fee_controller, event: MinFeeControllerEvent,
    );
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl MinFeeControllerImpl =
        MinFeeControllerComponent::MinFeeController<ContractState>;
    impl MinFeeControllerInternalImpl = MinFeeControllerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        min_fee_controller: MinFeeControllerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        MinFeeControllerEvent: MinFeeControllerComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, fee_controller: ContractAddress,
    ) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }
        if !fee_controller.is_zero() {
            self.min_fee_controller.initializer(fee_controller);
        }
    }

    // Expose internal functions for testing
    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_min_fee_controller_initializer(
            ref self: ContractState, fee_controller: ContractAddress,
        ) {
            self.min_fee_controller.initializer(fee_controller);
        }

        #[external(v0)]
        fn test_assert_only_min_fee_controller(self: @ContractState) {
            self.min_fee_controller.assert_only_min_fee_controller();
        }

        #[external(v0)]
        fn test_calc_min_fee_amount(
            self: @ContractState, burn_token: ContractAddress, amount: u256,
        ) -> u256 {
            self.min_fee_controller.calc_min_fee_amount(burn_token, amount)
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
    fn test_min_fee_controller_initializer(
        ref self: TContractState, fee_controller: ContractAddress,
    );
    fn test_assert_only_min_fee_controller(self: @TContractState);
    fn test_calc_min_fee_amount(
        self: @TContractState, burn_token: ContractAddress, amount: u256,
    ) -> u256;
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_contract(
    owner: ContractAddress, fee_controller: ContractAddress,
) -> ContractAddress {
    let contract = declare("MockMinFeeControllerContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), fee_controller.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_contract() -> ContractAddress {
    let contract = declare("MockMinFeeControllerContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![zero_address.into(), zero_address.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_addresses() -> (
    ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let fee_controller: ContractAddress = 456.try_into().unwrap();
    let burn_token: ContractAddress = 789.try_into().unwrap();
    let burn_token2: ContractAddress = 999.try_into().unwrap();
    let unauthorized: ContractAddress = 111.try_into().unwrap();
    (owner, fee_controller, burn_token, burn_token2, unauthorized)
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initialized_contract_state() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // Check that fee controller is set correctly and min fees are zero initially
    assert!(
        dispatcher.min_fee_controller() == fee_controller,
        "Fee controller should return the correct address",
    );
    assert!(dispatcher.min_fee(burn_token) == 0, "Min fee should be zero initially");
}

#[test]
fn test_uninitialized_contract_state() {
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = IMinFeeControllerDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let burn_token: ContractAddress = 789.try_into().unwrap();

    // Check that fee controller is zero when uninitialized
    assert!(
        dispatcher.min_fee_controller() == zero_address,
        "Uninitialized fee controller should be zero address",
    );
    assert!(dispatcher.min_fee(burn_token) == 0, "Min fee should be zero for uninitialized");
}

#[test]
fn test_set_min_fee_controller_functionality() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let new_fee_controller: ContractAddress = 'new_fee_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // Spy on events
    let mut spy = spy_events();

    // Update fee controller as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_min_fee_controller(new_fee_controller);
    stop_cheat_caller_address(contract_address);

    // Check that fee controller was updated
    assert!(
        dispatcher.min_fee_controller() == new_fee_controller, "Fee controller should be updated",
    );

    // Verify MinFeeControllerSet event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MinFeeControllerComponent::Event::MinFeeControllerSet(
                        MinFeeControllerComponent::MinFeeControllerSet {
                            min_fee_controller: new_fee_controller,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_set_min_fee_functionality() {
    let (owner, fee_controller, burn_token, burn_token2, _) = get_test_addresses();
    let min_fee: u256 = 1000;
    let min_fee2: u256 = 2000;
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // Spy on events
    let mut spy = spy_events();

    // Set min fee for first token as fee controller
    start_cheat_caller_address(contract_address, fee_controller);
    dispatcher.set_min_fee(burn_token, min_fee);

    // Check that min fee was set
    assert!(dispatcher.min_fee(burn_token) == min_fee, "Min fee should be set correctly");
    assert!(dispatcher.min_fee(burn_token2) == 0, "Other tokens should still have zero fee");

    // Verify MinFeeSet event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MinFeeControllerComponent::Event::MinFeeSet(
                        MinFeeControllerComponent::MinFeeSet {
                            burn_token: burn_token, min_fee: min_fee,
                        },
                    ),
                ),
            ],
        );

    // Set different fee for second token
    dispatcher.set_min_fee(burn_token2, min_fee2);
    stop_cheat_caller_address(contract_address);

    // Check both fees are set independently
    assert!(dispatcher.min_fee(burn_token) == min_fee, "First token fee should remain");
    assert!(dispatcher.min_fee(burn_token2) == min_fee2, "Second token fee should be set");
}

#[test]
fn test_complete_min_fee_workflow() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let new_fee_controller: ContractAddress = 'new_fee_controller'.try_into().unwrap();
    let min_fee: u256 = 5000;
    let updated_fee: u256 = 7500;
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // 1. Owner updates fee controller
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_min_fee_controller(new_fee_controller);
    stop_cheat_caller_address(contract_address);
    assert!(
        dispatcher.min_fee_controller() == new_fee_controller, "Fee controller should be updated",
    );

    // 2. New fee controller sets min fee
    start_cheat_caller_address(contract_address, new_fee_controller);
    dispatcher.set_min_fee(burn_token, min_fee);
    assert!(dispatcher.min_fee(burn_token) == min_fee, "Min fee should be set");

    // 3. New fee controller updates min fee
    dispatcher.set_min_fee(burn_token, updated_fee);
    stop_cheat_caller_address(contract_address);
    assert!(dispatcher.min_fee(burn_token) == updated_fee, "Min fee should be updated");
}

// ================================
// ERROR HANDLING TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_min_fee_controller_rejects_non_owner() {
    let (owner, fee_controller, _, _, unauthorized) = get_test_addresses();
    let new_fee_controller: ContractAddress = 'new_fee_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.set_min_fee_controller(new_fee_controller);
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_set_min_fee_controller_rejects_zero_address() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    let zero_address: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_min_fee_controller(zero_address);
}

#[test]
#[should_panic(expected: ('Caller not min fee controller',))]
fn test_set_min_fee_rejects_non_fee_controller() {
    let (owner, fee_controller, burn_token, _, unauthorized) = get_test_addresses();
    let min_fee: u256 = 1000;
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.set_min_fee(burn_token, min_fee);
}

#[test]
#[should_panic(expected: ('Min fee too high',))]
fn test_set_min_fee_rejects_too_high_fee() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // MIN_FEE_MULTIPLIER is 10_000_000, so use that value (should fail)
    let too_high_fee: u256 = 10_000_000;
    start_cheat_caller_address(contract_address, fee_controller);
    dispatcher.set_min_fee(burn_token, too_high_fee);
}

#[test]
fn test_set_min_fee_accepts_max_valid_fee() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // MAX valid fee is MIN_FEE_MULTIPLIER - 1
    let max_valid_fee: u256 = 9_999_999;
    start_cheat_caller_address(contract_address, fee_controller);
    dispatcher.set_min_fee(burn_token, max_valid_fee);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.min_fee(burn_token) == max_valid_fee, "Max valid fee should be accepted");
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_initializer_functionality() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let min_fee_dispatcher = IMinFeeControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for min_fee_controller)
    test_dispatcher.test_ownable_initializer(owner);
    // Initialize min_fee_controller with fee controller
    test_dispatcher.test_min_fee_controller_initializer(fee_controller);

    // Check that fee controller is set
    assert!(
        min_fee_dispatcher.min_fee_controller() == fee_controller,
        "Initializer should set the fee controller",
    );
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_initializer_rejects_zero_address() {
    let (owner, _, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    test_dispatcher.test_ownable_initializer(owner);
    let zero_address: ContractAddress = 0.try_into().unwrap();
    test_dispatcher.test_min_fee_controller_initializer(zero_address);
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initializer_rejects_already_initialized() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Try to initialize again - should fail
    test_dispatcher.test_min_fee_controller_initializer(fee_controller);
}

#[test]
fn test_assert_only_min_fee_controller_functionality() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Should pass for fee controller
    start_cheat_caller_address(contract_address, fee_controller);
    test_dispatcher.test_assert_only_min_fee_controller();
}

#[test]
#[should_panic(expected: ('Caller not min fee controller',))]
fn test_assert_only_min_fee_controller_fails_for_non_fee_controller() {
    let (owner, fee_controller, _, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    test_dispatcher.test_assert_only_min_fee_controller();
}

#[test]
fn test_calc_min_fee_amount_functionality() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let min_fee_dispatcher = IMinFeeControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Test with zero fee (should return 0)
    let amount: u256 = 1000000;
    let result = test_dispatcher.test_calc_min_fee_amount(burn_token, amount);
    assert!(result == 0, "Should return 0 when min fee is not set");

    // Set a min fee and test calculation
    start_cheat_caller_address(contract_address, fee_controller);
    let min_fee: u256 = 100000; // 1% (100000 / 10000000)
    min_fee_dispatcher.set_min_fee(burn_token, min_fee);
    stop_cheat_caller_address(contract_address);

    // Test calculation: (1000000 * 100000) / 10000000 = 10000
    let result = test_dispatcher.test_calc_min_fee_amount(burn_token, amount);
    assert!(result == 10000, "Should calculate correct min fee amount");

    // Test edge case where calculation would result in 0 but should return 1
    let small_amount: u256 = 50; // (50 * 100000) / 10000000 = 0.5 -> should return 1
    let result = test_dispatcher.test_calc_min_fee_amount(burn_token, small_amount);
    assert!(result == 1, "Should return 1 when calculation results in 0");
}

#[test]
fn test_calc_min_fee_amount_precision() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let min_fee_dispatcher = IMinFeeControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Set min fee to 0.01% (1000 / 10000000)
    start_cheat_caller_address(contract_address, fee_controller);
    let min_fee: u256 = 1000;
    min_fee_dispatcher.set_min_fee(burn_token, min_fee);
    stop_cheat_caller_address(contract_address);

    // Test various amounts
    let amount1: u256 = 10000000; // (10000000 * 1000) / 10000000 = 1000
    let result1 = test_dispatcher.test_calc_min_fee_amount(burn_token, amount1);
    assert!(result1 == 1000, "Should calculate correct fee for large amount");

    let amount2: u256 = 100000; // (100000 * 1000) / 10000000 = 10
    let result2 = test_dispatcher.test_calc_min_fee_amount(burn_token, amount2);
    assert!(result2 == 10, "Should calculate correct fee for medium amount");

    let amount3: u256 = 5000; // (5000 * 1000) / 10000000 = 0.5 -> should return 1
    let result3 = test_dispatcher.test_calc_min_fee_amount(burn_token, amount3);
    assert!(result3 == 1, "Should return 1 for small amounts that round to 0");
}

#[test]
#[should_panic(expected: ('u256_mul Overflow',))]
fn test_calc_min_fee_amount_overflow() {
    let (owner, fee_controller, burn_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let min_fee_dispatcher = IMinFeeControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Set min fee to maximum allowed value (just under MIN_FEE_MULTIPLIER)
    start_cheat_caller_address(contract_address, fee_controller);
    let max_min_fee: u256 = 9_999_999; // Close to 10_000_000 (MIN_FEE_MULTIPLIER)
    min_fee_dispatcher.set_min_fee(burn_token, max_min_fee);
    stop_cheat_caller_address(contract_address);

    // Use an extremely large amount that will cause overflow when multiplied
    // u256::MAX is approximately 2^256 - 1 ≈ 1.15 × 10^77
    // We use a value that will definitely cause overflow: near u256::MAX
    let overflow_amount: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00; // Very close to u256::MAX

    // This should panic due to overflow in the calculation (amount * min_fee)
    test_dispatcher.test_calc_min_fee_amount(burn_token, overflow_amount);
}

// ================================
// INTEGRATION WITH OWNABLE
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_old_owner_cannot_set_fee_controller_after_transfer() {
    let (owner, fee_controller, _, _, _) = get_test_addresses();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let new_fee_controller: ContractAddress = 'new_fee_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let min_fee_dispatcher = IMinFeeControllerDispatcher { contract_address };

    // Transfer ownership
    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(contract_address);

    // Old owner should not be able to update fee controller
    start_cheat_caller_address(contract_address, owner);
    min_fee_dispatcher.set_min_fee_controller(new_fee_controller);
}

#[test]
fn test_multiple_tokens_independent_fees() {
    let (owner, fee_controller, burn_token, burn_token2, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, fee_controller);
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    let fee1: u256 = 50000; // 0.5%
    let fee2: u256 = 100000; // 1%

    // Set different fees for different tokens
    start_cheat_caller_address(contract_address, fee_controller);
    dispatcher.set_min_fee(burn_token, fee1);
    dispatcher.set_min_fee(burn_token2, fee2);
    stop_cheat_caller_address(contract_address);

    // Verify fees are independent
    assert!(dispatcher.min_fee(burn_token) == fee1, "First token should have correct fee");
    assert!(dispatcher.min_fee(burn_token2) == fee2, "Second token should have correct fee");

    // Update one fee and verify the other is unchanged
    start_cheat_caller_address(contract_address, fee_controller);
    dispatcher.set_min_fee(burn_token, fee2);
    stop_cheat_caller_address(contract_address);

    assert!(dispatcher.min_fee(burn_token) == fee2, "First token fee should be updated");
    assert!(dispatcher.min_fee(burn_token2) == fee2, "Second token fee should remain unchanged");
}
