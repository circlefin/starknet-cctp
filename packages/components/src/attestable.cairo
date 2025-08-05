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

//! # Attestable Component
//!
//! This component provides a way to enable and disable attesters.
//! The component integrates with the Ownable component to ensure proper access control,
//! The attester manager is the address that can enable and disable attesters.
//! The attester manager is set by the owner of the contract.
//! The attester manager can manage the attesters list and the signature threshold.
//! It also provides a function to verify the attestation signatures.
//!
//! # Features
//!
//! - **Attester Management**: Attester manager can enable and disable attesters
//! - **Access Control**: Only the owner can set the attester manager
//! - **Event Emission**: Emits events for transparency and monitoring
//! - **Signature Verification**: Verifies the attestation signatures

use starknet::ContractAddress;

#[starknet::interface]
pub trait IAttestable<TContractState> {
    /// Enables an attester to be a valid signer of attestations.
    ///
    /// Only the attester manager can call this function
    ///
    /// # Arguments
    ///
    /// * `new_attester` - The address of the attester to enable.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the attester manager
    /// - Attester is zero address
    /// - Attester is already enabled
    fn enable_attester(ref self: TContractState, new_attester: ContractAddress);

    /// Disables an attester to no longer be a valid signer of attestations.
    ///
    /// Only the attester manager can call this function
    ///
    /// # Arguments
    ///
    /// * `attester` - The address of the attester to disable.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the attester manager
    /// - Attester is already disabled
    /// - There is only 1 active attester
    /// - Signature threshold is greater than the number of enabled attesters
    fn disable_attester(ref self: TContractState, attester: ContractAddress);

    /// Checks if an attester is enabled.
    ///
    /// # Arguments
    ///
    /// * `attester` - The address of the attester to check.
    ///
    /// # Returns
    ///
    /// * `true` - If the attester is enabled.
    /// * `false` - If the attester is disabled.
    fn is_enabled_attester(self: @TContractState, attester: ContractAddress) -> bool;

    /// Updates the attester manager.
    ///
    /// * `new_attester_manager` - The address of the new attester manager.
    ///
    /// Only the owner can update the attester manager.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the owner
    /// - New attester manager is zero address
    /// - New attester manager is the same as the current attester manager
    fn update_attester_manager(ref self: TContractState, new_attester_manager: ContractAddress);

    /// Sets the signature threshold.
    ///
    /// # Arguments
    ///
    /// * `new_signature_threshold` - The new signature threshold.
    ///
    /// Only the attester manager can set the signature threshold.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    /// - The caller is not the attester manager
    /// - New signature threshold is not positive
    /// - New signature threshold is greater than the number of enabled attesters
    /// - New signature threshold is the same as the current signature threshold
    fn set_signature_threshold(ref self: TContractState, new_signature_threshold: u64);

    /// Gets the attester manager.
    ///
    /// # Returns
    ///
    /// * `attester_manager` - The address of the attester manager.
    fn attester_manager(self: @TContractState) -> ContractAddress;

    /// Gets the signature threshold.
    ///
    /// # Returns
    ///
    /// * `signature_threshold` - The signature threshold.
    fn get_signature_threshold(self: @TContractState) -> u64;

    /// Gets the enabled attesters.
    ///
    /// # Returns
    ///
    /// * `enabled_attesters` - The array of enabled attesters.
    fn get_enabled_attesters(self: @TContractState) -> Array<ContractAddress>;
}

#[starknet::component]
pub mod AttestableComponent {
    use components::ownable::OwnableComponent;
    use components::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use core::keccak::compute_keccak_byte_array;
    use core::num::traits::Zero;
    use starknet::eth_signature::public_key_point_to_eth_address;
    use starknet::secp256_trait::{is_signature_entry_valid, recover_public_key, signature_from_vrs};
    use starknet::secp256k1::Secp256k1Point;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_caller_address};
    use utils::{extract_u256_be, reverse_u256_bytes};

    const SIGNATURE_LENGTH: usize = 65;

    #[storage]
    pub struct Storage {
        signature_threshold: u64,
        attester_manager: ContractAddress,
        attesters: Vec<ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        AttesterEnabled: AttesterEnabled,
        AttesterDisabled: AttesterDisabled,
        AttesterManagerUpdated: AttesterManagerUpdated,
        SignatureThresholdUpdated: SignatureThresholdUpdated,
    }

    /// Emitted when an attester is enabled.
    #[derive(Drop, starknet::Event)]
    pub struct AttesterEnabled {
        #[key]
        pub attester: ContractAddress,
    }

    /// Emitted when an attester is disabled.
    #[derive(Drop, starknet::Event)]
    pub struct AttesterDisabled {
        #[key]
        pub attester: ContractAddress,
    }

    /// Emitted when the attester manager is updated.
    #[derive(Drop, starknet::Event)]
    pub struct AttesterManagerUpdated {
        #[key]
        pub previous_attester_manager: ContractAddress,
        #[key]
        pub new_attester_manager: ContractAddress,
    }

    /// Emitted when the signature threshold is updated.
    #[derive(Drop, starknet::Event)]
    pub struct SignatureThresholdUpdated {
        #[key]
        previous_signature_threshold: u64,
        #[key]
        new_signature_threshold: u64,
    }

    pub mod Errors {
        pub const INVALID_ATTESTER_MANAGER: felt252 = 'Invalid attester manager';
        pub const INVALID_ATTESTER: felt252 = 'Invalid attester';
        pub const NOT_ATTESTER_MANAGER: felt252 = 'Caller not attester manager';
        pub const NOT_ENABLED_ATTESER: felt252 = 'Attester is not enabled';
        pub const ATTESTER_ALREADY_ENABLED: felt252 = 'Attester already enabled';
        pub const INVALID_SIGNATURE_THRESHOLD: felt252 = 'Invalid signature threshold';
        pub const SIGNATURE_THRESHOLD_TOO_HIGH: felt252 = 'New threshold too high';
        pub const INVALID_INDEX: felt252 = 'Invalid index';
        pub const SAME_ATTESTER_MANAGER: felt252 = 'Manager cannot be the same';
        pub const SAME_SIGNATURE_THRESHOLD: felt252 = 'Same signature threshold';
        pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
        pub const TOO_FEW_ENABLED_ATTESERS: felt252 = 'Too few enabled attesters';
        pub const SIGNATURE_THRESHOLD_TOO_LOW: felt252 = 'Signature threshold too low';
        pub const INVALID_SIGNATURE_ORDER_OR_DUPE: felt252 = 'Invalid signature order or dupe';
        pub const INVALID_ATTESTERS: felt252 = 'Invalid attesters';
        pub const INVALID_ATTESTATION: felt252 = 'Invalid attestation';
        pub const INVALID_SIGNATURE: felt252 = 'Invalid signature';
    }

    #[embeddable_as(Attestable)]
    pub impl AttestableImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IAttestable<ComponentState<TContractState>> {
        fn enable_attester(
            ref self: ComponentState<TContractState>, new_attester: ContractAddress,
        ) {
            // Only attester manager can enable an attester
            self.assert_only_attester_manager();

            // Check if attester is not zero
            assert(!new_attester.is_zero(), Errors::INVALID_ATTESTER);

            // Check if attester is already enabled
            assert(!self.is_enabled_attester(new_attester), Errors::ATTESTER_ALREADY_ENABLED);

            self.attesters.push(new_attester);

            // Emit event
            self.emit(AttesterEnabled { attester: new_attester });
        }

        fn disable_attester(ref self: ComponentState<TContractState>, attester: ContractAddress) {
            // Only attester manager can disable an attester
            self.assert_only_attester_manager();

            let position = self._get_attester_position(attester);
            // Check if attester is enabled
            assert(position > 0, Errors::NOT_ENABLED_ATTESER);

            // Disallow disabling attester if there is only 1 active attester
            assert(self.attesters.len() > 1, Errors::TOO_FEW_ENABLED_ATTESERS);

            // Disallow disabling attester if signature threshold is greater than the number of
            // enabled attesters
            assert(
                self.attesters.len() > self.signature_threshold.read(),
                Errors::SIGNATURE_THRESHOLD_TOO_LOW,
            );

            self._remove_attester(position);

            // Emit event
            self.emit(AttesterDisabled { attester });
        }

        fn is_enabled_attester(
            self: @ComponentState<TContractState>, attester: ContractAddress,
        ) -> bool {
            self._get_attester_position(attester) > 0
        }

        fn update_attester_manager(
            ref self: ComponentState<TContractState>, new_attester_manager: ContractAddress,
        ) {
            // Only Owner can update the attester manager
            let ownable_component = get_dep_component!(@self, Owner);
            ownable_component.assert_only_owner();

            // Check if new attester manager is not zero
            assert(!new_attester_manager.is_zero(), Errors::INVALID_ATTESTER_MANAGER);

            let attester_manager = self.attester_manager.read();

            // Check if new attester manager is not the same as the current attester manager
            assert(new_attester_manager != attester_manager, Errors::SAME_ATTESTER_MANAGER);

            self.attester_manager.write(new_attester_manager);

            // Emit event
            self
                .emit(
                    AttesterManagerUpdated {
                        previous_attester_manager: attester_manager, new_attester_manager,
                    },
                );
        }

        fn set_signature_threshold(
            ref self: ComponentState<TContractState>, new_signature_threshold: u64,
        ) {
            // Only attester manager can set the signature threshold
            self.assert_only_attester_manager();

            // Check if new signature threshold is positive
            assert(new_signature_threshold > 0, Errors::INVALID_SIGNATURE_THRESHOLD);
            assert(
                new_signature_threshold <= self.attesters.len(),
                Errors::SIGNATURE_THRESHOLD_TOO_HIGH,
            );

            let signature_threshold = self.signature_threshold.read();
            // Check if new signature threshold is not the same as the current signature threshold
            assert(
                new_signature_threshold != signature_threshold, Errors::SAME_SIGNATURE_THRESHOLD,
            );

            // Update signature threshold
            self.signature_threshold.write(new_signature_threshold);

            // Emit event
            self
                .emit(
                    SignatureThresholdUpdated {
                        previous_signature_threshold: signature_threshold, new_signature_threshold,
                    },
                );
        }

        fn attester_manager(self: @ComponentState<TContractState>) -> ContractAddress {
            self.attester_manager.read()
        }

        fn get_enabled_attesters(self: @ComponentState<TContractState>) -> Array<ContractAddress> {
            // return a array of the attesters list
            let mut addresses = array![];
            for i in 0..self.attesters.len() {
                addresses.append(self.attesters.at(i).read());
            }
            return addresses;
        }

        fn get_signature_threshold(self: @ComponentState<TContractState>) -> u64 {
            self.signature_threshold.read()
        }
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>,
            attester_manager: ContractAddress,
            attesters: Array<ContractAddress>,
            signature_threshold: u64,
        ) {
            assert(self.attester_manager.read().is_zero(), Errors::ALREADY_INITIALIZED);

            // Check if attester manager is not zero
            assert(!attester_manager.is_zero(), Errors::INVALID_ATTESTER_MANAGER);

            // Check if attesters is empty
            assert(attesters.len() > 0, Errors::INVALID_ATTESTERS);

            // Check if signature threshold is positive and less than or equal to the number of
            // attesters
            assert(
                signature_threshold > 0 && signature_threshold <= attesters.len().into(),
                Errors::INVALID_SIGNATURE_THRESHOLD,
            );

            // Add attester to attesters list
            for i in 0..attesters.len() {
                let attester = *attesters.at(i);
                assert(!attester.is_zero(), Errors::INVALID_ATTESTER);
                self.attesters.push(attester);
            }

            // Set attester manager
            self.attester_manager.write(attester_manager);

            // Set signature threshold to the provided value
            self.signature_threshold.write(signature_threshold);
        }

        fn assert_only_attester_manager(self: @ComponentState<TContractState>) {
            let attester_manager = self.attester_manager.read();
            let caller = get_caller_address();
            assert(caller == attester_manager, Errors::NOT_ATTESTER_MANAGER);
        }

        /// Verifies the attestation signatures.
        /// Returns an error if the attestation, which is comprised of one or more concatenated
        /// 65-byte signatures, is invalid.
        /// Rules for valid attestation:
        /// 1. length of `_attestation` == 65 (signature length) * signatureThreshold
        /// 2. addresses recovered from attestation must be in increasing order.
        /// For example, if signature A is signed by address 0x1..., and signature B
        /// is signed by address 0x2..., attestation must be passed as AB.
        /// 3. no duplicate signers
        /// 4. all signers must be enabled attesters
        ///
        /// Based on Christian Lundkvist's Simple Multisig
        /// (https://github.com/christianlundkvist/simple-multisig/tree/560c463c8651e0a4da331bd8f245ccd2a48ab63d)
        ///
        /// # Arguments
        ///
        /// * `message` - The message to verify.
        /// * `attestation` - The attestation to verify.
        ///
        fn verify_attestation_signatures(
            self: @ComponentState<TContractState>, message: ByteArray, attestation: ByteArray,
        ) {
            let signature_threshold: u32 = self.signature_threshold.read().try_into().unwrap();
            // Check if attestation length is valid
            assert(
                attestation.len() == SIGNATURE_LENGTH * signature_threshold,
                Errors::INVALID_ATTESTATION,
            );

            let mut latestAttester: ContractAddress = 0.try_into().unwrap();

            // compute the hash of the message
            let cairo_hash = compute_keccak_byte_array(@message);
            // cairo hash is u256 in little-endian, so we need to reverse it to get the big-endian
            // hash, which is the same as ethereum hash
            let digest = reverse_u256_bytes(cairo_hash);

            // Check if attestation is valid
            for i in 0..signature_threshold {
                let recovered_attester: ContractAddress = self
                    ._recover_attester(digest, @attestation, i * 65);

                // Signatures must be in increasing order of address, and may not duplicate
                // signatures from same address
                assert(
                    recovered_attester > latestAttester, Errors::INVALID_SIGNATURE_ORDER_OR_DUPE,
                );

                // Check if attester is enabled
                assert(self.is_enabled_attester(recovered_attester), Errors::NOT_ENABLED_ATTESER);

                // Update latest attester
                latestAttester = recovered_attester;
            }
        }

        /// Recover the attester from the signature.
        fn _recover_attester(
            self: @ComponentState<TContractState>,
            digest: u256,
            attestation: @ByteArray,
            start_index: u32,
        ) -> ContractAddress {
            // extract the r, s, v from the signature
            let r: u256 = extract_u256_be(attestation, start_index);
            let s: u256 = extract_u256_be(attestation, start_index + 32);
            let v: u32 = attestation.at(start_index + 64).unwrap().into();

            // check the given value is in value [1, N)
            assert(is_signature_entry_valid::<Secp256k1Point>(s), Errors::INVALID_SIGNATURE);
            assert(is_signature_entry_valid::<Secp256k1Point>(r), Errors::INVALID_SIGNATURE);

            let signature = signature_from_vrs(v, r, s);
            let point: Secp256k1Point = recover_public_key(digest, signature)
                .expect('Failed to recover public key');

            // convert the public key point to eth address
            let recovered_attester: felt252 = public_key_point_to_eth_address(point)
                .try_into()
                .expect('Invalid attester address size');
            recovered_attester.try_into().expect('Invalid attester address')
        }

        fn _get_attester_position(
            self: @ComponentState<TContractState>, attester: ContractAddress,
        ) -> u64 {
            // find the position of the attester in the attesters list
            for i in 0..self.attesters.len() {
                if self.attesters.at(i).read() == attester {
                    return i + 1;
                }
            }

            // if attester is not found, return 0
            return 0;
        }

        fn _remove_attester(ref self: ComponentState<TContractState>, position: u64) {
            // Remove attester from attesters list by swapping with the last attester
            if position < self.attesters.len() {
                let last_attester = self.attesters.at(self.attesters.len() - 1).read();

                // move last attester to the position of the attester to be removed
                self.attesters.at(position - 1).write(last_attester);
            }

            // remove attester from attesters list
            self.attesters.pop().unwrap();
        }
    }
}
