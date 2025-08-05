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

use cctp_components::fee_recipient_controller::{
    IFeeRecipientControllerDispatcher, IFeeRecipientControllerDispatcherTrait,
};
use cctp_components::min_fee_controller::{
    IMinFeeControllerDispatcher, IMinFeeControllerDispatcherTrait,
};
use cctp_components::remote_token_messenger_controller::{
    IRemoteTokenMessengerControllerDispatcher, IRemoteTokenMessengerControllerDispatcherTrait,
};
use cctp_components::rescuable::{IRescuableDispatcher, IRescuableDispatcherTrait};
use cctp_components::token_controller::{
    ITokenControllerDispatcher, ITokenControllerDispatcherTrait,
};
use components::denylistable::{IDenylistableDispatcher, IDenylistableDispatcherTrait};
use components::manageable::{IManageableDispatcher, IManageableDispatcherTrait};
use components::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use components::pausable::{IPausableDispatcher, IPausableDispatcherTrait};
use components::upgradeable::IUpgradeableDispatcher;
use interfaces::token_messager_minter_v2::{
    ITokenMessengerMinterV2Dispatcher, ITokenMessengerMinterV2DispatcherTrait,
};
use message::BurnMessageV2;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_account_contract_address, declare, spy_events, start_cheat_block_number,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use utils::{append_u256_be, append_u32_be};

// Mock FiatToken contract for testing
#[starknet::contract]
mod MockFiatTokenContract {
    use stablecoin::IFiatToken;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,
        transfer_from_should_fail: bool,
        burn_should_fail: bool,
    }

    #[abi(embed_v0)]
    impl FiatTokenImpl of IFiatToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            let to_balance = self.balances.read(to);
            self.balances.write(to, to_balance + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }

        fn burn(ref self: ContractState, amount: u256) {
            if self.burn_should_fail.read() {
                panic!("Burn failed");
            }
            let caller = starknet::get_caller_address();
            let caller_balance = self.balances.read(caller);
            assert!(caller_balance >= amount, "Insufficient balance to burn");
            self.balances.write(caller, caller_balance - amount);
            self.total_supply.write(self.total_supply.read() - amount);
        }

        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
            let caller = starknet::get_caller_address();
            let caller_balance = self.balances.read(caller);
            if caller_balance >= amount {
                self.balances.write(caller, caller_balance - amount);
                let to_balance = self.balances.read(to);
                self.balances.write(to, to_balance + amount);
                true
            } else {
                false
            }
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            if self.transfer_from_should_fail.read() {
                return false;
            }

            let caller = starknet::get_caller_address();
            let allowance = self.allowances.read((from, caller));
            let from_balance = self.balances.read(from);

            if allowance >= amount && from_balance >= amount {
                self.allowances.write((from, caller), allowance - amount);
                self.balances.write(from, from_balance - amount);
                let to_balance = self.balances.read(to);
                self.balances.write(to, to_balance + amount);
                true
            } else {
                false
            }
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let owner = starknet::get_caller_address();
            self.allowances.write((owner, spender), amount);
            true
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn set_balance(ref self: ContractState, account: ContractAddress, amount: u256) {
            let old_balance = self.balances.read(account);
            self.balances.write(account, amount);

            // Update total supply to reflect the balance change
            let old_total = self.total_supply.read();
            if amount > old_balance {
                // Balance increased, increase total supply
                self.total_supply.write(old_total + (amount - old_balance));
            } else if old_balance > amount {
                // Balance decreased, decrease total supply
                self.total_supply.write(old_total - (old_balance - amount));
            }
            // If equal, no change to total supply
        }

        #[external(v0)]
        fn set_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256,
        ) {
            self.allowances.write((owner, spender), amount);
        }

        #[external(v0)]
        fn set_transfer_from_should_fail(ref self: ContractState, should_fail: bool) {
            self.transfer_from_should_fail.write(should_fail);
        }

        #[external(v0)]
        fn set_burn_should_fail(ref self: ContractState, should_fail: bool) {
            self.burn_should_fail.write(should_fail);
        }
    }
}

// Mock MessageTransmitter contract for testing
#[starknet::contract]
pub mod MockMessageTransmitterContract {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        send_message_should_fail: bool,
        next_nonce: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MessageSent: MessageSent,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MessageSent {
        pub message: ByteArray,
    }

    #[external(v0)]
    fn send_message(
        ref self: ContractState,
        destination_domain: u32,
        recipient: u256,
        destination_caller: u256,
        min_finality_threshold: u32,
        message_body: ByteArray,
    ) {
        if self.send_message_should_fail.read() {
            panic!("Send message failed");
        }

        let nonce = self.next_nonce.read();
        self.next_nonce.write(nonce + 1);

        self.emit(MessageSent { message: message_body });
    }

    #[external(v0)]
    fn receive_message(
        ref self: ContractState, message: ByteArray, attestation: ByteArray,
    ) { // Mock implementation
    }

    #[abi(per_item)]
    #[generate_trait]
    impl TestHelperImpl of TestHelperTrait {
        #[external(v0)]
        fn set_send_message_should_fail(ref self: ContractState, should_fail: bool) {
            self.send_message_should_fail.write(should_fail);
        }
    }
}

// Mock Proxy contract that forwards calls to TokenMessengerMinter
#[starknet::contract]
mod MockProxyContract {
    use interfaces::token_messager_minter_v2::{
        ITokenMessengerMinterV2Dispatcher, ITokenMessengerMinterV2DispatcherTrait,
    };
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn forward_deposit_for_burn(
        ref self: ContractState,
        token_messenger_minter: ContractAddress,
        amount: u256,
        destination_domain: u32,
        mint_recipient: u256,
        burn_token: ContractAddress,
        destination_caller: u256,
        max_fee: u256,
        min_finality_threshold: u32,
    ) {
        let dispatcher = ITokenMessengerMinterV2Dispatcher {
            contract_address: token_messenger_minter,
        };

        dispatcher
            .deposit_for_burn(
                amount,
                destination_domain,
                mint_recipient,
                burn_token,
                destination_caller,
                max_fee,
                min_finality_threshold,
            );
    }
}

// Helper interfaces
#[starknet::interface]
trait IMockFiatTokenTestHelper<TContractState> {
    fn set_balance(ref self: TContractState, account: ContractAddress, amount: u256);
    fn set_allowance(
        ref self: TContractState, owner: ContractAddress, spender: ContractAddress, amount: u256,
    );
    fn set_transfer_from_should_fail(ref self: TContractState, should_fail: bool);
    fn set_burn_should_fail(ref self: TContractState, should_fail: bool);
}

#[starknet::interface]
trait IMockMessageTransmitterTestHelper<TContractState> {
    fn set_send_message_should_fail(ref self: TContractState, should_fail: bool);
}

#[starknet::interface]
trait IMockProxy<TContractState> {
    fn forward_deposit_for_burn(
        ref self: TContractState,
        token_messenger_minter: ContractAddress,
        amount: u256,
        destination_domain: u32,
        mint_recipient: u256,
        burn_token: ContractAddress,
        destination_caller: u256,
        max_fee: u256,
        min_finality_threshold: u32,
    );
}

// Helper function to format burn message with custom fee_executed and expiration_block
fn format_message_for_relay_with_fee_and_expiration(
    version: u32,
    burn_token: u256,
    mint_recipient: u256,
    amount: u256,
    message_sender: u256,
    max_fee: u256,
    fee_executed: u256,
    expiration_block: u256,
    hook_data: ByteArray,
) -> ByteArray {
    let mut message: ByteArray = Default::default();

    // Append version (4 bytes, u32)
    append_u32_be(ref message, version);

    // Append burn_token (32 bytes, u256)
    append_u256_be(ref message, burn_token);

    // Append mint_recipient (32 bytes, u256)
    append_u256_be(ref message, mint_recipient);

    // Append amount (32 bytes, u256)
    append_u256_be(ref message, amount);

    // Append message_sender (32 bytes, u256)
    append_u256_be(ref message, message_sender);

    // Append max_fee (32 bytes, u256)
    append_u256_be(ref message, max_fee);

    // Append fee_executed (32 bytes, u256) - CUSTOM VALUE
    append_u256_be(ref message, fee_executed);

    // Append expiration_block (32 bytes, u256) - CUSTOM VALUE
    append_u256_be(ref message, expiration_block);

    // Append hook_data (dynamic bytes)
    message.append(@hook_data);

    message
}

// Deploy functions
fn deploy_mock_fiat_token() -> ContractAddress {
    let contract = declare("MockFiatTokenContract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn deploy_mock_message_transmitter() -> ContractAddress {
    let contract = declare("MockMessageTransmitterContract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn deploy_mock_proxy() -> ContractAddress {
    let contract = declare("MockProxyContract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn deploy_token_messenger_minter() -> (ContractAddress, ContractAddress, ContractAddress) {
    let contract = declare("TokenMessengerMinterV2").unwrap().contract_class();

    // Deploy mock contracts
    let local_message_transmitter = deploy_mock_message_transmitter();
    let mock_token = deploy_mock_fiat_token();

    // Setup addresses using numeric values instead of strings
    let owner: ContractAddress = 0x1.try_into().unwrap();
    let admin: ContractAddress = 0x2.try_into().unwrap();
    let pauser: ContractAddress = 0x3.try_into().unwrap();
    let denylister: ContractAddress = 0x4.try_into().unwrap();
    let rescuer: ContractAddress = 0x5.try_into().unwrap();
    let token_controller: ContractAddress = 0x6.try_into().unwrap();
    let min_fee_controller: ContractAddress = 0x7.try_into().unwrap();
    let fee_recipient: ContractAddress = 0x8.try_into().unwrap();
    let message_body_version: u32 = 0_u32;

    // Deploy with just admin
    let mut constructor_calldata = array![];
    constructor_calldata.append(admin.into());

    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    // Now initialize the contract as admin
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Set caller to admin for initialization
    start_cheat_caller_address(contract_address, admin);

    // Remote domain configuration as arrays
    let remote_domains: Array<u32> = array![1_u32, 2_u32];
    let remote_token_messengers: Array<u256> = array![1000_u256, 2000_u256];

    // Initialize the contract
    dispatcher
        .initialize(
            owner,
            pauser,
            denylister,
            rescuer,
            token_controller,
            min_fee_controller,
            fee_recipient,
            message_body_version,
            local_message_transmitter,
            remote_domains,
            remote_token_messengers,
        );

    // Stop cheating caller
    stop_cheat_caller_address(contract_address);

    (contract_address, local_message_transmitter, mock_token)
}

// ================================
// COMPONENT EXISTENCE TESTS
// ================================

#[test]
fn test_full_deployment_with_mocks() {
    // Deploy mock contracts first
    let _mock_token = deploy_mock_fiat_token();
    let mock_transmitter = deploy_mock_message_transmitter();

    // Now deploy TokenMessengerMinter with the actual mock addresses
    let contract = declare("TokenMessengerMinterV2").unwrap().contract_class();

    let owner: ContractAddress = 0x1.try_into().unwrap();
    let admin: ContractAddress = 0x2.try_into().unwrap();
    let pauser: ContractAddress = 0x3.try_into().unwrap();
    let denylister: ContractAddress = 0x4.try_into().unwrap();
    let rescuer: ContractAddress = 0x5.try_into().unwrap();
    let token_controller: ContractAddress = 0x6.try_into().unwrap();
    let min_fee_controller: ContractAddress = 0x7.try_into().unwrap();
    let fee_recipient: ContractAddress = 0x8.try_into().unwrap();
    let message_body_version: u32 = 0_u32;

    // Deploy with just admin
    let mut constructor_calldata = array![];
    constructor_calldata.append(admin.into());

    let deploy_result = contract.deploy(@constructor_calldata);
    assert!(deploy_result.is_ok(), "Failed to deploy TokenMessengerMinter with mocks");

    // If we get here, deployment was successful
    let (contract_address, _) = deploy_result.unwrap();

    // Initialize the contract as admin
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Empty arrays for remote domains and messengers
    let remote_domains: Array<u32> = array![];
    let remote_token_messengers: Array<u256> = array![];

    dispatcher
        .initialize(
            owner,
            pauser,
            denylister,
            rescuer,
            token_controller,
            min_fee_controller,
            fee_recipient,
            message_body_version,
            mock_transmitter, // Use actual mock transmitter address
            remote_domains,
            remote_token_messengers,
        );

    stop_cheat_caller_address(contract_address);

    // Test that we can call a function
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let owner_result = ownable_dispatcher.owner();
    assert!(owner_result == owner, "Owner not set correctly");
}

#[test]
fn test_mock_contracts_deployment() {
    // Test deploying each mock contract individually
    let mock_token_class = declare("MockFiatTokenContract");
    assert!(mock_token_class.is_ok(), "Failed to declare MockFiatTokenContract");

    let mock_transmitter_class = declare("MockMessageTransmitterContract");
    assert!(mock_transmitter_class.is_ok(), "Failed to declare MockMessageTransmitterContract");

    // Deploy mock fiat token
    let token_contract = mock_token_class.unwrap().contract_class();
    let token_deploy_result = token_contract.deploy(@array![]);
    assert!(token_deploy_result.is_ok(), "Failed to deploy MockFiatTokenContract");

    // Deploy mock message transmitter
    let transmitter_contract = mock_transmitter_class.unwrap().contract_class();
    let transmitter_deploy_result = transmitter_contract.deploy(@array![]);
    assert!(transmitter_deploy_result.is_ok(), "Failed to deploy MockMessageTransmitterContract");
}

#[test]
fn test_simple_deployment() {
    // Let's try the simplest possible deployment first
    let contract_class = declare("TokenMessengerMinterV2");
    assert!(contract_class.is_ok(), "Failed to declare TokenMessengerMinterV2");

    let contract = contract_class.unwrap().contract_class();

    // Only need admin for constructor
    let admin: ContractAddress = 0x2.try_into().unwrap();

    let mut constructor_calldata = array![];
    constructor_calldata.append(admin.into());

    let deploy_result = contract.deploy(@constructor_calldata);
    assert!(deploy_result.is_ok(), "Failed to deploy TokenMessengerMinter");
}

#[test]
fn test_deployment_without_remote_domains() {
    // Deploy mock contracts first
    let _mock_token = deploy_mock_fiat_token();
    let mock_transmitter = deploy_mock_message_transmitter();

    // Now deploy TokenMessengerMinter with the actual mock addresses
    let contract = declare("TokenMessengerMinterV2").unwrap().contract_class();

    let owner: ContractAddress = 0x1.try_into().unwrap();
    let admin: ContractAddress = 0x2.try_into().unwrap();
    let pauser: ContractAddress = 0x3.try_into().unwrap();
    let denylister: ContractAddress = 0x4.try_into().unwrap();
    let rescuer: ContractAddress = 0x5.try_into().unwrap();
    let token_controller: ContractAddress = 0x6.try_into().unwrap();
    let min_fee_controller: ContractAddress = 0x7.try_into().unwrap();
    let fee_recipient: ContractAddress = 0x8.try_into().unwrap();
    let message_body_version: u32 = 0_u32;

    // Deploy with just admin
    let mut constructor_calldata = array![];
    constructor_calldata.append(admin.into());

    let deploy_result = contract.deploy(@constructor_calldata);
    assert!(deploy_result.is_ok(), "Failed to deploy TokenMessengerMinter without remote domains");

    // If we get here, deployment was successful
    let (contract_address, _) = deploy_result.unwrap();

    // Initialize the contract as admin
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    start_cheat_caller_address(contract_address, admin);

    // Empty arrays for remote domains and messengers
    let remote_domains: Array<u32> = array![];
    let remote_token_messengers: Array<u256> = array![];

    dispatcher
        .initialize(
            owner,
            pauser,
            denylister,
            rescuer,
            token_controller,
            min_fee_controller,
            fee_recipient,
            message_body_version,
            mock_transmitter, // Use actual mock transmitter address
            remote_domains,
            remote_token_messengers,
        );

    stop_cheat_caller_address(contract_address);

    // Test that we can call a function
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    let owner_result = ownable_dispatcher.owner();
    assert!(owner_result == owner, "Owner not set correctly");
}

#[test]
fn test_ownable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IOwnableDispatcher { contract_address };

    // Just verify the functions exist by calling them
    let owner = dispatcher.owner();
    assert!(owner == 0x1.try_into().unwrap(), "Owner should be set correctly");
}

#[test]
fn test_manageable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IManageableDispatcher { contract_address };

    // Just verify the function exists
    let admin = dispatcher.admin();
    assert!(admin == 0x2.try_into().unwrap(), "Admin should be set correctly");
}

#[test]
fn test_pausable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IPausableDispatcher { contract_address };

    // Just verify the functions exist
    let _ = dispatcher.pauser();
}

#[test]
fn test_denylistable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IDenylistableDispatcher { contract_address };

    // Just verify the functions exist
    let denylister = dispatcher.denylister();
    assert!(denylister == 0x4.try_into().unwrap(), "Denylister should be set correctly");
}

#[test]
fn test_rescuable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IRescuableDispatcher { contract_address };

    // Just verify the functions exist
    let rescuer = dispatcher.rescuer();
    assert!(rescuer == 0x5.try_into().unwrap(), "Rescuer should be set correctly");
}

#[test]
fn test_token_controller_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenControllerDispatcher { contract_address };

    // Just verify the functions exist
    let token_controller = dispatcher.token_controller();
    assert!(
        token_controller == 0x6.try_into().unwrap(), "Token controller should be set correctly",
    );
}

#[test]
fn test_min_fee_controller_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IMinFeeControllerDispatcher { contract_address };

    // Just verify the functions exist
    let min_fee_controller = dispatcher.min_fee_controller();
    assert!(
        min_fee_controller == 0x7.try_into().unwrap(), "Min fee controller should be set correctly",
    );
}

#[test]
fn test_fee_recipient_controller_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IFeeRecipientControllerDispatcher { contract_address };

    // Just verify the functions exist
    let fee_recipient = dispatcher.fee_recipient();
    assert!(fee_recipient == 0x8.try_into().unwrap(), "Fee recipient should be set correctly");
}

#[test]
fn test_remote_token_messenger_controller_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IRemoteTokenMessengerControllerDispatcher { contract_address };

    // Just verify the functions exist
    let remote_token_messenger = dispatcher.remote_token_messenger(1_u32);
    assert!(remote_token_messenger == 1000_u256, "Remote token messenger should be set correctly");
}

#[test]
fn test_upgradeable_component_exists() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = IUpgradeableDispatcher { contract_address };

    // Just verify upgrade function exists - we won't actually call it
    // as it requires a valid class hash
    let _ = dispatcher.contract_address;
}

// ================================
// TOKEN MESSENGER MINTER TESTS
// ================================

#[test]
#[should_panic(expected: ('Already initialized',))]
fn test_initialize_already_initialized() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Setup addresses using numeric values
    let owner: ContractAddress = 0x10.try_into().unwrap();
    let admin: ContractAddress = 0x2.try_into().unwrap(); // Same admin as deployment
    let pauser: ContractAddress = 0x30.try_into().unwrap();
    let denylister: ContractAddress = 0x40.try_into().unwrap();
    let rescuer: ContractAddress = 0x50.try_into().unwrap();
    let token_controller: ContractAddress = 0x60.try_into().unwrap();
    let min_fee_controller: ContractAddress = 0x70.try_into().unwrap();
    let fee_recipient: ContractAddress = 0x80.try_into().unwrap();
    let message_body_version: u32 = 1_u32;
    let local_message_transmitter: ContractAddress = 0x90.try_into().unwrap();

    // Set caller to admin for initialization
    start_cheat_caller_address(contract_address, admin);

    // Try to initialize again - should panic
    dispatcher
        .initialize(
            owner,
            pauser,
            denylister,
            rescuer,
            token_controller,
            min_fee_controller,
            fee_recipient,
            message_body_version,
            local_message_transmitter,
            array![],
            array![],
        );
}

#[test]
fn test_message_body_version() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    let version = dispatcher.message_body_version();
    assert!(version == 0_u32, "Message body version should be 0");
}

#[test]
fn test_local_message_transmitter() {
    let (contract_address, local_message_transmitter, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    let transmitter = dispatcher.local_message_transmitter();
    assert!(transmitter == local_message_transmitter, "Local message transmitter should match");
}

#[test]
fn test_deposit_for_burn_happy_path() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };
    let token_helper = IMockFiatTokenTestHelperDispatcher { contract_address: mock_token };

    // Setup
    let depositor: ContractAddress = 0x100.try_into().unwrap(); // Use numeric address
    let amount: u256 = 1000_u256;
    let destination_domain: u32 = 1_u32;
    let mint_recipient: u256 = 0x200.into(); // Use numeric value
    let destination_caller: u256 = 0_u256;
    let max_fee: u256 = 10_u256;
    let min_finality_threshold: u32 = 0_u32;

    // Set up token balances and allowances
    token_helper.set_balance(depositor, amount + 100);
    token_helper.set_allowance(depositor, contract_address, amount + 100);

    // Also ensure the contract starts with 0 balance (though it should be default)
    token_helper.set_balance(contract_address, 0);

    // Link token pair using the correct token controller address
    start_cheat_caller_address(
        contract_address, 0x6.try_into().unwrap(),
    ); // Use numeric token controller
    token_controller_dispatcher
        .link_token_pair(mock_token, destination_domain, 0x300.into()); // Use numeric remote token
    token_controller_dispatcher.set_max_burn_amount_per_message(mock_token, amount + 100);
    stop_cheat_caller_address(contract_address);

    // Spy on events
    let mut spy = spy_events();

    // Execute deposit for burn
    start_cheat_caller_address(contract_address, depositor);
    dispatcher
        .deposit_for_burn(
            amount,
            destination_domain,
            mint_recipient,
            mock_token,
            destination_caller,
            max_fee,
            min_finality_threshold,
        );
    stop_cheat_caller_address(contract_address);

    // Verify DepositForBurn event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::Event::DepositForBurn(
                        token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::DepositForBurn {
                            burn_token: mock_token,
                            amount,
                            depositor,
                            mint_recipient,
                            destination_domain,
                            destination_token_messenger: 1000_u256, // Domain 1 maps to messenger 1000
                            destination_caller,
                            max_fee,
                            min_finality_threshold,
                            hook_data: Default::default(),
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_deposit_for_burn_with_hook_happy_path() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };
    let token_helper = IMockFiatTokenTestHelperDispatcher { contract_address: mock_token };

    // Setup
    let depositor: ContractAddress = 0x100.try_into().unwrap(); // Use numeric address
    let amount: u256 = 1000_u256;
    let destination_domain: u32 = 1_u32;
    let mint_recipient: u256 = 0x200.into(); // Use numeric value
    let destination_caller: u256 = 0_u256;
    let max_fee: u256 = 10_u256;
    let min_finality_threshold: u32 = 0_u32;
    let hook_data = "test hook data";

    // Set up token balances and allowances
    token_helper.set_balance(depositor, amount + 100);
    token_helper.set_allowance(depositor, contract_address, amount + 100);

    // Also ensure the contract starts with 0 balance (though it should be default)
    token_helper.set_balance(contract_address, 0);

    // Link token pair using the correct token controller address
    start_cheat_caller_address(
        contract_address, 0x6.try_into().unwrap(),
    ); // Use numeric token controller
    token_controller_dispatcher
        .link_token_pair(mock_token, destination_domain, 0x300.into()); // Use numeric remote token
    token_controller_dispatcher.set_max_burn_amount_per_message(mock_token, amount + 100);
    stop_cheat_caller_address(contract_address);

    // Spy on events
    let mut spy = spy_events();

    // Execute deposit for burn with hook
    start_cheat_caller_address(contract_address, depositor);
    dispatcher
        .deposit_for_burn_with_hook(
            amount,
            destination_domain,
            mint_recipient,
            mock_token,
            destination_caller,
            max_fee,
            min_finality_threshold,
            hook_data.clone(),
        );
    stop_cheat_caller_address(contract_address);

    // Verify DepositForBurn event was emitted with hook data
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::Event::DepositForBurn(
                        token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::DepositForBurn {
                            burn_token: mock_token,
                            amount,
                            depositor,
                            mint_recipient,
                            destination_domain,
                            destination_token_messenger: 1000_u256, // Domain 1 maps to messenger 1000
                            destination_caller,
                            max_fee,
                            min_finality_threshold,
                            hook_data,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: ('Contract is paused',))]
fn test_deposit_for_burn_fails_when_paused() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address };

    // Pause the contract
    start_cheat_caller_address(contract_address, 0x3.try_into().unwrap()); // Use numeric pauser
    pausable_dispatcher.pause();
    stop_cheat_caller_address(contract_address);

    // Try to deposit for burn
    dispatcher
        .deposit_for_burn(
            1000_u256,
            1_u32,
            0x200.into(), // Use numeric mint_recipient
            mock_token,
            0_u256,
            10_u256,
            0_u32,
        );
}

#[test]
#[should_panic(expected: ('Address is denylisted',))]
fn test_deposit_for_burn_fails_when_denylisted() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let denylistable_dispatcher = IDenylistableDispatcher { contract_address };

    let depositor: ContractAddress = 0x100.try_into().unwrap(); // Use numeric depositor

    // Denylist the depositor
    start_cheat_caller_address(contract_address, 0x4.try_into().unwrap()); // Use numeric denylister
    denylistable_dispatcher.denylist(depositor);
    stop_cheat_caller_address(contract_address);

    // Try to deposit for burn
    start_cheat_caller_address(contract_address, depositor);
    dispatcher
        .deposit_for_burn(
            1000_u256,
            1_u32,
            0x200.into(), // Use numeric mint_recipient
            mock_token,
            0_u256,
            10_u256,
            0_u32,
        );
}

#[test]
#[should_panic(expected: ('Address is denylisted',))]
fn test_deposit_for_burn_fails_when_origin_denylisted() {
    // This test verifies that the enhanced denylist checking works correctly.
    // It simulates a scenario where:
    // - The direct caller (proxy contract) is NOT denylisted
    // - But the transaction origin (the account that initiated the tx) IS denylisted
    // The transaction should fail because we check both caller and origin

    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let denylistable_dispatcher = IDenylistableDispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };
    let token_helper = IMockFiatTokenTestHelperDispatcher { contract_address: mock_token };

    // Deploy proxy contract
    let proxy_address = deploy_mock_proxy();
    let proxy_dispatcher = IMockProxyDispatcher { contract_address: proxy_address };

    // Setup
    let origin: ContractAddress = 0x100.try_into().unwrap(); // The account initiating the tx
    let amount: u256 = 1000_u256;
    let destination_domain: u32 = 1_u32;
    let mint_recipient: u256 = 0x200.into();
    let destination_caller: u256 = 0_u256;
    let max_fee: u256 = 10_u256;
    let min_finality_threshold: u32 = 0_u32;

    // Set up token balances and allowances for the proxy contract
    token_helper.set_balance(proxy_address, amount + 100);
    token_helper.set_allowance(proxy_address, contract_address, amount + 100);

    // Link token pair
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, destination_domain, 0x300.into());
    token_controller_dispatcher.set_max_burn_amount_per_message(mock_token, amount + 100);
    stop_cheat_caller_address(contract_address);

    // Denylist the origin (not the proxy)
    start_cheat_caller_address(contract_address, 0x4.try_into().unwrap()); // Denylister
    denylistable_dispatcher.denylist(origin);
    stop_cheat_caller_address(contract_address);

    // Set the account contract address on the TokenMessengerMinter contract
    // This will make get_tx_info() return origin as the account_contract_address
    cheat_account_contract_address(contract_address, origin, CheatSpan::TargetCalls(1));

    // Call from proxy - caller will be proxy, but tx origin should be the denylisted address
    proxy_dispatcher
        .forward_deposit_for_burn(
            contract_address,
            amount,
            destination_domain,
            mint_recipient,
            mock_token,
            destination_caller,
            max_fee,
            min_finality_threshold,
        );
}

#[test]
fn test_deposit_for_burn_succeeds_when_proxy_and_origin_not_denylisted() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };
    let token_helper = IMockFiatTokenTestHelperDispatcher { contract_address: mock_token };

    // Deploy proxy contract
    let proxy_address = deploy_mock_proxy();
    let proxy_dispatcher = IMockProxyDispatcher { contract_address: proxy_address };

    // Setup
    let origin: ContractAddress = 0x100.try_into().unwrap(); // The account initiating the tx
    let amount: u256 = 1000_u256;
    let destination_domain: u32 = 1_u32;
    let mint_recipient: u256 = 0x200.into();
    let destination_caller: u256 = 0_u256;
    let max_fee: u256 = 10_u256;
    let min_finality_threshold: u32 = 0_u32;

    // Set up token balances and allowances for the proxy contract
    token_helper.set_balance(proxy_address, amount + 100);
    token_helper.set_allowance(proxy_address, contract_address, amount + 100);
    token_helper.set_balance(contract_address, 0);

    // Link token pair
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, destination_domain, 0x300.into());
    token_controller_dispatcher.set_max_burn_amount_per_message(mock_token, amount + 100);
    stop_cheat_caller_address(contract_address);

    // Call from origin through proxy - should succeed as neither is denylisted
    start_cheat_caller_address(proxy_address, origin);
    proxy_dispatcher
        .forward_deposit_for_burn(
            contract_address,
            amount,
            destination_domain,
            mint_recipient,
            mock_token,
            destination_caller,
            max_fee,
            min_finality_threshold,
        );
    // If we get here without panic, the test passed
}

#[test]
#[should_panic(expected: ('Amount must be nonzero',))]
fn test_deposit_for_burn_fails_with_zero_amount() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    dispatcher
        .deposit_for_burn(
            0_u256, // Zero amount
            1_u32,
            0x200.into(), // Use numeric mint_recipient
            mock_token,
            0_u256,
            10_u256,
            0_u32,
        );
}

#[test]
#[should_panic(expected: ('Mint recipient must be non-zero',))]
fn test_deposit_for_burn_fails_with_zero_mint_recipient() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    dispatcher
        .deposit_for_burn(
            1000_u256, 1_u32, 0_u256, // Zero mint recipient
            mock_token, 0_u256, 10_u256, 0_u32,
        );
}

#[test]
#[should_panic(expected: ('Max fee must be less than amt',))]
fn test_deposit_for_burn_fails_when_max_fee_equals_amount() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    dispatcher
        .deposit_for_burn(
            1000_u256,
            1_u32,
            0x200.into(), // Use numeric mint_recipient
            mock_token,
            0_u256,
            1000_u256, // Max fee equals amount
            0_u32,
        );
}

#[test]
#[should_panic(expected: ('Hook data is empty',))]
fn test_deposit_for_burn_with_hook_fails_with_empty_hook_data() {
    let (contract_address, _, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    dispatcher
        .deposit_for_burn_with_hook(
            1000_u256,
            1_u32,
            0x200.into(), // Use numeric mint_recipient
            mock_token,
            0_u256,
            10_u256,
            0_u32,
            Default::default() // Empty hook data
        );
}

#[test]
fn test_handle_receive_finalized_message_happy_path() {
    let (contract_address, local_message_transmitter, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };

    // Setup token mapping
    let source_domain: u32 = 1_u32;
    let burn_token: u256 = 0x200.into(); // Use numeric burn_token
    start_cheat_caller_address(
        contract_address, 0x6.try_into().unwrap(),
    ); // Use numeric token controller
    token_controller_dispatcher.link_token_pair(mock_token, source_domain, burn_token);
    stop_cheat_caller_address(contract_address);

    // Create a valid burn message
    let mint_recipient: ContractAddress = 0x200.try_into().unwrap(); // Use numeric mint_recipient
    let mint_recipient_felt: felt252 = mint_recipient.into();
    let mint_recipient_u256: u256 = mint_recipient_felt.into();
    let amount: u256 = 1000_u256;
    let depositor: u256 = 0x100.into(); // Use numeric depositor
    let max_fee: u256 = 10_u256;

    let message_body = BurnMessageV2::format_message_for_relay(
        0_u32, // version
        burn_token,
        mint_recipient_u256,
        amount,
        depositor,
        max_fee,
        Default::default() // hook data
    );

    // Spy on events
    let mut spy = spy_events();

    // Handle the message as the local message transmitter
    start_cheat_caller_address(contract_address, local_message_transmitter);
    let result = dispatcher
        .handle_receive_finalized_message(
            source_domain,
            1000_u256, // Remote token messenger for domain 1
            0_u32, // finality threshold (unused)
            message_body,
        );
    stop_cheat_caller_address(contract_address);

    assert!(result, "Handle receive finalized message should return true");

    // Verify MintAndWithdraw event was emitted
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::Event::MintAndWithdraw(
                        token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::MintAndWithdraw {
                            mint_recipient,
                            amount,
                            mint_token: mock_token,
                            fee_collected: 0_u256 // No fee for finalized messages
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_handle_receive_unfinalized_message_happy_path() {
    let (contract_address, local_message_transmitter, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };

    // Setup token mapping
    let source_domain: u32 = 1_u32;
    let burn_token: u256 = 0x200.into();
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, source_domain, burn_token);
    stop_cheat_caller_address(contract_address);

    // Create a valid burn message with fee
    let mint_recipient: ContractAddress = 0x200.try_into().unwrap(); // Use numeric mint_recipient
    let mint_recipient_felt: felt252 = mint_recipient.into();
    let mint_recipient_u256: u256 = mint_recipient_felt.into();
    let amount: u256 = 1000_u256;
    let depositor: u256 = 0x100.into(); // Use numeric depositor
    let max_fee: u256 = 100_u256;
    let fee_executed: u256 = 50_u256; // Non-zero fee

    // Format message with non-zero fee using custom formatter
    let message_body = format_message_for_relay_with_fee_and_expiration(
        0_u32, // version
        burn_token,
        mint_recipient_u256,
        amount,
        depositor,
        max_fee,
        fee_executed, // Non-zero fee
        0_u256, // expiration_block
        Default::default() // hook_data
    );

    // Spy on events
    let mut spy = spy_events();

    // Handle the message as the local message transmitter
    start_cheat_caller_address(contract_address, local_message_transmitter);
    let result = dispatcher
        .handle_receive_unfinalized_message(
            source_domain,
            1000_u256, // Remote token messenger for domain 1
            500_u32, // finality threshold (minimum required)
            message_body,
        );
    stop_cheat_caller_address(contract_address);

    assert!(result, "Handle receive unfinalized message should return true");

    // For unfinalized messages with non-zero fee:
    // - mint_recipient gets amount - fee (1000 - 50 = 950)
    // - fee_recipient gets fee (50)
    // The event should show the full amount and the fee collected
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::Event::MintAndWithdraw(
                        token_messenger_minter::token_messenger_minter_v2::TokenMessengerMinterV2::MintAndWithdraw {
                            mint_recipient,
                            amount: amount - fee_executed, // 950 (recipient gets amount minus fee)
                            mint_token: mock_token,
                            fee_collected: fee_executed // 50 (non-zero fee collected)
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: ('Caller not local MT',))]
fn test_handle_receive_finalized_message_fails_invalid_caller() {
    let (contract_address, _, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Try to call as unauthorized address
    start_cheat_caller_address(
        contract_address, 0x1000.try_into().unwrap(),
    ); // Use numeric unauthorized
    dispatcher.handle_receive_finalized_message(1_u32, 1000_u256, 0_u32, Default::default());
}

#[test]
#[should_panic(expected: ('Remote token messenger invalid',))]
fn test_handle_receive_finalized_message_fails_invalid_remote_token_messenger() {
    let (contract_address, local_message_transmitter, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Call with wrong remote token messenger
    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher
        .handle_receive_finalized_message(
            1_u32, 9999_u256, // Wrong remote token messenger
            0_u32, Default::default(),
        );
}

#[test]
#[should_panic(expected: ('Unsupported finality threshold',))]
fn test_handle_receive_unfinalized_message_fails_low_finality_threshold() {
    let (contract_address, local_message_transmitter, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Call with finality threshold below minimum
    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher
        .handle_receive_unfinalized_message(
            1_u32, 1000_u256, 499_u32, // Below minimum of 500
            Default::default(),
        );
}

#[test]
#[should_panic(expected: ('Invalid message body version',))]
fn test_handle_receive_message_fails_wrong_version() {
    let (contract_address, local_message_transmitter, _) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };

    // Create message with wrong version
    let message_body = BurnMessageV2::format_message_for_relay(
        1_u32, // Wrong version (1 instead of 0)
        0x200.into(), // Use numeric burn_token
        0x200.into(), // Use numeric mint_recipient
        1000_u256,
        0x100.into(), // Use numeric depositor
        10_u256,
        Default::default(),
    );

    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher.handle_receive_finalized_message(1_u32, 1000_u256, 0_u32, message_body);
}

#[test]
#[should_panic(expected: ('Message expired must re-sign',))]
fn test_handle_receive_message_fails_expired() {
    let (contract_address, local_message_transmitter, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };

    // Setup token mapping first
    let source_domain: u32 = 1_u32;
    let burn_token: u256 = 0x200.into();
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, source_domain, burn_token);
    stop_cheat_caller_address(contract_address);

    // Set current block number to 100
    start_cheat_block_number(contract_address, 100);

    // Create message with expiration in the past (block 50)
    let message_body = format_message_for_relay_with_fee_and_expiration(
        0_u32, // version
        burn_token,
        0x200.into(), // mint_recipient
        1000_u256, // amount
        0x100.into(), // message_sender
        10_u256, // max_fee
        0_u256, // fee_executed
        50_u256, // expiration_block (in the past)
        Default::default() // hook_data
    );

    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher.handle_receive_finalized_message(source_domain, 1000_u256, 0_u32, message_body);
}

#[test]
#[should_panic(expected: ('Fee equals or exceeds amount',))]
fn test_handle_receive_message_fails_fee_equals_amount() {
    let (contract_address, local_message_transmitter, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };

    // Setup token mapping first
    let source_domain: u32 = 1_u32;
    let burn_token: u256 = 0x200.into();
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, source_domain, burn_token);
    stop_cheat_caller_address(contract_address);

    let amount: u256 = 1000_u256;

    // Create message where fee equals amount
    let message_body = format_message_for_relay_with_fee_and_expiration(
        0_u32, // version
        burn_token,
        0x200.into(), // mint_recipient
        amount,
        0x100.into(), // message_sender
        amount + 100, // max_fee (higher than fee to pass that check)
        amount, // fee_executed = amount (should fail)
        0_u256, // expiration_block
        Default::default() // hook_data
    );

    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher.handle_receive_finalized_message(source_domain, 1000_u256, 0_u32, message_body);
}

#[test]
#[should_panic(expected: ('Fee exceeds max fee',))]
fn test_handle_receive_message_fails_fee_exceeds_max() {
    let (contract_address, local_message_transmitter, mock_token) = deploy_token_messenger_minter();
    let dispatcher = ITokenMessengerMinterV2Dispatcher { contract_address };
    let token_controller_dispatcher = ITokenControllerDispatcher { contract_address };

    // Setup token mapping first
    let source_domain: u32 = 1_u32;
    let burn_token: u256 = 0x200.into();
    start_cheat_caller_address(contract_address, 0x6.try_into().unwrap()); // Token controller
    token_controller_dispatcher.link_token_pair(mock_token, source_domain, burn_token);
    stop_cheat_caller_address(contract_address);

    let amount: u256 = 1000_u256;
    let max_fee: u256 = 50_u256;

    // Create message where fee exceeds max fee
    let message_body = format_message_for_relay_with_fee_and_expiration(
        0_u32, // version
        burn_token,
        0x200.into(), // mint_recipient
        amount,
        0x100.into(), // message_sender
        max_fee,
        100_u256, // fee_executed > max_fee (should fail)
        0_u256, // expiration_block
        Default::default() // hook_data
    );

    start_cheat_caller_address(contract_address, local_message_transmitter);
    dispatcher.handle_receive_finalized_message(source_domain, 1000_u256, 0_u32, message_body);
}
