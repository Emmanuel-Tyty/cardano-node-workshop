# Cardano Stake Pool Operator Workshop Guide

This guide walks you through setting up a Cardano relay node and registering a stake pool on the Preview testnet.

> **Before you begin:** Complete the [Attendee Pre-requisites Checklist](attendee-prereqs.md) — your node must be synced to ≥90% before you can submit transactions.

---

## Part 1: Relay Node Setup

A relay node is the public-facing entry point for your stake pool. It handles networking and protects your block-producing node from the internet.

### 1. Start the Relay Node

The workshop uses Docker to simplify the installation.

```bash
cd cardano-node-workshop
docker compose up -d cardano-relay
```

### 2. Fast Sync with Mithril (Optional but Recommended)

Syncing from scratch can take several hours. Use this script to download a verified snapshot in minutes.

```bash
# For Linux / macOS / WSL2
bash bootstrap-mithril.sh

# For Windows (PowerShell)
.\bootstrap-mithril.ps1
```

### 3. Verify the Node

Check the sync progress. You want `syncProgress` to reach `1.00`.

```bash
docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2
```

### 4. Configuration Files

The node image automatically downloads configuration for the Preview testnet:
- `config.json`: Node behavior and logging.
- `topology.json`: Peer-to-peer connection settings.
- `genesis.json`: Initial state of the network.

---

## Part 2: SPO Setup

Now that your relay is running, you will generate the keys and certificates required to run a stake pool.

### 1. Key Architecture

- **Cold Keys**: Your pool's identity. In production, these stay offline.
- **KES Keys**: Hot signing keys for minting blocks. Rotate every ~90 days.
- **VRF Keys**: Prove you won the "slot lottery" to mint a block.
- **Operational Certificate (opcert)**: Authorizes your KES key using your cold key.

### 2. Generate Keys

Set up your workspace and generate the required keys.

```bash
mkdir -p keys/{cold-keys,bp-keys,pool-keys} transactions
alias ccli='docker exec -w /workspace cardano-relay cardano-cli'

# Generate Cold keys
ccli node key-gen \
  --cold-verification-key-file keys/cold-keys/cold.vkey \
  --cold-signing-key-file      keys/cold-keys/cold.skey \
  --operational-certificate-issue-counter keys/cold-keys/cold.counter

# Generate KES keys
ccli node key-gen-KES \
  --verification-key-file keys/bp-keys/kes.vkey \
  --signing-key-file      keys/bp-keys/kes.skey

# Generate VRF keys
ccli node key-gen-VRF \
  --verification-key-file keys/bp-keys/vrf.vkey \
  --signing-key-file      keys/bp-keys/vrf.skey
```

### 3. Issue Operational Certificate

Calculate the current KES period and sign the KES key with your cold key.

```bash
CURRENT_SLOT=$(ccli query tip --testnet-magic 2 | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['slot'])")
KES_PERIOD=$((CURRENT_SLOT / 129600))

ccli node issue-op-cert \
  --kes-verification-key-file             keys/bp-keys/kes.vkey \
  --cold-signing-key-file                 keys/cold-keys/cold.skey \
  --operational-certificate-issue-counter keys/cold-keys/cold.counter \
  --kes-period $KES_PERIOD \
  --out-file keys/bp-keys/node.cert
```

### 4. Start the Block-Producing Node

The block producer (BP) node connects only to your relay and uses your signing keys to mint blocks.

```bash
docker compose up -d cardano-bp
```

### 5. Generate Payment Keys

You need a funded payment address to pay the pool deposit and transaction fees.

```bash
ccli address key-gen \
  --verification-key-file keys/payment.vkey \
  --signing-key-file      keys/payment.skey

ccli address build \
  --payment-verification-key-file keys/payment.vkey \
  --testnet-magic 2 \
  --out-file keys/payment.addr

cat keys/payment.addr
```

Fund the address from the Preview faucet: https://docs.cardano.org/cardano-testnets/tools/faucet/

Wait a few minutes, then confirm the funds arrived:

```bash
ccli query utxo \
  --address $(cat keys/payment.addr) \
  --testnet-magic 2
```

### 6. Pool Registration

Generate stake keys and create the registration certificates.

```bash
# Generate stake keys
ccli stake-address key-gen \
  --verification-key-file keys/pool-keys/stake.vkey \
  --signing-key-file      keys/pool-keys/stake.skey

ccli stake-address build \
  --stake-verification-key-file keys/pool-keys/stake.vkey \
  --testnet-magic 2 \
  --out-file keys/pool-keys/stake.addr

# Get your relay's public IP
RELAY_HOST=$(curl -4 -s ifconfig.me)
RELAY_PORT=3001
echo "Relay IP: $RELAY_HOST"

ccli stake-pool registration-certificate \
  --cold-verification-key-file keys/cold-keys/cold.vkey \
  --vrf-verification-key-file  keys/bp-keys/vrf.vkey \
  --pool-pledge 100000000 \
  --pool-cost   340000000 \
  --pool-margin 0.01 \
  --pool-reward-account-verification-key-file keys/pool-keys/stake.vkey \
  --pool-owner-stake-verification-key-file    keys/pool-keys/stake.vkey \
  --testnet-magic 2 \
  --pool-relay-ipv4 $RELAY_HOST \
  --pool-relay-port $RELAY_PORT \
  --metadata-url "https://example.com/poolmeta.json" \
  --metadata-hash "0000000000000000000000000000000000000000000000000000000000000000" \
  --out-file keys/pool-keys/pool.cert

# Create stake address registration certificate
ccli stake-address registration-certificate \
  --stake-verification-key-file keys/pool-keys/stake.vkey \
  --out-file keys/pool-keys/stake-reg.cert
```

### 7. Submit Registration Transaction

Submit the certificates to the blockchain. This requires three signatures: your payment key, your stake key, and your cold key.

```bash
# Get UTXO from your payment address (ensure it has funds from the faucet)
PAYMENT_ADDR=$(cat keys/payment.addr)
ccli query utxo --address $PAYMENT_ADDR --testnet-magic 2

# Build transaction
UTXO="TX_HASH#TX_INDEX"
ccli transaction build \
  --testnet-magic 2 \
  --tx-in "$UTXO" \
  --change-address $PAYMENT_ADDR \
  --certificate-file keys/pool-keys/stake-reg.cert \
  --certificate-file keys/pool-keys/pool.cert \
  --witness-override 3 \
  --out-file /workspace/transactions/reg.txbody

# Sign transaction
ccli transaction sign \
  --tx-body-file /workspace/transactions/reg.txbody \
  --signing-key-file keys/payment.skey \
  --signing-key-file keys/pool-keys/stake.skey \
  --signing-key-file keys/cold-keys/cold.skey \
  --testnet-magic 2 \
  --out-file /workspace/transactions/reg.tx

# Submit
ccli transaction submit --tx-file /workspace/transactions/reg.tx --testnet-magic 2
```

### 8. Verify Your Pool

Find your Pool ID and check it on the explorer.

```bash
ccli stake-pool id \
  --cold-verification-key-file keys/cold-keys/cold.vkey \
  --output-format hex
```

Explorer: `https://preview.cardanoscan.io/pool/<YOUR_POOL_ID>`

---

## Maintenance

### KES Rotation
KES keys expire every ~90 days. You must generate a new KES key and issue a new operational certificate before they expire.

### Monitoring
Check your node health regularly:
- Sync status: `ccli query tip --testnet-magic 2`
- Peer connections: `ccli query peer-info --testnet-magic 2`
