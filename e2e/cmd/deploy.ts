import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { json, Account } from 'starknet';
import * as fs from 'fs/promises';
import * as path from 'path';
import { loadTokenMessengerMinter, provider } from '../utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function deploy() {
  const accounts = JSON.parse(await fs.readFile(path.join(__dirname, '../resources/accounts.json'), 'utf8'));

  console.log('🚀 Starting contract deployment...');
  
  // Load and deploy Token Messenger Minter
  console.log('Deploying Token Messenger Minter...');
  const adminAddress = accounts.token_messenger_minter.admin.address;
  const deployer = new Account(
    provider,
    accounts.token_messenger_minter.deployer.address,
    accounts.token_messenger_minter.deployer.privateKey
  );
  const tmmSierra = json.parse(
    await fs.readFile(
      path.join(__dirname, '../../target/dev/token_messenger_minter_TokenMessengerMinter.contract_class.json'), 
      'utf8'
    )
  );
  
  const tmmCasm = json.parse(
    await fs.readFile(
      path.join(__dirname, '../../target/dev/token_messenger_minter_TokenMessengerMinter.compiled_contract_class.json'), 
      'utf8'
    )
  );
  
  const tmmDeployResponse = await deployer.declareAndDeploy({
    contract: tmmSierra,
    casm: tmmCasm,
    salt: '0x0',
    constructorCalldata: [adminAddress],
  });
  
  console.log(`✅ Token Messenger Minter deployed: ${tmmDeployResponse.deploy.contract_address}`);
  
  // Save contract addresses to contracts.json
  const contracts = {
    tokenMessengerMinter: tmmDeployResponse.deploy.contract_address,
  };
  
  const contractsPath = path.join(__dirname, '../resources/contracts.json');
  await fs.writeFile(contractsPath, JSON.stringify(contracts, null, 2));
  console.log(`✅ Contract addresses saved to: ${contractsPath}`);
  
  // Save Token Messenger Minter ABI
  const tmmAbiPath = path.join(__dirname, '../resources/token_messenger_minter.abi.json');
  await fs.writeFile(tmmAbiPath, JSON.stringify(tmmSierra.abi, null, 2));
  console.log(`✅ Token Messenger Minter ABI saved to: ${tmmAbiPath}`);

  // Initialize
  const tokenMessengerMinter = await loadTokenMessengerMinter();
  tokenMessengerMinter.contract.connect(tokenMessengerMinter.admin);
  await tokenMessengerMinter.contract.initialize(
    tokenMessengerMinter.owner.address,
    tokenMessengerMinter.pauser.address,
    tokenMessengerMinter.denylister.address,
    tokenMessengerMinter.rescuer.address,
    tokenMessengerMinter.token_controller.address,
    tokenMessengerMinter.min_fee_controller.address,
    tokenMessengerMinter.fee_recipient.address,
    1,
    '0x1234', // TODO: add local message transmitter address
    [1, 2, 3], // Remote domains
    ['0x1000', '0x2000', '0x3000'] // Remote token messengers
  );
  console.log('✅ Token Messenger Minter initialized');
}

// Run deployment if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
    try {
        await deploy();
        console.log('✅ All deployments completed successfully!');
        process.exit(0);
    } catch (error) {
        console.error('❌ Deployment failed:', error);
        process.exit(1);
    }
}
