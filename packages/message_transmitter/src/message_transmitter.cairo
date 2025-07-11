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

#[starknet::interface]
pub trait IMessageTransmitter<TContractState> {
    fn add_two_numbers(self: @TContractState, a: u32, b: u32) -> u32;
}

#[starknet::contract]
pub mod MessageTransmitter {
    use components::ownable::OwnableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::Ownable<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[abi(embed_v0)]
    impl MessageTransmitter of super::IMessageTransmitter<ContractState> {
        /// Add two numbers using the utility function from utils
        fn add_two_numbers(self: @ContractState, a: u32, b: u32) -> u32 {
            self._internal_add(a, b)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _internal_add(self: @ContractState, a: u32, b: u32) -> u32 {
            a + b
        }
    }
}
