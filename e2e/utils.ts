import { RpcProvider, Account, Contract, num, ParsingStrategy, fastParsingStrategy, CairoByteArray } from "starknet";
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
  return new Account({
    provider,
    address: accountConfig.address,
    signer: accountConfig.privateKey,
  });
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

const customParsingStrategy: ParsingStrategy = {
  request: fastParsingStrategy.request,
  response: {
    ...fastParsingStrategy.response,
    [CairoByteArray.abiSelector]: (responseIterator: Iterator<string>) => {
      return CairoByteArray.factoryFromApiResponse(responseIterator).toBuffer();
    },
  },
};

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
    contract: new Contract({
      abi: stablecoinAbi,
      address: contracts.stablecoin,
      providerOrAccount: provider,
    }),
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
    contract: new Contract({
      abi: tmmAbi,
      address: contracts.tokenMessengerMinterV2,
      providerOrAccount: provider,
      parsingStrategy: customParsingStrategy,
    }),
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
    contract: new Contract({
      abi: mtAbi,
      address: contracts.messageTransmitterV2,
      providerOrAccount: provider,
      parsingStrategy: customParsingStrategy,
    }),
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
}): Uint8Array {
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

  return new Uint8Array(burnMessage);
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
}): Uint8Array {
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

  return new Uint8Array(messageBuffer);
}
