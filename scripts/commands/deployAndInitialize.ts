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
import { inspect } from "util";
import { Account, RpcProvider, Contract, Abi } from "starknet";
import { readConfig, MessageTransmitterV2Config, TokenMessengerMinterV2Config } from "../config.js";
import { getStarknetProvider, waitForUserConfirmation, deployContract, ContractName } from "../utils.js";
import { LOCAL_DOMAIN_ID } from "../constants.js";

const program = new Command();
const DEFAULT_PROFILE = "release";

export default program
  .createCommand("deploy-and-initialize-contracts")
  .description("Deploy and initialize the cctp contracts: message transmitter and token messenger minter")
  .requiredOption("-r, --rpc-url <string>", "Starknet RPC URL")
  .requiredOption("--deployer-key <string>", "Deployer private key")
  .requiredOption("--deployer-address <string>", "Deployer account address")
  .requiredOption("--config-path <string>", "Path to contract config file")
  .option(
    "--profile <string>",
    "Scarb profile that was used to build the contracts. Default profile is 'release'",
    DEFAULT_PROFILE,
  )
  .option("--salt <string>", 'Salt for contract deployment. Default value is "0"', "0")
  .action(async (options: any) => {
    await deployAndInitializeContracts(options);
  });

async function initializeMessageTransmitter(
  provider: RpcProvider,
  contractAddress: string,
  abi: Abi,
  config: MessageTransmitterV2Config,
) {
  console.log("Initializing MessageTransmitterV2 contract...");

  const contract = new Contract(abi, contractAddress, provider);
  contract.connect(new Account(provider, config.admin.address, config.admin.privateKey));

  const initializeTx = await contract.initialize(
    LOCAL_DOMAIN_ID,
    config.version,
    config.owner,
    config.pauser,
    config.rescuer,
    config.attesterManager,
    config.attesters,
    config.signatureThreshold,
    config.maxMessageBodySize,
  );

  console.log(`Transaction submitted: ${initializeTx.transaction_hash}`);

  // wait for transaction confirmation
  const tx = await provider.waitForTransaction(initializeTx.transaction_hash);

  if (!tx.isSuccess()) {
    throw new Error(
      `MessageTransmitterV2 initialization failed, Transaction hash: ${initializeTx.transaction_hash}, Error: ${tx.value}`,
    );
  }

  console.log("✅ Message Transmitter initialized");
}

async function initializeTokenMessengerMinter(
  provider: RpcProvider,
  contractAddress: string,
  abi: Abi,
  config: TokenMessengerMinterV2Config,
  messageTransmitterAddress: string,
) {
  console.log("Initializing TokenMessengerMinterV2 contract...");

  const contract = new Contract(abi, contractAddress, provider);
  contract.connect(new Account(provider, config.admin.address, config.admin.privateKey));

  const initializeTx = await contract.initialize(
    config.owner,
    config.pauser,
    config.denylister,
    config.rescuer,
    config.tokenController,
    config.minFeeController,
    config.feeRecipient,
    config.messageBodyVersion,
    messageTransmitterAddress,
    config.remoteDomains,
    config.remoteTokenMessengers,
  );

  console.log(`Transaction submitted: ${initializeTx.transaction_hash}`);

  // wait for transaction confirmation
  const tx = await provider.waitForTransaction(initializeTx.transaction_hash);

  if (!tx.isSuccess()) {
    throw new Error(
      `TokenMessengerMinterV2 initialization failed, Transaction hash: ${initializeTx.transaction_hash}, Error: ${tx.value}`,
    );
  }

  console.log("✅ Token Messenger Minter initialized");
}

export async function deployAndInitializeContracts({
  rpcUrl,
  deployerKey,
  deployerAddress,
  configPath,
  profile,
  salt,
}: {
  rpcUrl: string;
  deployerKey: string;
  deployerAddress: string;
  configPath: string;
  profile: string;
  salt: string;
}) {
  const provider = getStarknetProvider(rpcUrl);
  const deployer = new Account(provider, deployerAddress, deployerKey);

  const { messageTransmitterV2, tokenMessengerMinterV2 } = readConfig(configPath);
  console.log(
    `Creating CCTP contracts with config`,
    inspect({ messageTransmitterV2, tokenMessengerMinterV2 }, false, 8, true),
  );

  if (!(await waitForUserConfirmation())) {
    process.exit(1);
  }

  // Deploy MessageTransmitter
  const messageTransmitterResult = await deployContract(deployer, salt, profile, ContractName.MessageTransmitterV2, [
    messageTransmitterV2.admin.address,
  ]);

  // Deploy TokenMessengerMinter
  const tokenMessengerMinterResult = await deployContract(
    deployer,
    salt,
    profile,
    ContractName.TokenMessengerMinterV2,
    [tokenMessengerMinterV2.admin.address],
  );

  // Initialize MessageTransmitter
  await initializeMessageTransmitter(
    provider,
    messageTransmitterResult.contractAddress,
    messageTransmitterResult.abi,
    messageTransmitterV2,
  );

  // Initialize TokenMessengerMinter
  await initializeTokenMessengerMinter(
    provider,
    tokenMessengerMinterResult.contractAddress,
    tokenMessengerMinterResult.abi,
    tokenMessengerMinterV2,
    messageTransmitterResult.contractAddress,
  );

  return {
    messageTransmitterV2: {
      contractAddress: messageTransmitterResult.contractAddress,
      transactionHash: messageTransmitterResult.transactionHash,
      contractClassHash: messageTransmitterResult.contractClassHash,
    },
    tokenMessengerMinterV2: {
      contractAddress: tokenMessengerMinterResult.contractAddress,
      transactionHash: tokenMessengerMinterResult.transactionHash,
      contractClassHash: tokenMessengerMinterResult.contractClassHash,
    },
  };
}
