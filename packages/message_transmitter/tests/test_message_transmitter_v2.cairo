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

use cctp_components::attestable::{IAttestableDispatcher, IAttestableDispatcherTrait};
use cctp_components::rescuable::{IRescuableDispatcher, IRescuableDispatcherTrait};
use components::manageable::{IManageableDispatcher, IManageableDispatcherTrait};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use components::pausable::{IPausableDispatcher, IPausableDispatcherTrait};
use components::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use core::keccak::compute_keccak_byte_array;
use interfaces::message_transmitter_v2::{
    IMessageTransmitterV2Dispatcher, IMessageTransmitterV2DispatcherTrait,
};
use interfaces::token_messager_minter_v2::ITokenMessengerMinterV2;
use message::MessageV2;
use message_transmitter::MessageTransmitterV2;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::{recover_public_key, signature_from_vrs};
use starknet::secp256k1::Secp256k1Point;
use test_utils::hex_string_to_bytes_array;
use utils::{
    AddressConversionTrait, append_u256_be, append_u32_be, extract_u256_be, reverse_u256_bytes,
};


// mock token messenger minter contract
#[starknet::contract]
mod MockTokenMessengerMinter {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        unfinalized: bool,
        finalized: bool,
        failed: bool,
    }

    #[abi(embed_v0)]
    impl MockTokenMessengerMinter of super::ITokenMessengerMinterV2<ContractState> {
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
        ) {}

        fn message_body_version(self: @ContractState) -> u32 {
            0
        }

        fn local_message_transmitter(self: @ContractState) -> ContractAddress {
            0.try_into().unwrap()
        }

        fn deposit_for_burn(
            ref self: ContractState,
            amount: u256,
            destination_domain: u32,
            mint_recipient: u256,
            burn_token: ContractAddress,
            destination_caller: u256,
            max_fee: u256,
            min_finality_threshold: u32,
        ) {}

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
        ) {}

        fn handle_receive_unfinalized_message(
            ref self: ContractState,
            remote_domain: u32,
            sender: u256,
            finality_threshold_executed: u32,
            message_body: ByteArray,
        ) -> bool {
            if (self.failed.read()) {
                return false;
            }

            self.unfinalized.write(true);
            true
        }

        fn handle_receive_finalized_message(
            ref self: ContractState,
            remote_domain: u32,
            sender: u256,
            finality_threshold_executed: u32,
            message_body: ByteArray,
        ) -> bool {
            if (self.failed.read()) {
                return false;
            }

            self.finalized.write(true);
            true
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn is_unfinalized(ref self: ContractState) -> bool {
            self.unfinalized.read()
        }

        #[external(v0)]
        fn is_finalized(ref self: ContractState) -> bool {
            self.finalized.read()
        }

        #[external(v0)]
        fn set_failed(ref self: ContractState, failed: bool) {
            self.failed.write(failed);
        }
    }
}

// helper trait for testing
#[starknet::interface]
trait ITokenMessengerMinterTestHelper<TContractState> {
    fn is_unfinalized(ref self: TContractState) -> bool;
    fn is_finalized(ref self: TContractState) -> bool;
    fn set_failed(ref self: TContractState, failed: bool);
}

fn format_message(
    version: u32,
    source_domain: u32,
    destination_domain: u32,
    nonce: u256,
    sender: u256,
    recipient: u256,
    destination_caller: u256,
    min_finality_threshold: u32,
    finality_threshold_executed: u32,
    message_body: ByteArray,
) -> ByteArray {
    let mut message: ByteArray = Default::default();

    // Append version (4 bytes, u32)
    append_u32_be(ref message, version);

    // Append source_domain (4 bytes, u32)
    append_u32_be(ref message, source_domain);

    // Append destination_domain (4 bytes, u32)
    append_u32_be(ref message, destination_domain);

    // Append nonce (32 bytes, u256) - empty/zero
    append_u256_be(ref message, nonce);

    // Append sender (32 bytes, u256)
    append_u256_be(ref message, sender);

    // Append recipient (32 bytes, u256)
    append_u256_be(ref message, recipient);

    // Append destination_caller (32 bytes, u256)
    append_u256_be(ref message, destination_caller);

    // Append min_finality_threshold (4 bytes, u32)
    append_u32_be(ref message, min_finality_threshold);

    // Append finality_threshold_executed (4 bytes, u32)
    append_u32_be(ref message, finality_threshold_executed);

    // Append message_body (dynamic, bytes)
    message.append(@message_body);

    message
}

fn get_attester(message: @ByteArray, attestation: @ByteArray) -> ContractAddress {
    let cairo_hash = compute_keccak_byte_array(message);
    // cairo hash is u256 in little-endian, so we need to reverse it to get the big-endian
    // hash, which is the same as ethereum hash
    let digest = reverse_u256_bytes(cairo_hash);

    let r: u256 = extract_u256_be(attestation, 0);
    let s: u256 = extract_u256_be(attestation, 32);
    let v: u32 = attestation.at(64).unwrap().into();

    let signature = signature_from_vrs(v, r, s);
    let point: Secp256k1Point = recover_public_key(digest, signature)
        .expect('Failed to recover public key');

    // convert the public key point to eth address
    let recovered_attester: felt252 = public_key_point_to_eth_address(point)
        .try_into()
        .expect('Invalid attester address size');
    recovered_attester.try_into().expect('Invalid attester address')
}

#[derive(Drop, Destruct, PanicDestruct)]
struct TestData {
    admin: ContractAddress,
    owner: ContractAddress,
    pauser: ContractAddress,
    rescuer: ContractAddress,
    attester_manager: ContractAddress,
    attesters: Array<ContractAddress>,
    signature_threshold: u32,
    max_message_body_size: u32,
    local_domain: u32,
    version: u32,
    destination_domain: u32,
    recipient: u256,
    destination_caller: u256,
    min_finality_threshold: u32,
    message_body: ByteArray,
    attestation: ByteArray,
}

fn get_test_data() -> TestData {
    let local_domain = 1.try_into().unwrap();
    let version = 0.try_into().unwrap();

    let admin = 1.try_into().unwrap();
    let owner = 2.try_into().unwrap();
    let pauser = 3.try_into().unwrap();
    let rescuer = 4.try_into().unwrap();
    let attester_manager = 5.try_into().unwrap();
    let attesters = array![6.try_into().unwrap(), 7.try_into().unwrap()];
    let signature_threshold = 2.try_into().unwrap();
    let max_message_body_size = 1000.try_into().unwrap();
    let destination_domain = 8.try_into().unwrap();
    let recipient = 9.try_into().unwrap();
    let destination_caller: u256 = 10.try_into().unwrap();
    let min_finality_threshold = 1.try_into().unwrap();
    let mut message_body: ByteArray = "message";

    let mut attestation: ByteArray =
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00";

    TestData {
        admin,
        local_domain,
        version,
        owner,
        pauser,
        rescuer,
        attester_manager,
        attesters,
        max_message_body_size,
        signature_threshold,
        destination_domain,
        recipient,
        destination_caller,
        min_finality_threshold,
        message_body,
        attestation,
    }
}

fn deploy_mock_token_messenger() -> ContractAddress {
    let contract = declare("MockTokenMessengerMinter").unwrap().contract_class();
    let constructor_calldata = array![];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_contract() -> ContractAddress {
    let contract = declare("MessageTransmitterV2").unwrap().contract_class();
    let test_data = get_test_data();
    let constructor_calldata = array![test_data.admin.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_contract_then_initialize() -> ContractAddress {
    let contract_address = deploy_contract();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher
        .initialize(
            test_data.local_domain.into(),
            test_data.version.into(),
            test_data.owner.into(),
            test_data.pauser.into(),
            test_data.rescuer.into(),
            test_data.attester_manager.into(),
            test_data.attesters.clone(),
            test_data.signature_threshold.into(),
            test_data.max_message_body_size.into(),
        );
    stop_cheat_caller_address(contract_address);

    contract_address
}

// ================================
// COMPONENT TESTS
// ================================

#[test]
fn test_ownable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IOwnableDispatcher { contract_address };

    // Just verify the functions exist by calling them
    let owner = dispatcher.owner();
    assert!(owner == 2.try_into().unwrap(), "Owner should be set correctly");
}

#[test]
fn test_manageable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IManageableDispatcher { contract_address };

    // Just verify the function exists
    let admin = dispatcher.admin();
    assert!(admin == 1.try_into().unwrap(), "Admin should be set correctly");
}

#[test]
fn test_pausable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IPausableDispatcher { contract_address };

    assert!(dispatcher.pauser() == 3.try_into().unwrap(), "Pauser should be set correctly");
}

#[test]
fn test_rescuable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IRescuableDispatcher { contract_address };

    assert!(dispatcher.rescuer() == 4.try_into().unwrap(), "Rescuer should be set correctly");
}

#[test]
fn test_attestable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IAttestableDispatcher { contract_address };

    assert!(
        dispatcher.attester_manager() == 5.try_into().unwrap(),
        "Attester manager should be set correctly",
    );
}

#[test]
#[should_panic(expected: ('Class hash cannot be zero',))]
fn test_upgradeable_component_exists() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IUpgradeableDispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher.upgrade(0.try_into().unwrap());
}

// ================================
// CORE FUNCTIONALITY TESTS
// ================================

#[test]
fn test_initializer() {
    let contract_address = deploy_contract();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher
        .initialize(
            test_data.local_domain.into(),
            test_data.version.into(),
            test_data.owner.into(),
            test_data.pauser.into(),
            test_data.rescuer.into(),
            test_data.attester_manager.into(),
            test_data.attesters.clone(),
            test_data.signature_threshold.into(),
            test_data.max_message_body_size.into(),
        );
    stop_cheat_caller_address(contract_address);

    // check component state
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address };
    let rescuable_dispatcher = IRescuableDispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };

    assert!(ownable_dispatcher.owner() == test_data.owner, "Owner should be the same");
    assert!(pausable_dispatcher.pauser() == test_data.pauser, "Pauser should be the same");
    assert!(rescuable_dispatcher.rescuer() == test_data.rescuer, "Rescuer should be the same");
    assert!(
        attestable_dispatcher.attester_manager() == test_data.attester_manager,
        "Attester manager should be the same",
    );
    assert!(
        attestable_dispatcher.get_enabled_attesters() == test_data.attesters,
        "Attesters should be the same",
    );
    assert!(
        attestable_dispatcher
            .get_signature_threshold() == test_data
            .signature_threshold
            .try_into()
            .unwrap(),
        "Signature threshold should be the same",
    );
    assert!(
        dispatcher
            .get_max_message_body_size() == test_data
            .max_message_body_size
            .try_into()
            .unwrap(),
        "Max message body size should be the same",
    );
}

#[test]
fn test_set_max_message_body_size() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.set_max_message_body_size(test_data.max_message_body_size.into());
    assert!(
        dispatcher
            .get_max_message_body_size() == test_data
            .max_message_body_size
            .try_into()
            .unwrap(),
        "Max message body size should be the same",
    );
}

#[test]
fn test_send_message() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();
    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher
        .send_message(
            test_data.destination_domain,
            test_data.recipient,
            test_data.destination_caller,
            test_data.min_finality_threshold,
            test_data.message_body.clone(),
        );
    stop_cheat_caller_address(contract_address);

    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.destination_domain,
        0.into(),
        test_data.owner.to_u256(),
        test_data.recipient,
        test_data.destination_caller,
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MessageTransmitterV2::Event::MessageSent(
                        MessageTransmitterV2::MessageSent { message },
                    ),
                ),
            ],
        );
}

#[test]
fn test_receive_unfinalized_message() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender = test_data.owner.to_u256();

    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };

    let nonce: u256 = 1.into();
    let finality_threshold_executed: u32 = 10;
    let destination_caller: felt252 = test_data.owner.into();

    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender,
        token_messenger_address.to_u256(),
        destination_caller.into(),
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );
    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    let mut spy = spy_events();

    assert!(!token_messenger_helper.is_unfinalized(), "Token messenger should not be unfinalized");
    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
    stop_cheat_caller_address(contract_address);

    assert!(token_messenger_helper.is_unfinalized(), "Token messenger should not be unfinalized");

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MessageTransmitterV2::Event::MessageReceived(
                        MessageTransmitterV2::MessageReceived {
                            caller: test_data.owner,
                            source_domain: test_data.local_domain,
                            nonce,
                            sender,
                            finality_threshold_executed: MessageV2::get_finality_threshold_executed(
                                @message,
                            ),
                            message_body: MessageV2::get_message_body(@message),
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_receive_finalized_message() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender = test_data.owner.to_u256();

    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };

    let nonce: u256 = 1.into();
    let finality_threshold_executed: u32 = 2001;
    let destination_caller = test_data.owner.to_u256();

    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender,
        token_messenger_address.to_u256(),
        destination_caller,
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    let mut spy = spy_events();

    assert!(!token_messenger_helper.is_finalized(), "Token messenger should not be finalized");
    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
    stop_cheat_caller_address(contract_address);

    assert!(token_messenger_helper.is_finalized(), "Token messenger should be finalized");

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MessageTransmitterV2::Event::MessageReceived(
                        MessageTransmitterV2::MessageReceived {
                            caller: test_data.owner,
                            source_domain: test_data.local_domain,
                            nonce,
                            sender,
                            finality_threshold_executed: MessageV2::get_finality_threshold_executed(
                                @message,
                            ),
                            message_body: MessageV2::get_message_body(@message),
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_receive_message_with_zero_destination_caller() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender = test_data.owner.to_u256();

    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };

    let nonce: u256 = 1.into();
    let finality_threshold_executed: u32 = 2001;

    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender,
        token_messenger_address.to_u256(),
        0.into(), // destination caller as zero
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    let mut spy = spy_events();

    assert!(!token_messenger_helper.is_finalized(), "Token messenger should not be finalized");
    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
    stop_cheat_caller_address(contract_address);

    assert!(token_messenger_helper.is_finalized(), "Token messenger should be finalized");

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    MessageTransmitterV2::Event::MessageReceived(
                        MessageTransmitterV2::MessageReceived {
                            caller: test_data.owner,
                            source_domain: test_data.local_domain,
                            nonce,
                            sender,
                            finality_threshold_executed: MessageV2::get_finality_threshold_executed(
                                @message,
                            ),
                            message_body: MessageV2::get_message_body(@message),
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_is_nonce_used() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };

    // Nonce 0 is used after initialization
    assert!(dispatcher.is_nonce_used(0.into()), "Nonce should be used");

    let nonce: u256 = 1.into();

    // Nonce 1 is not used
    assert!(!dispatcher.is_nonce_used(nonce), "Nonce should not be used");

    // Receiving a message with Nonce 1
    let test_data = get_test_data();
    let sender = test_data.owner.to_u256();
    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };
    let finality_threshold_executed: u32 = 2001;

    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender,
        token_messenger_address.to_u256(),
        0.into(), // destination caller as zero
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    assert!(!token_messenger_helper.is_finalized(), "Token messenger should not be finalized");
    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
    stop_cheat_caller_address(contract_address);

    // Nonce 1 is used after receiving a message
    assert!(dispatcher.is_nonce_used(nonce), "Nonce should be used");
}

#[test]
fn test_get_local_domain() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    assert_eq!(dispatcher.get_local_domain(), test_data.local_domain);
}

#[test]
fn test_get_version() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    assert_eq!(dispatcher.get_version(), test_data.version);
}

// ================================
// ERROR TESTS
// ================================

#[test]
#[should_panic(expected: ('Caller is not the admin',))]
fn test_non_admin_cannot_initialize() {
    let contract_address = deploy_contract();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher
        .initialize(
            test_data.local_domain.into(),
            test_data.version.into(),
            test_data.owner.into(),
            test_data.pauser.into(),
            test_data.rescuer.into(),
            test_data.attester_manager.into(),
            test_data.attesters.clone(),
            test_data.signature_threshold.into(),
            test_data.max_message_body_size.into(),
        );
}

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initialize_twice() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher
        .initialize(
            test_data.local_domain.into(),
            test_data.version.into(),
            test_data.owner.into(),
            test_data.pauser.into(),
            test_data.rescuer.into(),
            test_data.attester_manager.into(),
            test_data.attesters.clone(),
            test_data.signature_threshold.into(),
            test_data.max_message_body_size.into(),
        );
}

#[test]
#[should_panic(expected: ('Invalid max message body size',))]
fn test_initialize_with_invalid_max_message_body_size() {
    let contract_address = deploy_contract();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher
        .initialize(
            test_data.local_domain.into(),
            test_data.version.into(),
            test_data.owner.into(),
            test_data.pauser.into(),
            test_data.rescuer.into(),
            test_data.attester_manager.into(),
            test_data.attesters.clone(),
            test_data.signature_threshold.into(),
            0.into(),
        );
}

#[test]
#[should_panic(expected: ('Contract is paused',))]
fn test_send_message_with_paused_contract() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.pauser);
    pausable_dispatcher.pause();
    stop_cheat_caller_address(contract_address);

    dispatcher
        .send_message(
            test_data.local_domain.into(),
            test_data.recipient,
            test_data.destination_caller,
            test_data.min_finality_threshold,
            test_data.message_body.clone(),
        );
}

#[test]
#[should_panic(expected: ('Domain is local domain',))]
fn test_send_message_with_invalid_destination_domain() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher
        .send_message(
            test_data.local_domain,
            test_data.recipient,
            test_data.destination_caller,
            test_data.min_finality_threshold,
            test_data.message_body.clone(),
        );
}

#[test]
#[should_panic(expected: ('Message body exceeds max size',))]
fn test_send_message_with_invalid_message_body() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.set_max_message_body_size(1.into());
    dispatcher
        .send_message(
            test_data.destination_domain,
            test_data.recipient,
            test_data.destination_caller,
            test_data.min_finality_threshold,
            test_data.message_body.clone(),
        );
}

#[test]
#[should_panic(expected: ('Recipient must be non-zero',))]
fn test_send_message_with_invalid_recipient() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher
        .send_message(
            test_data.destination_domain,
            0,
            test_data.destination_caller,
            test_data.min_finality_threshold,
            test_data.message_body.clone(),
        );
}

#[test]
#[should_panic(expected: ('Contract is paused',))]
fn test_receive_message_with_paused_contract() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.pauser);
    pausable_dispatcher.pause();
    stop_cheat_caller_address(contract_address);

    dispatcher.receive_message(test_data.message_body.clone(), test_data.attestation.clone());
}

#[test]
#[should_panic(expected: ('Invalid message: too short',))]
fn test_receive_message_with_invalid_message_body() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher
        .enable_attester(0xb414dd0de175ce490997279832e9b0ab1bc24aa8.try_into().unwrap());
    stop_cheat_caller_address(contract_address);

    dispatcher.receive_message(test_data.message_body.clone(), attestation);
}

#[test]
#[should_panic(expected: ('Invalid destination domain',))]
fn test_receive_message_with_invalid_domain() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();
    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher
        .enable_attester(0x733641cebf19cb1c50f1c21b4fb9bf4e796ff80f.try_into().unwrap());
    stop_cheat_caller_address(contract_address);

    // create message with invalid destination domain
    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.destination_domain,
        1.into(),
        sender.into(),
        test_data.recipient.into(),
        test_data.destination_caller,
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    dispatcher.receive_message(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid destination caller',))]
fn test_receive_message_with_invalid_destination_caller() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher
        .enable_attester(0x8b450af858f0be4179de37a70b98f82cb8d2400d.try_into().unwrap());
    stop_cheat_caller_address(contract_address);

    // create message with invalid destination domain
    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        1.into(),
        sender.into(),
        test_data.recipient.into(),
        test_data.destination_caller,
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    dispatcher.receive_message(message, attestation);
}

#[test]
#[should_panic(expected: ('Invalid attestation',))]
fn test_receive_message_with_invalid_attestation() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    start_cheat_caller_address(contract_address, test_data.owner);

    // create message with invalid version
    let message = format_message(
        test_data.version + 1,
        test_data.local_domain,
        test_data.local_domain,
        1.into(),
        sender.into(),
        test_data.recipient.into(),
        sender.into(),
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    dispatcher.receive_message(message, test_data.attestation.clone());
}

#[test]
#[should_panic(expected: ('Invalid message version',))]
fn test_receive_message_with_invalid_version() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher
        .enable_attester(0x3e1f964c5c84fb93113ae1024144166c76b04633.try_into().unwrap());
    stop_cheat_caller_address(contract_address);

    // create message with invalid version
    let message = format_message(
        test_data.version + 1,
        test_data.local_domain,
        test_data.local_domain,
        1.into(),
        sender.into(),
        test_data.recipient.into(),
        sender.into(),
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message, attestation);
}

#[test]
#[should_panic(expected: ('Nonce already used',))]
fn test_receive_message_with_invalid_nonce() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );

    // set up attester
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher
        .enable_attester(0x4f8d0276ff32213204b9f50b74ade839b298dbb9.try_into().unwrap());
    stop_cheat_caller_address(contract_address);

    // create message with used nonce
    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        0.into(),
        sender.into(),
        test_data.recipient.into(),
        sender.into(),
        test_data.min_finality_threshold,
        0,
        test_data.message_body,
    );

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message, attestation);
}

#[test]
#[should_panic(expected: ('Failed unfinalized message',))]
fn test_failed_handle_unfinalized_message() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    // deploy mock token messenger
    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };

    // failed to handle unfinalized message
    token_messenger_helper.set_failed(true);

    let recipient: felt252 = token_messenger_address.into();
    let nonce: u256 = 1.into();
    let finality_threshold_executed: u32 = 10;
    let destination_caller: felt252 = test_data.owner.into();
    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );
    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender.into(),
        recipient.into(),
        destination_caller.into(),
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
}

#[test]
#[should_panic(expected: ('Failed finalized message',))]
fn test_failed_handle_finalized_message() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let attestable_dispatcher = IAttestableDispatcher { contract_address };
    let test_data = get_test_data();
    let sender: felt252 = test_data.owner.into();

    // deploy mock token messenger
    let token_messenger_address = deploy_mock_token_messenger();
    let token_messenger_helper = ITokenMessengerMinterTestHelperDispatcher {
        contract_address: token_messenger_address,
    };

    // failed to handle unfinalized message
    token_messenger_helper.set_failed(true);

    let recipient: felt252 = token_messenger_address.into();
    let nonce: u256 = 1.into();
    let finality_threshold_executed: u32 = 2001;
    let destination_caller: felt252 = test_data.owner.into();
    let attestation = hex_string_to_bytes_array(
        "0x6458bca532d26837d3efdb83d0f8805ac1ad31a1b6382075c3ea22653dc6da23172f23e0b4867df644ea021c9eac87cd3a55dc0c88a74b25d070d77db2ef84fb00",
    );
    let message = format_message(
        test_data.version,
        test_data.local_domain,
        test_data.local_domain,
        nonce,
        sender.into(),
        recipient.into(),
        destination_caller.into(),
        test_data.min_finality_threshold,
        finality_threshold_executed,
        test_data.message_body,
    );

    // set up attester
    let attester = get_attester(@message, @attestation);
    start_cheat_caller_address(contract_address, test_data.attester_manager);
    attestable_dispatcher.set_signature_threshold(1);
    attestable_dispatcher.enable_attester(attester);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, test_data.owner);
    dispatcher.receive_message(message.clone(), attestation);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_max_message_body_size_not_owner() {
    let contract_address = deploy_contract_then_initialize();
    let dispatcher = IMessageTransmitterV2Dispatcher { contract_address };
    let test_data = get_test_data();

    start_cheat_caller_address(contract_address, test_data.admin);
    dispatcher.set_max_message_body_size(1.into());
}
