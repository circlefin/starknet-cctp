/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// U256 maximum value: 2^256 - 1
export const U256_MAX = BigInt(2) ** BigInt(256) - BigInt(1);

// Felt252 maximum value: 2^251 + 17 * 2^192 https://docs.starknet.io/build/corelib/core-felt252#core-felt252
export const FELT252_MAX = BigInt(2) ** BigInt(251) + BigInt(17) * BigInt(2) ** BigInt(192);

// Starknet domain id
export const LOCAL_DOMAIN_ID = 25;
