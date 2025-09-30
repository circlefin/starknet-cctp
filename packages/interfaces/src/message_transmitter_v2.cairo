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
pub trait IMessageTransmitterV2<TContractState> {
    /// Send a message to the destination domain and recipient.
    /// Formats the message, and emits a `MessageSent` event with message information.
    ///
    /// # Arguments
    ///
    /// * `destination_domain` - The destination domain
    /// * `recipient` - Address of message recipient on destination chain
    /// * `destination_caller` - The destination caller
    /// * `min_finality_threshold` - The minimum finality at which the message should be attested
    /// to.
    /// * `message_body` - The message body.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The contract is paused
    /// - The destination domain equals the local domain
    /// - The message body size exceeds the maximum allowed size
    /// - The recipient address is zero
    fn send_message(
        ref self: TContractState,
        destination_domain: u32,
        recipient: u256,
        destination_caller: u256,
        min_finality_threshold: u32,
        message_body: ByteArray,
    );

    /// Receive a message. Messages can only be broadcast once for a given nonce.
    /// The message body of a valid message is passed to the specified recipient for further
    /// processing.
    ///
    /// A valid attestation is the concatenated 65-byte signature(s) of exactly
    /// `thresholdSignature` signatures, in increasing order of attester address.
    /// ***If the attester addresses recovered from signatures are not in
    /// increasing order, signature verification will fail.***
    /// If incorrect number of signatures or duplicate signatures are supplied,
    /// signature verification will fail.
    ///
    /// Message Format:
    ///
    /// Field                        Bytes      Type       Index
    /// version                      4          uint32     0
    /// sourceDomain                 4          uint32     4
    /// destinationDomain            4          uint32     8
    /// nonce                        32         bytes32    12
    /// sender                       32         bytes32    44
    /// recipient                    32         bytes32    76
    /// destinationCaller            32         bytes32    108
    /// minFinalityThreshold         4          uint32     140
    /// finalityThresholdExecuted    4          uint32     144
    /// messageBody                  dynamic    bytes      148
    ///
    /// # Arguments
    ///
    /// * `message` - The message bytes
    /// * `attestation` - The attestation bytes, concatenated 65-byte signature(s) of `message`, in
    /// increasing order of the attester address recovered from signatures.
    ///
    /// # Returns
    ///
    /// * `true` - If the message is valid and has not been broadcasted before
    /// * `false` - If the message is invalid or has already been broadcasted
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The contract is paused
    /// - The attestation signatures are invalid or insufficient
    /// - The message format is invalid
    /// - The destination domain doesn't match the local domain
    /// - The destination caller is specified but doesn't match the actual caller
    /// - The message version doesn't match the contract version
    /// - The nonce has already been used
    /// - The recipient's handle_receive message handler fails
    fn receive_message(
        ref self: TContractState, message: ByteArray, attestation: ByteArray,
    ) -> bool;

    /// Set the max message body size.
    ///
    /// # Arguments
    ///
    /// * `max_message_body_size` - The max message body size
    ///
    /// # Panics
    ///
    /// * `INVALID_MAX_MESSAGE_BODY_SIZE` - If the max message body size is invalid
    /// * `INVALID_OWNER` - If the caller is not the owner
    fn set_max_message_body_size(ref self: TContractState, max_message_body_size: u256);

    /// Get the max message body size.
    ///
    /// # Returns
    ///
    /// * `max_message_body_size` - The max message body size
    ///
    /// # Returns
    ///
    /// * `max_message_body_size` - The max message body size
    fn get_max_message_body_size(self: @TContractState) -> u256;

    /// Initialize the contract.
    ///
    /// # Arguments
    ///
    /// * `local_domain` - The local domain
    /// * `version` - The version
    /// * `owner` - The owner
    /// * `pauser` - The pauser
    /// * `rescuer` - The rescuer
    /// * `attester_manager` - The attester manager
    /// * `attesters` - The attesters
    /// * `signature_threshold` - The signature threshold
    /// * `max_message_body_size` - The max message body size
    ///
    /// # Panics
    ///
    /// * `ALREADY_INITIALIZED` - If the contract is already initialized
    /// * `NOT_ADMIN` - If the caller is not the admin
    /// * `INVALID_MAX_MESSAGE_BODY_SIZE` - If the max message body size is invalid
    fn initialize(
        ref self: TContractState,
        local_domain: u32,
        version: u32,
        owner: ContractAddress,
        pauser: ContractAddress,
        rescuer: ContractAddress,
        attester_manager: ContractAddress,
        attesters: Array<ContractAddress>,
        signature_threshold: u64,
        max_message_body_size: u256,
    );

    /// Check if a nonce has been used.
    ///
    /// # Arguments
    ///
    /// * `nonce` - The nonce to check
    ///
    /// # Returns
    ///
    /// * `true` - If the nonce has been used
    /// * `false` - If the nonce has not been used
    fn is_nonce_used(self: @TContractState, nonce: u256) -> bool;

    /// Get the local domain.
    ///
    /// # Returns
    ///
    /// * `local_domain` - The local domain
    fn get_local_domain(self: @TContractState) -> u32;

    /// Get the version.
    ///
    /// # Returns
    ///
    /// * `version` - The version
    fn get_version(self: @TContractState) -> u32;
}
