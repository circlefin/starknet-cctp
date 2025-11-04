// Copyright (c) 2025 Circle Internet Group, Inc. All rights reserved.
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

use core::byte_array::ByteArrayTrait;
use test_utils::hex_string_to_bytes_array;

#[test]
fn test_hex_string_to_bytes_array() {
    let hex =
        "0x111a2b4ce084ccc83c8ef18eabf50fc332f603c7cd2ef7e177ea45a1c332f1d97c0fc30429b2c6ce57f7cb6bbcbdabff5d94b487075dff3b09182c25d6e9d98a1cc901a511af9b85b6db2b6660d3aeb029129a26944b69a74dd7c26a64e154726f23bd811da1a90c6ce36a9170785966de2a9280c39042fedb95bbc29bbf301c0d1c";
    let bytes_array = hex_string_to_bytes_array(hex);
    assert_eq!(bytes_array.len(), 130);
}
