import { RpcProvider, Account, Contract } from 'starknet';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import * as fs from 'fs/promises';
import * as path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Constants
export const DEVNET_URL = 'http://127.0.0.1:5050';

// Provider instance
export const provider = new RpcProvider({
  nodeUrl: DEVNET_URL,
});

export const toAccount = (accountConfig: { address: string, privateKey: string }): Account => {
  return new Account(provider, accountConfig.address, accountConfig.privateKey);
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

export const loadTokenMessengerMinter = async (): Promise<TokenMessengerMinterInfo> => {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, 'resources/accounts.json'), 'utf8'));
  // Load contract addresses
  const contractsPath = path.join(__dirname, 'resources/contracts.json');
  const contracts = JSON.parse(await fs.readFile(contractsPath, 'utf8'));

  // Load Token Messenger Minter ABI
  const tmmAbiPath = path.join(__dirname, 'resources/token_messenger_minter.abi.json');
  const tmmAbi = JSON.parse(await fs.readFile(tmmAbiPath, 'utf8'));

  // Setup contract instance
  const tokenMessengerMinter = {
    contract: new Contract(
      tmmAbi,
      contracts.tokenMessengerMinter,
      provider
    ),
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
}
