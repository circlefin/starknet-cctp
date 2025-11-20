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
import { Account, ec, CallData } from "starknet";
import { getStarknetProvider } from "../utils.js";

const program = new Command();

export type TaskArguments = {
  rpcUrl: string;
  ozClassHash: string;
  accountAddress: string;
  accountPrivateKey: string;
};

export default program
  .createCommand("deploy-account")
  .description("Deploy an account on Starknet using OpenZeppelin's implementation")
  .requiredOption("-r, --rpc-url <string>", "Starknet RPC URL")
  .requiredOption("--account-address <string>", "The account address to deploy")
  .requiredOption("--account-private-key <string>", "The account private key to deploy")
  .requiredOption(
    "--oz-class-hash <string>",
    "The OpenZeppelin Account class hash that will be used for deploying the new account",
    // https://docs.openzeppelin.com/contracts-cairo/2.x/presets
    "0x079a9a12fdfa0481e8d8d46599b90226cd7247b2667358bb00636dd864002314",
  )
  .action(async (options: any) => {
    await deployAccount(options);
  });

export async function deployAccount(options: TaskArguments): Promise<void> {
  const privateKey = options.accountPrivateKey;
  const starkKeyPub = ec.starkCurve.getStarkKey(privateKey);
  const OZcontractAddress = options.accountAddress;
  const provider = getStarknetProvider(options.rpcUrl);
  const account = new Account({
    provider: provider,
    address: OZcontractAddress,
    signer: privateKey,
  });
  const { transaction_hash, contract_address } = await account.deployAccount({
    classHash: options.ozClassHash,
    constructorCalldata: CallData.compile({ publicKey: starkKeyPub }),
    addressSalt: starkKeyPub,
  });

  await provider.waitForTransaction(transaction_hash);

  console.log(`Deployed Account Address: ${contract_address}`);
  if (contract_address !== OZcontractAddress) {
    throw new Error(
      `Deployed account address does not match the expected address. Expected: ${OZcontractAddress}, Got: ${contract_address}`,
    );
  }
}
