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

//! # Remote Token Messenger Controller Component
//!
//! This component provides functionality to manage remote token messenger addresses for different
//! domains.
//! It allows the contract owner to set and remove remote token messenger addresses for specific
//! domains.
//!
//! The component integrates with the Ownable component to ensure proper access control,
//! where only the owner can set and remove remote token messenger addresses.

//! # Features
//!
//! - **Remote Token Messenger Management**: Owner can set and remove remote token messenger
//! addresses for different domains
//! - **Access Control**: Only the owner can set and remove remote token messenger addresses
//! - **Event Emission**: Emits events for transparency and monitoring

/// Interface for remote token messenger controller functionality
///
/// This interface provides methods to manage remote token messenger controller functionality.
#[starknet::interface]
pub trait IRemoteTokenMessengerController<TContractState> {
    fn remote_token_messenger(self: @TContractState, domain: u32) -> u256;

    fn add_remote_token_messenger(ref self: TContractState, domain: u32, token_messenger: u256);

    fn remove_remote_token_messenger(ref self: TContractState, domain: u32);
}

#[starknet::component]
pub mod RemoteTokenMessengerControllerComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::num::traits::Zero;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    pub struct Storage {
        remote_token_messengers: Map<u32, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RemoteTokenMessengerAdded: RemoteTokenMessengerAdded,
        RemoteTokenMessengerRemoved: RemoteTokenMessengerRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RemoteTokenMessengerAdded {
        #[key]
        pub domain: u32,
        pub token_messenger: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RemoteTokenMessengerRemoved {
        #[key]
        pub domain: u32,
        pub token_messenger: u256,
    }

    pub mod Errors {
        pub const ZERO_ADDRESS_NOT_ALLOWED: felt252 = 'Zero address not allowed';
        pub const TOKEN_MESSENGER_ALREADY_SET: felt252 = 'Token messenger already set';
        pub const NO_TOKEN_MESSENGER_SET: felt252 = 'No token messenger set';
        pub const REMOTE_TOKEN_MESSENGER_INVALID: felt252 = 'Remote token messenger invalid';
    }

    #[embeddable_as(RemoteTokenMessengerController)]
    impl RemoteTokenMessengerControllerImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IRemoteTokenMessengerController<ComponentState<TContractState>> {
        /// Returns the current remote token messenger address for a specific domain
        ///
        /// # Arguments
        ///
        /// * `domain` - The domain to query the remote token messenger address for
        ///
        /// # Returns
        ///
        /// The address of the remote token messenger for the specified domain (0 if not set)
        fn remote_token_messenger(self: @ComponentState<TContractState>, domain: u32) -> u256 {
            self.remote_token_messengers.read(domain)
        }

        /// Set remote token messenger address for a specific domain
        ///
        /// # Arguments
        ///
        /// * `domain` - The domain to set the remote token messenger address for
        /// * `token_messenger` - The address of the remote token messenger
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The provided token messenger address is the zero address
        /// - The token messenger is already set for the domain
        ///
        /// # Events
        ///
        /// Emits a `RemoteTokenMessengerAdded` event upon successful addition.
        fn add_remote_token_messenger(
            ref self: ComponentState<TContractState>, domain: u32, token_messenger: u256,
        ) {
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Validate token messenger is not zero address
            assert(!token_messenger.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);

            // Validate token messenger is not already set
            assert(
                self.remote_token_messengers.read(domain).is_zero(),
                Errors::TOKEN_MESSENGER_ALREADY_SET,
            );

            // Set token messenger
            self.remote_token_messengers.write(domain, token_messenger);

            // Emit event
            self.emit(RemoteTokenMessengerAdded { domain, token_messenger });
        }

        /// Remove remote token messenger address for a specific domain
        ///
        /// # Arguments
        ///
        /// * `domain` - The domain to remove the remote token messenger address for
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The token messenger is not set for the domain
        ///
        /// # Events
        ///
        /// Emits a `RemoteTokenMessengerRemoved` event upon successful removal.
        fn remove_remote_token_messenger(ref self: ComponentState<TContractState>, domain: u32) {
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Validate token messenger is set
            assert(
                !self.remote_token_messengers.read(domain).is_zero(),
                Errors::NO_TOKEN_MESSENGER_SET,
            );

            // Get token messenger
            let token_messenger_to_remove = self.remote_token_messengers.read(domain);

            // Remove token messenger
            self.remote_token_messengers.write(domain, 0);

            // Emit event
            self
                .emit(
                    RemoteTokenMessengerRemoved {
                        domain, token_messenger: token_messenger_to_remove,
                    },
                );
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Asserts that the remote token messenger set for a specific domain is the same as the
        /// provided address
        ///
        /// # Arguments
        ///
        /// * `domain` - The domain to query the remote token messenger address for
        /// * `token_messenger` - The address of the remote token messenger to assert is correct
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The provided address is the zero address
        /// - The remote token messenger for the domain is not the same as the provided address
        fn assert_only_remote_token_messenger(
            self: @ComponentState<TContractState>, domain: u32, token_messenger: u256,
        ) {
            assert(!token_messenger.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);
            let remote_token_messenger = self.remote_token_messengers.read(domain);
            assert(
                remote_token_messenger == token_messenger, Errors::REMOTE_TOKEN_MESSENGER_INVALID,
            );
        }
    }
}
