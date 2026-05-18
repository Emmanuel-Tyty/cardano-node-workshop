# Before the Workshop — Attendee Checklist

Please complete everything here **the day before** the session. The node sync alone takes
several hours and cannot be done live.

---

## 1. System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 8 GB | 16 GB |
| CPU | 2 cores | 4 cores |
| Disk | 30 GB free | 50 GB free (SSD) |
| OS | Ubuntu 22.04 / macOS / WSL2 | Ubuntu 22.04 |
| Network | Stable broadband | — |

---

## 2. Install Required Tools

```bash
# Docker
# macOS: install Docker Desktop from https://docs.docker.com/desktop/mac/install/
# Ubuntu:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version           # need 20+
docker compose version     # need 2+
```

---

## 3. Clone the Workshop Repo

```bash
git clone https://github.com/Emmanuel-Tyty/cardano-node-workshop.git
cd cardano-node-workshop
```

---

## 4. Start Syncing the Node NOW (do this today)

The node must reach >90% sync before you can submit transactions.
Run this and let it sync overnight:

```bash
cd cardano-cli-demo/workshop
docker compose up -d cardano-relay

# Watch sync progress (Ctrl+C to stop watching, node keeps running)
watch -n 10 'docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2'
```

You want `syncProgress` to show `"1.00"` before the session starts.

---

## 5. Verify Node is Running

```bash
docker ps | grep cardano-relay
# Should show "Up X hours"

docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2
# Should return JSON with block, epoch, syncProgress
```

---

## 6. Create Your Workspace Directories

```bash
mkdir -p ~/cardano-workshop/{transactions,keys/{cold-keys,bp-keys,pool-keys}}
```

---

## 7. Optional: Fund a Testnet Wallet

During Part 2 you will need ~1000 test-ADA to register your pool.
Get funds from the Preview faucet before the session:
https://docs.cardano.org/cardano-testnets/tools/faucet/

You need your wallet address first — Host B will generate one live, but if you want
to follow along you can generate yours ahead of time:

```bash
# Generate payment keys
docker exec -w /workspace cardano-relay cardano-cli address key-gen \
  --verification-key-file /workspace/keys/payment.vkey \
  --signing-key-file /workspace/keys/payment.skey

# Build address
docker exec -w /workspace cardano-relay cardano-cli address build \
  --payment-verification-key-file /workspace/keys/payment.vkey \
  --testnet-magic 2 \
  --out-file /workspace/keys/payment.addr

cat ~/cardano-workshop/keys/payment.addr
```

Paste that address into the faucet to receive test ADA.

---

## 8. Didn't Sync Overnight? Use Mithril Instead

If you're reading this the morning of the workshop and your node hasn't synced, use the provided automation script. It downloads a cryptographically verified snapshot signed by SPOs — sync goes from 4–8 hours down to 15–45 minutes depending on your connection.

> [!TIP]
> **Windows Users**: We strongly recommend using **WSL2 (Ubuntu)** for this workshop. If you are using native PowerShell, use the `.ps1` version of the script.

**For Linux / macOS / WSL2:**
```bash
cd cardano-cli-demo/workshop
bash bootstrap-mithril.sh
```

**For Windows (PowerShell):**
```powershell
cd cardano-cli-demo/workshop
.\bootstrap-mithril.ps1
```

The script will automatically:
1. Detect your OS.
2. Install the Mithril client if needed.
3. Download the latest Preview snapshot (idempotent).
4. Restore it into your Docker volumes and restart the relay.

Verify that your node is synced:
```bash
docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2
```

---

## 9. Ready for the Workshop?

Once your node is synced, you are ready to start the [Workshop Guide](guide.md).

## 9. Quick Sanity Check Before the Session

Run this the morning of the workshop:

```bash
docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2 \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Sync:', d['syncProgress'])"
```

If sync is below 0.90 and you have less than an hour, use the Mithril steps above.

---

## Questions?

Post in the workshop Discord channel or open a GitHub issue.
