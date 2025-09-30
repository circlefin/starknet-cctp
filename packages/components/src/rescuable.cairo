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

//! # Rescuable Component
//!
//! This component provides functionality to rescue tokens that may become locked in the
//! contract. This is essential for recovering tokens that are sent to the contract by mistake
//! or become stuck due to failed operations. The component integrates with the Ownable component
//! to control rescuer role management, where only the owner can update the rescuer address.
//!
//! The component implements a two-tier access control system:
//! - **Owner**: Can update the rescuer address (inherited from Ownable component)
//! - **Rescuer**: Can rescue tokens locked in the contract
//!
//! # Features
//!
//! - **Rescuer Management**: Owner can set and update the rescuer address
//! - **Token Recovery**: Rescuer can recover tokens locked in the contract
//! - **Access Control**: Two-tier access control (Owner → Rescuer → Token Recovery)
//! - **Input Validation**: Built-in validation to prevent invalid operations
//! - **Transfer Validation**: Ensures rescue operations actually succeed before completing
//! - **Event Emission**: Emits events for transparency and monitoring
//!
//! # Security Considerations
//!
//! - **Token Recovery Capability**: Enables recovery of tokens accidentally sent to the contract
//! - **Role Separation**: Separate rescuer role allows specialized token recovery management
//! - **Zero Address Protection**: Prevents invalid operations with zero addresses
//! - **Owner Control**: Only the owner can designate who has rescue privileges
//! - **Input Validation**: All parameters are validated before attempting rescue operations
//!
//! # Usage
//!
//! ```
//! #[starknet::contract]
//! mod MyContract {
//!     use cctp_components::rescuable::RescuableComponent;
//!     use components::ownable::OwnableComponent;
//!
//!     component!(
//!         path: RescuableComponent,
//!         storage: rescuable,
//!         event: RescuableEvent,
//!     );
//!     component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
//!
//!     #[abi(embed_v0)]
//!     impl RescuableImpl = RescuableComponent::Rescuable<ContractState>;
//!
//!     #[external(v0)]
//!     fn initialize(ref self: ContractState, owner: ContractAddress, rescuer: ContractAddress) {
//!         self.ownable.initializer(owner);
//!         self.rescuable.initializer(rescuer);
//!     }
//! }
//! ```

use starknet::ContractAddress;

/// Interface for rescuable functionality
///
/// This interface provides methods to manage token rescue operations with
/// role-based access control.
#[starknet::interface]
pub trait IRescuable<TContractState> {
    fn rescuer(self: @TContractState) -> ContractAddress;

    fn update_rescuer(ref self: TContractState, new_rescuer: ContractAddress);

    fn rescue_erc20(
        ref self: TContractState,
        token_contract: ContractAddress,
        to: ContractAddress,
        amount: u256,
    );
}

#[starknet::component]
pub mod RescuableComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::num::traits::Zero;
    use stablecoin::{IFiatTokenDispatcher, IFiatTokenDispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        rescuer: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RescuerChanged: RescuerChanged,
    }

    /// Emitted when the rescuer address is updated
    #[derive(Drop, starknet::Event)]
    pub struct RescuerChanged {
        #[key]
        pub new_rescuer: ContractAddress,
    }

    pub mod Errors {
        pub const RESCUER_CANNOT_BE_ZERO_ADDRESS: felt252 = 'Rescuer cannot be zero address';
        pub const CALLER_NOT_RESCUER: felt252 = 'Caller is not the rescuer';
        pub const TOKEN_CANNOT_BE_ZERO_ADDRESS: felt252 = 'Token cannot be zero address';
        pub const RECIPIENT_CANNOT_BE_ZERO: felt252 = 'Recipient cannot be zero';
        pub const AMOUNT_CANNOT_BE_ZERO: felt252 = 'Amount cannot be zero';
        pub const RESCUE_TRANSFER_FAILED: felt252 = 'Rescue transfer failed';
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    }

    #[embeddable_as(Rescuable)]
    impl RescuableImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IRescuable<ComponentState<TContractState>> {
        /// Returns the current rescuer address
        fn rescuer(self: @ComponentState<TContractState>) -> ContractAddress {
            self.rescuer.read()
        }

        /// Updates the rescuer address to a new account
        ///
        /// This function can only be called by the contract owner. It validates that the
        /// new rescuer is not the zero address before updating the storage.
        ///
        /// # Arguments
        ///
        /// * `new_rescuer` - The new address authorized to rescue tokens
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The provided address is the zero address
        ///
        /// # Events
        ///
        /// Emits a `RescuerChanged` event upon successful update.
        fn update_rescuer(ref self: ComponentState<TContractState>, new_rescuer: ContractAddress) {
            // Only owner can update rescuer
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Validate new rescuer is not zero address
            assert(!new_rescuer.is_zero(), Errors::RESCUER_CANNOT_BE_ZERO_ADDRESS);

            // Update rescuer
            self.rescuer.write(new_rescuer);

            // Emit event
            self.emit(RescuerChanged { new_rescuer });
        }

        /// Rescues tokens locked in this contract by transferring them to a recipient
        ///
        /// This function can only be called by the designated rescuer. It validates all
        /// parameters and ensures the transfer succeeds before completing.
        ///
        /// # Arguments
        ///
        /// * `token_contract` - The address of the token contract to rescue from
        /// * `to` - The recipient address for the rescued tokens
        /// * `amount` - The amount of tokens to rescue
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the designated rescuer
        /// - The token contract address is the zero address
        /// - The recipient address is the zero address
        /// - The amount is zero
        /// - The token transfer operation fails
        fn rescue_erc20(
            ref self: ComponentState<TContractState>,
            token_contract: ContractAddress,
            to: ContractAddress,
            amount: u256,
        ) {
            // Only rescuer can rescue tokens
            self.assert_only_rescuer();

            // Validate token contract is not zero address
            assert(!token_contract.is_zero(), Errors::TOKEN_CANNOT_BE_ZERO_ADDRESS);

            // Validate recipient is not zero address
            assert(!to.is_zero(), Errors::RECIPIENT_CANNOT_BE_ZERO);

            // Validate amount is not zero
            assert(amount != 0, Errors::AMOUNT_CANNOT_BE_ZERO);

            // Create token dispatcher
            let token_dispatcher = IFiatTokenDispatcher { contract_address: token_contract };

            // Attempt transfer
            let transfer_result = token_dispatcher.transfer(to, amount);

            // Validate transfer succeeded
            assert(transfer_result, Errors::RESCUE_TRANSFER_FAILED);
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the rescuable component with an initial rescuer address
        ///
        /// This function should be called during contract initialization to set the
        /// initial rescuer address. Can only be called once.
        ///
        /// # Arguments
        ///
        /// * `rescuer` - The initial rescuer address
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The provided address is the zero address
        /// - The component has already been initialized
        ///
        /// # Events
        ///
        /// Emits a `RescuerChanged` event upon successful initialization.
        fn initializer(ref self: ComponentState<TContractState>, rescuer: ContractAddress) {
            // Check if already initialized by verifying current rescuer is zero
            let current_rescuer = self.rescuer.read();
            assert(current_rescuer.is_zero(), Errors::ALREADY_INITIALIZED);

            // Validate rescuer is not zero address
            assert(!rescuer.is_zero(), Errors::RESCUER_CANNOT_BE_ZERO_ADDRESS);

            // Set initial rescuer
            self.rescuer.write(rescuer);

            // Emit event
            self.emit(RescuerChanged { new_rescuer: rescuer });
        }

        /// Asserts that the caller is the designated rescuer
        ///
        /// # Panics
        ///
        /// This function will panic if the caller is not the designated rescuer.
        fn assert_only_rescuer(self: @ComponentState<TContractState>) {
            let rescuer = self.rescuer.read();
            let caller = get_caller_address();
            assert(caller == rescuer, Errors::CALLER_NOT_RESCUER);
        }
    }
}
