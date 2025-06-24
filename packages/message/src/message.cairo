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

/// A basic message structure containing a single u32 value
#[derive(Drop, Copy)]
pub struct Message {
    pub value: u32,
}

#[generate_trait]
pub impl MessageImpl of MessageTrait {
    /// Creates a new Message with the given value
    ///
    /// # Arguments
    /// * `value` - The u32 value to store in the message
    ///
    /// # Returns
    /// A new Message instance
    fn new(value: u32) -> Message {
        Message { value }
    }

    /// Serializes the message into a ByteArray
    ///
    /// # Returns
    /// A ByteArray containing the serialized message
    fn serialize(self: @Message) -> ByteArray {
        let mut byte_array: ByteArray = "";

        // Convert the u32 value to bytes (big-endian format)
        let value = *self.value;
        let byte1: u8 = ((value / 0x1000000) % 0x100).try_into().unwrap();
        let byte2: u8 = ((value / 0x10000) % 0x100).try_into().unwrap();
        let byte3: u8 = ((value / 0x100) % 0x100).try_into().unwrap();
        let byte4: u8 = (value % 0x100).try_into().unwrap();

        byte_array.append_byte(byte1);
        byte_array.append_byte(byte2);
        byte_array.append_byte(byte3);
        byte_array.append_byte(byte4);

        byte_array
    }
}
