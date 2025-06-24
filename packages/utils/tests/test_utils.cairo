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

use utils::add_numbers;

#[test]
fn test_add_numbers() {
    assert!(add_numbers(2, 3) == 5, "2 + 3 should equal 5");
    assert!(add_numbers(0, 0) == 0, "0 + 0 should equal 0");
    assert!(add_numbers(10, 15) == 25, "10 + 15 should equal 25");
}
