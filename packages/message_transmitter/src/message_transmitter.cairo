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
    fn send_message(
        ref self: TContractState,
        destination_domain: u32,
        recipient: u256,
        destination_caller: u256,
        min_finality_threshold: u32,
        message_body: ByteArray,
    );

    fn receive_message(ref self: TContractState, message: ByteArray, attestation: ByteArray);
}
