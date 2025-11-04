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

//! # Fee Recipient Controller Component
//!
//! This component provides a way to set and manage the fee recipient for a contract.
//! The fee recipient is the address that will receive the fees from the contract.
//! The component integrates with the Ownable component to ensure proper access control,
//! where only the owner can set the fee recipient.
//!
//! # Features
//!
//! - **Fee Recipient Management**: Owner can set the fee recipient
//! - **Access Control**: Only the owner can set the fee recipient
//! - **Event Emission**: Emits events for transparency and monitoring

use starknet::ContractAddress;

/// Interface for fee recipient controller functionality
///
/// This interface provides methods to manage fee recipient controller functionality.
#[starknet::interface]
pub trait IFeeRecipientController<TContractState> {
    fn fee_recipient(self: @TContractState) -> ContractAddress;

    fn set_fee_recipient(ref self: TContractState, fee_recipient: ContractAddress);
}

#[starknet::component]
pub mod FeeRecipientControllerComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    pub struct Storage {
        fee_recipient: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        FeeRecipientSet: FeeRecipientSet,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeRecipientSet {
        pub fee_recipient: ContractAddress,
    }

    pub mod Errors {
        pub const ZERO_ADDRESS_NOT_ALLOWED: felt252 = 'Zero address not allowed';
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    }

    #[embeddable_as(FeeRecipientController)]
    impl FeeRecipientControllerImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IFeeRecipientController<ComponentState<TContractState>> {
        /// Returns the current fee recipient address
        ///
        /// # Returns
        ///
        /// The address of the fee recipient
        fn fee_recipient(self: @ComponentState<TContractState>) -> ContractAddress {
            self.fee_recipient.read()
        }

        /// Sets the fee recipient address
        ///
        /// # Arguments
        ///
        /// * `fee_recipient` - The address of the fee recipient
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The provided fee recipient address is the zero address
        ///
        /// # Events
        ///
        /// Emits a `FeeRecipientSet` event upon successful setting of the fee recipient.
        fn set_fee_recipient(
            ref self: ComponentState<TContractState>, fee_recipient: ContractAddress,
        ) {
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            assert(!fee_recipient.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);

            self.fee_recipient.write(fee_recipient);
            self.emit(FeeRecipientSet { fee_recipient });
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the fee recipient controller with an initial fee recipient address
        ///
        /// This function should be called during contract initialization to set the
        /// initial fee recipient address. The fee recipient is initialized to the provided address.
        /// Can only be called once.
        ///
        /// # Arguments
        ///
        /// * `fee_recipient` - The address of the fee recipient
        ///
        /// # Panics
        ///
        /// This function will panic if:
        ///- The provided address is the zero address
        /// - The component has already been initialized
        ///
        /// # Events
        ///
        /// Emits a `FeeRecipientSet` event upon successful initialization.
        fn initializer(ref self: ComponentState<TContractState>, fee_recipient: ContractAddress) {
            // Check if already initialized by verifying current fee recipient is zero
            let current_fee_recipient = self.fee_recipient.read();
            assert(current_fee_recipient.is_zero(), Errors::ALREADY_INITIALIZED);

            // Validate fee recipient is not zero address
            assert(!fee_recipient.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);

            // Set initial fee recipient
            self.fee_recipient.write(fee_recipient);

            // Emit event
            self.emit(FeeRecipientSet { fee_recipient });
        }
    }
}
