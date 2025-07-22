import { num } from 'starknet';
import { loadTokenMessengerMinter, TokenMessengerMinterInfo, provider } from './utils.js';

describe('token messenger minter', () => {
  let tokenMessengerMinter: TokenMessengerMinterInfo;

  beforeAll(async () => {
    tokenMessengerMinter = await loadTokenMessengerMinter();
  });
  describe('manageable', () => {
    it('should have admin account and handle admin transfer flow', async () => {
      // 1. Check initial admin
      const initialAdmin = num.toHex(await tokenMessengerMinter.contract.admin());
      expect(initialAdmin).toBe(num.toHex(tokenMessengerMinter.admin.address));
      
      // 2. Check initial pending_admin (should be zero)
      const initialPendingAdmin = num.toHex(await tokenMessengerMinter.contract.pending_admin());
      expect(initialPendingAdmin).toBe('0x0');
      
      // 3. Transfer admin to tester address (as admin)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.admin)
      const testerAddress = tokenMessengerMinter.tester.address;
      const transferTx = await tokenMessengerMinter.contract.transfer_admin(testerAddress);
      const transferReceipt = await provider.waitForTransaction(transferTx.transaction_hash);
      
      // Verify AdminTransferStarted event
      expect(transferReceipt.isSuccess()).toBe(true);
      const transferEvents = tokenMessengerMinter.contract.parseEvents(transferReceipt);
      expect(transferEvents).toEqual([expect.objectContaining({
        'components::manageable::ManageableComponent::AdminTransferStarted': {
        previous_admin: num.toBigInt(tokenMessengerMinter.admin.address),
        new_admin: num.toBigInt(testerAddress)
      }
      })])
      
      // 4. Check pending_admin (should now be tester)
      const pendingAdminAfterTransfer = num.toHex(await tokenMessengerMinter.contract.pending_admin());
      expect(pendingAdminAfterTransfer).toBe(num.toHex(testerAddress));
      
      // 5. Accept admin (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const acceptTx = await tokenMessengerMinter.contract.accept_admin();
      const acceptReceipt = await provider.waitForTransaction(acceptTx.transaction_hash);
      
      // Verify AdminTransferred event
      expect(acceptReceipt.isSuccess()).toBe(true);
      const acceptEvents = tokenMessengerMinter.contract.parseEvents(acceptReceipt);
      expect(acceptEvents).toEqual([expect.objectContaining({
        'components::manageable::ManageableComponent::AdminTransferred': {
        previous_admin: num.toBigInt(tokenMessengerMinter.admin.address),
        new_admin: num.toBigInt(testerAddress)
      }
      })])
      
      // 6. Check admin (should now be tester)
      const adminAfterAccept = num.toHex(await tokenMessengerMinter.contract.admin());
      expect(adminAfterAccept).toBe(num.toHex(testerAddress));
      
      // 7. Check pending_admin (should be zero again)
      const pendingAdminAfterAccept = num.toHex(await tokenMessengerMinter.contract.pending_admin());
      expect(pendingAdminAfterAccept).toBe('0x0');
      
      // 8. Transfer admin back to original admin (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const originalAdminAddress = tokenMessengerMinter.admin.address;
      await tokenMessengerMinter.contract.transfer_admin(originalAdminAddress);
      
      // 9. Accept admin back (as original admin)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.admin)
      await tokenMessengerMinter.contract.accept_admin();
      
      // 10. Verify admin is back to original
      const finalAdmin = num.toHex(await tokenMessengerMinter.contract.admin());
      expect(finalAdmin).toBe(num.toHex(originalAdminAddress));
      
      // 11. Verify pending_admin is zero
      const finalPendingAdmin = num.toHex(await tokenMessengerMinter.contract.pending_admin());
      expect(finalPendingAdmin).toBe('0x0');
    });
  })
  describe('ownable', () => {
    it('should have owner account and handle ownership transfer flow', async () => {
      // 1. Check initial owner
      const initialOwner = num.toHex(await tokenMessengerMinter.contract.owner());
      expect(initialOwner).toBe(num.toHex(tokenMessengerMinter.owner.address));
      
      // 2. Check initial pending_owner (should be zero)
      const initialPendingOwner = num.toHex(await tokenMessengerMinter.contract.pending_owner());
      expect(initialPendingOwner).toBe('0x0');
      
      // 3. Transfer ownership to tester address (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const transferTx = await tokenMessengerMinter.contract.transfer_ownership(testerAddress);
      const transferReceipt = await provider.waitForTransaction(transferTx.transaction_hash);
      
      // Verify OwnershipTransferStarted event
      expect(transferReceipt.isSuccess()).toBe(true);
      const transferEvents = tokenMessengerMinter.contract.parseEvents(transferReceipt);
      expect(transferEvents).toEqual([expect.objectContaining({
        'components::ownable::OwnableComponent::OwnershipTransferStarted': {
        previous_owner: num.toBigInt(tokenMessengerMinter.owner.address),
        new_owner: num.toBigInt(testerAddress)
      }
      })])
      
      // 4. Check pending_owner (should now be tester)
      const pendingOwnerAfterTransfer = num.toHex(await tokenMessengerMinter.contract.pending_owner());
      expect(pendingOwnerAfterTransfer).toBe(num.toHex(testerAddress));
      
      // 5. Accept ownership (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const acceptTx = await tokenMessengerMinter.contract.accept_ownership();
      const acceptReceipt = await provider.waitForTransaction(acceptTx.transaction_hash);
      
      // Verify OwnershipTransferred event
      expect(acceptReceipt.isSuccess()).toBe(true);
      const acceptEvents = tokenMessengerMinter.contract.parseEvents(acceptReceipt);
      expect(acceptEvents).toEqual([expect.objectContaining({
        'components::ownable::OwnableComponent::OwnershipTransferred': {
        previous_owner: num.toBigInt(tokenMessengerMinter.owner.address),
        new_owner: num.toBigInt(testerAddress)
      }
      })])
      
      // 6. Check owner (should now be tester)
      const ownerAfterAccept = num.toHex(await tokenMessengerMinter.contract.owner());
      expect(ownerAfterAccept).toBe(num.toHex(testerAddress));
      
      // 7. Check pending_owner (should be zero again)
      const pendingOwnerAfterAccept = num.toHex(await tokenMessengerMinter.contract.pending_owner());
      expect(pendingOwnerAfterAccept).toBe('0x0');
      
      // 8. Transfer ownership back to original owner (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const originalOwnerAddress = tokenMessengerMinter.owner.address;
      await tokenMessengerMinter.contract.transfer_ownership(originalOwnerAddress);
      
      // 9. Accept ownership back (as original owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      await tokenMessengerMinter.contract.accept_ownership();
      
      // 10. Verify owner is back to original
      const finalOwner = num.toHex(await tokenMessengerMinter.contract.owner());
      expect(finalOwner).toBe(num.toHex(originalOwnerAddress));
      
      // 11. Verify pending_owner is zero
      const finalPendingOwner = num.toHex(await tokenMessengerMinter.contract.pending_owner());
      expect(finalPendingOwner).toBe('0x0');
    });
  })
  describe('pausable', () => {
    it('should manage pauser and pause/unpause functionality', async () => {
      // 1. Check initial pauser
      const initialPauser = num.toHex(await tokenMessengerMinter.contract.pauser());
      expect(initialPauser).toBe(num.toHex(tokenMessengerMinter.pauser.address));
      
      // 2. Check initial paused state (should be false)
      const initialPaused = await tokenMessengerMinter.contract.paused();
      expect(initialPaused).toBe(false);
      
      // 3. Pause the contract (as pauser)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.pauser)
      const pauseTx = await tokenMessengerMinter.contract.pause();
      const pauseReceipt = await provider.waitForTransaction(pauseTx.transaction_hash);
      
      // Verify Paused event
      expect(pauseReceipt.isSuccess()).toBe(true);
      const pauseEvents = tokenMessengerMinter.contract.parseEvents(pauseReceipt);
      expect(pauseEvents).toEqual([expect.objectContaining({
        'components::pausable::PausableComponent::Paused': {}
      })])
      
      // 4. Check paused state (should be true)
      const pausedAfterPause = await tokenMessengerMinter.contract.paused();
      expect(pausedAfterPause).toBe(true);
      
      // 5. Unpause the contract (as pauser)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.pauser)
      const unpauseTx = await tokenMessengerMinter.contract.unpause();
      const unpauseReceipt = await provider.waitForTransaction(unpauseTx.transaction_hash);
      
      // Verify Unpaused event
      expect(unpauseReceipt.isSuccess()).toBe(true);
      const unpauseEvents = tokenMessengerMinter.contract.parseEvents(unpauseReceipt);
      expect(unpauseEvents).toEqual([expect.objectContaining({
        'components::pausable::PausableComponent::Unpaused': {}
      })])
      
      // 6. Check paused state (should be false)
      const pausedAfterUnpause = await tokenMessengerMinter.contract.paused();
      expect(pausedAfterUnpause).toBe(false);
      
      // 7. Update pauser to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const updatePauserTx = await tokenMessengerMinter.contract.update_pauser(testerAddress);
      const updatePauserReceipt = await provider.waitForTransaction(updatePauserTx.transaction_hash);
      
      // Verify PauserChanged event
      expect(updatePauserReceipt.isSuccess()).toBe(true);
      const updatePauserEvents = tokenMessengerMinter.contract.parseEvents(updatePauserReceipt);
      expect(updatePauserEvents).toEqual([expect.objectContaining({
        'components::pausable::PausableComponent::PauserChanged': {
          new_address: num.toBigInt(testerAddress)
        }
      })])
      
      // 8. Check new pauser
      const newPauser = num.toHex(await tokenMessengerMinter.contract.pauser());
      expect(newPauser).toBe(num.toHex(testerAddress));
      
      // 9. Pause with new pauser (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const pauseWithNewPauserTx = await tokenMessengerMinter.contract.pause();
      const pauseWithNewPauserReceipt = await provider.waitForTransaction(pauseWithNewPauserTx.transaction_hash);
      
      // Verify Paused event
      expect(pauseWithNewPauserReceipt.isSuccess()).toBe(true);
      const pauseWithNewPauserEvents = tokenMessengerMinter.contract.parseEvents(pauseWithNewPauserReceipt);
      expect(pauseWithNewPauserEvents).toEqual([expect.objectContaining({
        'components::pausable::PausableComponent::Paused': {}
      })])
      
      // 10. Check paused state (should be true)
      const finalPausedState = await tokenMessengerMinter.contract.paused();
      expect(finalPausedState).toBe(true);
      
      // 11. Unpause with new pauser to restore state (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      await tokenMessengerMinter.contract.unpause();
      
      // 12. Update pauser back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      await tokenMessengerMinter.contract.update_pauser(tokenMessengerMinter.pauser.address);
      
      // 13. Verify pauser is back to original
      const restoredPauser = num.toHex(await tokenMessengerMinter.contract.pauser());
      expect(restoredPauser).toBe(num.toHex(tokenMessengerMinter.pauser.address));
    });
  })
  describe('denylistable', () => {
    it('should update denylister and change back', async () => {
      // 1. Check initial denylister
      const initialDenylister = num.toHex(await tokenMessengerMinter.contract.denylister());
      expect(initialDenylister).toBe(num.toHex(tokenMessengerMinter.denylister.address));
      
      // 2. Update denylister to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const updateDenylisterTx = await tokenMessengerMinter.contract.update_denylister(testerAddress);
      const updateDenylisterReceipt = await provider.waitForTransaction(updateDenylisterTx.transaction_hash);
      
      // Verify DenylisterChanged event
      expect(updateDenylisterReceipt.isSuccess()).toBe(true);
      const updateDenylisterEvents = tokenMessengerMinter.contract.parseEvents(updateDenylisterReceipt);
      expect(updateDenylisterEvents).toEqual([expect.objectContaining({
        'components::denylistable::DenylistableComponent::DenylisterChanged': {
          old_denylister: num.toBigInt(tokenMessengerMinter.denylister.address),
          new_denylister: num.toBigInt(testerAddress)
        }
      })])
      
      // 3. Check new denylister
      const newDenylister = num.toHex(await tokenMessengerMinter.contract.denylister());
      expect(newDenylister).toBe(num.toHex(testerAddress));
      
      // 4. Update denylister back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const updateBackTx = await tokenMessengerMinter.contract.update_denylister(tokenMessengerMinter.denylister.address);
      const updateBackReceipt = await provider.waitForTransaction(updateBackTx.transaction_hash);
      
      // Verify DenylisterChanged event
      expect(updateBackReceipt.isSuccess()).toBe(true);
      const updateBackEvents = tokenMessengerMinter.contract.parseEvents(updateBackReceipt);
      expect(updateBackEvents).toEqual([expect.objectContaining({
        'components::denylistable::DenylistableComponent::DenylisterChanged': {
          old_denylister: num.toBigInt(testerAddress),
          new_denylister: num.toBigInt(tokenMessengerMinter.denylister.address)
        }
      })])
      
      // 5. Verify denylister is back to original
      const restoredDenylister = num.toHex(await tokenMessengerMinter.contract.denylister());
      expect(restoredDenylister).toBe(num.toHex(tokenMessengerMinter.denylister.address));
    });

    it('should add and remove address from denylist and block transfers', async () => {
      const testerAddress = tokenMessengerMinter.tester.address;
      
      // 1. Add tester to denylist (as denylister)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.denylister)
      const denylistTx = await tokenMessengerMinter.contract.denylist(testerAddress);
      
      // 2. Wait for transaction and verify event
      const denylistReceipt = await provider.waitForTransaction(denylistTx.transaction_hash);
      if (denylistReceipt.isSuccess()) {
        const denylistEvents = tokenMessengerMinter.contract.parseEvents(denylistReceipt);
        expect(denylistEvents).toEqual([expect.objectContaining({
          'components::denylistable::DenylistableComponent::Denylisted': {
            address: num.toBigInt(testerAddress)
          }
        })])
      }
      
      // 3. Check if tester is denylisted (should be true)
      const isDenylistedAfterAdd = await tokenMessengerMinter.contract.is_denylisted(testerAddress);
      expect(isDenylistedAfterAdd).toBe(true);
      
      // 4. Try to perform a transfer operation as denylisted address (should fail)
      // Using deposit_for_burn as an example transfer operation
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      try {
        // This should fail because tester is denylisted
        await tokenMessengerMinter.contract.deposit_for_burn(
          1000n, // amount
          1, // destination domain
          '0x1234567890123456789012345678901234567890123456789012345678901234', // mint recipient
          '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef123456', // burn token
          0n, // destination_caller (0 means any address can call)
          100n, // max_fee
          500 // min_finality_threshold
        );
        // If we reach here, the test should fail
        expect(true).toBe(false); // Force test failure
      } catch (error: any) {
        // Expected to fail with denylisted error
        expect(error.message).toContain('Address is denylisted');
      }
      
      // 5. Remove tester from denylist (as denylister)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.denylister)
      const undenylistTx = await tokenMessengerMinter.contract.undenylist(testerAddress);
      
      // 6. Wait for transaction and verify event
      const undenylistReceipt = await provider.waitForTransaction(undenylistTx.transaction_hash);
      if (undenylistReceipt.isSuccess()) {
        const undenylistEvents = tokenMessengerMinter.contract.parseEvents(undenylistReceipt);
        expect(undenylistEvents).toEqual([expect.objectContaining({
          'components::denylistable::DenylistableComponent::Undenylisted': {
            address: num.toBigInt(testerAddress)
          }
        })])
      }
    });
  })
  describe('fee_recipient_controller', () => {
    it('should manage fee recipient', async () => {
      // 1. Check initial fee recipient
      const initialFeeRecipient = num.toHex(await tokenMessengerMinter.contract.fee_recipient());
      expect(initialFeeRecipient).toBe(num.toHex(tokenMessengerMinter.fee_recipient.address));
      
      // 2. Set fee recipient to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const setFeeRecipientTx = await tokenMessengerMinter.contract.set_fee_recipient(testerAddress);
      const setFeeRecipientReceipt = await provider.waitForTransaction(setFeeRecipientTx.transaction_hash);
      
      // Verify FeeRecipientSet event
      expect(setFeeRecipientReceipt.isSuccess()).toBe(true);
      const setFeeRecipientEvents = tokenMessengerMinter.contract.parseEvents(setFeeRecipientReceipt);
      expect(setFeeRecipientEvents).toEqual([expect.objectContaining({
        'cctp_components::fee_recipient_controller::FeeRecipientControllerComponent::FeeRecipientSet': {
          fee_recipient: num.toBigInt(testerAddress)
        }
      })])
      
      // 3. Check new fee recipient
      const newFeeRecipient = num.toHex(await tokenMessengerMinter.contract.fee_recipient());
      expect(newFeeRecipient).toBe(num.toHex(testerAddress));
      
      // 4. Set fee recipient back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const setBackTx = await tokenMessengerMinter.contract.set_fee_recipient(tokenMessengerMinter.fee_recipient.address);
      const setBackReceipt = await provider.waitForTransaction(setBackTx.transaction_hash);
      
      // Verify FeeRecipientSet event
      expect(setBackReceipt.isSuccess()).toBe(true);
      const setBackEvents = tokenMessengerMinter.contract.parseEvents(setBackReceipt);
      expect(setBackEvents).toEqual([expect.objectContaining({
        'cctp_components::fee_recipient_controller::FeeRecipientControllerComponent::FeeRecipientSet': {
          fee_recipient: num.toBigInt(tokenMessengerMinter.fee_recipient.address)
        }
      })])
      
      // 5. Verify fee recipient is back to original
      const restoredFeeRecipient = num.toHex(await tokenMessengerMinter.contract.fee_recipient());
      expect(restoredFeeRecipient).toBe(num.toHex(tokenMessengerMinter.fee_recipient.address));
    });
  })
  describe('min_fee_controller', () => {
    it('should manage min fee controller and min fees', async () => {
      // Use a dummy burn token address for testing (valid StarkNet address)
      const dummyBurnToken = '0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef12';
      
      // 1. Check initial min fee controller
      const initialMinFeeController = num.toHex(await tokenMessengerMinter.contract.min_fee_controller());
      expect(initialMinFeeController).toBe(num.toHex(tokenMessengerMinter.min_fee_controller.address));
      
      // 2. Check initial min fee for dummy token (should be 0)
      const initialMinFee = await tokenMessengerMinter.contract.min_fee(dummyBurnToken);
      expect(initialMinFee).toBe(0n);
      
      // 3. Set min fee for dummy token (as min fee controller)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.min_fee_controller)
      const minFeeValue = 100000n; // 1% (100000 / 10000000)
      const setMinFeeTx = await tokenMessengerMinter.contract.set_min_fee(dummyBurnToken, minFeeValue);
      const setMinFeeReceipt = await provider.waitForTransaction(setMinFeeTx.transaction_hash);
      
      // Verify MinFeeSet event
      expect(setMinFeeReceipt.isSuccess()).toBe(true);
      const setMinFeeEvents = tokenMessengerMinter.contract.parseEvents(setMinFeeReceipt);
      expect(setMinFeeEvents).toEqual([expect.objectContaining({
        'cctp_components::min_fee_controller::MinFeeControllerComponent::MinFeeSet': {
          burn_token: num.toBigInt(dummyBurnToken),
          min_fee: minFeeValue
        }
      })])
      
      // 4. Check new min fee
      const newMinFee = await tokenMessengerMinter.contract.min_fee(dummyBurnToken);
      expect(newMinFee).toBe(minFeeValue);
      
      // 5. Update min fee controller to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const updateControllerTx = await tokenMessengerMinter.contract.set_min_fee_controller(testerAddress);
      const updateControllerReceipt = await provider.waitForTransaction(updateControllerTx.transaction_hash);
      
      // Verify MinFeeControllerSet event
      expect(updateControllerReceipt.isSuccess()).toBe(true);
      const updateControllerEvents = tokenMessengerMinter.contract.parseEvents(updateControllerReceipt);
      expect(updateControllerEvents).toEqual([expect.objectContaining({
        'cctp_components::min_fee_controller::MinFeeControllerComponent::MinFeeControllerSet': {
          min_fee_controller: num.toBigInt(testerAddress)
        }
      })])
      
      // 6. Check new min fee controller
      const newMinFeeController = num.toHex(await tokenMessengerMinter.contract.min_fee_controller());
      expect(newMinFeeController).toBe(num.toHex(testerAddress));
      
      // 7. Update min fee with new controller (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      const updatedMinFeeValue = 200000n; // 2% (200000 / 10000000)
      const updateMinFeeTx = await tokenMessengerMinter.contract.set_min_fee(dummyBurnToken, updatedMinFeeValue);
      const updateMinFeeReceipt = await provider.waitForTransaction(updateMinFeeTx.transaction_hash);
      
      // Verify MinFeeSet event
      expect(updateMinFeeReceipt.isSuccess()).toBe(true);
      const updateMinFeeEvents = tokenMessengerMinter.contract.parseEvents(updateMinFeeReceipt);
      expect(updateMinFeeEvents).toEqual([expect.objectContaining({
        'cctp_components::min_fee_controller::MinFeeControllerComponent::MinFeeSet': {
          burn_token: num.toBigInt(dummyBurnToken),
          min_fee: updatedMinFeeValue
        }
      })])
      
      // 8. Check updated min fee
      const updatedMinFee = await tokenMessengerMinter.contract.min_fee(dummyBurnToken);
      expect(updatedMinFee).toBe(updatedMinFeeValue);
      
      // 9. Set min fee back to 0 to clean up (as tester)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.tester)
      await tokenMessengerMinter.contract.set_min_fee(dummyBurnToken, 0n);
      
      // 10. Update min fee controller back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      await tokenMessengerMinter.contract.set_min_fee_controller(tokenMessengerMinter.min_fee_controller.address);
      
      // 11. Verify min fee controller is back to original
      const restoredMinFeeController = num.toHex(await tokenMessengerMinter.contract.min_fee_controller());
      expect(restoredMinFeeController).toBe(num.toHex(tokenMessengerMinter.min_fee_controller.address));
    });
  })
  describe('token_controller', () => {
    it('should set token controller and change back', async () => {
      // 1. Check initial token controller
      const initialTokenController = num.toHex(await tokenMessengerMinter.contract.token_controller());
      expect(initialTokenController).toBe(num.toHex(tokenMessengerMinter.token_controller.address));
      
      // 2. Set token controller to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const setTokenControllerTx = await tokenMessengerMinter.contract.set_token_controller(testerAddress);
      const setTokenControllerReceipt = await provider.waitForTransaction(setTokenControllerTx.transaction_hash);
      
      // Verify SetTokenController event
      expect(setTokenControllerReceipt.isSuccess()).toBe(true);
      const setTokenControllerEvents = tokenMessengerMinter.contract.parseEvents(setTokenControllerReceipt);
      expect(setTokenControllerEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::SetTokenController': {
          token_controller: num.toBigInt(testerAddress)
        }
      })])
      
      // 3. Check new token controller
      const newTokenController = num.toHex(await tokenMessengerMinter.contract.token_controller());
      expect(newTokenController).toBe(num.toHex(testerAddress));
      
      // 4. Set token controller back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const setBackTx = await tokenMessengerMinter.contract.set_token_controller(tokenMessengerMinter.token_controller.address);
      const setBackReceipt = await provider.waitForTransaction(setBackTx.transaction_hash);
      
      // Verify SetTokenController event
      expect(setBackReceipt.isSuccess()).toBe(true);
      const setBackEvents = tokenMessengerMinter.contract.parseEvents(setBackReceipt);
      expect(setBackEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::SetTokenController': {
          token_controller: num.toBigInt(tokenMessengerMinter.token_controller.address)
        }
      })])
      
      // 5. Verify token controller is back to original
      const restoredTokenController = num.toHex(await tokenMessengerMinter.contract.token_controller());
      expect(restoredTokenController).toBe(num.toHex(tokenMessengerMinter.token_controller.address));
    });

    it('should link/unlink token pair and set max burn amount', async () => {
      // Test data
      const localToken = '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef123456';
      const remoteDomain = 1; // Ethereum
      const remoteToken = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      const maxBurnAmount = 1000000000n; // 1000 tokens with 6 decimals
      
      // 1. Set max burn amount for the token (as token controller)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller)
      const setMaxBurnTx = await tokenMessengerMinter.contract.set_max_burn_amount_per_message(localToken, maxBurnAmount);
      const setMaxBurnReceipt = await provider.waitForTransaction(setMaxBurnTx.transaction_hash);
      
      // Verify SetBurnLimitPerMessage event
      expect(setMaxBurnReceipt.isSuccess()).toBe(true);
      const setMaxBurnEvents = tokenMessengerMinter.contract.parseEvents(setMaxBurnReceipt);
      expect(setMaxBurnEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::SetBurnLimitPerMessage': {
          token: num.toBigInt(localToken),
          burn_limit_per_message: maxBurnAmount
        }
      })])
      
      // 2. Link token pair (as token controller)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller)
      const linkTx = await tokenMessengerMinter.contract.link_token_pair(localToken, remoteDomain, remoteToken);
      const linkReceipt = await provider.waitForTransaction(linkTx.transaction_hash);
      
      // Verify TokenPairLinked event
      expect(linkReceipt.isSuccess()).toBe(true);
      const linkEvents = tokenMessengerMinter.contract.parseEvents(linkReceipt);
      expect(linkEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::TokenPairLinked': {
          local_token: num.toBigInt(localToken),
          remote_domain: num.toBigInt(remoteDomain),
          remote_token: num.toBigInt(remoteToken)
        }
      })])
      
      // 3. Update max burn amount to a different value (as token controller)
      const updatedMaxBurnAmount = 2000000000n; // 2000 tokens with 6 decimals
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller)
      const updateMaxBurnTx = await tokenMessengerMinter.contract.set_max_burn_amount_per_message(localToken, updatedMaxBurnAmount);
      const updateMaxBurnReceipt = await provider.waitForTransaction(updateMaxBurnTx.transaction_hash);
      
      // Verify SetBurnLimitPerMessage event with updated amount
      expect(updateMaxBurnReceipt.isSuccess()).toBe(true);
      const updateMaxBurnEvents = tokenMessengerMinter.contract.parseEvents(updateMaxBurnReceipt);
      expect(updateMaxBurnEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::SetBurnLimitPerMessage': {
          token: num.toBigInt(localToken),
          burn_limit_per_message: updatedMaxBurnAmount
        }
      })])
      
      // 4. Unlink token pair (as token controller)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller)
      const unlinkTx = await tokenMessengerMinter.contract.unlink_token_pair(localToken, remoteDomain, remoteToken);
      const unlinkReceipt = await provider.waitForTransaction(unlinkTx.transaction_hash);
      
      // Verify TokenPairUnlinked event
      expect(unlinkReceipt.isSuccess()).toBe(true);
      const unlinkEvents = tokenMessengerMinter.contract.parseEvents(unlinkReceipt);
      expect(unlinkEvents).toEqual([expect.objectContaining({
        'cctp_components::token_controller::TokenControllerComponent::TokenPairUnlinked': {
          local_token: num.toBigInt(localToken),
          remote_domain: num.toBigInt(remoteDomain),
          remote_token: num.toBigInt(remoteToken)
        }
      })])
      
      // 5. Set max burn amount back to 0 to clean up (as token controller)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.token_controller)
      await tokenMessengerMinter.contract.set_max_burn_amount_per_message(localToken, 0n);
    });
  })
  describe('remote_token_messenger_controller', () => {
    it('should manage remote token messengers for different domains', async () => {
      // Test domains and addresses
      const existingDomain1 = 1; // Ethereum (pre-configured)
      const existingDomain2 = 2; // Avalanche (pre-configured)
      const existingDomain3 = 3; // Pre-configured
      const newDomain4 = 4; // New domain to add
      
      const existingRemoteTokenMessenger1 = '0x1000';
      const existingRemoteTokenMessenger2 = '0x2000';
      const existingRemoteTokenMessenger3 = '0x3000';
      const newRemoteTokenMessenger4 = '0x4444444444444444444444444444444444444444444444444444444444444444';
      
      // 1. Check initial state (pre-configured remote token messengers)
      const initialRemoteTokenMessenger1 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain1);
      expect(num.toHex(initialRemoteTokenMessenger1)).toBe(existingRemoteTokenMessenger1);
      
      const initialRemoteTokenMessenger2 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain2);
      expect(num.toHex(initialRemoteTokenMessenger2)).toBe(existingRemoteTokenMessenger2);
      
      const initialRemoteTokenMessenger3 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain3);
      expect(num.toHex(initialRemoteTokenMessenger3)).toBe(existingRemoteTokenMessenger3);
      
      // 2. Check no remote token messenger for new domain4
      const initialRemoteTokenMessenger4 = await tokenMessengerMinter.contract.remote_token_messenger(newDomain4);
      expect(initialRemoteTokenMessenger4).toBe(0n);
      
      // 3. Add remote token messenger for new domain4 (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const addTx4 = await tokenMessengerMinter.contract.add_remote_token_messenger(newDomain4, newRemoteTokenMessenger4);
      const addReceipt4 = await provider.waitForTransaction(addTx4.transaction_hash);
      
      // Verify RemoteTokenMessengerAdded event
      expect(addReceipt4.isSuccess()).toBe(true);
      const addEvents4 = tokenMessengerMinter.contract.parseEvents(addReceipt4);
      expect(addEvents4).toEqual([expect.objectContaining({
        'cctp_components::remote_token_messenger_controller::RemoteTokenMessengerControllerComponent::RemoteTokenMessengerAdded': {
          domain: num.toBigInt(newDomain4),
          token_messenger: num.toBigInt(newRemoteTokenMessenger4)
        }
      })])
      
      // 4. Check remote token messenger was set for domain4
      const remoteTokenMessengerAfterAdd4 = await tokenMessengerMinter.contract.remote_token_messenger(newDomain4);
      expect(num.toHex(remoteTokenMessengerAfterAdd4)).toBe(newRemoteTokenMessenger4);
      
      // 5. Remove one of the existing pre-configured domains (domain1) (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const removeTx1 = await tokenMessengerMinter.contract.remove_remote_token_messenger(existingDomain1);
      const removeReceipt1 = await provider.waitForTransaction(removeTx1.transaction_hash);
      
      // Verify RemoteTokenMessengerRemoved event
      expect(removeReceipt1.isSuccess()).toBe(true);
      const removeEvents1 = tokenMessengerMinter.contract.parseEvents(removeReceipt1);
      expect(removeEvents1).toEqual([expect.objectContaining({
        'cctp_components::remote_token_messenger_controller::RemoteTokenMessengerControllerComponent::RemoteTokenMessengerRemoved': {
          domain: num.toBigInt(existingDomain1),
          token_messenger: num.toBigInt(existingRemoteTokenMessenger1)
        }
      })])
      
      // 6. Check remote token messenger was removed for domain1
      const remoteTokenMessengerAfterRemove1 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain1);
      expect(remoteTokenMessengerAfterRemove1).toBe(0n);
      
      // 7. Check other domains still have their remote token messengers
      const stillSet2 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain2);
      expect(num.toHex(stillSet2)).toBe(existingRemoteTokenMessenger2);
      
      const stillSet3 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain3);
      expect(num.toHex(stillSet3)).toBe(existingRemoteTokenMessenger3);
      
      const stillSet4 = await tokenMessengerMinter.contract.remote_token_messenger(newDomain4);
      expect(num.toHex(stillSet4)).toBe(newRemoteTokenMessenger4);
      
      // 8. Clean up: remove the newly added domain
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      await tokenMessengerMinter.contract.remove_remote_token_messenger(newDomain4);
      
      // 9. Restore domain1 to its original state
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      await tokenMessengerMinter.contract.add_remote_token_messenger(existingDomain1, existingRemoteTokenMessenger1);
      
      // 10. Verify original state is restored
      const finalRemoteTokenMessenger1 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain1);
      expect(num.toHex(finalRemoteTokenMessenger1)).toBe(existingRemoteTokenMessenger1);
      
      const finalRemoteTokenMessenger2 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain2);
      expect(num.toHex(finalRemoteTokenMessenger2)).toBe(existingRemoteTokenMessenger2);
      
      const finalRemoteTokenMessenger3 = await tokenMessengerMinter.contract.remote_token_messenger(existingDomain3);
      expect(num.toHex(finalRemoteTokenMessenger3)).toBe(existingRemoteTokenMessenger3);
      
      const finalRemoteTokenMessenger4 = await tokenMessengerMinter.contract.remote_token_messenger(newDomain4);
      expect(finalRemoteTokenMessenger4).toBe(0n);
    });
  })
  describe('rescuable', () => {
    // TODO: test erc20 rescue
    it('should read and update rescuer', async () => {
      // 1. Check initial rescuer
      const initialRescuer = num.toHex(await tokenMessengerMinter.contract.rescuer());
      expect(initialRescuer).toBe(num.toHex(tokenMessengerMinter.rescuer.address));
      
      // 2. Update rescuer to tester (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const testerAddress = tokenMessengerMinter.tester.address;
      const updateRescuerTx = await tokenMessengerMinter.contract.update_rescuer(testerAddress);
      const updateRescuerReceipt = await provider.waitForTransaction(updateRescuerTx.transaction_hash);
      
      // Verify RescuerChanged event
      expect(updateRescuerReceipt.isSuccess()).toBe(true);
      const updateRescuerEvents = tokenMessengerMinter.contract.parseEvents(updateRescuerReceipt);
      expect(updateRescuerEvents).toEqual([expect.objectContaining({
        'cctp_components::rescuable::RescuableComponent::RescuerChanged': {
          new_rescuer: num.toBigInt(testerAddress)
        }
      })])
      
      // 3. Check new rescuer
      const newRescuer = num.toHex(await tokenMessengerMinter.contract.rescuer());
      expect(newRescuer).toBe(num.toHex(testerAddress));
      
      // 4. Update rescuer back to original (as owner)
      tokenMessengerMinter.contract.connect(tokenMessengerMinter.owner)
      const updateBackTx = await tokenMessengerMinter.contract.update_rescuer(tokenMessengerMinter.rescuer.address);
      const updateBackReceipt = await provider.waitForTransaction(updateBackTx.transaction_hash);
      
      // Verify RescuerChanged event
      expect(updateBackReceipt.isSuccess()).toBe(true);
      const updateBackEvents = tokenMessengerMinter.contract.parseEvents(updateBackReceipt);
      expect(updateBackEvents).toEqual([expect.objectContaining({
        'cctp_components::rescuable::RescuableComponent::RescuerChanged': {
          new_rescuer: num.toBigInt(tokenMessengerMinter.rescuer.address)
        }
      })])
      
      // 5. Verify rescuer is back to original
      const restoredRescuer = num.toHex(await tokenMessengerMinter.contract.rescuer());
      expect(restoredRescuer).toBe(num.toHex(tokenMessengerMinter.rescuer.address));
    });
  })
});
