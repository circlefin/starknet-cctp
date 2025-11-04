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

import * as env from "env-var";

// Iris
export const IRIS_API_URL = env.get("IRIS_API_URL").default("https://iris-api-sandbox.circle.com").asString();

// Remote EVM config
export const REMOTE_TOKEN_HEX = env.get("REMOTE_TOKEN_HEX").required().asString();
export const REMOTE_EVM_DOMAIN = env.get("REMOTE_EVM_DOMAIN").default("1").asInt();
export const REMOTE_EVM_ADDRESS = env.get("REMOTE_EVM_ADDRESS").required().asString();
export const REMOTE_EVM_PRIVATE_KEY = env.get("REMOTE_EVM_PRIVATE_KEY").required().asString();
export const REMOTE_EVM_RPC_URL = env.get("REMOTE_EVM_RPC_URL").required().asString();
export const REMOTE_EVM_TOKEN_MESSENGER_ADDRESS = env.get("REMOTE_EVM_TOKEN_MESSENGER_ADDRESS").required().asString();
export const REMOTE_EVM_MESSAGE_TRANSMITTER_ADDRESS = env
  .get("REMOTE_EVM_MESSAGE_TRANSMITTER_ADDRESS")
  .required()
  .asString();

// Starknet config
export const NODE_URL = env.get("NODE_URL").required().asString();
export const ACCOUNT_ADDRESS = env.get("ACCOUNT_ADDRESS").required().asString();
export const PRIVATE_KEY = env.get("PRIVATE_KEY").required().asString();

export const TOKEN_MESSENGER_MINTER_ADDRESS = env.get("TOKEN_MESSENGER_MINTER_ADDRESS").required().asString();
export const MESSAGE_TRANSMITTER_ADDRESS = env.get("MESSAGE_TRANSMITTER_ADDRESS").required().asString();
export const BURN_TOKEN_ADDRESS = env.get("BURN_TOKEN_ADDRESS").required().asString();

export const DESTINATION_CALLER = env.get("DESTINATION_CALLER").asString();
export const STARKNET_DOMAIN_ID = 25;
