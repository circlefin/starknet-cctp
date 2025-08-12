# CCTP Starknet Deployment Guide

This comprehensive guide walks you through deploying Cross-Chain Transfer Protocol (CCTP) contracts on Starknet networks, from local development to sepolia/production environments.

## 📋 Overview

The deployment process involves two main contracts:
- **MessageTransmitter**: Handles cross-chain message transmission and verification
- **TokenMessengerMinter**: Manages token burning and minting operations

## Local Development Deployment

1. **Start the local network**:
   ```bash
   yarn start-network
   ```

   This spins up a local Starknet node using [`starknet-devnet`](https://github.com/0xSpaceShard/starknet-devnet) at `http://127.0.0.1:5050`.

2. **Choose Deployer Account**
   
   The local network provides prefunded accounts. Select one from the startup logs for deployment.

### Deploy Contracts

Execute the deployment command:

```bash
yarn scripts deploy-and-initialize-contracts \
    --rpc-url http://127.0.0.1:5050 \
    --deployer-key <DEPLOYER_PRIVATE_KEY> \
    --deployer-address <DEPLOYER_ADDRESS> \
    --config-path "./scripts/resources/default.json" \
    --mt-admin-key <MESSAGE_TRANSMITTER_ADMIN_KEY> \
    --tmm-admin-key <TOKEN_MESSENGER_MINTER_ADMIN_KEY> \
    --profile dev
```

> [!NOTE]  
> Local deployments use default configurations from `./scripts/resources/default.json`. For sepolia/production deployments, copy `scripts/resources/contracts_template.json` and customize all settings.

## Sepolia/Production Network Deployment

For deploying to live Starknet networks (mainnet, sepolia, etc.), follow these steps:

### 1. Create and Fund Account

Create and deploy a dedicated account for the target network:

```bash
# Create account
sncast account create --network <NETWORK> --name <ACCOUNT_NAME>

# Example for Sepolia
sncast account create --network sepolia --name sepolia-deployer
```

### 2. Fund Your Account

**For Sepolia Testnet:**
1. Visit the [Starknet Faucet](https://starknet-faucet.vercel.app/)
2. Enter your account address
3. Request test STRK tokens

### 3. Deploy Account On-Chain

```bash
sncast account deploy --network <NETWORK> --name <ACCOUNT_NAME>

# Example
sncast account deploy --network sepolia --name sepolia-deployer
```

**Note:** You can use `sncast account list -p` to list the private key, public key and address of your deployed account.

### 4. Configure Contracts

**Copy the template:**

```bash
cp scripts/resources/contracts_template.json scripts/resources/<CONFIG_NAME>_config.json
```

**Fill in all required settings** in your config file

**Note:** If deploying to sepolia, you can repeat steps 1-3 for all roles (ie admin, owner, pauser, rescuer, attesterManager etc) on contracts and use them within the contract config file.

### 5. Deploy CCTP Contracts

Deploy the MessageTransmitterV2 and TokenMessengerMinterV2 contracts to the production network:

```bash
yarn scripts deploy-and-initialize-contracts \
    -r <RPC_URL> \
    --deployer-key <DEPLOYER_PRIVATE_KEY> \
    --deployer-address <DEPLOYER_ADDRESS> \
    --config-path "<PATH_TO_CONFIG_FILE (ie ./scripts/resources/default.json)>" \
    --mt-admin-key <MESSAGE_TRANSMITTER_ADMIN_KEY> \
    --tmm-admin-key <TOKEN_MESSENGER_MINTER_ADMIN_KEY> \
    --profile <BUILD_PROFILE (ie dev/release)>
```

**Note:** Contracts deployed on localnet should use the `dev` build while contracts deployed to `testnet` or `mainnet` should use the `release` build.

## Network Configuration

- **Local**: `http://localhost:5050` (via starknet-devnet)
- **Sepolia Testnet**: `https://starknet-sepolia.public.blastapi.io/rpc/v0_8`

## Build Profiles for Deployment

Choose the appropriate build profile:

- **Development/Testing**: Use `SCARB_PROFILE=dev scarb build`

  - Faster compilation
  - Includes debug information
  - Not optimized for gas

- **Production**: Use `SCARB_PROFILE=release scarb build`
  - Optimized for gas efficiency
  - Smaller contract size
  - Production-ready

## Security Considerations

### For Production Deployments

1. **Private Key Security:**

   - Never commit private keys to version control
   - Use environment variables or secure key management
   - Consider using hardware wallets for mainnet
   - When passing admin keys via command line, ensure your shell history is secure or disabled
   - Consider using environment variables: `--mt-admin-key $MT_ADMIN_KEY`

2. **Configuration Verification:**

   - Double-check all addresses in your contract configuration
   - Verify contract parameters before deployment
   - Test thoroughly on testnets first

3. **Network Verification:**
   - Confirm you're deploying to the correct network
   - Verify RPC endpoint is correct and trusted
   - Check network fees and gas limits

## Troubleshooting

### Common Deployment Issues

1. **Insufficient Funds**: Ensure your deployer account has enough STRK or ETH for gas fees
2. **Network Connection**: Verify RPC endpoint is accessible and correct
3. **Network Compatibility**: Verify that the version of the RPC endpoint is compatible with the version of the tooling you're using (ie scripts using outdated versions of the starknet js library may not be compatible with the latest RPC version)
4. **Account Not Deployed**: Make sure you've deployed your account before contract deployment
5. **Configuration Errors**: Validate your token configuration file format and values

### Verification Steps

After deployment:

1. Verify the contract address matches expected calculations
2. Check that contract initialization was successful
3. Confirm all roles and permissions are set correctly
4. Run the bytecode verification script and ensure all tests pass successfully
5. Test basic contract functionality (if on testnet)

# Scripts References
## Compute Class Hash

Compute the class hash from a compiled contract file without declaring it to the network.

### Usage

```bash
yarn scripts compute-class-hash \
  --contract-name <contract name> \
  --profile <PROFILE>
```

### Parameters

- **`--contract-name`**: Provide the contract name: messageTransmitterV2 or tokenMessengerMinterV2.
- **`--profile`** (optional): Scarb profile that was used to build the contracts ('dev' or 'release'). Default profile is 'dev'.

### Examples

**Checking messageTransmitterV2 contract:**

```bash
yarn scripts compute-class-hash \
  --contract-name messageTransmitterV2 \
  --profile release
```

### Output

```
Contract name: messageTransmitterV2
Class hash: 0xc86418de43b6ca38ef7d12aacd064ddf053b3b8695394e992832a513640d4c
```

## Calculate Deployment Address

Calculate the contract address before deployment to predict where your contract will be deployed.

### Usage

```bash
yarn scripts calculate-deployment-address \
  --class-hash <CLASS_HASH> \
  --salt <SALT> \
  --constructor-calldata <ARG1> <ARG2> ...
```

### Parameters

- **`--class-hash`** (required): The class hash of the contract
- **`--salt`** (optional): Salt for address calculation (defaults to "0")
- **`--constructor-calldata`** (optional): Constructor arguments (defaults to empty array)

### Example

```bash
yarn scripts calculate-deployment-address \
  --class-hash 0xc86418de43b6ca38ef7d12aacd064ddf053b3b8695394e992832a513640d4c \
  --salt 0 \
  --constructor-calldata \
  0x064b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691
```

### Output

```
class hash: 0xc86418de43b6ca38ef7d12aacd064ddf053b3b8695394e992832a513640d4c
contract address: 0x68c2c6e73ccbfb82f2c299ca325176f0335390fa3940067d809625849a2498c
```

## Deploy and Initialize Contracts

Deploy and initialize CCTP contracts with all necessary configuration.

### Usage

```bash
yarn scripts deploy-and-initialize-contracts \
  -r <RPC_URL> \
  --deployer-key <PRIVATE_KEY> \
  --deployer-address <ADDRESS> \
  --config-path <CONFIG_PATH> \
  --mt-admin-key <MT_ADMIN_KEY> \
  --tmm-admin-key <TMM_ADMIN_KEY> \
  --profile <PROFILE>
```

### Parameters

- **`-r, --rpc-url`** (required): RPC URL for the target network
- **`--deployer-key`** (required): Private key of the deployer account
- **`--deployer-address`** (required): Address of the deployer account
- **`--config-path`** (required): Path to the token configuration JSON file
- **`--mt-admin-key`** (required): Message Transmitter admin private key
- **`--tmm-admin-key`** (required): Token Messenger Minter admin private key
- **`--salt`** (optional): Salt for contract deployment. Default value is "0"
- **`--profile`** (optional): Build profile to use ('dev' or 'release'). Default is 'release'.

### Examples

**Local Network:**

```bash
yarn scripts deploy-and-initialize-contracts \
  -r http://localhost:5050 \
  --deployer-key 0x1234... \
  --deployer-address 0x5678... \
  --config-path "./scripts/resources/default.json" \
  --mt-admin-key 0xABCD... \
  --tmm-admin-key 0xEFGH... \
  --profile dev
```

**Sepolia Testnet:**

```bash
yarn scripts deploy-and-initialize-contracts \
  -r https://starknet-sepolia.public.blastapi.io/rpc/v0_8 \
  --deployer-key 0x36fd2719940a65a3f77223657992f914bc49b638bebb1560185ff791c48cdbb \
  --deployer-address 0x06ae696e73762dfe81b76c96bfbe7a0ae600f8e22811bf172347a63f972e7f83 \
  --config-path "./scripts/resources/default.json" \
  --mt-admin-key 0x1234... \
  --tmm-admin-key 0x5678... \
  --profile release
```

### Configuration Files

The script uses JSON configuration files to set up the token:

- **`default.json`**: Default configuration for testing and development
- **`contracts.template.json`**: Template for production/testnet deployments

For production deployments, copy the template and fill in all required values:

```bash
cp scripts/resources/contracts_template.json my_production_config.json
# Edit my_production_config.json with your values
```

> [!IMPORTANT]
> In Starknet, account addresses are smart contract addresses and cannot be derived from private keys. Therefore, you must provide the admin private keys separately via command-line options (`--mt-admin-key` and `--tmm-admin-key`) that correspond to the admin addresses configured in your JSON configuration file.

## Verify Contract State

Verify that a deployed contract's state matches the expected configuration. This script compares on-chain values with expected values from a token configuration file to ensure proper deployment and initialization.

### Usage

```bash
yarn scripts verify-contract-state \
  --rpc-url <RPC_URL> \
  --message-transmitter-contract-address <CONTRACT_ADDRESS> \
  --token-messenger-minter-contract-address <CONTRACT_ADDRESS> \
  --config-path <CONFIG_PATH>
```

### Parameters

- **`--rpc-url`** (required): RPC URL for the target network
- **`--message-transmitter-contract-address`** (required): Address of the deployed messageTransmmiterV2 contract to verify
- **`--token-messenger-minter-contract-address`** (required): Address of the deployed tokenMessengerMinterV2 contract to verify
- **`--config-path`** (required): Path to the contract configuration JSON file

### Examples

```bash
yarn scripts verify-contract-state \
  --rpc-url http://localhost:5050 \
  --message-transmitter-contract-address=0x68c2c6e73ccbfb82f2c299ca325176f0335390fa3940067d809625849a2498c \
  --token-messenger-minter-contract-address=0x35be01e7e809410bcc827cdc944d7658427be7b119f1fc9f33724289ad6a6fe \
  --config-path="./scripts/resources/default.json"
```

### What It Verifies

The script verifies the following contract state variables against the configuration file:

* messageTransmitterV2
  * config: local domain id, version, signatureThreshold, maxMessageBodySize
  * roles: admin, owner, pauser, rescuer, attesterManager, attesters

* tokenMessengerMinterV2
  * config: messageBodyVersion, remoteDomainMessengers
  * roles: admin, owner, pauser, denylister, rescuer, tokenController, minFeeController, feeRecipient


### Output

The script provides detailed verification results with color-coded status messages:

**Successful Verification:**

```
===== Contract State Verification Results =====

✅ STATE VERIFICATION PASSED - localDomain matches expected value
  Value: 25

✅ STATE VERIFICATION PASSED - version matches expected value
  Value: 1

✅ STATE VERIFICATION PASSED - admin matches expected value
  Value: 2846891009026995430665703316224827616914889274105712248413538305735679628945

✅ STATE VERIFICATION PASSED - owner matches expected value
  Value: 2846891009026995430665703316224827616914889274105712248413538305735679628945

✅ STATE VERIFICATION PASSED - pauser matches expected value
  Value: 2088382520822101438622848791645965515244906237111619041539381827895598052238

✅ STATE VERIFICATION PASSED - rescuer matches expected value
  Value: 376475558541706534617805357327539442513854110774346318494410214781103070389

✅ STATE VERIFICATION PASSED - attesterManager matches expected value
  Value: 863593130030508859995274930609320645967251762530214051423444504129298554488

✅ STATE VERIFICATION PASSED - signatureThreshold matches expected value
  Value: 1

✅ STATE VERIFICATION PASSED - maxMessageBodySize matches expected value
  Value: 1000

✅ STATE VERIFICATION PASSED - attester 0x47E832D17C7a6F44787d6B71aBE1092e69de760A matches expected value
  Value: true

✅ STATE VERIFICATION PASSED - attester 0x8ADB4389439BD6fCDAf0520C14a0CAbA3Da22C86 matches expected value
  Value: true

✅ STATE VERIFICATION PASSED - admin matches expected value
  Value: 2846891009026995430665703316224827616914889274105712248413538305735679628945

✅ STATE VERIFICATION PASSED - owner matches expected value
  Value: 2846891009026995430665703316224827616914889274105712248413538305735679628945

✅ STATE VERIFICATION PASSED - pauser matches expected value
  Value: 2088382520822101438622848791645965515244906237111619041539381827895598052238

✅ STATE VERIFICATION PASSED - denylister matches expected value
  Value: 2239093708642760634850621647057638003055498576820834977003174853173448812499

✅ STATE VERIFICATION PASSED - rescuer matches expected value
  Value: 376475558541706534617805357327539442513854110774346318494410214781103070389

✅ STATE VERIFICATION PASSED - tokenController matches expected value
  Value: 863593130030508859995274930609320645967251762530214051423444504129298554488

✅ STATE VERIFICATION PASSED - minFeeController matches expected value
  Value: 2416567947955609863780400577866930700537357018869990854524703278967938174078

✅ STATE VERIFICATION PASSED - feeRecipient matches expected value
  Value: 97550372959780798398538416273147719574966389149887675199750347649434706031

✅ STATE VERIFICATION PASSED - messageBodyVersion matches expected value
  Value: 1

✅ STATE VERIFICATION PASSED - remoteTokenMessenger 1 matches expected value
  Value: 4096

✅ STATE VERIFICATION PASSED - remoteTokenMessenger 2 matches expected value
  Value: 8192

✅ STATE VERIFICATION PASSED - remoteTokenMessenger 3 matches expected value
  Value: 12288

==================================================
```

**Failed Verification:**

```
===== Contract State Verification Results =====

❌ STATE VERIFICATION FAILED - attester 0x47E832D17C7a6F44787d6B71aBE1092e69de760A mismatch
  On-chain: false
  Expected: true

❌ STATE VERIFICATION FAILED - attester 0x8ADB4389439BD6fCDAf0520C14a0CAbA3Da22C86 mismatch
  On-chain: false
  Expected: true
==================================================
```

## Verify Onchain Bytecode

Verify that deployed contract bytecode matches your local compiled artifacts. This script helps ensure that what's deployed on-chain matches your local compilation by comparing class hashes and optionally the full CASM bytecode.

### Usage

```bash
yarn scripts verify-onchain-bytecode \
  --rpc-url <RPC_URL> \
  --contract-address <CONTRACT_ADDRESS> \
  --contract-name <CONTRACT_NAME> \
  [--contract-creation-tx-hash <TX_HASH>] \
  [--verification-type <TYPE>] \
  [--local-artifact-contract-path <PATH>] \
  [--local-artifact-compiled-contract-path <PATH>] \
  [--profile <PROFILE>]
```

### Parameters

- **`--rpc-url`** (required): RPC URL for the target network
- **`--contract-address`** (required): Address of the deployed contract to verify
- **`--contract-name`** (required): The contract name: messageTransmitterV2 or tokenMessengerMinterV2.
- **`--contract-creation-tx-hash`** (optional): Transaction hash of contract creation (for additional deployment details)
- **`--verification-type`** (optional): Type of verification to perform ('class-hash' or 'full-bytecode'). Default is 'full-bytecode'
- **`--profile`** (optional): Build profile ('dev' or 'release'). Default is 'release'.

### Verification Types

- **`class-hash`**: Only verifies that the class hash matches between local and on-chain
- **`full-bytecode`**: Verifies both class hash and the complete CASM bytecode (more thorough)

### Examples

**Full verification with transaction details:**

```bash
yarn scripts verify-onchain-bytecode \
  --rpc-url=http://127.0.0.1:5050 \
  --contract-address=0x68c2c6e73ccbfb82f2c299ca325176f0335390fa3940067d809625849a2498c \
  --contract-name=messageTransmitterV2 \
  --contract-creation-tx-hash=0x7d26ef8d36228e8b85c058e670bae23c0c7a7a1a28eb43a6722cd9fc5bb4c12 \
  --verification-type=full-bytecode \ 
  --profile release 
```

**Class hash only verification:**

```bash
yarn scripts verify-onchain-bytecode \
  --rpc-url=http://127.0.0.1:5050 \
  --contract-address=0x68c2c6e73ccbfb82f2c299ca325176f0335390fa3940067d809625849a2498c \ 
  --contract-name=messageTransmitterV2 \
  --verification-type class-hash \
  --profile release
```

### Output

The script provides detailed verification results:

**Successful Verification:**

```
===== Contract Creation Details =====
Transaction Hash: 0x7d26ef8d36228e8b85c058e670bae23c0c7a7a1a28eb43a6722cd9fc5bb4c12
Transaction Type: INVOKE
Transaction Version: 0x3
======================================


===== Starknet Bytecode Verification Results =====

✅ VERIFICATION PASSED - class hash matches local compilation
   class hash: 0xc86418de43b6ca38ef7d12aacd064ddf053b3b8695394e992832a513640d4c
✅ VERIFICATION PASSED - CASM bytecode matches local compilation
   CASM bytecode: ["0x40780017fff7fff","0x6","0xa0680017fff8000","0x7","0x482680017ffa8000","0xfffffffffffffffffffffff...

==================================================
```

**Note:** The CASM bytecode is truncated to 100 characters. To view the full bytecode, look at the build file located at `target/{profile}/{package}_{contract}.compiled_contract_class.json`.

**Failed Verification:**

```
===== Contract Creation Details =====
Transaction Hash: 0x7cba0ec1d41e334dfbfcbbfef27ad413ffac4223ae2408ad41b416b112c283d
Transaction Type: INVOKE
Transaction Version: 0x3
======================================


===== Starknet Bytecode Verification Results =====

❌ VERIFICATION FAILED - class hash mismatch
  On-chain: 0x5f523cc45c1a63b5321b64dcb75e384086ecba5e9cf8c0aaf49dd5789c38481
  Local:    0x1489191175bc010aa62396dc03676ab97f4d9ef7b7a9abcc667003170c25a33
❌ VERIFICATION FAILED - CASM bytecode mismatch
  On-chain: ["0xa0680017fff8000","0x7","0x482680017ffa8000","0xffffffffffffffffffffffffffffc842","0x400280007ff9...
  Local:    ["0xa0680017fff8000","0x7","0x482680017ffa8000","0x100000000000000000000000000000000","0x400280007ff...

==================================================
```
