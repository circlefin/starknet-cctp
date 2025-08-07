import { RpcProvider, Account, Contract, num } from "starknet";
import { fileURLToPath } from "url";
import { dirname } from "path";
import * as fs from "fs/promises";
import * as path from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Constants
export const DEVNET_URL = "http://127.0.0.1:5050";

// Provider instance
export const provider = new RpcProvider({
  nodeUrl: DEVNET_URL,
});

export const toAccount = (accountConfig: { address: string; privateKey: string }): Account => {
  return new Account(provider, accountConfig.address, accountConfig.privateKey);
};

export interface StablecoinInfo {
  contract: Contract;
  admin: Account;
  owner: Account;
  pauser: Account;
  blocklister: Account;
  metadata_updater: Account;
  master_minter: Account;
  minter: Account;
}

export interface TokenMessengerMinterInfo {
  contract: Contract;
  admin: Account;
  owner: Account;
  pauser: Account;
  denylister: Account;
  rescuer: Account;
  token_controller: Account;
  min_fee_controller: Account;
  fee_recipient: Account;
  tester: Account;
}

export interface MessageTransmitterInfo {
  contract: Contract;
  admin: Account;
  owner: Account;
  pauser: Account;
  rescuer: Account;
  tester: Account;
  attester_manager: Account;
  attesters: { privateKey: string; address: string }[];
}

export const loadStablecoin = async (): Promise<StablecoinInfo> => {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, "resources/accounts.json"), "utf8"));
  // Load contract addresses
  const contractsPath = path.join(__dirname, "resources/contracts.json");
  const contracts = JSON.parse(await fs.readFile(contractsPath, "utf8"));

  // Load Stablecoin ABI
  const stablecoinAbiPath = path.join(__dirname, "resources/stablecoin.abi.json");
  const stablecoinAbi = JSON.parse(await fs.readFile(stablecoinAbiPath, "utf8"));

  // Setup contract instance
  const stablecoin = {
    contract: new Contract(stablecoinAbi, contracts.stablecoin, provider),
    admin: toAccount(accounts.stablecoin.admin),
    owner: toAccount(accounts.stablecoin.owner),
    pauser: toAccount(accounts.stablecoin.pauser),
    blocklister: toAccount(accounts.stablecoin.blocklister),
    metadata_updater: toAccount(accounts.stablecoin.metadata_updater),
    master_minter: toAccount(accounts.stablecoin.master_minter),
    minter: toAccount(accounts.stablecoin.minter),
  };

  return stablecoin;
};

export const loadTokenMessengerMinter = async (): Promise<TokenMessengerMinterInfo> => {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, "resources/accounts.json"), "utf8"));
  // Load contract addresses
  const contractsPath = path.join(__dirname, "resources/contracts.json");
  const contracts = JSON.parse(await fs.readFile(contractsPath, "utf8"));

  // Load Token Messenger Minter ABI
  const tmmAbiPath = path.join(__dirname, "resources/token_messenger_minter_v2.abi.json");
  const tmmAbi = JSON.parse(await fs.readFile(tmmAbiPath, "utf8"));

  // Setup contract instance
  const tokenMessengerMinter = {
    contract: new Contract(tmmAbi, contracts.tokenMessengerMinterV2, provider),
    admin: toAccount(accounts.token_messenger_minter.admin),
    owner: toAccount(accounts.token_messenger_minter.owner),
    pauser: toAccount(accounts.token_messenger_minter.pauser),
    denylister: toAccount(accounts.token_messenger_minter.denylister),
    rescuer: toAccount(accounts.token_messenger_minter.rescuer),
    token_controller: toAccount(accounts.token_messenger_minter.token_controller),
    min_fee_controller: toAccount(accounts.token_messenger_minter.min_fee_controller),
    fee_recipient: toAccount(accounts.token_messenger_minter.fee_recipient),
    tester: toAccount(accounts.token_messenger_minter.tester),
  };

  return tokenMessengerMinter;
};

export const loadMessageTransmitter = async (): Promise<MessageTransmitterInfo> => {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, "resources/accounts.json"), "utf8"));
  // Load contract addresses
  const contractsPath = path.join(__dirname, "resources/contracts.json");
  const contracts = JSON.parse(await fs.readFile(contractsPath, "utf8"));

  // Load Message Transmitter ABI
  const mtAbiPath = path.join(__dirname, "resources/message_transmitter_v2.abi.json");
  const mtAbi = JSON.parse(await fs.readFile(mtAbiPath, "utf8"));

  // Setup contract instance
  const messageTransmitter = {
    contract: new Contract(mtAbi, contracts.messageTransmitterV2, provider),
    admin: toAccount(accounts.message_transmitter.admin),
    owner: toAccount(accounts.message_transmitter.owner),
    pauser: toAccount(accounts.message_transmitter.pauser),
    rescuer: toAccount(accounts.message_transmitter.rescuer),
    tester: toAccount(accounts.message_transmitter.tester),
    attester_manager: toAccount(accounts.message_transmitter.attester_manager),
    attesters: accounts.message_transmitter.attesters,
  };

  return messageTransmitter;
};

// ByteArray encoder/decoder for StarkNet events
export class ByteArray {
  static decode(data: string[]): Uint8Array {
    // 1. Decode the first cell to get the number of 31-byte chunks
    const dataLength = parseInt(data[0], 16);

    // 2. Decode the next x cells and ensure they're 31 bytes each
    const chunks: number[] = [];
    for (let i = 1; i <= dataLength; i++) {
      const chunk = data[i].substring(2); // Remove '0x' prefix
      // Pad to 31 bytes (62 hex chars) from the left
      const paddedChunk = chunk.padStart(62, "0");
      // Convert hex to bytes
      for (let j = 0; j < 62; j += 2) {
        chunks.push(parseInt(paddedChunk.substr(j, 2), 16));
      }
    }

    // 3. Decode the pending data
    const pendingDataIndex = dataLength + 1;
    const pendingData = data[pendingDataIndex].substring(2); // Remove '0x' prefix

    // 4. Decode the length of pending data
    const pendingLengthIndex = dataLength + 2;
    const pendingLength = parseInt(data[pendingLengthIndex], 16);

    // 5. Process pending data according to its length
    const pendingBytes: number[] = [];
    if (pendingLength > 0) {
      // Pad with leading zeros to reach the required length (pendingLength * 2 hex chars)
      const hexData = pendingData.padStart(pendingLength * 2, "0");

      // Parse the padded hex string into bytes
      for (let i = 0; i < pendingLength * 2; i += 2) {
        pendingBytes.push(parseInt(hexData.substr(i, 2), 16));
      }
    }

    // 6. Concatenate all bytes together
    const allBytes = [...chunks, ...pendingBytes];
    return new Uint8Array(allBytes);
  }

  static encode(bytes: Uint8Array | number[]): string[] {
    const byteArray = bytes instanceof Uint8Array ? Array.from(bytes) : bytes;
    const result: string[] = [];

    // 1. Split the array into 31-byte chunks
    const chunks: number[][] = [];
    let remaining: number[] = [];

    for (let i = 0; i < byteArray.length; i += 31) {
      if (i + 31 <= byteArray.length) {
        // Full 31-byte chunk
        chunks.push(byteArray.slice(i, i + 31));
      } else {
        // Remaining bytes (less than 31)
        remaining = byteArray.slice(i);
      }
    }

    // 2. First, push the number of full chunks (excluding remaining)
    result.push("0x" + chunks.length.toString(16));

    // 3. Push chunks as hex strings
    for (const chunk of chunks) {
      const hexChunk = chunk.map((b) => b.toString(16).padStart(2, "0")).join("");
      result.push("0x" + hexChunk);
    }

    // 4. Push remaining chunk as hex string (or empty if no remaining)
    const remainingHex = remaining.map((b) => b.toString(16).padStart(2, "0")).join("");
    result.push("0x" + remainingHex);

    // 5. Push the length of remaining chunk
    result.push("0x" + remaining.length.toString(16));

    return result;
  }
}

export const uint8ArrayToHexString = (bytes: Uint8Array): string => {
  return (
    "0x" +
    Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")
  );
};

export const numberArrayToHexString = (bytes: number[]): string => {
  return "0x" + bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
};

export const stringToHexString = (str: string): string => {
  return (
    "0x" +
    Array.from(str)
      .map((c) => c.charCodeAt(0).toString(16).padStart(2, "0"))
      .join("")
  );
};

// Helper functions to construct messages
export function appendU32BE(buffer: number[], value: number): void {
  buffer.push((value >>> 24) & 0xff);
  buffer.push((value >>> 16) & 0xff);
  buffer.push((value >>> 8) & 0xff);
  buffer.push(value & 0xff);
}

export function appendU256BE(buffer: number[], value: bigint): void {
  const hex = value.toString(16).padStart(64, "0");
  for (let i = 0; i < 64; i += 2) {
    buffer.push(parseInt(hex.substr(i, 2), 16));
  }
}

export function stringToBytes(str: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    bytes.push(str.charCodeAt(i));
  }
  return bytes;
}

export function appendZeroU256(buffer: number[]): void {
  for (let i = 0; i < 32; i++) {
    buffer.push(0);
  }
}

// Construct a burn message following the format in burn_message.cairo
export function constructBurnMessage(params: {
  version: number;
  burnToken: string;
  mintRecipient: string;
  amount: bigint;
  messageSender: string;
  maxFee: bigint;
  hookData: string;
}): number[] {
  const burnMessage: number[] = [];

  // version (4 bytes, u32)
  appendU32BE(burnMessage, params.version);

  // burnToken (32 bytes, u256)
  appendU256BE(burnMessage, num.toBigInt(params.burnToken));

  // mintRecipient (32 bytes, u256)
  appendU256BE(burnMessage, num.toBigInt(params.mintRecipient));

  // amount (32 bytes, u256)
  appendU256BE(burnMessage, params.amount);

  // messageSender (32 bytes, u256)
  appendU256BE(burnMessage, num.toBigInt(params.messageSender));

  // maxFee (32 bytes, u256)
  appendU256BE(burnMessage, params.maxFee);

  // feeExecuted (32 bytes, u256) - always 0
  appendZeroU256(burnMessage);

  // expirationBlock (32 bytes, u256) - always 0
  appendZeroU256(burnMessage);

  // hookData (dynamic bytes)
  const hookDataBytes = stringToBytes(params.hookData);
  burnMessage.push(...hookDataBytes);

  return burnMessage;
}

// Construct a message for receiving (with burn message as body)
export function constructMessage(params: {
  version: number;
  sourceDomain: number;
  destinationDomain: number;
  nonce: bigint;
  sender: string;
  recipient: string;
  destinationCaller: string;
  minFinalityThreshold: number;
  finalityThresholdExecuted: number;
  burnMessage: {
    version: number;
    burnToken: string;
    mintRecipient: string;
    amount: bigint;
    messageSender: string;
    maxFee: bigint;
    hookData: string;
  };
}): number[] {
  const messageBuffer: number[] = [];

  // Append version (4 bytes)
  appendU32BE(messageBuffer, params.version);

  // Append source_domain (4 bytes)
  appendU32BE(messageBuffer, params.sourceDomain);

  // Append destination_domain (4 bytes)
  appendU32BE(messageBuffer, params.destinationDomain);

  // Append nonce (32 bytes)
  appendU256BE(messageBuffer, params.nonce);

  // Append sender (32 bytes)
  appendU256BE(messageBuffer, num.toBigInt(params.sender));

  // Append recipient (32 bytes)
  appendU256BE(messageBuffer, num.toBigInt(params.recipient));

  // Append destination_caller (32 bytes)
  appendU256BE(messageBuffer, num.toBigInt(params.destinationCaller));

  // Append min_finality_threshold (4 bytes)
  appendU32BE(messageBuffer, params.minFinalityThreshold);

  // Append finality_threshold_executed (4 bytes)
  appendU32BE(messageBuffer, params.finalityThresholdExecuted);

  // Append message_body (the burn message)
  const burnMessageBytes = constructBurnMessage(params.burnMessage);
  messageBuffer.push(...burnMessageBytes);

  return messageBuffer;
}
