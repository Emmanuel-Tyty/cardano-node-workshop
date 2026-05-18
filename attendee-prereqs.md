# Before the Workshop — Attendee Checklist

Please complete everything here **the day before** the session. The node sync alone takes
time and cannot be done live.

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

The node image includes a built-in Mithril client. On first start it automatically downloads
a cryptographically verified chain snapshot — sync takes 15–45 minutes instead of hours.

Start the relay and leave it running overnight:

```bash
docker compose up -d cardano-relay
```

Watch the Mithril download and subsequent sync progress:

```bash
docker compose logs -f cardano-relay
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
mkdir -p {transactions,keys/{cold-keys,bp-keys,pool-keys}}
```

---

## 7. Optional: Fund a Testnet Wallet

During Part 2 you will need ~1000 test-ADA to register your pool.
Get funds from the Preview faucet before the session:
https://docs.cardano.org/cardano-testnets/tools/faucet/

You need your wallet address first — it will be generated live, but if you want
to follow along ahead of time:

```bash
# Generate payment keys
docker exec -w /workspace cardano-relay cardano-cli latest address key-gen \
  --verification-key-file keys/payment.vkey \
  --signing-key-file      keys/payment.skey

# Build address
docker exec -w /workspace cardano-relay cardano-cli latest address build \
  --payment-verification-key-file keys/payment.vkey \
  --testnet-magic 2 \
  --out-file keys/payment.addr

cat keys/payment.addr
```

Paste that address into the faucet to receive test ADA.

---

## 8. Ready for the Workshop?

Once your node is synced, you are ready to start the [Workshop Guide](guide.md).

---

## 9. Quick Sanity Check Before the Session

Run this the morning of the workshop:

```bash
docker exec cardano-relay cardano-cli query tip \
  --socket-path /ipc/node.socket --testnet-magic 2 \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Sync:', d['syncProgress'])"
```

If sync is below 0.90 the node is still catching up — give it more time.

---

## Questions?

Post in the workshop Discord channel or open a GitHub issue.
