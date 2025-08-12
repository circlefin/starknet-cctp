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
import { getStarknetProvider, ContractName, getContractCasmPath } from "../utils.js";
import { readFileToJson } from "../utils.js";
import { computeClassHash } from "./computeClassHash.js";
import { RpcProvider } from "starknet";

const program = new Command();

export type TaskArguments = {
  rpcUrl: string;
  contractAddress: string;
  contractCreationTxHash?: string;
  verificationType: BytecodeVerificationType;
  contractName: ContractName;
  profile?: string;
};

export enum BytecodeVerificationType {
  ClassHash = "class-hash", // verifies the class hash matches
  FullBytecode = "full-bytecode", // verifies the entire CASM bytecode
}

export enum BytecodeInputType {
  ClassHash = "class hash",
  CasmBytecode = "CASM bytecode",
}

export interface StarknetContractArtifact {
  classHash: string;
  compiledContractCasm: any;
}

type BytecodeComparisonResult = {
  type: BytecodeInputType;
  equal: boolean;
  onchainValue?: string;
  localValue?: string;
};

export default program
  .createCommand("verify-onchain-bytecode")
  .description("Verify the onchain bytecode of a Starknet contract")
  .requiredOption("--rpc-url <string>", "Starknet RPC URL")
  .requiredOption("--contract-address <string>", "Contract address to verify")
  .requiredOption("--contract-name <string>", "Contract name: messageTransmitterV2 or tokenMessengerMinterV2")
  .option("--contract-creation-tx-hash <string>", "Transaction hash of contract creation")
  .option(
    "--verification-type <string>",
    "Type of verification: 'class-hash' or 'full-bytecode'",
    BytecodeVerificationType.FullBytecode,
  )
  .option("--profile <string>", "Build profile (dev or release)", "release")
  .action(async (options: any) => {
    await taskAction(options);
  });

/**
 * Wrapper function to pretty print the results of `verifyOnchainBytecode`.
 */
async function taskAction(options: TaskArguments): Promise<BytecodeComparisonResult[]> {
  const results = await verifyOnchainBytecode(options);
  logBytecodeComparisonResults(results);
  return results;
}

/**
 * A utility script to verify Starknet contract bytecode against locally compiled bytecode.
 *
 * Anatomy of Starknet contract deployment:
 * 1. Cairo source code is compiled to Sierra (intermediate representation)
 * 2. Sierra is compiled to CASM (Cairo Assembly)
 * 3. CASM bytecode and Sierra are used to compute a class hash
 * 4. Contracts are deployed as instances of a class (identified by class hash)
 *
 * This script automatically:
 * - Computes class hash from the Sierra contract class (.contract_class.json)
 * - Reads CASM bytecode from compiled contract class (.compiled_contract_class.json)
 * - Compares both against on-chain values
 */
export async function verifyOnchainBytecode({
  rpcUrl,
  contractAddress,
  verificationType = BytecodeVerificationType.FullBytecode,
  contractCreationTxHash,
  contractName,
  profile = "release",
}: TaskArguments): Promise<BytecodeComparisonResult[]> {
  const provider = getStarknetProvider(rpcUrl);
  const bytecodeComparisonResults: BytecodeComparisonResult[] = [];

  // Get on-chain class hash
  const onchainClassHash = await provider.getClassHashAt(contractAddress);

  // Get local artifact
  const localArtifact = await getContractArtifact(profile, contractName);

  // Compare class hashes
  bytecodeComparisonResults.push({
    type: BytecodeInputType.ClassHash,
    equal: onchainClassHash.toLowerCase() === localArtifact.classHash.toLowerCase(),
    onchainValue: onchainClassHash,
    localValue: localArtifact.classHash,
  });

  // If full bytecode verification is requested, compare CASM bytecode
  if (verificationType === BytecodeVerificationType.FullBytecode) {
    // Get on-chain CASM bytecode
    const onchainCasm = await provider.getCompiledCasm(onchainClassHash);
    const onchainBytecode = JSON.stringify(onchainCasm.bytecode);
    const localBytecode = JSON.stringify(localArtifact.compiledContractCasm.bytecode);

    // Compare CASM bytecode
    bytecodeComparisonResults.push({
      type: BytecodeInputType.CasmBytecode,
      equal: onchainBytecode === localBytecode,
      onchainValue: onchainBytecode.substring(0, 100) + "...", // Truncate for display
      localValue: localBytecode.substring(0, 100) + "...", // Truncate for display
    });
  }

  // If contract creation transaction is provided, log deployment details
  if (contractCreationTxHash) {
    await logContractCreationDetails(provider, contractCreationTxHash);
  }

  return bytecodeComparisonResults;
}

/**
 * Log the results of the bytecode comparison
 */
export function logBytecodeComparisonResults(results: BytecodeComparisonResult[]): void {
  console.log("\n===== Starknet Bytecode Verification Results =====\n");

  for (const { type, equal, onchainValue, localValue } of results) {
    if (!equal) {
      console.log("\x1b[31m❌ VERIFICATION FAILED\x1b[0m", `- ${type} mismatch`);
      if (onchainValue && localValue) {
        console.log(`  On-chain: ${onchainValue}`);
        console.log(`  Local:    ${localValue}`);
      }
    } else {
      console.log(
        "\x1b[32m✅ VERIFICATION PASSED\x1b[0m",
        `- ${type} matches local compilation\n`,
        `  ${type}: ${onchainValue}`,
      );
    }
  }

  console.log("\n" + "=".repeat(50));
}

/**
 * Returns contract artifact from local compilation
 * - Computes class hash from Sierra contract class using computeClassHash()
 * - Reads CASM bytecode from compiled contract class
 */
async function getContractArtifact(
  profile: string = "release",
  contractName: ContractName,
): Promise<StarknetContractArtifact> {
  // Compute class hash from Sierra contract class using the existing script
  const computedHash = await computeClassHash({
    profile: profile,
    contractName: contractName,
  });

  return {
    classHash: computedHash.classHash,
    compiledContractCasm: await readFileToJson(getContractCasmPath(profile, contractName)),
  };
}

/**
 * Log details about contract creation transaction
 */
async function logContractCreationDetails(provider: RpcProvider, contractCreationTxHash: string): Promise<void> {
  try {
    const transaction = await provider.getTransactionByHash(contractCreationTxHash);

    console.log("\n===== Contract Creation Details =====");
    console.log(`Transaction Hash: ${transaction.transaction_hash}`);
    console.log(`Transaction Type: ${transaction.type}`);
    console.log(`Transaction Version: ${transaction.version}`);
    console.log("======================================\n");
  } catch (error) {
    console.warn(`Warning: Could not retrieve transaction details: ${error}`);
  }
}
