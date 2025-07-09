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

//! # Min Fee Controller Component
//!
//! This component provides minimum fee management functionality for contracts that implement
//! fee-based operations. It allows the contract owner to designate a fee controller address
//! and enables that controller to set minimum fee parameters.
//!
//! The component integrates with the Ownable component to ensure proper access control,
//! where only the owner can update the fee controller, and only the fee controller can
//! update fee parameters.
//!
//! # Features
//!
//! - **Fee Controller Management**: Owner can set and update the fee controller address
//! - **Min Fee Management**: Fee controller can set minimum fee values with validation
//! - **Fee Calculation**: Provides utility functions to calculate minimum fees for given amounts
//! - **Access Control**: Two-tier access control (Owner → Fee Controller → Fee Settings)
//! - **Validation**: Built-in validation to prevent excessive fees and zero addresses
//! - **Event Emission**: Emits events for transparency and monitoring
//!
//! # Fee Calculation
//!
//! The component uses a multiplier-based fee calculation system:
//! - Fees are specified as a ratio against `MIN_FEE_MULTIPLIER` (10,000,000)
//! - Actual fee = (amount × min_fee) ÷ MIN_FEE_MULTIPLIER
//! - Minimum fee result is always at least 1 if the calculation would result in 0

use starknet::ContractAddress;

/// Interface for minimum fee controller functionality
///
/// This interface provides methods to manage minimum fee settings and fee controller
/// address in a contract with two-tier access control.
#[starknet::interface]
pub trait IMinFeeController<TContractState> {
    /// Returns the current minimum fee controller address
    ///
    /// # Returns
    ///
    /// The address that is authorized to set minimum fee values
    fn min_fee_controller(self: @TContractState) -> ContractAddress;

    /// Returns the current minimum fee value for a specific burn token
    ///
    /// # Arguments
    ///
    /// * `burn_token` - The address of the burn token to query
    ///
    /// # Returns
    ///
    /// The minimum fee value for the specified burn token (0 if not set)
    fn min_fee(self: @TContractState, burn_token: ContractAddress) -> u256;

    /// Sets a new minimum fee controller address
    ///
    /// Only the contract owner can call this function.
    ///
    /// # Arguments
    ///
    /// * `min_fee_controller` - The new address authorized to set minimum fees
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the contract owner
    /// - The provided address is the zero address
    fn set_min_fee_controller(ref self: TContractState, min_fee_controller: ContractAddress);

    /// Sets a new minimum fee value for a specific burn token
    ///
    /// Only the designated fee controller can call this function.
    ///
    /// # Arguments
    ///
    /// * `burn_token` - The address of the burn token to set the fee for
    /// * `min_fee` - The new minimum fee value (must be less than MIN_FEE_MULTIPLIER)
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the designated fee controller
    /// - The fee value is greater than or equal to MIN_FEE_MULTIPLIER (10,000,000)
    fn set_min_fee(ref self: TContractState, burn_token: ContractAddress, min_fee: u256);
}

#[starknet::component]
pub mod MinFeeControllerComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        min_fee_controller: ContractAddress,
        token_to_min_fee: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MinFeeControllerSet: MinFeeControllerSet,
        MinFeeSet: MinFeeSet,
    }

    /// Emitted when the minimum fee controller address is updated
    #[derive(Drop, starknet::Event)]
    pub struct MinFeeControllerSet {
        #[key]
        pub min_fee_controller: ContractAddress,
    }

    /// Emitted when the minimum fee value is updated for a specific burn token
    #[derive(Drop, starknet::Event)]
    pub struct MinFeeSet {
        #[key]
        pub burn_token: ContractAddress,
        pub min_fee: u256,
    }

    pub mod Errors {
        pub const ZERO_ADDRESS_NOT_ALLOWED: felt252 = 'Zero address not allowed';
        pub const CALLER_NOT_MIN_FEE_CONTROLLER: felt252 = 'Caller not min fee controller';
        pub const MIN_FEE_TOO_HIGH: felt252 = 'Min fee too high';
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    }

    /// The multiplier used in fee calculations to maintain precision
    ///
    /// Fee calculation: (amount × min_fee) ÷ MIN_FEE_MULTIPLIER
    pub const MIN_FEE_MULTIPLIER: u256 = 10_000_000;

    #[embeddable_as(MinFeeController)]
    impl MinFeeControllerImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IMinFeeController<ComponentState<TContractState>> {
        /// Returns the current minimum fee controller address
        fn min_fee_controller(self: @ComponentState<TContractState>) -> ContractAddress {
            self.min_fee_controller.read()
        }

        /// Returns the current minimum fee value for a specific burn token
        fn min_fee(self: @ComponentState<TContractState>, burn_token: ContractAddress) -> u256 {
            self.token_to_min_fee.read(burn_token)
        }

        /// Sets a new minimum fee controller address
        ///
        /// This function can only be called by the contract owner. It validates that the
        /// new fee controller is not the zero address before updating the storage.
        ///
        /// # Arguments
        ///
        /// * `min_fee_controller` - The new address authorized to set minimum fees
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the contract owner
        /// - The provided address is the zero address
        ///
        /// # Events
        ///
        /// Emits a `MinFeeControllerSet` event upon successful update.
        fn set_min_fee_controller(
            ref self: ComponentState<TContractState>, min_fee_controller: ContractAddress,
        ) {
            // Only owner can set min fee controller
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Validate min fee controller is not zero address
            assert(!min_fee_controller.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);

            // Set min fee controller
            self.min_fee_controller.write(min_fee_controller);

            // Emit event
            self.emit(MinFeeControllerSet { min_fee_controller });
        }

        /// Sets a new minimum fee value for a specific burn token
        ///
        /// This function can only be called by the designated fee controller. It validates
        /// that the fee value is within acceptable bounds before updating the storage.
        ///
        /// # Arguments
        ///
        /// * `burn_token` - The address of the burn token to set the fee for
        /// * `min_fee` - The new minimum fee value (must be less than MIN_FEE_MULTIPLIER)
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The caller is not the designated fee controller
        /// - The fee value is greater than or equal to MIN_FEE_MULTIPLIER (10,000,000)
        ///
        /// # Events
        ///
        /// Emits a `MinFeeSet` event upon successful update.
        fn set_min_fee(
            ref self: ComponentState<TContractState>, burn_token: ContractAddress, min_fee: u256,
        ) {
            // Only min fee controller can set min fee
            self.assert_only_min_fee_controller();

            // Validate min fee is not too high
            assert(min_fee < MIN_FEE_MULTIPLIER, Errors::MIN_FEE_TOO_HIGH);

            // Set min fee for specific burn token
            self.token_to_min_fee.write(burn_token, min_fee);

            // Emit event
            self.emit(MinFeeSet { burn_token, min_fee });
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the minimum fee controller with an initial fee controller address
        ///
        /// This function should be called during contract initialization to set the
        /// initial fee controller address. The minimum fee map is initialized empty.
        /// Can only be called once.
        ///
        /// # Arguments
        ///
        /// * `min_fee_controller` - The initial fee controller address
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The provided address is the zero address
        /// - The component has already been initialized
        ///
        /// # Events
        ///
        /// Emits a `MinFeeControllerSet` event upon successful initialization.
        fn initializer(
            ref self: ComponentState<TContractState>, min_fee_controller: ContractAddress,
        ) {
            // Check if already initialized by verifying current controller is zero
            let current_controller = self.min_fee_controller.read();
            assert(current_controller.is_zero(), Errors::ALREADY_INITIALIZED);

            // Validate min fee controller is not zero address
            assert(!min_fee_controller.is_zero(), Errors::ZERO_ADDRESS_NOT_ALLOWED);

            // Set initial min fee controller
            self.min_fee_controller.write(min_fee_controller);

            // Note: token_to_min_fee map is initialized empty by default

            // Emit event
            self.emit(MinFeeControllerSet { min_fee_controller });
        }

        /// Asserts that the caller is the designated minimum fee controller
        ///
        /// # Panics
        ///
        /// This function will panic if the caller is not the designated fee controller.
        fn assert_only_min_fee_controller(self: @ComponentState<TContractState>) {
            let min_fee_controller = self.min_fee_controller.read();
            let caller = get_caller_address();
            assert(caller == min_fee_controller, Errors::CALLER_NOT_MIN_FEE_CONTROLLER);
        }

        /// Calculates the minimum fee amount for a given amount and burn token.
        ///
        /// Amount should be constrained to be greater than 1.
        /// Assumes `min_fee` is non-zero.
        ///
        /// # Arguments
        ///
        /// * `burn_token` - The address of the burn token
        /// * `amount` - The amount for which to calculate the minimum fee.
        ///
        /// # Returns
        ///
        /// The minimum fee for the given amount and burn token.
        fn calc_min_fee_amount(
            self: @ComponentState<TContractState>, burn_token: ContractAddress, amount: u256,
        ) -> u256 {
            let min_fee = self.token_to_min_fee.read(burn_token);
            if min_fee == 0 {
                return 0;
            }
            let min_fee_amount = (amount * min_fee) / MIN_FEE_MULTIPLIER;
            if min_fee_amount == 0 {
                1
            } else {
                min_fee_amount
            }
        }
    }
}
