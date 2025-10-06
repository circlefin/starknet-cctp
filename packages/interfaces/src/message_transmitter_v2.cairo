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
    /// Sends a cross-chain message to a recipient on another domain.
    ///
    /// # Arguments
    ///
    /// * `destination_domain` - The domain ID of the destination chain
    /// * `recipient` - The address of the recipient on the destination chain
    /// * `destination_caller` - The authorized caller on destination domain (0 allows any)
    /// * `min_finality_threshold` - The minimum finality threshold for the message
    /// * `message_body` - The message content to send
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The contract is paused
    /// - The destination_domain equals the local domain
    /// - The message body size exceeds the maximum allowed size
    /// - The recipient is zero address
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
    /// - The attestation signatures are invalid
    /// - The message format is invalid
    /// - The destination domain doesn't match the local domain
    /// - The destination caller is specified and doesn't match the caller
    /// - The message version doesn't match the contract version
    /// - The nonce has already been used
    /// - The unfinalized message handler fails (for messages below finality threshold)
    /// - The finalized message handler fails (for messages at or above finality threshold)
    fn receive_message(
        ref self: TContractState, message: ByteArray, attestation: ByteArray,
    ) -> bool;

    /// Sets the maximum allowed message body size. Only callable by the owner.
    ///
    /// # Arguments
    ///
    /// * `max_message_body_size` - The new maximum message body size to set
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the owner
    fn set_max_message_body_size(ref self: TContractState, max_message_body_size: u256);

    /// Returns the current maximum allowed message body size
    ///
    /// # Returns
    ///
    /// The maximum message body size as u256
    fn get_max_message_body_size(self: @TContractState) -> u256;

    /// Initializes the MessageTransmitter contract with all necessary role addresses
    /// and configuration. This function can only be called once by the admin.
    ///
    /// # Arguments
    ///
    /// * `local_domain` - The domain ID of this chain
    /// * `version` - The message format version
    /// * `owner` - Address to be set as owner
    /// * `pauser` - Address to be set as pauser
    /// * `rescuer` - Address to be set as rescuer
    /// * `attester_manager` - Address to be set as attester manager
    /// * `attesters` - Array of initial attester addresses
    /// * `signature_threshold` - The minimum number of signatures required
    /// * `max_message_body_size` - The maximum allowed message body size
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the admin
    /// - The contract has already been initialized
    /// - The max_message_body_size is 0
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

    /// Checks if a nonce has already been used
    ///
    /// # Arguments
    ///
    /// * `nonce` - The nonce to check
    ///
    /// # Returns
    ///
    /// Returns true if the nonce has been used, false otherwise
    fn is_nonce_used(self: @TContractState, nonce: u256) -> bool;

    /// Returns the domain ID of this chain
    ///
    /// # Returns
    ///
    /// The local domain ID as u32
    fn get_local_domain(self: @TContractState) -> u32;

    /// Returns the message format version used by this contract
    ///
    /// # Returns
    ///
    /// The message version as u32
    fn get_version(self: @TContractState) -> u32;
}
