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

//! # ERC20 Interface
//!
//! This module provides a minimal ERC20 interface for interacting with ERC20 tokens.
//! It includes only the essential functions needed for token operations within the
//! CCTP components.

use starknet::ContractAddress;

/// Minimal ERC20 interface for token operations
///
/// This interface provides the essential ERC20 functions needed for token
/// interactions within the CCTP components.
#[starknet::interface]
pub trait IERC20<TContractState> {
    /// Transfers tokens from the contract to a specified address
    ///
    /// # Arguments
    ///
    /// * `to` - The recipient address
    /// * `amount` - The amount of tokens to transfer
    ///
    /// # Returns
    ///
    /// `true` if the transfer succeeded, `false` otherwise
    fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;

    /// Returns the balance of a specified address
    ///
    /// # Arguments
    ///
    /// * `account` - The address to query the balance of
    ///
    /// # Returns
    ///
    /// The balance of the specified address
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}
