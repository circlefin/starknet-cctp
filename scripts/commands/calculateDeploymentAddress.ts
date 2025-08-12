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

export default program
  .createCommand("calculate-deployment-address")
  .description("Calculate the address that the contract will be deployed to")
  .option("--salt <string>", "Salt for address calculation (optional, defaults to 0)", "0")
  .requiredOption("--class-hash <string>", "The class hash for the contract")
  .option("--constructor-calldata [string...]", "Constructor calldata (optional, defaults to empty array)")
  .action((options) => {
    const { classHash, contractAddress } = calculateDeploymentAddress(options);

    console.log(`class hash: ${classHash}`);
    console.log(`contract address: ${contractAddress}`);
  });

export function calculateDeploymentAddress({
  salt = "0",
  classHash,
  constructorCalldata = [],
}: {
  salt?: string;
  classHash: string;
  constructorCalldata?: string[];
}) {
  // Validate stablecoinClassHash is not zero
  if (!classHash || classHash === "0" || classHash === "0x0" || classHash === "0x") {
    throw new Error("classHash cannot be zero or empty. Please provide a valid class hash.");
  }

  const contractAddress = hash.calculateContractAddressFromHash(
    salt,
    classHash,
    constructorCalldata,
    // Use "0" as the deployer address since we do not use unique option
    // unique option = non deterministic address
    // https://github.com/starknet-io/starknet.js/blob/7870847048880843031639b3c357fbea2c9d177e/src/utils/transaction.ts#L227-L231
    "0",
  );

  return {
    classHash,
    contractAddress: contractAddress.toString(),
  };
}
