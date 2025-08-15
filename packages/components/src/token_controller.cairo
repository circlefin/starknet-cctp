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

//! # Token Controller Component
//!
//! This component provides token control functionality for cross-chain token operations.
//! It allows the contract owner to designate a token controller address and enables that
//! controller to manage token pairs between local and remote domains, as well as set
//! burn limits for tokens.
//!
//! The component integrates with the Ownable component to ensure proper access control,
//! where only the owner can update the token controller, and only the token controller
//! can manage token pairs and burn limits.
//!
//! # Features
//!
//! - **Token Controller Management**: Owner can set and update the token controller address
//! - **Token Pair Management**: Token controller can link/unlink local and remote token pairs
//! - **Burn Limit Management**: Token controller can set maximum burn amounts per message
//! - **Cross-Domain Mapping**: Maps remote domain tokens to local token addresses
//! - **Access Control**: Two-tier access control (Owner → Token Controller → Token Settings)
//! - **Validation**: Built-in validation to prevent invalid operations and duplicate links
//! - **Event Emission**: Emits events for transparency and monitoring
//!
//! # Token Pair Management
//!
//! The component manages bidirectional token mappings between local and remote domains:
//! - **Local Token**: Token address on the current chain
//! - **Remote Domain**: Identifier for the remote chain
//! - **Remote Token**: Token identifier on the remote chain (typically address as u256)

use starknet::ContractAddress;

/// Interface for token controller functionality
///
/// This interface provides methods to manage token controller settings, token pairs,
/// and burn limits in a contract with two-tier access control.
#[starknet::interface]
pub trait ITokenController<TContractState> {
    fn token_controller(self: @TContractState) -> ContractAddress;

    fn set_token_controller(ref self: TContractState, new_token_controller: ContractAddress);

    fn set_max_burn_amount_per_message(
        ref self: TContractState, local_token: ContractAddress, burn_limit_per_message: u256,
    );

    fn link_token_pair(
        ref self: TContractState,
        local_token: ContractAddress,
        remote_domain: u32,
        remote_token: u256,
    );

    fn unlink_token_pair(
        ref self: TContractState,
        local_token: ContractAddress,
        remote_domain: u32,
        remote_token: u256,
    );

    fn get_burn_limit_per_message(self: @TContractState, token: ContractAddress) -> u256;

    fn get_local_token(
        self: @TContractState, remote_domain: u32, remote_token: u256,
    ) -> ContractAddress;
}

#[starknet::component]
pub mod TokenControllerComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    /// Key structure for identifying remote tokens in cross-domain mappings
    ///
    /// This structure combines the remote domain identifier with the remote token
    /// identifier to create a unique key for token pair mappings.
    /// Storage space may be optimized using StorePacking however we won't store lots of token pairs
    /// So keep it simple for now
    #[derive(Drop, Copy, Hash, starknet::Store)]
    pub struct RemoteTokenKey {
        /// The identifier of the remote domain/chain
        remote_domain: u32,
        /// The token identifier on the remote domain (typically address as u256)
        remote_token: u256,
    }

    #[storage]
    pub struct Storage {
        /// The address authorized to manage token pairs and burn limits
        token_controller: ContractAddress,
        /// Mapping of local token addresses to their maximum burn amounts per message
        burn_limits_per_message: Map<ContractAddress, u256>,
        /// Mapping of remote token keys to their corresponding local token addresses
        remote_tokens_to_local_tokens: Map<RemoteTokenKey, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SetTokenController: SetTokenController,
        SetBurnLimitPerMessage: SetBurnLimitPerMessage,
        TokenPairLinked: TokenPairLinked,
        TokenPairUnlinked: TokenPairUnlinked,
    }

    /// Emitted when the token controller address is updated
    #[derive(Drop, starknet::Event)]
    pub struct SetTokenController {
        #[key]
        pub token_controller: ContractAddress,
    }

    /// Emitted when the burn limit per message is updated for a specific token
    #[derive(Drop, starknet::Event)]
    pub struct SetBurnLimitPerMessage {
        #[key]
        pub token: ContractAddress,
        pub burn_limit_per_message: u256,
    }

    /// Emitted when a token pair is linked between local and remote domains
    #[derive(Drop, starknet::Event)]
    pub struct TokenPairLinked {
        #[key]
        pub local_token: ContractAddress,
        #[key]
        pub remote_domain: u32,
        pub remote_token: u256,
    }

    /// Emitted when a token pair is unlinked between local and remote domains
    #[derive(Drop, starknet::Event)]
    pub struct TokenPairUnlinked {
        #[key]
        pub local_token: ContractAddress,
        #[key]
        pub remote_domain: u32,
        pub remote_token: u256,
    }

    pub mod Errors {
        /// Error thrown when attempting to set a zero address as token controller
        pub const ZERO_ADDRESS_TOKEN_CONTROLLER: felt252 = 'Token controller cannot be zero';
        /// Error thrown when caller is not the designated token controller
        pub const NOT_TOKEN_CONTROLLER: felt252 = 'Caller is not token controller';
        /// Error thrown when trying to burn a token that doesn't have a burn limit set
        pub const BURN_TOKEN_NOT_SUPPORTED: felt252 = 'Burn token not supported';
        /// Error thrown when attempting to burn more than the allowed limit per message
        pub const BURN_AMOUNT_EXCEEDS_LIMIT: felt252 = 'Burn amount exceeds limit';
        /// Error thrown when trying to link a token pair that is already linked
        pub const UNABLE_TO_LINK_TOKEN_PAIR: felt252 = 'Unable to link token pair';
        /// Error thrown when trying to unlink a token pair that is not currently linked
        pub const UNABLE_TO_UNLINK_TOKEN_PAIR: felt252 = 'Unable to unlink token pair';
        /// Error thrown when trying to initialize an already initialized component
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    }

    #[embeddable_as(TokenController)]
    impl TokenControllerImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::ITokenController<ComponentState<TContractState>> {
        /// Returns the current token controller address
        fn token_controller(self: @ComponentState<TContractState>) -> ContractAddress {
            self.token_controller.read()
        }

        /// Sets a new token controller address
        ///
        /// This function can only be called by the contract owner. It validates that the
        /// new token controller is not the zero address before updating the storage.
        ///
        /// # Arguments
        ///
        /// * `new_token_controller` - The new address authorized to manage tokens
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The provided address is the zero address
        ///
        /// # Events
        ///
        /// Emits a `SetTokenController` event upon successful update.
        fn set_token_controller(
            ref self: ComponentState<TContractState>, new_token_controller: ContractAddress,
        ) {
            // Only owner can update token controller
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Validate new token controller is not zero address
            assert(!new_token_controller.is_zero(), Errors::ZERO_ADDRESS_TOKEN_CONTROLLER);

            // Update token controller
            self.token_controller.write(new_token_controller);

            // Emit event
            self.emit(SetTokenController { token_controller: new_token_controller });
        }

        /// Sets the maximum burn amount per message for a specific token
        ///
        /// This function can only be called by the designated token controller.
        /// It allows setting limits on how much of a token can be burned in a single message.
        ///
        /// # Arguments
        ///
        /// * `local_token` - The address of the local token to set the limit for
        /// * `burn_limit_per_message` - The maximum amount that can be burned per message
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the designated token controller
        ///
        /// # Events
        ///
        /// Emits a `SetBurnLimitPerMessage` event upon successful update.
        fn set_max_burn_amount_per_message(
            ref self: ComponentState<TContractState>,
            local_token: ContractAddress,
            burn_limit_per_message: u256,
        ) {
            // Only token controller can call this function
            self.assert_only_token_controller();

            // Update burn limit for the token
            self.burn_limits_per_message.entry(local_token).write(burn_limit_per_message);

            // Emit event
            self
                .emit(
                    SetBurnLimitPerMessage {
                        token: local_token, burn_limit_per_message: burn_limit_per_message,
                    },
                );
        }

        /// Links a local token to a remote domain token pair
        ///
        /// This function can only be called by the designated token controller.
        /// It creates a bidirectional mapping between a local token and a remote domain token,
        /// enabling cross-chain token operations.
        ///
        /// # Arguments
        ///
        /// * `local_token` - The address of the local token
        /// * `remote_domain` - The identifier of the remote domain/chain
        /// * `remote_token` - The token identifier on the remote domain
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the designated token controller
        /// - The remote token is already linked to another local token
        ///
        /// # Events
        ///
        /// Emits a `TokenPairLinked` event upon successful linking.
        fn link_token_pair(
            ref self: ComponentState<TContractState>,
            local_token: ContractAddress,
            remote_domain: u32,
            remote_token: u256,
        ) {
            // Only token controller can call this function
            self.assert_only_token_controller();

            // Create remote token key
            let remote_key = RemoteTokenKey { remote_domain, remote_token };

            // Check if remote token is not already linked
            let existing_token = self.remote_tokens_to_local_tokens.entry(remote_key).read();
            assert(existing_token.is_zero(), Errors::UNABLE_TO_LINK_TOKEN_PAIR);

            // Link the token pair
            self.remote_tokens_to_local_tokens.entry(remote_key).write(local_token);

            // Emit event
            self.emit(TokenPairLinked { local_token, remote_domain, remote_token });
        }

        /// Unlinks a previously linked token pair
        ///
        /// This function can only be called by the designated token controller.
        /// It removes the bidirectional mapping between a local token and a remote domain token.
        ///
        /// # Arguments
        ///
        /// * `local_token` - The address of the local token
        /// * `remote_domain` - The identifier of the remote domain/chain
        /// * `remote_token` - The token identifier on the remote domain
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the designated token controller
        /// - The specified token pair is not currently linked
        ///
        /// # Events
        ///
        /// Emits a `TokenPairUnlinked` event upon successful unlinking.
        fn unlink_token_pair(
            ref self: ComponentState<TContractState>,
            local_token: ContractAddress,
            remote_domain: u32,
            remote_token: u256,
        ) {
            // Only token controller can call this function
            self.assert_only_token_controller();

            // Create remote token key
            let remote_key = RemoteTokenKey { remote_domain, remote_token };

            // Check if remote token is linked
            let existing_token = self.remote_tokens_to_local_tokens.entry(remote_key).read();
            assert(!existing_token.is_zero(), Errors::UNABLE_TO_UNLINK_TOKEN_PAIR);

            // Unlink the token pair (set to zero address)
            let zero_address = Zero::<ContractAddress>::zero();
            self.remote_tokens_to_local_tokens.entry(remote_key).write(zero_address);

            // Emit event
            self.emit(TokenPairUnlinked { local_token, remote_domain, remote_token });
        }

        /// Returns the burn limit per message for a specific token
        ///
        /// This function retrieves the maximum amount that can be burned in a single message
        /// for the specified token. Returns 0 if no limit has been set.
        ///
        /// # Arguments
        ///
        /// * `token` - The address of the token to query
        ///
        /// # Returns
        ///
        /// The burn limit per message for the token, or 0 if not set
        fn get_burn_limit_per_message(
            self: @ComponentState<TContractState>, token: ContractAddress,
        ) -> u256 {
            self.burn_limits_per_message.entry(token).read()
        }

        /// Retrieves the local token address for a given remote domain and token
        ///
        /// This function looks up the local token address that corresponds to
        /// a specific remote domain and token combination. It returns the zero address
        /// if no mapping exists.
        ///
        /// # Arguments
        ///
        /// * `remote_domain` - The identifier of the remote domain/chain
        /// * `remote_token` - The token identifier on the remote domain
        ///
        /// # Returns
        ///
        /// The local token address if a mapping exists, otherwise the zero address
        fn get_local_token(
            self: @ComponentState<TContractState>, remote_domain: u32, remote_token: u256,
        ) -> ContractAddress {
            // Create remote token key
            let remote_key = RemoteTokenKey { remote_domain, remote_token };

            // Return the local token address
            self.remote_tokens_to_local_tokens.entry(remote_key).read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the token controller with an initial token controller address
        ///
        /// This function should be called during contract initialization to set the
        /// initial token controller address. The burn limits and token pair mappings
        /// are initialized empty. Can only be called once.
        ///
        /// # Arguments
        ///
        /// * `token_controller` - The initial token controller address
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The provided address is the zero address
        /// - The component has already been initialized
        ///
        /// # Events
        ///
        /// Emits a `SetTokenController` event upon successful initialization.
        fn initializer(
            ref self: ComponentState<TContractState>, token_controller: ContractAddress,
        ) {
            // Check if already initialized by verifying current controller is zero
            let current_controller = self.token_controller.read();
            assert(current_controller.is_zero(), Errors::ALREADY_INITIALIZED);

            assert(!token_controller.is_zero(), Errors::ZERO_ADDRESS_TOKEN_CONTROLLER);
            self.token_controller.write(token_controller);

            // Emit event
            self.emit(SetTokenController { token_controller });
        }

        /// Asserts that the caller is the designated token controller
        ///
        /// This internal function is used to enforce access control for token controller
        /// operations. It compares the caller's address with the stored token controller
        /// address and panics if they don't match.
        ///
        /// # Panics
        ///
        /// This function will panic if the caller is not the designated token controller.
        fn assert_only_token_controller(self: @ComponentState<TContractState>) {
            let token_controller = self.token_controller.read();
            let caller = get_caller_address();
            assert(caller == token_controller, Errors::NOT_TOKEN_CONTROLLER);
        }

        /// Asserts that a burn amount is within the allowed limit for a specific token
        ///
        /// This internal function validates that the requested burn amount does not exceed
        /// the maximum burn limit set for the token. It also checks if the token is
        /// supported for burning (has a limit > 0).
        ///
        /// # Arguments
        ///
        /// * `token` - The address of the token to check
        /// * `amount` - The amount to validate against the burn limit
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The token is not supported for burning (no limit set or limit is 0)
        /// - The amount exceeds the allowed burn limit per message
        fn assert_within_burn_limit(
            self: @ComponentState<TContractState>, token: ContractAddress, amount: u256,
        ) {
            // Get the allowed burn amount for this token
            let allowed_burn_amount = self.burn_limits_per_message.entry(token).read();

            // Check if burn token is supported (limit > 0)
            assert(allowed_burn_amount > 0, Errors::BURN_TOKEN_NOT_SUPPORTED);

            // Check if amount is within the limit
            assert(amount <= allowed_burn_amount, Errors::BURN_AMOUNT_EXCEEDS_LIMIT);
        }
    }
}
