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

import "dotenv/config";
import { minimist } from "zx";
import { depositForBurn, receiveMessage } from "./starknet";
import { depositForBurnEvm, depositForBurnEvmWithHook, receiveMessageEvm } from "./evm";
import { IRIS_API_URL, REMOTE_EVM_DOMAIN, STARKNET_DOMAIN_ID } from "./config";

enum CommandName {
  Strk2Evm = "strk2evm",
  Evm2Strk = "evm2strk",
}

interface ParsedArgs {
  amount: number;
  fastBurn: boolean;
  hookData: string;
}

interface AttestationResponse {
  error?: string;
  messages?: {
    message: string;
    attestation: string;
  }[];
}

interface BurnFee {
  finalityThreshold: number;
  minimumFee: number;
}

function getMaxFee(amount: number, minimumFee: number) {
  // minimumFee is in bps, convert to % and multiple by amount to get actual fee
  return (amount * minimumFee) / 100;
}

const main = async () => {
  const commandName: CommandName = process.argv.slice(2)[0] as CommandName;

  const rawArgs = minimist(process.argv.slice(3), {
    string: ["amount", "fastBurn", "hookData"],
  });
  const args: ParsedArgs = {
    amount: Number(rawArgs.amount),
    fastBurn: Boolean(rawArgs.fastBurn),
    hookData: rawArgs.hookData,
  };
  console.log("args", args);

  if (commandName === CommandName.Strk2Evm) {
    const burnFee = await fetchBurnFee(STARKNET_DOMAIN_ID, REMOTE_EVM_DOMAIN);
    const { minimumFee, finalityThreshold: minFinalityThreshold } = args.fastBurn ? burnFee.fast : burnFee.slow;
    const maxFee = getMaxFee(args.amount, minimumFee);

    const depositTxHash = await depositForBurn(args.amount, maxFee, minFinalityThreshold, args.hookData);
    console.log("DepositForBurn txHash:", depositTxHash);
    const attestationResponse = await fetchAttestation(depositTxHash, STARKNET_DOMAIN_ID);

    const receiveTxHash = await receiveMessageEvm(attestationResponse.message, attestationResponse.attestation);
    console.log("ReceiveMessage txHash:", receiveTxHash);
  } else if (commandName === CommandName.Evm2Strk) {
    const burnFee = await fetchBurnFee(REMOTE_EVM_DOMAIN, STARKNET_DOMAIN_ID);
    const { minimumFee, finalityThreshold: minFinalityThreshold } = args.fastBurn ? burnFee.fast : burnFee.slow;
    const maxFee = getMaxFee(args.amount, minimumFee);

    const depositTxHash = args.hookData
      ? await depositForBurnEvmWithHook(args.amount, maxFee, minFinalityThreshold, args.hookData)
      : await depositForBurnEvm(args.amount, maxFee, minFinalityThreshold);
    console.log("DepositForBurn txHash:", depositTxHash);

    const attestationResponse = await fetchAttestation(depositTxHash, REMOTE_EVM_DOMAIN);
    const receiveTxHash = await receiveMessage(attestationResponse.message, attestationResponse.attestation);
    console.log("ReceiveMessage txHash:", receiveTxHash);
  } else {
    console.error("Command must be one of: ", Object.values(CommandName).join(", "));
    process.exit(1);
  }
};

async function fetchAttestation(txHash: string, domainId: number) {
  console.log("Fetching attestation...");
  let attestationResponse: AttestationResponse = {};

  while (true) {
    const response = await fetch(`${IRIS_API_URL}/v2/messages/${domainId}?transactionHash=${txHash}`);
    attestationResponse = await response.json();
    // Wait 2 seconds to avoid getting rate limited
    if (
      attestationResponse.error ||
      !attestationResponse.messages ||
      attestationResponse.messages?.[0]?.attestation === "PENDING"
    ) {
      await new Promise((r) => setTimeout(r, 2000));
    } else {
      break;
    }
  }

  console.debug("Attestation response:", attestationResponse);
  return attestationResponse.messages[0];
}

async function fetchBurnFee(sourceDomainId: number, destDomainId: number) {
  console.log("Fetching Fees...");

  const response = await fetch(`${IRIS_API_URL}/v2/burn/usdc/fees/${sourceDomainId}/${destDomainId}`);
  if (!response.ok) {
    console.warn(`Failed to fetch burn fees: ${response.statusText}, use the default fees`);
    return {
      fast: {
        finalityThreshold: 1000,
        minimumFee: 1,
      },
      slow: {
        finalityThreshold: 2000,
        minimumFee: 1,
      },
    };
  }

  const fees: BurnFee[] = await response.json();
  const result: {
    fast: BurnFee;
    slow: BurnFee;
  } = {
    fast: fees.find((fee) => fee.finalityThreshold === 1000) ?? {
      finalityThreshold: 1000,
      minimumFee: 1,
    },
    slow: fees.find((fee) => fee.finalityThreshold === 2000) ?? {
      finalityThreshold: 2000,
      minimumFee: 1,
    },
  };

  return result;
}

main();
