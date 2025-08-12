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

import readline from "readline/promises";
import * as path from "path";
import * as fs from "fs/promises";
import { fileURLToPath } from "url";
import { Account, RpcProvider, RawArgs, Contract, CallData } from "starknet";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export enum ContractName {
  MessageTransmitterV2 = "messageTransmitterV2",
  TokenMessengerMinterV2 = "tokenMessengerMinterV2",
}

export const contractNameToPath = {
  [ContractName.MessageTransmitterV2]: "message_transmitter_MessageTransmitterV2",
  [ContractName.TokenMessengerMinterV2]: "token_messenger_minter_TokenMessengerMinterV2",
};

export function getStarknetProvider(rpcUrl: string): RpcProvider {
  return new RpcProvider({ nodeUrl: rpcUrl });
}

export async function waitForUserConfirmation() {
  if (process.env.NODE_ENV === "TESTING") {
    return true;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  let userResponse: boolean;

  while (true) {
    const response = (await rl.question("Are you sure? (Y/N): ")).toUpperCase();
    if (response != "Y" && response != "N") {
      continue;
    }
    userResponse = response === "Y";
    break;
  }
  rl.close();

  return userResponse;
}

export function getTargetPath(profile: string, fileName: string): string {
  return path.join(__dirname, `../target/${profile}/${fileName}`);
}

export function getContractSierraPath(profile: string, contractName: ContractName): string {
  return getTargetPath(profile, `${contractNameToPath[contractName]}.contract_class.json`);
}

export function getContractCasmPath(profile: string, contractName: ContractName): string {
  return getTargetPath(profile, `${contractNameToPath[contractName]}.compiled_contract_class.json`);
}

export async function readFileToJson(filePath: string) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

export async function declareAndDeployContract(
  deployer: Account,
  salt: string,
  sierraPath: string,
  casmPath: string,
  constructorCalldata: RawArgs,
) {
  const sierra = await readFileToJson(sierraPath);
  const casm = await readFileToJson(casmPath);
  const deployResponse = await deployer.declareAndDeploy({
    contract: sierra,
    casm,
    salt,
    constructorCalldata: CallData.compile(constructorCalldata),
    // set `unique` to false in order to get reproducible, deployer-independent deployments.
    unique: false,
  });

  return {
    contractClassHash: deployResponse.declare.class_hash.toString(),
    contractAddress: deployResponse.deploy.contract_address,
    transactionHash: deployResponse.deploy.transaction_hash,
    abi: sierra.abi,
  };
}

export async function deployContract(
  deployer: Account,
  salt: string,
  profile: string,
  contractName: ContractName,
  constructorCalldata: RawArgs,
) {
  console.log(`Deploying ${contractName} contract...`);

  const result = await declareAndDeployContract(
    deployer,
    salt,
    getContractSierraPath(profile, contractName),
    getContractCasmPath(profile, contractName),
    constructorCalldata,
  );

  console.log(`${contractName} deployed at: ${result.contractAddress}`);
  console.log(`Transaction hash: ${result.transactionHash}`);
  console.log(`${contractName} class hash: ${result.contractClassHash}`);

  return result;
}

export async function getContract(provider: RpcProvider, contractAddress: string): Promise<Contract> {
  const contractClass = await provider.getClassAt(contractAddress);
  return new Contract(contractClass.abi, contractAddress, provider);
}
