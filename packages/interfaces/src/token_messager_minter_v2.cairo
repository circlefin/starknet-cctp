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

use starknet::ContractAddress;

#[starknet::interface]
pub trait ITokenMessengerMinterV2<TContractState> {
    /// Initializes the contract.
    ///
    /// # Arguments
    ///
    /// * `owner` - The owner of the contract.
    /// * `pauser` - The pauser of the contract.
    /// * `denylister` - The denylister of the contract.
    /// * `rescuer` - The rescuer of the contract.
    /// * `token_controller` - The token controller of the contract.
    /// * `min_fee_controller` - The min fee controller of the contract.
    /// * `fee_recipient` - The fee recipient of the contract.
    /// * `message_body_version` - The message body version of the contract.
    /// * `local_message_transmitter` - The local message transmitter of the contract.
    /// * `remote_domains` - The remote domains of the contract.
    /// * `remote_token_messengers` - The remote token messengers of the contract.
    fn initialize(
        ref self: TContractState,
        owner: ContractAddress,
        pauser: ContractAddress,
        denylister: ContractAddress,
        rescuer: ContractAddress,
        token_controller: ContractAddress,
        min_fee_controller: ContractAddress,
        fee_recipient: ContractAddress,
        message_body_version: u32,
        local_message_transmitter: ContractAddress,
        remote_domains: Array<u32>,
        remote_token_messengers: Array<u256>,
    );

    /// Handles an incoming finalized message received by the local MessageTransmitter,
    /// and takes the appropriate action. For a burn message, mints the
    /// associated token to the requested recipient on the local domain.
    /// Fees are separately minted to the currently set `feeRecipient` address.
    ///
    /// Validates the local sender is the local MessageTransmitter, and the
    /// remote sender is a registered remote TokenMessenger for `remote_domain`.
    ///
    /// # Arguments
    ///
    /// * `remote_domain` - The domain where the message originated from.
    /// * `sender` - The sender of the message (remote TokenMessenger).
    /// * `finality_threshold_executed` - The finality threshold (unused for finalized messages)
    /// * `message_body` - The message body bytes.
    ///
    /// # Returns
    ///
    /// Bool, true if successful.
    fn handle_receive_finalized_message(
        ref self: TContractState,
        remote_domain: u32,
        sender: u256,
        finality_threshold_executed: u32,
        message_body: ByteArray,
    ) -> bool;

    /// Handles an incoming unfinalized message received by the local
    /// MessageTransmitter, and takes the appropriate action. For a burn message, mints the
    /// associated token to the requested recipient on the local domain, less fees.
    /// Fees are separately minted to the currently set `feeRecipient` address.
    ///
    /// Validates the local sender is the local MessageTransmitter, and the
    /// remote sender is a registered remote TokenMessenger for `remote_domain`.
    /// Validates that `finality_threshold_executed` is at least 500.
    ///
    /// # Arguments
    ///
    /// * `remote_domain` - The domain where the message originated from.
    /// * `sender` - The sender of the message (remote TokenMessenger).
    /// * `finality_threshold_executed` - The level of finality at which the message was
    /// attested to
    /// * `message_body` - The message body bytes.
    ///
    /// # Returns
    ///
    /// Bool, true if successful.
    fn handle_receive_unfinalized_message(
        ref self: TContractState,
        remote_domain: u32,
        sender: u256,
        finality_threshold_executed: u32,
        message_body: ByteArray,
    ) -> bool;

    /// Returns the message body version.
    ///
    /// # Returns
    ///
    /// The message body version.
    fn message_body_version(self: @TContractState) -> u32;

    /// Returns the local message transmitter.
    ///
    /// # Returns
    ///
    /// The local message transmitter.
    fn local_message_transmitter(self: @TContractState) -> ContractAddress;

    /// Deposits and burns tokens from sender to be minted on destination domain.
    /// Emits a `DepositForBurn` event.
    ///
    /// # Arguments
    ///
    /// * `amount` - amount of tokens to burn
    /// * `destination_domain` - destination domain to receive message on
    /// * `mint_recipient` - address of mint recipient on destination domain
    /// * `burn_token` - token to burn `amount` of, on local domain
    /// * `destination_caller` - authorized caller on the destination domain, as u256. If equal
    /// to 0, any address can broadcast the message.
    /// * `max_fee` - maximum fee to pay on the destination domain, specified in units of
    /// burnToken
    /// * `min_finality_threshold` - the minimum finality at which a burn message will
    /// be attested to.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - `burnToken` is not supported
    /// - `destinationDomain` has no TokenMessenger registered
    /// - transferFrom() reverts. For example, if sender's burnToken balance or approved
    /// allowance to this contract is less than `amount`.
    /// - burn() reverts. For example, if `amount` is 0.
    /// - maxFee is greater than or equal to `amount`.
    /// - maxFee is less than `amount * minFee / MIN_FEE_MULTIPLIER`.
    /// - MessageTransmitter#sendMessage reverts.
    fn deposit_for_burn(
        ref self: TContractState,
        amount: u256,
        destination_domain: u32,
        mint_recipient: u256,
        burn_token: ContractAddress,
        destination_caller: u256,
        max_fee: u256,
        min_finality_threshold: u32,
    );

    /// Deposits and burns tokens from sender to be minted on destination domain.
    /// Emits a `DepositForBurn` event.
    ///
    /// # Arguments
    ///
    /// * `amount` - amount of tokens to burn
    /// * `destination_domain` - destination domain to receive message on
    /// * `mint_recipient` - address of mint recipient on destination domain
    /// * `burn_token` - token to burn `amount` of, on local domain
    /// * `destination_caller` - authorized caller on the destination domain, as u256. If equal
    /// to 0, any address can broadcast the message.
    /// * `max_fee` - maximum fee to pay on the destination domain, specified in units of
    /// burnToken
    /// * `min_finality_threshold` - the minimum finality at which a burn message will
    /// be attested to.
    /// * `hook_data` - hook data to append to burn message for interpretation on destination
    /// domain
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - `hookData` is zero-length
    /// - `burnToken` is not supported
    /// - `destinationDomain` has no TokenMessenger registered
    /// - transferFrom() reverts. For example, if sender's burnToken balance or approved
    /// allowance to this contract is less than `amount`.
    /// - burn() reverts. For example, if `amount` is 0.
    /// - maxFee is greater than or equal to `amount`.
    /// - maxFee is less than `amount * minFee / MIN_FEE_MULTIPLIER`.
    /// - MessageTransmitter#sendMessage reverts.
    fn deposit_for_burn_with_hook(
        ref self: TContractState,
        amount: u256,
        destination_domain: u32,
        mint_recipient: u256,
        burn_token: ContractAddress,
        destination_caller: u256,
        max_fee: u256,
        min_finality_threshold: u32,
        hook_data: ByteArray,
    );
}
