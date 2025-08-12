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

import { Command } from "commander";
import { getContract, getStarknetProvider } from "../utils.js";
import { MessageTransmitterV2Config, readConfig, TokenMessengerMinterV2Config } from "../config.js";
import { RpcProvider } from "starknet";
import { LOCAL_DOMAIN_ID } from "../constants.js";

const program = new Command();

export type TaskArguments = {
  rpcUrl: string;
  messageTransmitterContractAddress: string;
  tokenMessengerMinterContractAddress: string;
  configPath: string;
};

type ContractStateResult = {
  message: string;
  equal: boolean;
  onchainValue?: any;
  expectedValue?: any;
};

/**
 * Helper function to create and add a ContractStateResult to the results array
 */
function addContractStateResult(
  results: ContractStateResult[],
  stateVariableName: string,
  onchainValue: any,
  expectedValue: any,
): void {
  const isEqual = onchainValue === expectedValue;
  const formattedMessage = isEqual
    ? `\x1b[32m✅ STATE VERIFICATION PASSED\x1b[0m - ${stateVariableName} matches expected value`
    : `\x1b[31m❌ STATE VERIFICATION FAILED\x1b[0m - ${stateVariableName} mismatch`;

  results.push({
    message: formattedMessage,
    equal: isEqual,
    onchainValue,
    expectedValue,
  });
}

/**
 * Log the results of the contract state verification
 */
export function logContractStateResults(results: ContractStateResult[]): void {
  console.log("\n===== Contract State Verification Results =====\n");

  for (const { message, equal, onchainValue, expectedValue } of results) {
    if (!equal) {
      console.log(message);
      if (onchainValue !== undefined && expectedValue !== undefined) {
        console.log(`  On-chain: ${onchainValue}`);
        console.log(`  Expected: ${expectedValue}`);
      }
      console.log("");
    } else {
      console.log(message);
      console.log(`  Value: ${onchainValue}\n`);
    }
  }

  console.log("=".repeat(50));
}

export default program
  .createCommand("verify-contract-state")
  .description("Verify the state of a deployed CCTP contract")
  .requiredOption("--rpc-url <string>", "Starknet RPC URL")
  .requiredOption("--message-transmitter-contract-address <string>", "Message transmitter contract address")
  .requiredOption("--token-messenger-minter-contract-address <string>", "Token messenger contract address")
  .requiredOption("--config-path <string>", "Path to contract config file")
  .action(async (options: any) => {
    await taskAction(options);
  });

async function taskAction(options: TaskArguments): Promise<ContractStateResult[]> {
  const results = await verifyContractState(options);
  logContractStateResults(results);
  return results;
}

export async function verifyContractState({
  rpcUrl,
  messageTransmitterContractAddress,
  tokenMessengerMinterContractAddress,
  configPath,
}: TaskArguments): Promise<ContractStateResult[]> {
  const provider = getStarknetProvider(rpcUrl);
  const { messageTransmitterV2, tokenMessengerMinterV2 } = readConfig(configPath);

  const messageTransmitterResults = await verifyMessageTransmitterState(
    provider,
    messageTransmitterContractAddress,
    messageTransmitterV2,
  );
  const tokenMessengerMinterResults = await verifyTokenMessengerMinterState(
    provider,
    tokenMessengerMinterContractAddress,
    tokenMessengerMinterV2,
  );

  return [...messageTransmitterResults, ...tokenMessengerMinterResults];
}

async function verifyMessageTransmitterState(
  provider: RpcProvider,
  contractAddress: string,
  contractConfig: MessageTransmitterV2Config,
) {
  const results: ContractStateResult[] = [];

  const contract = await getContract(provider, contractAddress);

  // Get onchain values
  const localDomain = await contract.get_local_domain();
  const version = await contract.get_version();
  const admin = await contract.admin();
  const owner = await contract.owner();
  const pauser = await contract.pauser();
  const rescuer = await contract.rescuer();
  const attesterManager = await contract.attester_manager();
  const attesters = await contract.get_enabled_attesters();
  const signatureThreshold = await contract.get_signature_threshold();
  const maxMessageBodySize = await contract.get_max_message_body_size();

  // Verify contract state variables
  addContractStateResult(results, "localDomain", localDomain, BigInt(LOCAL_DOMAIN_ID));
  addContractStateResult(results, "version", version, BigInt(contractConfig.version));
  addContractStateResult(results, "admin", admin, BigInt(contractConfig.admin.address));
  addContractStateResult(results, "owner", owner, BigInt(contractConfig.owner));
  addContractStateResult(results, "pauser", pauser, BigInt(contractConfig.pauser));
  addContractStateResult(results, "rescuer", rescuer, BigInt(contractConfig.rescuer));
  addContractStateResult(results, "attesterManager", attesterManager, BigInt(contractConfig.attesterManager));
  addContractStateResult(results, "signatureThreshold", signatureThreshold, BigInt(contractConfig.signatureThreshold));
  addContractStateResult(results, "maxMessageBodySize", maxMessageBodySize, BigInt(contractConfig.maxMessageBodySize));

  for (const attester of contractConfig.attesters) {
    const enabled = attesters.includes(BigInt(attester));
    addContractStateResult(results, `attester ${attester}`, enabled, true);
  }

  return results;
}

async function verifyTokenMessengerMinterState(
  provider: RpcProvider,
  contractAddress: string,
  contractConfig: TokenMessengerMinterV2Config,
) {
  const results: ContractStateResult[] = [];

  const contract = await getContract(provider, contractAddress);

  // Get onchain values
  const admin = await contract.admin();
  const owner = await contract.owner();
  const pauser = await contract.pauser();
  const denylister = await contract.denylister();
  const rescuer = await contract.rescuer();
  const tokenController = await contract.token_controller();
  const minFeeController = await contract.min_fee_controller();
  const feeRecipient = await contract.fee_recipient();
  const messageBodyVersion = await contract.message_body_version();

  // Verify contract state variables
  addContractStateResult(results, "admin", admin, BigInt(contractConfig.admin.address));
  addContractStateResult(results, "owner", owner, BigInt(contractConfig.owner));
  addContractStateResult(results, "pauser", pauser, BigInt(contractConfig.pauser));
  addContractStateResult(results, "denylister", denylister, BigInt(contractConfig.denylister));
  addContractStateResult(results, "rescuer", rescuer, BigInt(contractConfig.rescuer));
  addContractStateResult(results, "tokenController", tokenController, BigInt(contractConfig.tokenController));
  addContractStateResult(results, "minFeeController", minFeeController, BigInt(contractConfig.minFeeController));
  addContractStateResult(results, "feeRecipient", feeRecipient, BigInt(contractConfig.feeRecipient));
  addContractStateResult(results, "messageBodyVersion", messageBodyVersion, BigInt(contractConfig.messageBodyVersion));

  for (let i = 0; i < contractConfig.remoteDomains.length; i++) {
    const domain = contractConfig.remoteDomains[i];
    const messenger = contractConfig.remoteTokenMessengers[i];
    const remoteTokenMessenger = await contract.remote_token_messenger(domain);
    addContractStateResult(results, `remoteTokenMessenger ${domain}`, remoteTokenMessenger, BigInt(messenger ?? 0));
  }

  return results;
}
