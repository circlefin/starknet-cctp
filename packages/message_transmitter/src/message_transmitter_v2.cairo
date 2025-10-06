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

#[starknet::contract]
pub mod MessageTransmitterV2 {
    use cctp_components::attestable::AttestableComponent;
    use cctp_components::rescuable::RescuableComponent;
    use components::manageable::ManageableComponent;
    use components::ownable::OwnableComponent;
    use components::pausable::PausableComponent;
    use components::upgradeable::UpgradeableComponent;
    use core::num::traits::Zero;
    use interfaces::message_transmitter_v2::IMessageTransmitterV2;
    use interfaces::token_messager_minter_v2::{
        ITokenMessengerMinterV2Dispatcher, ITokenMessengerMinterV2DispatcherTrait,
    };
    use message::MessageV2;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use utils::AddressConversionTrait;

    // The threshold at which (and above) messages are considered finalized.
    pub const FINALITY_THRESHOLD_FINALIZED: u32 = 2000;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ManageableComponent, storage: manageable, event: ManageableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AttestableComponent, storage: attestable, event: AttestableEvent);
    component!(path: RescuableComponent, storage: rescuable, event: RescuableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::Pausable<ContractState>;

    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ManageableImpl = ManageableComponent::Manageable<ContractState>;

    impl ManageableInternalImpl = ManageableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl UpgradeableImpl = UpgradeableComponent::Upgradeable<ContractState>;

    #[abi(embed_v0)]
    impl AttestableImpl = AttestableComponent::Attestable<ContractState>;

    impl AttestableInternalImpl = AttestableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl RescuableImpl = RescuableComponent::Rescuable<ContractState>;

    impl RescuableInternalImpl = RescuableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        manageable: ManageableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        attestable: AttestableComponent::Storage,
        #[substorage(v0)]
        rescuable: RescuableComponent::Storage,
        used_nonces: Map<u256, bool>,
        local_domain: u32,
        version: u32,
        max_message_body_size: u256,
        initialized: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ManageableEvent: ManageableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        AttestableEvent: AttestableComponent::Event,
        #[flat]
        RescuableEvent: RescuableComponent::Event,
        MaxMessageBodySizeUpdated: MaxMessageBodySizeUpdated,
        MessageSent: MessageSent,
        MessageReceived: MessageReceived,
    }

    /// Emitted when the max message body size is updated
    #[derive(Drop, starknet::Event)]
    pub struct MaxMessageBodySizeUpdated {
        pub max_message_body_size: u256,
    }

    /// Emitted when a message is sent
    #[derive(Drop, starknet::Event)]
    pub struct MessageSent {
        pub message: ByteArray,
    }

    /// Emitted when a message is received
    #[derive(Drop, starknet::Event)]
    pub struct MessageReceived {
        #[key]
        pub caller: ContractAddress,
        pub source_domain: u32,
        #[key]
        pub nonce: u256,
        pub sender: u256,
        #[key]
        pub finality_threshold_executed: u32,
        pub message_body: ByteArray,
    }

    pub mod Errors {
        pub const INVALID_DESTINATION_DOMAIN: felt252 = 'Invalid destination domain';
        pub const DOMAIN_IS_LOCAL_DOMAIN: felt252 = 'Domain is local domain';
        pub const INVALID_MESSAGE_BODY_SIZE: felt252 = 'Message body exceeds max size';
        pub const INVALID_RECIPIENT: felt252 = 'Recipient must be non-zero';
        pub const INVALID_DESTINATION_CALLER: felt252 = 'Invalid destination caller';
        pub const INVALID_VERSION: felt252 = 'Invalid message version';
        pub const NONCE_ALREADY_USED: felt252 = 'Nonce already used';
        pub const UNFINALIZED_MESSAGE_FAILED: felt252 = 'Failed unfinalized message';
        pub const FINALIZED_MESSAGE_FAILED: felt252 = 'Failed finalized message';
        pub const INVALID_MAX_MESSAGE_BODY_SIZE: felt252 = 'Invalid max message body size';
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    }

    /// Contract constructor that sets up the initial admin
    ///
    /// # Arguments
    ///
    /// * `admin` - The address to be set as the initial admin
    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // initialize manageable component with admin
        self.manageable.initializer(admin);

        self.initialized.write(false);
    }

    #[abi(embed_v0)]
    impl MessageTransmitter of IMessageTransmitterV2<ContractState> {
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
            ref self: ContractState,
            local_domain: u32,
            version: u32,
            owner: ContractAddress,
            pauser: ContractAddress,
            rescuer: ContractAddress,
            attester_manager: ContractAddress,
            attesters: Array<ContractAddress>,
            signature_threshold: u64,
            max_message_body_size: u256,
        ) {
            // only admin can initialize
            self.manageable.assert_only_admin();

            // ensure not already initialized
            assert(!self.initialized.read(), Errors::ALREADY_INITIALIZED);

            // initialize components
            self.ownable.initializer(owner);
            self.rescuable.initializer(rescuer);
            self.pausable.initializer(pauser);
            self.attestable.initializer(attester_manager, attesters, signature_threshold);

            // set local domain and version
            self.local_domain.write(local_domain);
            self.version.write(version);

            // set max message body size
            assert(max_message_body_size > 0, Errors::INVALID_MAX_MESSAGE_BODY_SIZE);
            self.max_message_body_size.write(max_message_body_size);

            self.used_nonces.entry(0).write(true);

            // set initialized to true
            self.initialized.write(true);
        }

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
            ref self: ContractState,
            destination_domain: u32,
            recipient: u256,
            destination_caller: u256,
            min_finality_threshold: u32,
            message_body: ByteArray,
        ) {
            // ensure the contract is not paused
            self.pausable.assert_not_paused();

            assert(destination_domain != self.local_domain.read(), Errors::DOMAIN_IS_LOCAL_DOMAIN);

            // validate message body size
            assert(
                message_body.len().into() <= self.max_message_body_size.read(),
                Errors::INVALID_MESSAGE_BODY_SIZE,
            );

            assert(!recipient.is_zero(), Errors::INVALID_RECIPIENT);

            let message = MessageV2::format_message(
                self.version.read(),
                self.local_domain.read(),
                destination_domain,
                get_caller_address().to_u256(),
                recipient,
                destination_caller,
                min_finality_threshold,
                @message_body,
            );

            // emit MessageSent event
            self.emit(MessageSent { message });
        }

        /// Receives and processes a cross-chain message with its attestation.
        ///
        /// # Arguments
        ///
        /// * `message` - The encoded message to receive
        /// * `attestation` - The attestation signatures proving message validity
        ///
        /// # Returns
        ///
        /// Returns true if the message was successfully processed
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
            ref self: ContractState, message: ByteArray, attestation: ByteArray,
        ) -> bool {
            // when not paused, we can receive messages
            self.pausable.assert_not_paused();

            // validate message and attestation
            let (
                nonce, source_domain, sender, recipient, finality_threshold_executed, message_body,
            ) =
                self
                .validate_received_message(message, attestation);

            // mark nonce as used
            self.used_nonces.entry(nonce).write(true);

            // get token messenger dispatcher
            let token_messenger_dispatcher = ITokenMessengerMinterV2Dispatcher {
                contract_address: recipient,
            };

            // handle receive message
            if (finality_threshold_executed < FINALITY_THRESHOLD_FINALIZED) {
                assert(
                    token_messenger_dispatcher
                        .handle_receive_unfinalized_message(
                            source_domain,
                            sender,
                            finality_threshold_executed,
                            message_body.clone(),
                        ),
                    Errors::UNFINALIZED_MESSAGE_FAILED,
                );
            } else {
                assert(
                    token_messenger_dispatcher
                        .handle_receive_finalized_message(
                            source_domain,
                            sender,
                            finality_threshold_executed,
                            message_body.clone(),
                        ),
                    Errors::FINALIZED_MESSAGE_FAILED,
                );
            }

            // emit MessageReceived event
            self
                .emit(
                    MessageReceived {
                        caller: get_caller_address(),
                        source_domain,
                        nonce,
                        sender,
                        finality_threshold_executed,
                        message_body,
                    },
                );

            true
        }

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
        fn set_max_message_body_size(ref self: ContractState, max_message_body_size: u256) {
            self.ownable.assert_only_owner();
            self.max_message_body_size.write(max_message_body_size);

            self.emit(MaxMessageBodySizeUpdated { max_message_body_size });
        }

        /// Returns the current maximum allowed message body size
        ///
        /// # Returns
        ///
        /// The maximum message body size as u256
        fn get_max_message_body_size(self: @ContractState) -> u256 {
            self.max_message_body_size.read()
        }

        /// Checks if a nonce has already been used
        ///
        /// # Arguments
        ///
        /// * `nonce` - The nonce to check
        ///
        /// # Returns
        ///
        /// Returns true if the nonce has been used, false otherwise
        fn is_nonce_used(self: @ContractState, nonce: u256) -> bool {
            self.used_nonces.entry(nonce).read()
        }

        /// Returns the domain ID of this chain
        ///
        /// # Returns
        ///
        /// The local domain ID as u32
        fn get_local_domain(self: @ContractState) -> u32 {
            self.local_domain.read()
        }

        /// Returns the message format version used by this contract
        ///
        /// # Returns
        ///
        /// The message version as u32
        fn get_version(self: @ContractState) -> u32 {
            self.version.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl of ContractInternalTrait {
        /// Validates a received message and its attestation, returning the message details
        ///
        /// # Arguments
        ///
        /// * `message` - The encoded message to validate
        /// * `attestation` - The attestation signatures to verify
        ///
        /// # Returns
        ///
        /// Returns a tuple containing:
        /// - nonce: The message nonce
        /// - source_domain: The domain where the message originated
        /// - sender: The address that sent the message
        /// - recipient: The intended recipient on this domain
        /// - finality_threshold_executed: The finality level of the attestation
        /// - message_body: The decoded message body
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The attestation signatures are invalid or insufficient
        /// - The message format is invalid
        /// - The destination domain doesn't match the local domain
        /// - The destination caller is specified and doesn't match the current caller
        /// - The message version doesn't match the contract version
        /// - The nonce has already been used
        fn validate_received_message(
            ref self: ContractState, message: ByteArray, attestation: ByteArray,
        ) -> (
            u256, // nonce
            u32, // source domain
            u256, // sender
            ContractAddress, // recipient
            u32, // finality threshold executed
            ByteArray // message body
        ) {
            // validate message and attestation
            self.attestable.verify_attestation_signatures(@message, @attestation);

            // validate message format
            MessageV2::validate_message_format(@message);

            // validate destination domain
            assert(
                MessageV2::get_destination_domain(@message) == self.local_domain.read(),
                Errors::INVALID_DESTINATION_DOMAIN,
            );

            let destination_caller = MessageV2::get_destination_caller(@message);
            // validate destination caller
            if (!destination_caller.is_zero()) {
                assert(
                    destination_caller == get_caller_address().to_u256(),
                    Errors::INVALID_DESTINATION_CALLER,
                );
            }

            // validate version
            assert(
                MessageV2::get_version(@message) == self.version.read(), Errors::INVALID_VERSION,
            );

            // validate nonce
            let nonce = MessageV2::get_nonce(@message);
            assert(!self.used_nonces.entry(nonce).read(), Errors::NONCE_ALREADY_USED);

            (
                nonce,
                MessageV2::get_source_domain(@message),
                MessageV2::get_sender(@message),
                MessageV2::get_recipient(@message).to_address(),
                MessageV2::get_finality_threshold_executed(@message),
                MessageV2::get_message_body(@message),
            )
        }
    }
}
