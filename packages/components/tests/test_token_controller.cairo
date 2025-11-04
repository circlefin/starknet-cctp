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

use cctp_components::token_controller::{
    ITokenControllerDispatcher, ITokenControllerDispatcherTrait, TokenControllerComponent,
};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use core::num::traits::Zero;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Mock contract that uses both ownable and token_controller components for testing
#[starknet::contract]
mod MockTokenControllerContract {
    use cctp_components::token_controller::TokenControllerComponent;
    use components::ownable::OwnableComponent;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    component!(
        path: TokenControllerComponent, storage: token_controller, event: TokenControllerEvent,
    );
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl TokenControllerImpl =
        TokenControllerComponent::TokenController<ContractState>;
    impl TokenControllerInternalImpl = TokenControllerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        token_controller: TokenControllerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        TokenControllerEvent: TokenControllerComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, token_controller: ContractAddress,
    ) {
        if !owner.is_zero() {
            self.ownable.initializer(owner);
        }
        if !token_controller.is_zero() {
            self.token_controller.initializer(token_controller);
        }
    }

    // Expose internal functions for testing
    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn test_token_controller_initializer(
            ref self: ContractState, token_controller: ContractAddress,
        ) {
            self.token_controller.initializer(token_controller);
        }

        #[external(v0)]
        fn test_assert_only_token_controller(self: @ContractState) {
            self.token_controller.assert_only_token_controller();
        }

        #[external(v0)]
        fn test_assert_within_burn_limit(
            self: @ContractState, token: ContractAddress, amount: u256,
        ) {
            self.token_controller.assert_within_burn_limit(token, amount);
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
    fn test_token_controller_initializer(
        ref self: TContractState, token_controller: ContractAddress,
    );
    fn test_assert_only_token_controller(self: @TContractState);
    fn test_assert_within_burn_limit(self: @TContractState, token: ContractAddress, amount: u256);
    fn test_ownable_initializer(ref self: TContractState, owner: ContractAddress);
}

fn deploy_mock_contract(
    owner: ContractAddress, token_controller: ContractAddress,
) -> ContractAddress {
    let contract = declare("MockTokenControllerContract").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), token_controller.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_uninitialized_contract() -> ContractAddress {
    let contract = declare("MockTokenControllerContract").unwrap().contract_class();
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let constructor_calldata = array![zero_address.into(), zero_address.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn get_test_addresses() -> (
    ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let token_controller: ContractAddress = 456.try_into().unwrap();
    let local_token: ContractAddress = 789.try_into().unwrap();
    let local_token2: ContractAddress = 999.try_into().unwrap();
    let unauthorized: ContractAddress = 111.try_into().unwrap();
    (owner, token_controller, local_token, local_token2, unauthorized)
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initialized_contract_state() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    // Check that token controller is set correctly
    assert!(
        dispatcher.token_controller() == token_controller,
        "Token controller should return the correct address",
    );

    // Check that local token lookup returns zero for unlinked pairs
    let local_token_result = dispatcher.get_local_token(1, 0x123);
    assert!(local_token_result.is_zero(), "Unlinked token pair should return zero address");
}

#[test]
fn test_uninitialized_contract_state() {
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let zero_address: ContractAddress = 0.try_into().unwrap();

    // Check that token controller is zero when uninitialized
    assert!(
        dispatcher.token_controller() == zero_address,
        "Uninitialized token controller should be zero address",
    );
}

#[test]
fn test_set_token_controller_functionality() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let new_token_controller: ContractAddress = 'new_token_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    // Spy on events
    let mut spy = spy_events();

    // Update token controller as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_token_controller(new_token_controller);
    stop_cheat_caller_address(contract_address);

    // Check that token controller was updated
    assert!(
        dispatcher.token_controller() == new_token_controller, "Token controller should be updated",
    );

    // Verify SetTokenController event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    TokenControllerComponent::Event::SetTokenController(
                        TokenControllerComponent::SetTokenController {
                            token_controller: new_token_controller,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_set_max_burn_amount_per_message_functionality() {
    let (owner, token_controller, local_token, local_token2, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let burn_limit: u256 = 1000000;
    let burn_limit2: u256 = 2000000;

    // Spy on events
    let mut spy = spy_events();

    // Set burn limit for first token as token controller
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit);

    // Check that burn limit was set
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit);
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit - 1);

    // Verify SetBurnLimitPerMessage event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    TokenControllerComponent::Event::SetBurnLimitPerMessage(
                        TokenControllerComponent::SetBurnLimitPerMessage {
                            token: local_token, burn_limit_per_message: burn_limit,
                        },
                    ),
                ),
            ],
        );

    // Set different limit for second token
    dispatcher.set_max_burn_amount_per_message(local_token2, burn_limit2);
    stop_cheat_caller_address(contract_address);

    // Verify both limits are set independently
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit);
    test_dispatcher.test_assert_within_burn_limit(local_token2, burn_limit2);
}

#[test]
fn test_link_token_pair_functionality() {
    let (owner, token_controller, local_token, local_token2, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let remote_domain: u32 = 1;
    let remote_token: u256 = 0x1234567890abcdef;
    let remote_domain2: u32 = 2;
    let remote_token2: u256 = 0xfedcba0987654321;

    // Spy on events
    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, token_controller);
    // Link first token pair
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);

    // Verify token pair is linked
    let local_token_result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(local_token_result == local_token, "Token pair should be linked");

    // Verify TokenPairLinked event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    TokenControllerComponent::Event::TokenPairLinked(
                        TokenControllerComponent::TokenPairLinked {
                            local_token, remote_domain, remote_token,
                        },
                    ),
                ),
            ],
        );

    // Link second token pair
    dispatcher.link_token_pair(local_token2, remote_domain2, remote_token2);
    stop_cheat_caller_address(contract_address);

    // Verify both pairs are linked independently
    let local_token_result2 = dispatcher.get_local_token(remote_domain2, remote_token2);
    assert!(local_token_result2 == local_token2, "Second token pair should be linked");
}

#[test]
fn test_unlink_token_pair_functionality() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let remote_domain: u32 = 1;
    let remote_token: u256 = 0x1234567890abcdef;

    start_cheat_caller_address(contract_address, token_controller);
    // First link the token pair
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);

    // Verify it's linked
    let local_token_result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(local_token_result == local_token, "Token pair should be linked");

    // Spy on events after linking
    let mut spy = spy_events();

    // Unlink the token pair
    dispatcher.unlink_token_pair(local_token, remote_domain, remote_token);
    stop_cheat_caller_address(contract_address);

    // Verify it's unlinked
    let local_token_result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(local_token_result.is_zero(), "Token pair should be unlinked");

    // Verify TokenPairUnlinked event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    TokenControllerComponent::Event::TokenPairUnlinked(
                        TokenControllerComponent::TokenPairUnlinked {
                            local_token, remote_domain, remote_token,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_complete_token_controller_workflow() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let new_token_controller: ContractAddress = 'new_token_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let burn_limit: u256 = 1000000;
    let remote_domain: u32 = 1;
    let remote_token: u256 = 0x1234567890abcdef;

    // 1. Token controller sets burn limit
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit);
    // Verify burn limit was set correctly
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit);

    // 2. Token controller links token pair
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);
    let local_token_result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(local_token_result == local_token, "Token pair should be linked");
    stop_cheat_caller_address(contract_address);

    // 3. Owner changes token controller
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_token_controller(new_token_controller);
    stop_cheat_caller_address(contract_address);
    assert!(
        dispatcher.token_controller() == new_token_controller, "Token controller should be updated",
    );

    // 4. New token controller unlinks token pair
    start_cheat_caller_address(contract_address, new_token_controller);
    dispatcher.unlink_token_pair(local_token, remote_domain, remote_token);
    stop_cheat_caller_address(contract_address);

    // Verify final state
    let local_token_result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(local_token_result.is_zero(), "Token pair should be unlinked");
    // Burn limit should still be set from before
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit);
}

// ================================
// ERROR HANDLING TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_token_controller_rejects_non_owner() {
    let (owner, token_controller, _, _, unauthorized) = get_test_addresses();
    let new_token_controller: ContractAddress = 'new_token_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.set_token_controller(new_token_controller);
}

#[test]
#[should_panic(expected: ('Token controller cannot be zero',))]
fn test_set_token_controller_rejects_zero_address() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    let zero_address: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_token_controller(zero_address);
}

#[test]
#[should_panic(expected: ('Caller is not token controller',))]
fn test_set_max_burn_amount_per_message_rejects_non_controller() {
    let (owner, token_controller, local_token, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.set_max_burn_amount_per_message(local_token, 1000000);
}

#[test]
#[should_panic(expected: ('Caller is not token controller',))]
fn test_link_token_pair_rejects_non_controller() {
    let (owner, token_controller, local_token, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.link_token_pair(local_token, 1, 0x123);
}

#[test]
#[should_panic(expected: ('Unable to link token pair',))]
fn test_link_token_pair_rejects_already_linked() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let remote_domain: u32 = 1;
    let remote_token: u256 = 0x1234567890abcdef;

    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);
    // Try to link the same pair again
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);
}

#[test]
#[should_panic(expected: ('Caller is not token controller',))]
fn test_unlink_token_pair_rejects_non_controller() {
    let (owner, token_controller, local_token, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.unlink_token_pair(local_token, 1, 0x123);
}

#[test]
#[should_panic(expected: ('Unable to unlink token pair',))]
fn test_unlink_token_pair_rejects_not_linked() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.unlink_token_pair(local_token, 1, 0x123);
}

#[test]
#[should_panic(expected: ('Burn token not supported',))]
fn test_assert_within_burn_limit_rejects_unsupported_token() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Try to burn without setting limit (unsupported token)
    test_dispatcher.test_assert_within_burn_limit(local_token, 100);
}

#[test]
#[should_panic(expected: ('Burn amount exceeds limit',))]
fn test_assert_within_burn_limit_rejects_excessive_amount() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let burn_limit: u256 = 1000000;

    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit);
    stop_cheat_caller_address(contract_address);

    // Try to burn more than limit
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit + 1);
}

// ================================
// INTERNAL FUNCTIONS TESTS
// ================================

#[test]
fn test_initializer_functionality() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Initialize ownable first (required for token_controller)
    test_dispatcher.test_ownable_initializer(owner);
    // Initialize token_controller
    test_dispatcher.test_token_controller_initializer(token_controller);

    // Check that token controller is set
    assert!(
        dispatcher.token_controller() == token_controller,
        "Initializer should set the token controller",
    );
}

#[test]
#[should_panic(expected: ('Token controller cannot be zero',))]
fn test_initializer_rejects_zero_address() {
    let (owner, _, _, _, _) = get_test_addresses();
    let contract_address = deploy_uninitialized_contract();
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    test_dispatcher.test_ownable_initializer(owner);
    let zero_address: ContractAddress = 0.try_into().unwrap();
    test_dispatcher.test_token_controller_initializer(zero_address);
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initializer_rejects_already_initialized() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Try to initialize again - should fail
    test_dispatcher.test_token_controller_initializer(token_controller);
}

#[test]
fn test_assert_only_token_controller_functionality() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    // Should pass for token controller
    start_cheat_caller_address(contract_address, token_controller);
    test_dispatcher.test_assert_only_token_controller();
}

#[test]
#[should_panic(expected: ('Caller is not token controller',))]
fn test_assert_only_token_controller_fails_for_non_controller() {
    let (owner, token_controller, _, _, unauthorized) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let test_dispatcher = ITestHelperDispatcher { contract_address };

    start_cheat_caller_address(contract_address, unauthorized);
    test_dispatcher.test_assert_only_token_controller();
}

#[test]
fn test_public_getter_functions() {
    let (owner, token_controller, local_token, _, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let remote_domain: u32 = 1;
    let remote_token: u256 = 0x1234567890abcdef;
    let burn_limit: u256 = 500000;

    // Test get_burn_limit_per_message with unset token (should return 0)
    let initial_burn_limit = dispatcher.get_burn_limit_per_message(local_token);
    assert!(initial_burn_limit == 0, "Unset burn limit should return 0");

    // Set burn limit and test again
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit);
    stop_cheat_caller_address(contract_address);

    let new_burn_limit = dispatcher.get_burn_limit_per_message(local_token);
    assert!(new_burn_limit == burn_limit, "Should return the set burn limit");

    // Test get_local_token with unlinked pair (should return zero)
    let result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(result.is_zero(), "Should return zero for unlinked pair");

    // Link the pair and test again
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.link_token_pair(local_token, remote_domain, remote_token);
    stop_cheat_caller_address(contract_address);

    let result = dispatcher.get_local_token(remote_domain, remote_token);
    assert!(result == local_token, "Should return local token for linked pair");
}

// ================================
// INTEGRATION WITH OWNABLE
// ================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_old_owner_cannot_set_token_controller_after_transfer() {
    let (owner, token_controller, _, _, _) = get_test_addresses();
    let new_owner: ContractAddress = 'new_owner'.try_into().unwrap();
    let new_token_controller: ContractAddress = 'new_token_controller'.try_into().unwrap();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let dispatcher = ITokenControllerDispatcher { contract_address };

    // Transfer ownership
    start_cheat_caller_address(contract_address, owner);
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(contract_address);

    // Old owner should not be able to update token controller
    start_cheat_caller_address(contract_address, owner);
    dispatcher.set_token_controller(new_token_controller);
}

#[test]
fn test_multiple_tokens_independent_burn_limits() {
    let (owner, token_controller, local_token, local_token2, _) = get_test_addresses();
    let contract_address = deploy_mock_contract(owner, token_controller);
    let dispatcher = ITokenControllerDispatcher { contract_address };
    let test_dispatcher = ITestHelperDispatcher { contract_address };
    let burn_limit1: u256 = 1000000;
    let burn_limit2: u256 = 2000000;

    // Set different burn limits for different tokens
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit1);
    dispatcher.set_max_burn_amount_per_message(local_token2, burn_limit2);
    stop_cheat_caller_address(contract_address);

    // Verify limits are independent
    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit1);
    test_dispatcher.test_assert_within_burn_limit(local_token2, burn_limit2);

    // Update one limit and verify the other is unchanged
    start_cheat_caller_address(contract_address, token_controller);
    dispatcher.set_max_burn_amount_per_message(local_token, burn_limit2);
    stop_cheat_caller_address(contract_address);

    test_dispatcher.test_assert_within_burn_limit(local_token, burn_limit2);
    test_dispatcher.test_assert_within_burn_limit(local_token2, burn_limit2);
}
