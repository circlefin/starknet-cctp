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

import { existsSync, readFileSync } from "fs";
import * as yup from "yup";
import { FELT252_MAX, U256_MAX } from "./constants.js";

function yupStarknetAddress() {
  return yup.string().test(isValidStarknetAddress);
}

function isEmptyOrZeroAddress(address: string): boolean {
  return !address || address.trim() === "" || address === "0x0" || address === "0";
}

function yumU256() {
  return yup.string().test(isValidU256);
}

function isValidU256(value: any): boolean {
  if (typeof value !== "string") {
    return false;
  }

  if (!isValidHex(value)) {
    return false;
  }

  const num = BigInt(value);
  return num >= BigInt(0) && num <= U256_MAX;
}

function isValidHex(value: string): boolean {
  const hexPattern = /^0x[0-9a-fA-F]+$/;
  return hexPattern.test(value);
}

function isValidStarknetAddress(value: any): boolean {
  if (typeof value !== "string") {
    return false;
  }

  const address = value.toString();
  if (isEmptyOrZeroAddress(address)) {
    return false;
  }

  if (!isValidHex(address)) {
    return false;
  }

  // Try to parse as BigInt to ensure it's a valid hex number
  let addressBigInt: bigint;
  try {
    addressBigInt = BigInt(address);
  } catch {
    return false;
  }

  if (addressBigInt < BigInt(0) || addressBigInt > FELT252_MAX) {
    return false;
  }

  return true;
}

const MessageTransmitterV2ConfigSchema = yup.object().shape({
  version: yup.number().integer().positive().required(),
  admin: yupStarknetAddress().required(),
  owner: yupStarknetAddress().required(),
  pauser: yupStarknetAddress().required(),
  rescuer: yupStarknetAddress().required(),
  attesterManager: yupStarknetAddress().required(),
  attesters: yup.array(yupStarknetAddress().required()).required(),
  signatureThreshold: yup.number().integer().positive().required(),
  maxMessageBodySize: yup.number().integer().positive().required(),
});

const TokenMessengerMinterV2ConfigSchema = yup.object().shape({
  admin: yupStarknetAddress().required(),
  owner: yupStarknetAddress().required(),
  pauser: yupStarknetAddress().required(),
  denylister: yupStarknetAddress().required(),
  rescuer: yupStarknetAddress().required(),
  tokenController: yupStarknetAddress().required(),
  minFeeController: yupStarknetAddress().required(),
  feeRecipient: yupStarknetAddress().required(),
  messageBodyVersion: yup.number().integer().positive().required(),
  remoteDomains: yup.array(yup.number().integer().positive()).required(),
  remoteTokenMessengers: yup.array(yumU256()).required(),
});

const contractConfigSchema = yup.object().shape({
  messageTransmitterV2: MessageTransmitterV2ConfigSchema,
  tokenMessengerMinterV2: TokenMessengerMinterV2ConfigSchema,
});

export type ContractConfig = yup.InferType<typeof contractConfigSchema>;
export type MessageTransmitterV2Config = yup.InferType<typeof MessageTransmitterV2ConfigSchema>;
export type TokenMessengerMinterV2Config = yup.InferType<typeof TokenMessengerMinterV2ConfigSchema>;

export function readConfig(configPath: string): ContractConfig {
  if (!existsSync(configPath)) {
    throw new Error(`Failed to load config file: ${configPath}`);
  }

  const configData = readFileSync(configPath, "utf8");
  const config = JSON.parse(configData) as ContractConfig;

  // Validate that the token configuration JSON follows the expected schema.
  const contractConfig = contractConfigSchema.validateSync(config, {
    abortEarly: false,
    strict: true,
  });

  return contractConfig;
}
