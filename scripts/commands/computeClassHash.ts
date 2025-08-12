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

import { hash } from "starknet";
import { program } from "commander";
import { readFileToJson, getTargetPath, ContractName, contractNameToPath } from "../utils.js";

export default program
  .createCommand("compute-class-hash")
  .description("Compute class hash from compiled contract (.contract_class.json) without declaring")
  .requiredOption("--contract-name <string>", "Contract name: messageTransmitterV2 or tokenMessengerMinterV2")
  .option(
    "--profile <string>",
    "Scarb profile that was used to build the contracts ('dev' or 'release'). Default profile is 'dev'",
    "dev",
  )
  .action(async (options) => {
    try {
      const result = await computeClassHash({
        profile: options.profile,
        contractName: options.contractName,
      });

      console.log(`Contract name: ${options.contractName}`);
      console.log(`Class hash: ${result.classHash}`);
    } catch (error) {
      console.error("Error:", error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  });

export async function computeClassHash({ profile, contractName }: { profile: string; contractName: ContractName }) {
  const localArtifactPath = getTargetPath(profile, `${contractNameToPath[contractName]}.contract_class.json`);

  try {
    // Read the compiled contract file
    const compiledSierraContract = await readFileToJson(localArtifactPath);

    // Compute the class hash using StarknetJS
    const classHash = hash.computeContractClassHash(compiledSierraContract);

    return {
      classHash,
    };
  } catch (error: any) {
    if (error.code === "ENOENT") {
      throw new Error(
        `Contract file not found: ${localArtifactPath}\n` +
          `Make sure the contract is compiled and the name is correct.\n`,
      );
    } else if (error instanceof SyntaxError) {
      throw new Error(
        `Invalid JSON in contract file: ${localArtifactPath}\n` +
          `Please ensure the contract file is properly formatted.`,
      );
    } else {
      throw new Error(`Failed to compute class hash: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
}
