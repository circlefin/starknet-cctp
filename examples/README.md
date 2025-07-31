# CCTP on Starknet Example Scripts

This directory provides example scripts for calling depositForBurn and receiveMessage on Starknet Devnet.

For more information see our [developer documentation](https://developers.circle.com/stablecoins/docs/cctp-getting-started).


## How It Works

1. **Burn**: USDC is burned on the source chain (e.g., Starknet)
2. **Attest**: Circle's attestation service signs the burn transaction
3. **Mint**: Native USDC is minted on the destination chain (e.g., Ethereum, Avalanche)

---

## Getting Started

### Prerequisites

**1. Install Starknet Foundry**
```bash
# Follow the installation guide
# https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html
```

**2. Install Dependencies**
```bash
npm install
```

**3. Set Up Your Wallet**

Create a new account on Starknet Sepolia testnet:
```bash
sncast account create --network sepolia --name my_cctp_account
```

This will create a new wallet and give you:
- An account address (your wallet address)
- A private key (keep this secret!)

**4. Configure Environment**

Copy the example environment file:
```bash
cp .env.example .env
```

**5. Update Your .env File**

Open `.env` and set these required variables:

```bash
# Your Starknet wallet details (from step 3)
ACCOUNT_ADDRESS=0x1234...  # Your account address
PRIVATE_KEY=0x5678...      # Your private key

# Where you want to receive tokens on EVM chains
REMOTE_EVM_ADDRESS=0x9abc...     # Your Ethereum/Avalanche address
REMOTE_EVM_PRIVATE_KEY=0xdef...  # Private key for EVM address
REMOTE_EVM_RPC_URL=https://...   # RPC URL for destination chain

# Optional: Change destination chain (default is Avalanche Fuji)
# For supported domain, please refer: https://developers.circle.com/cctp/supported-domains 
REMOTE_EVM_DOMAIN=1
```

**6. Get Test Tokens**

Get testnet USDC from the Circle faucet and gas token
- Visit: https://faucet.circle.com/
- Get USDC on both Starknet Sepolia and your chosen EVM testnet
- Get gas token for Starknet Sepolia and EVM testnet 

---

## Bridge Examples

### Starknet → EVM (e.g., to Avalanche)

**Fast Transfer Example:**
```bash
npm run bridge-v2 strk2evm -- --amount 100 --fastBurn true
```

**Standard Transfer Example:**
```bash
npm run bridge-v2 strk2evm -- --amount 100
```

### EVM → Starknet

**Fast Transfer Example:**
```bash
npm run bridge-v2 evm2strk -- --amount 100 --fastBurn true
```

**Standard Transfer Example:**
```bash
npm run bridge-v2 evm2strk -- --amount 100
```

### Using Hooks

Hooks allow you to execute custom logic when tokens are minted on the destination chain.

**Example:**
```bash
npm run bridge-v2 strk2evm -- --amount 100 --maxFee 1 --minFinalityThreshold 1000 --hookData 0x1234
```
