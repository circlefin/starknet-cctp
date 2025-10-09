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

import { program } from "commander";
import deployAndInitialize from "./commands/deployAndInitialize.js";
import verifyOnchainBytecode from "./commands/verifyOnchainBytecode.js";
import computeClassHash from "./commands/computeClassHash.js";
import verifyContractState from "./commands/verifyContractState.js";
import calculateDeploymentAddress from "./commands/calculateDeploymentAddress.js";
import generateAccount from "./commands/generateAccount.js";
import deployAccount from "./commands/deployAccount.js";

program.name("scripts").description("Scripts related to Starknet contract development.");

program.addCommand(deployAndInitialize);
program.addCommand(verifyOnchainBytecode);
program.addCommand(computeClassHash);
program.addCommand(verifyContractState);
program.addCommand(calculateDeploymentAddress);
program.addCommand(generateAccount);
program.addCommand(deployAccount);

if (process.env.NODE_ENV !== "TESTING") {
  program.parse();
}
