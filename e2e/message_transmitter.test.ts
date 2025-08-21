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

import { CallData, num } from "starknet";
import {
  loadMessageTransmitter,
  loadTokenMessengerMinter,
  MessageTransmitterInfo,
  provider,
  ByteArray,
  numberArrayToHexString,
  uint8ArrayToHexString,
  appendU32BE,
  appendU256BE,
  appendZeroU256,
  stringToBytes,
  constructMessage,
  TokenMessengerMinterInfo,
  loadStablecoin,
  StablecoinInfo,
  constructBurnMessage,
} from "./utils.js";
import type { Account } from "starknet";
import * as ethers from "ethers";
import { randomInt } from "crypto";

describe("message transmitter", () => {
  let messageTransmitter: MessageTransmitterInfo;
  let tokenMessengerMinter: TokenMessengerMinterInfo;
  let stablecoin: StablecoinInfo;

  beforeAll(async () => {
    messageTransmitter = await loadMessageTransmitter();
    tokenMessengerMinter = await loadTokenMessengerMinter();
    stablecoin = await loadStablecoin();
  });

  describe("manageable", () => {
    it("should have admin account and handle admin transfer flow", async () => {
      // 1. Check initial admin
      const initialAdmin = num.toHex(await messageTransmitter.contract.admin());
      expect(initialAdmin).toBe(num.toHex(messageTransmitter.admin.address));

      // 2. Check initial pending_admin (should be zero)
      const initialPendingAdmin = num.toHex(await messageTransmitter.contract.pending_admin());
      expect(initialPendingAdmin).toBe("0x0");

      // 3. Transfer admin to tester address (as admin)
      messageTransmitter.contract.connect(messageTransmitter.admin);
      const testerAddress = messageTransmitter.tester.address;
      const transferTx = await messageTransmitter.contract.transfer_admin(testerAddress);
      const transferReceipt = await provider.waitForTransaction(transferTx.transaction_hash);

      // Verify AdminChangeStarted event
      expect(transferReceipt.isSuccess()).toBe(true);
      const transferEvents = messageTransmitter.contract.parseEvents(transferReceipt);
      expect(transferEvents).toEqual([
        expect.objectContaining({
          "components::manageable::events::AdminChangeStarted": {
            old_admin: num.toBigInt(messageTransmitter.admin.address),
            new_admin: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 4. Check pending_admin (should now be tester)
      const pendingAdminAfterTransfer = num.toHex(await messageTransmitter.contract.pending_admin());
      expect(pendingAdminAfterTransfer).toBe(num.toHex(testerAddress));

      // 5. Accept admin (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const acceptTx = await messageTransmitter.contract.accept_admin();
      const acceptReceipt = await provider.waitForTransaction(acceptTx.transaction_hash);

      // Verify AdminChanged event
      expect(acceptReceipt.isSuccess()).toBe(true);
      const acceptEvents = messageTransmitter.contract.parseEvents(acceptReceipt);
      expect(acceptEvents).toEqual([
        expect.objectContaining({
          "components::manageable::events::AdminChanged": {
            old_admin: num.toBigInt(messageTransmitter.admin.address),
            new_admin: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 6. Check admin (should now be tester)
      const adminAfterAccept = num.toHex(await messageTransmitter.contract.admin());
      expect(adminAfterAccept).toBe(num.toHex(testerAddress));

      // 7. Check pending_admin (should be zero again)
      const pendingAdminAfterAccept = num.toHex(await messageTransmitter.contract.pending_admin());
      expect(pendingAdminAfterAccept).toBe("0x0");

      // 8. Transfer admin back to original admin (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const originalAdminAddress = messageTransmitter.admin.address;
      await messageTransmitter.contract.transfer_admin(originalAdminAddress);

      // 9. Accept admin back (as original admin)
      messageTransmitter.contract.connect(messageTransmitter.admin);
      await messageTransmitter.contract.accept_admin();

      // 10. Verify admin is back to original
      const finalAdmin = num.toHex(await messageTransmitter.contract.admin());
      expect(finalAdmin).toBe(num.toHex(originalAdminAddress));

      // 11. Verify pending_admin is zero
      const finalPendingAdmin = num.toHex(await messageTransmitter.contract.pending_admin());
      expect(finalPendingAdmin).toBe("0x0");
    });
  });

  describe("ownable", () => {
    it("should have owner account and handle ownership transfer flow", async () => {
      // 1. Check initial owner
      const initialOwner = num.toHex(await messageTransmitter.contract.owner());
      expect(initialOwner).toBe(num.toHex(messageTransmitter.owner.address));

      // 2. Check initial pending_owner (should be zero)
      const initialPendingOwner = num.toHex(await messageTransmitter.contract.pending_owner());
      expect(initialPendingOwner).toBe("0x0");

      // 3. Transfer ownership to tester address (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const testerAddress = messageTransmitter.tester.address;
      const transferTx = await messageTransmitter.contract.transfer_ownership(testerAddress);
      const transferReceipt = await provider.waitForTransaction(transferTx.transaction_hash);

      // Verify OwnershipTransferStarted event
      expect(transferReceipt.isSuccess()).toBe(true);
      const transferEvents = messageTransmitter.contract.parseEvents(transferReceipt);
      expect(transferEvents).toEqual([
        expect.objectContaining({
          "components::ownable::events::OwnershipTransferStarted": {
            old_owner: num.toBigInt(messageTransmitter.owner.address),
            new_owner: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 4. Check pending_owner (should now be tester)
      const pendingOwnerAfterTransfer = num.toHex(await messageTransmitter.contract.pending_owner());
      expect(pendingOwnerAfterTransfer).toBe(num.toHex(testerAddress));

      // 5. Accept ownership (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const acceptTx = await messageTransmitter.contract.accept_ownership();
      const acceptReceipt = await provider.waitForTransaction(acceptTx.transaction_hash);

      // Verify OwnershipTransferred event
      expect(acceptReceipt.isSuccess()).toBe(true);
      const acceptEvents = messageTransmitter.contract.parseEvents(acceptReceipt);
      expect(acceptEvents).toEqual([
        expect.objectContaining({
          "components::ownable::events::OwnershipTransferred": {
            old_owner: num.toBigInt(messageTransmitter.owner.address),
            new_owner: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 6. Check owner (should now be tester)
      const ownerAfterAccept = num.toHex(await messageTransmitter.contract.owner());
      expect(ownerAfterAccept).toBe(num.toHex(testerAddress));

      // 7. Check pending_owner (should be zero again)
      const pendingOwnerAfterAccept = num.toHex(await messageTransmitter.contract.pending_owner());
      expect(pendingOwnerAfterAccept).toBe("0x0");

      // 8. Transfer ownership back to original owner (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const originalOwnerAddress = messageTransmitter.owner.address;
      await messageTransmitter.contract.transfer_ownership(originalOwnerAddress);

      // 9. Accept ownership back (as original owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      await messageTransmitter.contract.accept_ownership();

      // 10. Verify owner is back to original
      const finalOwner = num.toHex(await messageTransmitter.contract.owner());
      expect(finalOwner).toBe(num.toHex(originalOwnerAddress));

      // 11. Verify pending_owner is zero
      const finalPendingOwner = num.toHex(await messageTransmitter.contract.pending_owner());
      expect(finalPendingOwner).toBe("0x0");
    });
  });

  describe("pausable", () => {
    it("should manage pauser and pause/unpause functionality", async () => {
      // 1. Check initial pauser
      const initialPauser = num.toHex(await messageTransmitter.contract.pauser());
      expect(initialPauser).toBe(num.toHex(messageTransmitter.pauser.address));

      // 2. Check initial paused state (should be false)
      const initialPaused = await messageTransmitter.contract.paused();
      expect(initialPaused).toBe(false);

      // 3. Pause the contract (as pauser)
      messageTransmitter.contract.connect(messageTransmitter.pauser);
      const pauseTx = await messageTransmitter.contract.pause();
      const pauseReceipt = await provider.waitForTransaction(pauseTx.transaction_hash);

      // Verify Paused event
      expect(pauseReceipt.isSuccess()).toBe(true);
      const pauseEvents = messageTransmitter.contract.parseEvents(pauseReceipt);
      expect(pauseEvents).toEqual([
        expect.objectContaining({
          "components::pausable::events::Paused": {},
        }),
      ]);

      // 4. Check paused state (should be true)
      const pausedAfterPause = await messageTransmitter.contract.paused();
      expect(pausedAfterPause).toBe(true);

      // 5. Unpause the contract (as pauser)
      messageTransmitter.contract.connect(messageTransmitter.pauser);
      const unpauseTx = await messageTransmitter.contract.unpause();
      const unpauseReceipt = await provider.waitForTransaction(unpauseTx.transaction_hash);

      // Verify Unpaused event
      expect(unpauseReceipt.isSuccess()).toBe(true);
      const unpauseEvents = messageTransmitter.contract.parseEvents(unpauseReceipt);
      expect(unpauseEvents).toEqual([
        expect.objectContaining({
          "components::pausable::events::Unpaused": {},
        }),
      ]);

      // 6. Check paused state (should be false)
      const pausedAfterUnpause = await messageTransmitter.contract.paused();
      expect(pausedAfterUnpause).toBe(false);

      // 7. Update pauser to tester (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const testerAddress = messageTransmitter.tester.address;
      const updatePauserTx = await messageTransmitter.contract.update_pauser(testerAddress);
      const updatePauserReceipt = await provider.waitForTransaction(updatePauserTx.transaction_hash);

      // Verify PauserChanged event
      expect(updatePauserReceipt.isSuccess()).toBe(true);
      const updatePauserEvents = messageTransmitter.contract.parseEvents(updatePauserReceipt);
      expect(updatePauserEvents).toEqual([
        expect.objectContaining({
          "components::pausable::events::PauserChanged": {
            old_pauser: num.toBigInt(initialPauser),
            new_pauser: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 8. Check new pauser
      const newPauser = num.toHex(await messageTransmitter.contract.pauser());
      expect(newPauser).toBe(num.toHex(testerAddress));

      // 9. Pause with new pauser (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const pauseWithNewPauserTx = await messageTransmitter.contract.pause();
      const pauseWithNewPauserReceipt = await provider.waitForTransaction(pauseWithNewPauserTx.transaction_hash);

      // Verify Paused event
      expect(pauseWithNewPauserReceipt.isSuccess()).toBe(true);
      const pauseWithNewPauserEvents = messageTransmitter.contract.parseEvents(pauseWithNewPauserReceipt);
      expect(pauseWithNewPauserEvents).toEqual([
        expect.objectContaining({
          "components::pausable::events::Paused": {},
        }),
      ]);

      // 10. Check paused state (should be true)
      const finalPausedState = await messageTransmitter.contract.paused();
      expect(finalPausedState).toBe(true);

      // 11. Unpause with new pauser to restore state (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      await messageTransmitter.contract.unpause();

      // 12. Update pauser back to original (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      await messageTransmitter.contract.update_pauser(messageTransmitter.pauser.address);

      // 13. Verify pauser is back to original
      const restoredPauser = num.toHex(await messageTransmitter.contract.pauser());
      expect(restoredPauser).toBe(num.toHex(messageTransmitter.pauser.address));
    });
  });

  describe("attestable", () => {
    it("should manage attesters and signature threshold", async () => {
      // 1. Check initial attester manager
      const initialAttesterManager = num.toHex(await messageTransmitter.contract.attester_manager());
      expect(initialAttesterManager).toBe(num.toHex(messageTransmitter.attester_manager.address));

      // 2. Get initial enabled attesters
      const initialAttesters = await messageTransmitter.contract.get_enabled_attesters();
      const initialAttesterCount = initialAttesters.length;

      // 3. Get initial signature threshold
      const initialThreshold = await messageTransmitter.contract.get_signature_threshold();

      // 4. Enable a new attester (as attester manager)
      messageTransmitter.contract.connect(messageTransmitter.attester_manager);
      const newAttester = "0x1234567890123456789012345678901234567890";
      const enableAttesterTx = await messageTransmitter.contract.enable_attester(newAttester);
      const enableAttesterReceipt = await provider.waitForTransaction(enableAttesterTx.transaction_hash);

      // Verify AttesterEnabled event
      expect(enableAttesterReceipt.isSuccess()).toBe(true);
      const enableAttesterEvents = messageTransmitter.contract.parseEvents(enableAttesterReceipt);
      expect(enableAttesterEvents).toEqual([
        expect.objectContaining({
          "cctp_components::attestable::AttestableComponent::AttesterEnabled": {
            attester: num.toBigInt(newAttester),
          },
        }),
      ]);

      // 5. Check attester is enabled
      const isEnabled = await messageTransmitter.contract.is_enabled_attester(newAttester);
      expect(isEnabled).toBe(true);

      // 6. Check attesters count increased
      const attestersAfterEnable = await messageTransmitter.contract.get_enabled_attesters();
      expect(attestersAfterEnable.length).toBe(initialAttesterCount + 1);

      // 7. Update signature threshold (as attester manager)
      const newThreshold = initialThreshold + 1n;
      messageTransmitter.contract.connect(messageTransmitter.attester_manager);
      const setThresholdTx = await messageTransmitter.contract.set_signature_threshold(newThreshold);
      const setThresholdReceipt = await provider.waitForTransaction(setThresholdTx.transaction_hash);

      // Verify SignatureThresholdUpdated event
      expect(setThresholdReceipt.isSuccess()).toBe(true);
      const setThresholdEvents = messageTransmitter.contract.parseEvents(setThresholdReceipt);
      expect(setThresholdEvents).toEqual([
        expect.objectContaining({
          "cctp_components::attestable::AttestableComponent::SignatureThresholdUpdated": {
            previous_signature_threshold: initialThreshold,
            new_signature_threshold: newThreshold,
          },
        }),
      ]);

      // 8. Check new threshold
      const updatedThreshold = await messageTransmitter.contract.get_signature_threshold();
      expect(updatedThreshold).toBe(newThreshold);

      // 9. Restore threshold back (as attester manager)
      messageTransmitter.contract.connect(messageTransmitter.attester_manager);
      await messageTransmitter.contract.set_signature_threshold(initialThreshold);

      // 10. Disable the attester (as attester manager)
      messageTransmitter.contract.connect(messageTransmitter.attester_manager);
      const disableAttesterTx = await messageTransmitter.contract.disable_attester(newAttester);
      const disableAttesterReceipt = await provider.waitForTransaction(disableAttesterTx.transaction_hash);

      // Verify AttesterDisabled event
      expect(disableAttesterReceipt.isSuccess()).toBe(true);
      const disableAttesterEvents = messageTransmitter.contract.parseEvents(disableAttesterReceipt);
      expect(disableAttesterEvents).toEqual([
        expect.objectContaining({
          "cctp_components::attestable::AttestableComponent::AttesterDisabled": {
            attester: num.toBigInt(newAttester),
          },
        }),
      ]);

      // 11. Check attester is disabled
      const isEnabledAfterDisable = await messageTransmitter.contract.is_enabled_attester(newAttester);
      expect(isEnabledAfterDisable).toBe(false);

      // 12. Check attesters count back to original
      const finalAttesters = await messageTransmitter.contract.get_enabled_attesters();
      expect(finalAttesters.length).toBe(initialAttesterCount);
    });

    it("should update attester manager", async () => {
      // 1. Check initial attester manager
      const initialAttesterManager = num.toHex(await messageTransmitter.contract.attester_manager());
      expect(initialAttesterManager).toBe(num.toHex(messageTransmitter.attester_manager.address));

      // 2. Update attester manager to tester (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const testerAddress = messageTransmitter.tester.address;
      const updateAttesterManagerTx = await messageTransmitter.contract.update_attester_manager(testerAddress);
      const updateAttesterManagerReceipt = await provider.waitForTransaction(updateAttesterManagerTx.transaction_hash);

      // Verify AttesterManagerUpdated event
      expect(updateAttesterManagerReceipt.isSuccess()).toBe(true);
      const updateAttesterManagerEvents = messageTransmitter.contract.parseEvents(updateAttesterManagerReceipt);
      expect(updateAttesterManagerEvents).toEqual([
        expect.objectContaining({
          "cctp_components::attestable::AttestableComponent::AttesterManagerUpdated": {
            previous_attester_manager: num.toBigInt(messageTransmitter.attester_manager.address),
            new_attester_manager: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 3. Check new attester manager
      const newAttesterManager = num.toHex(await messageTransmitter.contract.attester_manager());
      expect(newAttesterManager).toBe(num.toHex(testerAddress));

      // 4. Enable an attester with new attester manager (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      const testAttester = "0xabcdef1234567890abcdef1234567890abcdef12";
      const enableAttesterTx = await messageTransmitter.contract.enable_attester(testAttester);
      const enableAttesterReceipt = await provider.waitForTransaction(enableAttesterTx.transaction_hash);

      // Verify that new attester manager can enable attesters
      expect(enableAttesterReceipt.isSuccess()).toBe(true);

      // 5. Disable the test attester (as tester)
      messageTransmitter.contract.connect(messageTransmitter.tester);
      await messageTransmitter.contract.disable_attester(testAttester);

      // 6. Update attester manager back to original (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const originalAttesterManagerAddress = messageTransmitter.attester_manager.address;
      await messageTransmitter.contract.update_attester_manager(originalAttesterManagerAddress);

      // 7. Verify attester manager is back to original
      const restoredAttesterManager = num.toHex(await messageTransmitter.contract.attester_manager());
      expect(restoredAttesterManager).toBe(num.toHex(originalAttesterManagerAddress));
    });
  });

  describe("rescuable", () => {
    it("should read and update rescuer", async () => {
      // 1. Check initial rescuer
      const initialRescuer = num.toHex(await messageTransmitter.contract.rescuer());
      expect(initialRescuer).toBe(num.toHex(messageTransmitter.rescuer.address));

      // 2. Update rescuer to tester (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const testerAddress = messageTransmitter.tester.address;
      const updateRescuerTx = await messageTransmitter.contract.update_rescuer(testerAddress);
      const updateRescuerReceipt = await provider.waitForTransaction(updateRescuerTx.transaction_hash);

      // Verify RescuerChanged event
      expect(updateRescuerReceipt.isSuccess()).toBe(true);
      const updateRescuerEvents = messageTransmitter.contract.parseEvents(updateRescuerReceipt);
      expect(updateRescuerEvents).toEqual([
        expect.objectContaining({
          "cctp_components::rescuable::RescuableComponent::RescuerChanged": {
            new_rescuer: num.toBigInt(testerAddress),
          },
        }),
      ]);

      // 3. Check new rescuer
      const newRescuer = num.toHex(await messageTransmitter.contract.rescuer());
      expect(newRescuer).toBe(num.toHex(testerAddress));

      // 4. Update rescuer back to original (as owner)
      messageTransmitter.contract.connect(messageTransmitter.owner);
      const updateBackTx = await messageTransmitter.contract.update_rescuer(messageTransmitter.rescuer.address);
      const updateBackReceipt = await provider.waitForTransaction(updateBackTx.transaction_hash);

      // Verify RescuerChanged event
      expect(updateBackReceipt.isSuccess()).toBe(true);
      const updateBackEvents = messageTransmitter.contract.parseEvents(updateBackReceipt);
      expect(updateBackEvents).toEqual([
        expect.objectContaining({
          "cctp_components::rescuable::RescuableComponent::RescuerChanged": {
            new_rescuer: num.toBigInt(messageTransmitter.rescuer.address),
          },
        }),
      ]);

      // 5. Verify rescuer is back to original
      const restoredRescuer = num.toHex(await messageTransmitter.contract.rescuer());
      expect(restoredRescuer).toBe(num.toHex(messageTransmitter.rescuer.address));
    });
  });

  describe("send_message", () => {
    // Common function to test send_message
    const testSendMessage = async (params: {
      sender: Account;
      destinationDomain: number;
      recipient: string;
      destinationCaller: string;
      minFinalityThreshold: number;
      messageBody: string;
      testName: string;
    }) => {
      // Send message
      messageTransmitter.contract.connect(params.sender);
      const sendTx = await messageTransmitter.contract.send_message(
        params.destinationDomain,
        params.recipient,
        params.destinationCaller,
        params.minFinalityThreshold,
        params.messageBody,
      );

      // Wait for transaction and verify event
      const sendReceipt = await provider.waitForTransaction(sendTx.transaction_hash);
      expect(sendReceipt.isSuccess()).toBe(true);

      // Parse events - we need to get the raw event data from the receipt
      // Access the events array from the receipt object
      const receiptWithEvents = sendReceipt as any;
      const events = receiptWithEvents.events || [];

      const messageSentEvent = events.find((event: any) => event.from_address === messageTransmitter.contract.address);

      expect(messageSentEvent).toBeDefined();

      // Decode the ByteArray from the event data
      const decodedMessage = ByteArray.decode(messageSentEvent!.data);

      // Construct the expected message
      const expectedMessageBytes: number[] = [];

      // Version (4 bytes)
      appendU32BE(expectedMessageBytes, 1);

      // Source domain (4 bytes) - StarkNet is domain 25
      appendU32BE(expectedMessageBytes, 25);

      // Destination domain (4 bytes)
      appendU32BE(expectedMessageBytes, params.destinationDomain);

      // Nonce (32 bytes) - use zero nonce
      appendZeroU256(expectedMessageBytes);

      // Sender (32 bytes) - the message transmitter contract address
      appendU256BE(expectedMessageBytes, num.toBigInt(params.sender.address));

      // Recipient (32 bytes)
      appendU256BE(expectedMessageBytes, num.toBigInt(params.recipient));

      // Destination caller (32 bytes)
      appendU256BE(expectedMessageBytes, num.toBigInt(params.destinationCaller));

      // Min finality threshold (4 bytes)
      appendU32BE(expectedMessageBytes, params.minFinalityThreshold);

      // Finality threshold executed (4 bytes) - should be 0 for sending
      appendU32BE(expectedMessageBytes, 0);

      // Message body
      const bodyBytes = stringToBytes(params.messageBody);
      expectedMessageBytes.push(...bodyBytes);

      // Check the basic structure (skip nonce verification for now)
      const decodedHex = uint8ArrayToHexString(decodedMessage);

      const expectedHex = numberArrayToHexString(expectedMessageBytes);

      expect(decodedHex).toEqual(expectedHex);
    };

    it("should send a message and emit MessageSent event", async () => {
      await testSendMessage({
        sender: messageTransmitter.tester,
        destinationDomain: 2, // Avalanche
        recipient: "0x1234567890123456789012345678901234567890123456789012345678901234",
        destinationCaller: "0x0", // Anyone can call
        minFinalityThreshold: 500,
        messageBody: "Hello from StarkNet! This is a test message.",
        testName: "basic message with zero destination caller",
      });
    });

    it("should send a message with specific destination caller", async () => {
      await testSendMessage({
        sender: messageTransmitter.owner,
        destinationDomain: 3, // Another domain
        recipient: "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef123456789a",
        destinationCaller: "0x2222222222222222222222222222222222222222222222222222222222222222", // Specific caller
        minFinalityThreshold: 1000,
        messageBody: "Restricted message - only specific caller can process this on destination.",
        testName: "message with specific destination caller",
      });
    });
  });

  describe("receive_message", () => {
    // Helper function to generate attestation encoded as a ByteArray
    const generateAttestation = (
      message: Uint8Array,
      attesters: { privateKey: string; address: string }[],
    ): string[] => {
      // Hash the message using Keccak256 (raw hash, no Ethereum prefix)
      const messageHash = ethers.keccak256(message);

      // Generate signatures from attesters
      const signatures: { signature: string; address: string }[] = [];

      for (const attester of attesters) {
        const wallet = new ethers.Wallet(attester.privateKey);
        // Sign the raw message hash (no Ethereum prefix)
        const signature = wallet.signingKey.sign(messageHash);

        // Format: r (32 bytes) + s (32 bytes) + v (1 byte)
        const r = signature.r.substring(2).padStart(64, "0");
        const s = signature.s.substring(2).padStart(64, "0");
        const v = signature.v.toString(16).padStart(2, "0");

        signatures.push({
          signature: r + s + v,
          address: attester.address,
        });
      }

      // Sort signatures by address (ascending order)
      signatures.sort((a, b) => {
        const addrA = BigInt(a.address);
        const addrB = BigInt(b.address);
        return addrA < addrB ? -1 : addrA > addrB ? 1 : 0;
      });

      // Concatenate all signatures in order
      const attestationHex = signatures.map((s) => s.signature).join("");

      // Convert hex string to bytes
      const attestationBytes: number[] = [];
      for (let i = 0; i < attestationHex.length; i += 2) {
        attestationBytes.push(parseInt(attestationHex.substr(i, 2), 16));
      }

      // Encode as ByteArray
      return ByteArray.encode(attestationBytes);
    };

    // Common function to test receiving messages
    const testReceiveMessage = async (params: {
      finalityThresholdExecuted: number;
      destinationCaller: string;
      hookData: string;
      testDescription: string;
    }) => {
      const nonce = BigInt(randomInt(1000000000, 9999999999));
      const initialBalance = await stablecoin.contract.balance_of(tokenMessengerMinter.tester.address);

      // Construct a message to receive
      const messageParams = {
        version: 1,
        sourceDomain: 2, // From Avalanche
        destinationDomain: 25, // Local domain (StarkNet)
        nonce: nonce,
        sender: "0x2000", // remote token messenger for domain 2, defined in deploy.ts
        recipient: tokenMessengerMinter.contract.address,
        destinationCaller: params.destinationCaller,
        minFinalityThreshold: params.finalityThresholdExecuted < 2000 ? 1000 : 500,
        finalityThresholdExecuted: params.finalityThresholdExecuted,
        burnMessage: {
          version: 1,
          burnToken: "0x1111111111111111111111111111111111111111111111111111111111111111",
          mintRecipient: tokenMessengerMinter.tester.address,
          amount: 1000000n,
          messageSender: "0x3333333333333333333333333333333333333333333333333333333333333333",
          maxFee: 50000n,
          hookData: params.hookData,
        },
      };

      const burnMessageBytes = constructBurnMessage(messageParams.burnMessage);
      const messageBytes = constructMessage(messageParams);
      const messageUint8Array = new Uint8Array(messageBytes);

      // Generate attestation using the configured attesters
      const attestation = generateAttestation(messageUint8Array, messageTransmitter.attesters);

      // Encode the message as a StarkNet ByteArray (array of strings)
      const encodedMessage = ByteArray.encode(messageBytes);

      // Call receive_message with the encoded message array
      messageTransmitter.contract.connect(messageTransmitter.tester);

      const receiveTx = await messageTransmitter.contract.receive_message(
        CallData.compile([...encodedMessage, ...attestation]),
      );

      // Wait for transaction
      const receiveReceipt = await provider.waitForTransaction(receiveTx.transaction_hash);
      expect(receiveReceipt.isSuccess()).toBe(true);

      // Parse events
      const receiveEvents = messageTransmitter.contract.parseEvents(receiveReceipt);

      expect(receiveEvents).toEqual([
        expect.objectContaining({
          "message_transmitter::message_transmitter_v2::MessageTransmitterV2::MessageReceived": {
            caller: num.toBigInt(messageTransmitter.tester.address),
            source_domain: num.toBigInt(messageParams.sourceDomain),
            nonce: messageParams.nonce,
            sender: num.toBigInt(messageParams.sender),
            finality_threshold_executed: num.toBigInt(messageParams.finalityThresholdExecuted),
            message_body: expect.any(String), // The message body should be a burn message
          },
        }),
      ]);

      const burnMessageHex = numberArrayToHexString(burnMessageBytes);
      // we will need to manually parse the burn message from the event data
      const rawEvents = (receiveReceipt as any).events || [];
      const messageReceivedEvent = rawEvents.find(
        (event: any) => event.from_address === messageTransmitter.contract.address,
      );
      const messageBody = (messageReceivedEvent.data as string[]).slice(3); // 1st felt is sourcedomain, 2nd and 3rd are sender
      const messageBodyHex = uint8ArrayToHexString(ByteArray.decode(messageBody));
      expect(messageBodyHex).toEqual(burnMessageHex);

      const finalBalance = await stablecoin.contract.balance_of(tokenMessengerMinter.tester.address);
      expect(finalBalance).toBe(initialBalance + messageParams.burnMessage.amount);

      // Try to receive the same message again (should fail due to nonce already used)
      try {
        await messageTransmitter.contract.receive_message(CallData.compile([...encodedMessage, ...attestation]));
        expect(true).toBe(false); // Should not reach here
      } catch (error: any) {
        expect(error.message).toContain("Nonce already used");
      }
    };

    beforeAll(async () => {
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller);
      try {
        await tokenMessengerMinter.contract.link_token_pair(
          stablecoin.contract.address,
          2,
          "0x1111111111111111111111111111111111111111111111111111111111111111",
        );
      } catch (error: any) {
        if (error.message && error.message.includes("Unable to link token pair")) {
          // The token may have already been linked if the test is run multiple times
        } else {
          throw error;
        }
      }
    });

    afterAll(async () => {
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller);
      try {
        await tokenMessengerMinter.contract.unlink_token_pair(
          stablecoin.contract.address,
          2,
          "0x1111111111111111111111111111111111111111111111111111111111111111",
        );
      } catch (error: any) {
        if (error.message && error.message.includes("Unable to unlink token pair")) {
          // The token may have already been linked if the test is run multiple times
        } else {
          throw error;
        }
      }
    });

    it("should receive a finalized message and emit MessageReceived event", async () => {
      await testReceiveMessage({
        finalityThresholdExecuted: 2000, // >= FINALITY_THRESHOLD_FINALIZED (2000)
        destinationCaller: "0x0", // Anyone can call
        hookData: "Test burn message from Avalanche",
        testDescription: "finalized message with zero destination caller",
      });
    });

    it("should receive an unfinalized message with specific destination caller", async () => {
      await testReceiveMessage({
        finalityThresholdExecuted: 1000, // < FINALITY_THRESHOLD_FINALIZED (2000)
        destinationCaller: messageTransmitter.tester.address, // Specific caller required
        hookData: "Restricted burn message requiring specific caller",
        testDescription: "unfinalized message with specific destination caller",
      });
    });
  });
});
