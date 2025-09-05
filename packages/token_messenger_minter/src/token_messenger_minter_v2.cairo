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
pub mod TokenMessengerMinterV2 {
    use cctp_components::fee_recipient_controller::FeeRecipientControllerComponent;
    use cctp_components::min_fee_controller::MinFeeControllerComponent;
    use cctp_components::remote_token_messenger_controller::RemoteTokenMessengerControllerComponent;
    use cctp_components::rescuable::RescuableComponent;
    use cctp_components::token_controller::TokenControllerComponent;
    use components::denylistable::DenylistableComponent;
    use components::manageable::ManageableComponent;
    use components::ownable::OwnableComponent;
    use components::pausable::PausableComponent;
    use components::upgradeable::UpgradeableComponent;
    use core::num::traits::Zero;
    use interfaces::message_transmitter_v2::{
        IMessageTransmitterV2Dispatcher, IMessageTransmitterV2DispatcherTrait,
    };
    use interfaces::token_messager_minter_v2::ITokenMessengerMinterV2;
    use message::BurnMessageV2;
    use stablecoin::{IFiatTokenDispatcher, IFiatTokenDispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, get_block_info, get_caller_address, get_contract_address, get_tx_info,
    };
    use utils::AddressConversionTrait;

    pub mod Errors {
        pub const INVALID_MESSAGE_BODY_VERSION: felt252 = 'Invalid message body version';
        pub const MESSAGE_EXPIRED: felt252 = 'Message expired must re-sign';
        pub const FEE_EQUALS_OR_EXCEEDS_AMOUNT: felt252 = 'Fee equals or exceeds amount';
        pub const FEE_EXCEEDS_MAX_FEE: felt252 = 'Fee exceeds max fee';
        pub const MINT_TOKEN_NOT_SUPPORTED: felt252 = 'Mint token not supported';
        pub const FIRST_MINT_OPERATION_FAILED: felt252 = 'First mint operation failed';
        pub const SECOND_MINT_OPERATION_FAILED: felt252 = 'Second mint operation failed';
        pub const CALLER_NOT_LOCAL_MSG_TRANSMITTER: felt252 = 'Caller not local MT';
        pub const UNSUPPORTED_FINALITY_THRESHOLD: felt252 = 'Unsupported finality threshold';
        pub const AMOUNT_MUST_BE_NONZERO: felt252 = 'Amount must be nonzero';
        pub const MINT_RECIPIENT_MUST_BE_NONZERO: felt252 = 'Mint recipient must be non-zero';
        pub const MAX_FEE_MUST_BE_LESS_THAN_AMOUNT: felt252 = 'Max fee must be less than amt';
        pub const INSUFFICIENT_MAX_FEE: felt252 = 'Insufficient max fee';
        pub const BURN_OPERATION_FAILED: felt252 = 'Burn operation failed';
        pub const TRANSFER_OPERATION_FAILED: felt252 = 'Transfer operation failed';
        pub const HOOK_DATA_IS_EMPTY: felt252 = 'Hook data is empty';
        pub const MESSAGE_TRANSMITTER_MUST_BE_NONZERO: felt252 = 'MessageTransmitter is zero';
    }

    // Constants
    pub const TOKEN_MESSENGER_MIN_FINALITY_THRESHOLD: u32 = 500;

    // Component declarations
    component!(path: DenylistableComponent, storage: denylistable, event: DenylistableEvent);
    component!(
        path: FeeRecipientControllerComponent,
        storage: fee_recipient_controller,
        event: FeeRecipientControllerEvent,
    );
    component!(path: ManageableComponent, storage: manageable, event: ManageableEvent);
    component!(
        path: MinFeeControllerComponent, storage: min_fee_controller, event: MinFeeControllerEvent,
    );
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: RemoteTokenMessengerControllerComponent,
        storage: remote_token_messenger_controller,
        event: RemoteTokenMessengerControllerEvent,
    );
    component!(path: RescuableComponent, storage: rescuable, event: RescuableEvent);
    component!(
        path: TokenControllerComponent, storage: token_controller, event: TokenControllerEvent,
    );
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // Component implementations
    #[abi(embed_v0)]
    impl DenylistableImpl = DenylistableComponent::Denylistable<ContractState>;
    impl DenylistableInternalImpl = DenylistableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl FeeRecipientControllerImpl =
        FeeRecipientControllerComponent::FeeRecipientController<ContractState>;
    impl FeeRecipientControllerInternalImpl =
        FeeRecipientControllerComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ManageableImpl = ManageableComponent::Manageable<ContractState>;
    impl ManageableInternalImpl = ManageableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl MinFeeControllerImpl =
        MinFeeControllerComponent::MinFeeController<ContractState>;
    impl MinFeeControllerInternalImpl = MinFeeControllerComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::Pausable<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl RemoteTokenMessengerControllerImpl =
        RemoteTokenMessengerControllerComponent::RemoteTokenMessengerController<ContractState>;
    impl RemoteTokenMessengerControllerInternalImpl =
        RemoteTokenMessengerControllerComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl RescuableImpl = RescuableComponent::Rescuable<ContractState>;
    impl RescuableInternalImpl = RescuableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl TokenControllerImpl =
        TokenControllerComponent::TokenController<ContractState>;
    impl TokenControllerInternalImpl = TokenControllerComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl UpgradeableImpl = UpgradeableComponent::Upgradeable<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        denylistable: DenylistableComponent::Storage,
        #[substorage(v0)]
        fee_recipient_controller: FeeRecipientControllerComponent::Storage,
        #[substorage(v0)]
        manageable: ManageableComponent::Storage,
        #[substorage(v0)]
        min_fee_controller: MinFeeControllerComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        remote_token_messenger_controller: RemoteTokenMessengerControllerComponent::Storage,
        #[substorage(v0)]
        rescuable: RescuableComponent::Storage,
        #[substorage(v0)]
        token_controller: TokenControllerComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        message_body_version: u32,
        local_message_transmitter: ContractAddress,
        initialized: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        DenylistableEvent: DenylistableComponent::Event,
        #[flat]
        FeeRecipientControllerEvent: FeeRecipientControllerComponent::Event,
        #[flat]
        ManageableEvent: ManageableComponent::Event,
        #[flat]
        MinFeeControllerEvent: MinFeeControllerComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        RemoteTokenMessengerControllerEvent: RemoteTokenMessengerControllerComponent::Event,
        #[flat]
        RescuableEvent: RescuableComponent::Event,
        #[flat]
        TokenControllerEvent: TokenControllerComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        MintAndWithdraw: MintAndWithdraw,
        DepositForBurn: DepositForBurn,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MintAndWithdraw {
        #[key]
        pub mint_recipient: ContractAddress,
        pub amount: u256,
        #[key]
        pub mint_token: ContractAddress,
        pub fee_collected: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositForBurn {
        #[key]
        pub burn_token: ContractAddress,
        pub amount: u256,
        #[key]
        pub depositor: ContractAddress,
        pub mint_recipient: u256,
        pub destination_domain: u32,
        pub destination_token_messenger: u256,
        pub destination_caller: u256,
        pub max_fee: u256,
        pub min_finality_threshold: u32,
        pub hook_data: ByteArray,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // Only initialize the manageable component with admin
        self.manageable.initializer(admin);

        // Set initialized to false
        self.initialized.write(false);
    }

    #[abi(embed_v0)]
    impl TokenMessengerMinterV2Impl of ITokenMessengerMinterV2<ContractState> {
        fn initialize(
            ref self: ContractState,
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
        ) {
            // Only admin can initialize
            self.manageable.assert_only_admin();

            // Ensure not already initialized
            assert(!self.initialized.read(), 'Already initialized');

            // Ensure local message transmitter is not zero
            assert(
                !local_message_transmitter.is_zero(), Errors::MESSAGE_TRANSMITTER_MUST_BE_NONZERO,
            );

            // Initialize ownable FIRST as other components depend on it
            self.ownable.initializer(owner);

            // Initialize all other components
            self.pausable.initializer(pauser);
            self.denylistable.initializer(denylister);
            self.rescuable.initializer(rescuer);
            self.token_controller.initializer(token_controller);
            self.min_fee_controller.initializer(min_fee_controller);
            self.fee_recipient_controller.initializer(fee_recipient);

            // Set message body version (immutable after initialization)
            self.message_body_version.write(message_body_version);

            // Set local message transmitter (immutable after initialization)
            self.local_message_transmitter.write(local_message_transmitter);

            // Remote token messenger configuration
            let remote_domains_length = remote_domains.len();
            assert(
                remote_domains_length == remote_token_messengers.len(), 'Array lengths must match',
            );

            let mut i: u32 = 0;
            while i != remote_domains_length {
                let domain = *remote_domains.at(i.into());
                let messenger = *remote_token_messengers.at(i.into());

                // Use internal function to add remote token messenger without ownership check
                self
                    .remote_token_messenger_controller
                    .add_remote_token_messenger_internal(domain, messenger);

                i += 1;
            }

            // Mark as initialized
            self.initialized.write(true);
        }

        fn message_body_version(self: @ContractState) -> u32 {
            self.message_body_version.read()
        }

        fn local_message_transmitter(self: @ContractState) -> ContractAddress {
            self.local_message_transmitter.read()
        }

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
            ref self: ContractState,
            remote_domain: u32,
            sender: u256,
            finality_threshold_executed: u32,
            message_body: ByteArray,
        ) -> bool {
            // Assert caller is local message transmitter
            self.assert_local_message_transmitter();

            // Assert sender is registered remote token messenger for the domain
            self
                .remote_token_messenger_controller
                .assert_only_remote_token_messenger(remote_domain, sender);

            // Handle the message
            self.handle_receive_message(@message_body, remote_domain)
        }

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
            ref self: ContractState,
            remote_domain: u32,
            sender: u256,
            finality_threshold_executed: u32,
            message_body: ByteArray,
        ) -> bool {
            // Assert caller is local message transmitter
            self.assert_local_message_transmitter();

            // Assert sender is registered remote token messenger for the domain
            self
                .remote_token_messenger_controller
                .assert_only_remote_token_messenger(remote_domain, sender);

            // Validate finality threshold
            assert(
                finality_threshold_executed >= TOKEN_MESSENGER_MIN_FINALITY_THRESHOLD,
                Errors::UNSUPPORTED_FINALITY_THRESHOLD,
            );

            // Handle the message
            self.handle_receive_message(@message_body, remote_domain)
        }

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
        /// burnToken * `min_finality_threshold` - the minimum finality at which a burn message will
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
            ref self: ContractState,
            amount: u256,
            destination_domain: u32,
            mint_recipient: u256,
            burn_token: ContractAddress,
            destination_caller: u256,
            max_fee: u256,
            min_finality_threshold: u32,
        ) {
            // Check that contract is not paused
            self.pausable.assert_not_paused();

            // Check that caller and origin are not denylisted
            self.assert_not_denylisted_caller_and_origin();

            // Use empty hook data for standard deposit for burn
            let empty_hook_data: ByteArray = Default::default();

            // Call internal deposit for burn function with empty hook data
            self
                .deposit_for_burn_internal(
                    amount,
                    destination_domain,
                    mint_recipient,
                    burn_token,
                    destination_caller,
                    max_fee,
                    min_finality_threshold,
                    empty_hook_data,
                );
        }

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
        /// burnToken * `min_finality_threshold` - the minimum finality at which a burn message will
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
            ref self: ContractState,
            amount: u256,
            destination_domain: u32,
            mint_recipient: u256,
            burn_token: ContractAddress,
            destination_caller: u256,
            max_fee: u256,
            min_finality_threshold: u32,
            hook_data: ByteArray,
        ) {
            // Check that contract is not paused
            self.pausable.assert_not_paused();

            // Check that caller and origin are not denylisted
            self.assert_not_denylisted_caller_and_origin();

            // Validate that hook data is not empty
            assert(hook_data.len() > 0, Errors::HOOK_DATA_IS_EMPTY);

            // Call internal deposit for burn function with provided hook data
            self
                .deposit_for_burn_internal(
                    amount,
                    destination_domain,
                    mint_recipient,
                    burn_token,
                    destination_caller,
                    max_fee,
                    min_finality_threshold,
                    hook_data,
                );
        }
    }


    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Asserts that both the caller and transaction origin are not denylisted
        fn assert_not_denylisted_caller_and_origin(self: @ContractState) {
            let caller = get_caller_address();

            // First check the direct caller
            self.denylistable.assert_not_denylisted(caller);

            // Get transaction info to check origin
            let tx_info = get_tx_info().unbox();
            let account_contract_address = tx_info.account_contract_address;

            // If origin is different from caller, also check the origin
            if account_contract_address != caller {
                self.denylistable.assert_not_denylisted(account_contract_address);
            }
        }

        /// Validates a BurnMessage and unpacks relevant fields.
        ///
        /// # Arguments
        ///
        /// * `message` - Finalized message
        ///
        /// # Returns
        ///
        /// (mint_recipient, burn_token, amount, fee)
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - The BurnMessage is malformed
        /// - The BurnMessage version isn't supported
        /// - The BurnMessage has expired
        /// - The fee equals or exceeds the amount
        /// - The fee exceeds the max fee specified on the source chain
        fn validated_received_message(
            self: @ContractState, message: @ByteArray,
        ) -> (ContractAddress, u256, u256, u256) {
            // Validate message format
            BurnMessageV2::validate_burn_message_format(message);

            // Check message version
            let version = BurnMessageV2::get_version(message);
            let expected_version = self.message_body_version.read();
            assert(version == expected_version, Errors::INVALID_MESSAGE_BODY_VERSION);

            // Enforce message expiration
            let expiration_block = BurnMessageV2::get_expiration_block(message);
            if expiration_block != 0 {
                let current_block: u256 = get_block_info().unbox().block_number.into();
                assert(expiration_block > current_block, Errors::MESSAGE_EXPIRED);
            }

            // Get amounts and validate fee
            let amount = BurnMessageV2::get_amount(message);
            let fee = BurnMessageV2::get_fee_executed(message);
            let max_fee = BurnMessageV2::get_max_fee(message);

            // Validate fee doesn't equal or exceed amount
            if fee != 0 {
                assert(fee < amount, Errors::FEE_EQUALS_OR_EXCEEDS_AMOUNT);
            }

            // Validate fee doesn't exceed max fee
            assert(fee <= max_fee, Errors::FEE_EXCEEDS_MAX_FEE);

            // Get recipient and burn token
            let mint_recipient_bytes = BurnMessageV2::get_mint_recipient(message);
            let burn_token = BurnMessageV2::get_burn_token(message);
            let mint_recipient: ContractAddress = mint_recipient_bytes.to_address();

            (mint_recipient, burn_token, amount, fee)
        }

        /// Mints to multiple recipients amounts of local tokens corresponding to the
        /// given (source_domain, burn_token) pair.
        ///
        /// # Arguments
        ///
        /// * `source_domain` - Source domain where burn_token was burned.
        /// * `burn_token` - Burned token address as bytes32.
        /// * `recipient_one` - Address to receive amount_one of minted tokens
        /// * `recipient_two` - Address to receive amount_two of minted tokens
        /// * `amount_one` - Amount of tokens to mint to recipient_one
        /// * `amount_two` - Amount of tokens to mint to recipient_two
        ///
        /// # Returns
        ///
        /// token minted.
        ///
        /// # Panics
        ///
        /// This function will panic if the (source_domain, burn_token) pair does not
        /// map to a nonzero local token address. This mapping can be queried using
        /// get_local_token().
        fn mint(
            ref self: ContractState,
            source_domain: u32,
            burn_token: u256,
            recipient_one: ContractAddress,
            recipient_two: ContractAddress,
            amount_one: u256,
            amount_two: u256,
        ) -> ContractAddress {
            // Check that contract is not paused
            self.pausable.assert_not_paused();

            // Get local token for the (source_domain, burn_token) pair
            let mint_token = self.token_controller.get_local_token(source_domain, burn_token);

            // Ensure the mint token is supported (non-zero address)
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(mint_token != zero_address, Errors::MINT_TOKEN_NOT_SUPPORTED);

            // Create token dispatcher
            let token_dispatcher = IFiatTokenDispatcher { contract_address: mint_token };

            // Mint to first recipient if amount is non-zero
            if amount_one != 0 {
                token_dispatcher.mint(recipient_one, amount_one);
            }

            // Mint to second recipient if amount is non-zero
            if amount_two != 0 {
                token_dispatcher.mint(recipient_two, amount_two);
            }

            mint_token
        }

        /// Mints tokens to a recipient and optionally a fee to the
        /// currently set fee recipient.
        ///
        /// # Arguments
        ///
        /// * `remote_domain` - domain where burned tokens originate from
        /// * `burn_token` - address of token burned
        /// * `mint_recipient` - recipient address of minted tokens
        /// * `amount` - amount of tokens to mint to mint_recipient
        /// * `fee` - fee collected for mint
        fn mint_and_withdraw(
            ref self: ContractState,
            remote_domain: u32,
            burn_token: u256,
            mint_recipient: ContractAddress,
            amount: u256,
            fee: u256,
        ) {
            // Get fee recipient from component
            let fee_recipient = self.fee_recipient_controller.fee_recipient();

            // Call internal mint function - it will handle zero amounts efficiently
            // mint_recipient gets the main amount, fee_recipient gets the fee (if any)
            let mint_token = self
                .mint(remote_domain, burn_token, mint_recipient, fee_recipient, amount, fee);

            // Emit event
            self.emit(MintAndWithdraw { mint_recipient, amount, mint_token, fee_collected: fee });
        }

        /// Validates a received message and mints the token to the mintRecipient, less
        /// fees.
        ///
        /// # Arguments
        ///
        /// * `message` - Received message
        /// * `remote_domain` - The domain where the message originated from
        ///
        /// # Returns
        ///
        /// Bool, true if successful.
        ///
        /// # Panics
        ///
        /// This function will panic if:
        /// - validated_received_message fails to validate the message.
        /// - the mint operation fails.
        fn handle_receive_message(
            ref self: ContractState, message: @ByteArray, remote_domain: u32,
        ) -> bool {
            // Validate message and unpack fields
            let (mint_recipient, burn_token, amount, fee) = self
                .validated_received_message(message);

            // Mint tokens (recipient gets amount minus fee, fee recipient gets fee)
            self.mint_and_withdraw(remote_domain, burn_token, mint_recipient, amount - fee, fee);

            true
        }

        /// Asserts that the caller is the local message transmitter
        fn assert_local_message_transmitter(self: @ContractState) {
            let local_message_transmitter = self.local_message_transmitter.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(
                local_message_transmitter != zero_address
                    && get_caller_address() == local_message_transmitter,
                Errors::CALLER_NOT_LOCAL_MSG_TRANSMITTER,
            );
        }

        /// Deposits and burns tokens to be minted on destination domain
        ///
        /// # Arguments
        ///
        /// * `amount` - amount of tokens to burn (must be non-zero)
        /// * `destination_domain` - destination domain
        /// * `mint_recipient` - address of mint recipient on destination domain
        /// * `burn_token` - address of the token burned on the source chain
        /// * `destination_caller` - caller on the destination domain, as u256
        /// * `max_fee` - maximum fee to pay on destination chain
        /// * `min_finality_threshold` - minimum finality threshold for the message
        /// * `hook_data` - optional hook data for interpretation on destination chain
        fn deposit_for_burn_internal(
            ref self: ContractState,
            amount: u256,
            destination_domain: u32,
            mint_recipient: u256,
            burn_token: ContractAddress,
            destination_caller: u256,
            max_fee: u256,
            min_finality_threshold: u32,
            hook_data: ByteArray,
        ) {
            // Validate inputs
            assert(amount > 0, Errors::AMOUNT_MUST_BE_NONZERO);
            assert(mint_recipient != 0, Errors::MINT_RECIPIENT_MUST_BE_NONZERO);
            assert(max_fee < amount, Errors::MAX_FEE_MUST_BE_LESS_THAN_AMOUNT);

            // Verify minimum fee if minFee > 0
            let min_fee = self.min_fee_controller.min_fee(burn_token);
            if min_fee > 0 {
                let min_fee_amount = self
                    .min_fee_controller
                    .calc_min_fee_amount(burn_token, amount);
                assert(max_fee >= min_fee_amount, Errors::INSUFFICIENT_MAX_FEE);
            }

            // Get remote token messenger for destination domain
            let destination_token_messenger = self
                .remote_token_messenger_controller
                .remote_token_messenger(destination_domain);

            // Deposit and burn tokens
            self.deposit_and_burn(burn_token, get_caller_address(), amount);

            // Format message body
            let burn_token_felt: felt252 = burn_token.into();
            let burn_token_u256: u256 = burn_token_felt.into();
            let depositor_felt: felt252 = get_caller_address().into();
            let depositor_u256: u256 = depositor_felt.into();
            let burn_message = BurnMessageV2::format_message_for_relay(
                self.message_body_version.read(),
                burn_token_u256,
                mint_recipient,
                amount,
                depositor_u256,
                max_fee,
                hook_data.clone(),
            );

            // Send message via local message transmitter
            let local_message_transmitter = self.local_message_transmitter.read();
            let message_transmitter = IMessageTransmitterV2Dispatcher {
                contract_address: local_message_transmitter,
            };
            message_transmitter
                .send_message(
                    destination_domain,
                    destination_token_messenger,
                    destination_caller,
                    min_finality_threshold,
                    burn_message,
                );

            // Emit event
            self
                .emit(
                    DepositForBurn {
                        burn_token,
                        amount,
                        depositor: get_caller_address(),
                        mint_recipient,
                        destination_domain,
                        destination_token_messenger,
                        destination_caller,
                        max_fee,
                        min_finality_threshold,
                        hook_data,
                    },
                );
        }

        /// Deposits tokens from `from` address and burns them
        ///
        /// # Arguments
        ///
        /// * `burn_token` - address of contract to burn deposited tokens, on local domain
        /// * `from` - address depositing the funds
        /// * `amount` - deposit amount
        fn deposit_and_burn(
            ref self: ContractState,
            burn_token: ContractAddress,
            from: ContractAddress,
            amount: u256,
        ) {
            // Validate burn limit
            self.token_controller.assert_within_burn_limit(burn_token, amount);

            // Get local minter (this contract)
            let local_minter = get_contract_address();

            // Create token dispatcher
            let token_dispatcher = IFiatTokenDispatcher { contract_address: burn_token };

            // Transfer tokens from depositor to local minter (this contract)
            let transfer_success = token_dispatcher.transfer_from(from, local_minter, amount);
            assert(transfer_success, Errors::TRANSFER_OPERATION_FAILED);

            // Burn the tokens from local minter
            token_dispatcher.burn(amount);
        }
    }
}
