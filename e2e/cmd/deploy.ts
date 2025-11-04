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

import { fileURLToPath } from "url";
import { dirname } from "path";
import { json, Account, byteArray } from "starknet";
import * as fs from "fs/promises";
import * as path from "path";
import { loadMessageTransmitter, loadTokenMessengerMinter, loadStablecoin, provider } from "../utils.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const LOCAL_DOMAIN = 25; // Starknet domain id
const VERSION = 1;

async function deployStablecoin(accounts: any): Promise<string> {
  console.log("Deploying Stablecoin...");
  const deployer = new Account({
    provider,
    address: accounts.stablecoin.deployer.address,
    signer: accounts.stablecoin.deployer.privateKey,
  });
  const stablecoinSierra = json.parse(
    await fs.readFile(
      path.join(__dirname, "../../stablecoin-starknet-private/target/dev/stablecoin_FiatToken.contract_class.json"),
      "utf8",
    ),
  );
  const stablecoinCasm = json.parse(
    await fs.readFile(
      path.join(
        __dirname,
        "../../stablecoin-starknet-private/target/dev/stablecoin_FiatToken.compiled_contract_class.json",
      ),
      "utf8",
    ),
  );
  const stablecoinDeployResponse = await deployer.declareAndDeploy({
    contract: stablecoinSierra,
    casm: stablecoinCasm,
    salt: "0x0",
    constructorCalldata: [
      byteArray.byteArrayFromString("USDC"),
      byteArray.byteArrayFromString("USDC"),
      6,
      accounts.stablecoin.master_minter.address,
      accounts.stablecoin.owner.address,
      accounts.stablecoin.pauser.address,
      accounts.stablecoin.blocklister.address,
      accounts.stablecoin.metadata_updater.address,
      accounts.stablecoin.admin.address,
    ],
  });
  console.log(`✅ Stablecoin deployed: ${stablecoinDeployResponse.deploy.contract_address}`);
  // Save Stablecoin ABI
  const stablecoinAbiPath = path.join(__dirname, "../resources/stablecoin.abi.json");
  await fs.writeFile(stablecoinAbiPath, JSON.stringify(stablecoinSierra.abi, null, 2));
  console.log(`✅ Stablecoin ABI saved to: ${stablecoinAbiPath}`);
  return stablecoinDeployResponse.deploy.contract_address;
}

async function deployMessageTransmitter(accounts: any): Promise<string> {
  console.log("Deploying Message Transmitter...");
  const adminAddress = accounts.message_transmitter.admin.address;
  const deployer = new Account({
    provider,
    address: accounts.message_transmitter.deployer.address,
    signer: accounts.message_transmitter.deployer.privateKey,
  });
  const mtSierra = json.parse(
    await fs.readFile(
      path.join(__dirname, "../../target/dev/message_transmitter_MessageTransmitterV2.contract_class.json"),
      "utf8",
    ),
  );
  const mtCasm = json.parse(
    await fs.readFile(
      path.join(__dirname, "../../target/dev/message_transmitter_MessageTransmitterV2.compiled_contract_class.json"),
      "utf8",
    ),
  );
  const mtDeployResponse = await deployer.declareAndDeploy({
    contract: mtSierra,
    casm: mtCasm,
    salt: "0x0",
    constructorCalldata: [adminAddress],
  });
  console.log(`✅ Message Transmitter deployed: ${mtDeployResponse.deploy.contract_address}`);

  // Save Message Transmitter ABI
  const mtAbiPath = path.join(__dirname, "../resources/message_transmitter_v2.abi.json");
  await fs.writeFile(mtAbiPath, JSON.stringify(mtSierra.abi, null, 2));
  console.log(`✅ Message Transmitter ABI saved to: ${mtAbiPath}`);
  return mtDeployResponse.deploy.contract_address;
}

async function deployTokenMessengerMinter(accounts: any): Promise<string> {
  console.log("Deploying Token Messenger Minter...");
  const adminAddress = accounts.token_messenger_minter.admin.address;
  const deployer = new Account({
    provider,
    address: accounts.token_messenger_minter.deployer.address,
    signer: accounts.token_messenger_minter.deployer.privateKey,
  });
  const tmmSierra = json.parse(
    await fs.readFile(
      path.join(__dirname, "../../target/dev/token_messenger_minter_TokenMessengerMinterV2.contract_class.json"),
      "utf8",
    ),
  );

  const tmmCasm = json.parse(
    await fs.readFile(
      path.join(
        __dirname,
        "../../target/dev/token_messenger_minter_TokenMessengerMinterV2.compiled_contract_class.json",
      ),
      "utf8",
    ),
  );

  const tmmDeployResponse = await deployer.declareAndDeploy({
    contract: tmmSierra,
    casm: tmmCasm,
    salt: "0x0",
    constructorCalldata: [adminAddress],
  });

  console.log(`✅ Token Messenger Minter deployed: ${tmmDeployResponse.deploy.contract_address}`);

  // Save Token Messenger Minter ABI
  const tmmAbiPath = path.join(__dirname, "../resources/token_messenger_minter_v2.abi.json");
  await fs.writeFile(tmmAbiPath, JSON.stringify(tmmSierra.abi, null, 2));
  console.log(`✅ Token Messenger Minter ABI saved to: ${tmmAbiPath}`);
  return tmmDeployResponse.deploy.contract_address;
}

async function initializeStablecoin(tmmContractAddress: string) {
  // Initialize Stablecoin
  const stablecoin = await loadStablecoin();
  stablecoin.contract.providerOrAccount = stablecoin.master_minter;
  // Enable token messenger minter to mint
  await stablecoin.contract.configure_controller(
    stablecoin.master_minter.address, // controller for minter
    tmmContractAddress, // minter address
  );
  await stablecoin.contract.configure_minter(
    1_000000_000000_000000n, // 1 trillion USDC
  );
  // Enable additional minter to mint
  await stablecoin.contract.configure_controller(
    stablecoin.master_minter.address, // controller for minter
    stablecoin.minter.address, // minter address
  );
  await stablecoin.contract.configure_minter(
    1_000000_000000_000000n, // 1 trillion USDC
  );
  console.log("✅ Stablecoin initialized");
}

async function initializeTokenMessengerMinter(mtContractAddress: string) {
  // Initialize Token Messenger Minter
  const tokenMessengerMinter = await loadTokenMessengerMinter();
  tokenMessengerMinter.contract.providerOrAccount = tokenMessengerMinter.admin;
  await tokenMessengerMinter.contract.initialize(
    tokenMessengerMinter.owner.address,
    tokenMessengerMinter.pauser.address,
    tokenMessengerMinter.denylister.address,
    tokenMessengerMinter.rescuer.address,
    tokenMessengerMinter.token_controller.address,
    tokenMessengerMinter.min_fee_controller.address,
    tokenMessengerMinter.fee_recipient.address,
    1,
    mtContractAddress,
    [1, 2, 3], // Remote domains
    ["0x1000", "0x2000", "0x3000"], // Remote token messengers
  );
  console.log("✅ Token Messenger Minter initialized");
}

async function initializeMessageTransmitter() {
  // Initialize Message Transmitter
  const messageTransmitter = await loadMessageTransmitter();
  messageTransmitter.contract.providerOrAccount = messageTransmitter.admin;
  await messageTransmitter.contract.initialize(
    LOCAL_DOMAIN, // local domain
    VERSION, // version
    messageTransmitter.owner.address,
    messageTransmitter.pauser.address,
    messageTransmitter.rescuer.address,
    messageTransmitter.attester_manager.address,
    messageTransmitter.attesters.map((attester) => attester.address),
    2,
    1024,
  );
  console.log("✅ Message Transmitter initialized");
}

async function deploy() {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, "../resources/accounts.json"), "utf8"));

  console.log("🚀 Starting contract deployment...");
  const stablecoinContractAddress = await deployStablecoin(accounts);
  const mtContractAddress = await deployMessageTransmitter(accounts);
  const tmmContractAddress = await deployTokenMessengerMinter(accounts);

  // Save contract addresses to contracts.json
  const contracts = {
    tokenMessengerMinterV2: tmmContractAddress,
    messageTransmitterV2: mtContractAddress,
    stablecoin: stablecoinContractAddress,
  };

  const contractsPath = path.join(__dirname, "../resources/contracts.json");
  await fs.writeFile(contractsPath, JSON.stringify(contracts, null, 2));
  console.log(`✅ Contract addresses saved to: ${contractsPath}`);

  await initializeStablecoin(tmmContractAddress);
  await initializeMessageTransmitter();
  await initializeTokenMessengerMinter(mtContractAddress);
}

// Run deployment if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    await deploy();
    console.log("✅ All deployments completed successfully!");
    process.exit(0);
  } catch (error) {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }
}
