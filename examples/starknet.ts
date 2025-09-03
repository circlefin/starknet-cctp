// Copyright (c) 2025, Circle Internet Financial LTD. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { RpcProvider, Contract, Account, CallData } from "starknet";
import { hexToBytesArray } from "./utils";
import {
  NODE_URL,
  ACCOUNT_ADDRESS,
  PRIVATE_KEY,
  MESSAGE_TRANSMITTER_ADDRESS,
  TOKEN_MESSENGER_MINTER_ADDRESS,
  BURN_TOKEN_ADDRESS,
  REMOTE_EVM_ADDRESS,
  REMOTE_EVM_DOMAIN,
  DESTINATION_CALLER,
} from "./config";

// Initialize provider and account
async function initializeAccount(nodeUrl: string, address: string, privateKey: string) {
  const provider = new RpcProvider({ nodeUrl });
  return new Account(provider, address, privateKey);
}

// Initialize contract with ABI
async function initializeContract(provider: RpcProvider, contractAddress: string) {
  const { abi } = await provider.getClassAt(contractAddress);
  if (!abi) {
    throw new Error(`Failed to retrieve ABI for contract: ${contractAddress}`);
  }
  return new Contract(abi, contractAddress, provider);
}

// Prepare message data for the contract call
function prepareMessageData(messageHex: string, attestationHex: string): any[] {
  try {
    const messageBytes = hexToBytesArray(messageHex);
    const attestationBytes = hexToBytesArray(attestationHex);
    return CallData.compile([...messageBytes, ...attestationBytes]);
  } catch (error) {
    throw new Error(`Failed to prepare message data: ${error}`);
  }
}

async function getContracts() {
  const usdcAddress = BURN_TOKEN_ADDRESS;

  // Initialize provider
  const provider = new RpcProvider({ nodeUrl: NODE_URL });

  // Initialize account
  const account = await initializeAccount(NODE_URL, ACCOUNT_ADDRESS!, PRIVATE_KEY!);

  // Initialize contract
  const messageTransmitter = await initializeContract(provider, MESSAGE_TRANSMITTER_ADDRESS);
  const tokenMessengerMinter = await initializeContract(provider, TOKEN_MESSENGER_MINTER_ADDRESS!);
  const usdcContract = await initializeContract(provider, usdcAddress!);

  // Connect account to contract
  messageTransmitter.providerOrAccount = account;
  tokenMessengerMinter.providerOrAccount = account;
  usdcContract.providerOrAccount = account;

  return { messageTransmitter, tokenMessengerMinter, usdcContract, provider };
}

export async function receiveMessage(messageHex: string, attestationHex: string) {
  try {
    const { messageTransmitter, provider } = await getContracts();

    // Prepare call data
    const callData = prepareMessageData(messageHex, attestationHex);

    console.log("Initiating receive message transaction...");

    // Execute receive message transaction
    const receiveMessageTx = await messageTransmitter.receive_message(callData);

    console.log(`Transaction submitted: ${receiveMessageTx.transaction_hash}`);

    // Wait for transaction confirmation
    const receipt = await provider.waitForTransaction(receiveMessageTx.transaction_hash);
    if (!receipt.isSuccess()) {
      throw new Error(
        `Receive message transaction failed, Transaction hash: ${receiveMessageTx.transaction_hash}, Error: ${receipt.value}`,
      );
    }

    console.log("Receive receipt:", receipt);
    return receiveMessageTx.transaction_hash;
  } catch (error) {
    console.error("Error in receiveMessage:", error);
    process.exit(1);
  }
}

async function approve(provider: RpcProvider, usdcContract: Contract, amount: number, address: string) {
  console.log("Approving USDC spend on Starknet...");
  const approveTx = await usdcContract.approve(address, amount);
  const approveTxReceipt = await provider.waitForTransaction(approveTx.transaction_hash);
  if (!approveTxReceipt.isSuccess()) {
    throw new Error(
      `Approve transaction failed, Transaction hash: ${approveTx.transaction_hash}, Error: ${approveTxReceipt.value}`,
    );
  }
  console.log("Approve receipt:", approveTxReceipt);
}

export async function depositForBurn(amount: number, maxFee: number, minFinalityThreshold: number, hookData?: string) {
  try {
    const { tokenMessengerMinter, usdcContract, provider } = await getContracts();

    // Approve USDC spend
    await approve(provider, usdcContract, amount, TOKEN_MESSENGER_MINTER_ADDRESS!);

    console.log("Initiating deposit for burn transaction...");

    // Execute deposit for burn transaction
    const depositTx = hookData
      ? await tokenMessengerMinter.deposit_for_burn_with_hook(
          amount,
          REMOTE_EVM_DOMAIN,
          REMOTE_EVM_ADDRESS,
          BURN_TOKEN_ADDRESS,
          DESTINATION_CALLER,
          maxFee,
          minFinalityThreshold,
          hookData,
        )
      : await tokenMessengerMinter.deposit_for_burn(
          amount,
          REMOTE_EVM_DOMAIN,
          REMOTE_EVM_ADDRESS,
          BURN_TOKEN_ADDRESS,
          DESTINATION_CALLER,
          maxFee,
          minFinalityThreshold,
        );

    console.log(`Transaction submitted: ${depositTx.transaction_hash}`);

    // Wait for transaction confirmation
    const receipt = await provider.waitForTransaction(depositTx.transaction_hash);
    if (!receipt.isSuccess()) {
      throw new Error(
        `Deposit transaction failed, Transaction hash: ${depositTx.transaction_hash}, Error: ${receipt.value}`,
      );
    }

    console.log("Deposit receipt:", receipt);
    return depositTx.transaction_hash;
  } catch (error) {
    console.error("Error in depositForBurn:", error);
    process.exit(1);
  }
}
