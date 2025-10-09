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
import { CallData, stark, ec, hash } from "starknet";

const program = new Command();

export type TaskArguments = {
  ozClassHash: string;
};

export default program
  .createCommand("generate-account")
  .description("Generate an account on Starknet using OpenZeppelin's implementation")
  .requiredOption(
    "--oz-class-hash <string>",
    "The OpenZeppelin Account class hash that will be used for deploying the new account",
    // https://docs.openzeppelin.com/contracts-cairo/2.x/presets
    "0x079a9a12fdfa0481e8d8d46599b90226cd7247b2667358bb00636dd864002314",
  )
  .action(async (options: any) => {
    await generateAccount(options);
  });

export async function generateAccount(options: TaskArguments): Promise<void> {
  const privateKey = stark.randomAddress();
  const starkKeyPub = ec.starkCurve.getStarkKey(privateKey);
  const OZaccountConstructorCallData = CallData.compile({ publicKey: starkKeyPub });
  const OZcontractAddress = hash.calculateContractAddressFromHash(
    starkKeyPub,
    options.ozClassHash,
    OZaccountConstructorCallData,
    0,
  );

  console.log(`[Public Key]:\n  ${starkKeyPub}`);
  console.log(`[Private Key]:\n  ${privateKey}`);
  console.log(`[Address]:\n  ${OZcontractAddress}`);

  console.log(
    `***************\nPlease fund the Starknet account with STARK before proceeding. This is required to deploy the contract. Then use below command to deploy the account:
***************\n
[sepolia]
    yarn scripts deploy-account \\
      --account-address ${OZcontractAddress} \\
      --account-private-key ${privateKey} \\
      --oz-class-hash ${options.ozClassHash} \\
      -r "https://starknet-sepolia.public.blastapi.io/rpc/v0_9"
[mainnet]
    yarn scripts deploy-account \\
      --account-address ${OZcontractAddress} \\
      --account-private-key ${privateKey} \\
      --oz-class-hash ${options.ozClassHash} \\
      -r "https://starknet-mainnet.public.blastapi.io/rpc/v0_9"`,
  );
}
