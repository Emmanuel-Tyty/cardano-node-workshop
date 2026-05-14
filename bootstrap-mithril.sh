#!/bin/bash
set -e

# --- Configuration ---
AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
GENESIS_KEY_URL="https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey"
ANCILLARY_KEY_URL="https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/ancillary.vkey"
BIN_DIR="./bin"
MITHRIL_BIN="$BIN_DIR/mithril-client"

# --- Functions ---
echo_step() { echo -e "\n🚀 \033[1;34m$1\033[0m"; }
echo_success() { echo -e "✅ \033[1;32m$1\033[0m"; }
echo_error() { echo -e "❌ \033[1;31m$1\033[0m"; }

check_dep() {
    if ! command -v "$1" &> /dev/null; then
        echo_error "Missing dependency: $1"
        exit 1
    fi
}

# --- Initialization ---
echo_step "Starting Cardano Mithril Bootstrap"

# Detect OS
OS_TYPE="linux"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
fi

# Ensure we are in the workshop directory
if [[ ! -f "docker-compose.yml" ]]; then
    echo_error "Please run this script from the workshop directory."
    exit 1
fi

# Dependency check
check_dep "curl"
check_dep "docker"

mkdir -p "$BIN_DIR"

# --- Install Mithril Client ---
if ! command -v mithril-client &> /dev/null && [ ! -f "$MITHRIL_BIN" ]; then
    echo_step "Installing Mithril client..."
    curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/input-output-hk/mithril/refs/heads/main/mithril-install.sh | sh -s -- -c mithril-client -d latest -p "$BIN_DIR/"
else
    echo_success "Mithril client is already installed."
fi

# Determine binary to use
if command -v mithril-client &> /dev/null; then
    RUN_MITHRIL="mithril-client"
else
    RUN_MITHRIL="$MITHRIL_BIN"
fi

# --- Download Snapshot ---
export AGGREGATOR_ENDPOINT
export GENESIS_VERIFICATION_KEY=$(curl -fsSL "$GENESIS_KEY_URL")
export ANCILLARY_VERIFICATION_KEY=$(curl -fsSL "$ANCILLARY_KEY_URL")

echo_step "Downloading latest Cardano DB snapshot..."
# Idempotent: check if a valid DB already exists locally to avoid re-download
if [ -d "db" ] && [ "$(ls -A db)" ]; then
    echo "Found existing 'db' directory. Skipping download."
    echo "To force a fresh download, run 'rm -rf db' and restart this script."
else
    rm -rf db
    $RUN_MITHRIL cardano-db download latest --include-ancillary
fi

# --- Docker Volume Restoration ---
if ! docker ps &> /dev/null; then
    echo_error "Docker is not running or you don't have permissions."
    exit 1
fi

echo_step "Restoring database into Docker volumes..."
echo "🛑 Stopping services..."
docker compose stop cardano-relay cardano-bp

# Function to restore to a volume
restore_volume() {
    local vol_name=$1
    echo "🏗️ Restoring to $vol_name..."
    docker run --rm \
      -v "$vol_name":/data \
      -v "$(pwd)/db":/source \
      alpine sh -c "rm -rf /data/* && cp -r /source/* /data/"
}

restore_volume "cardano-relay-data"
restore_volume "cardano-bp-data"

echo_step "Starting relay node..."
docker compose up -d cardano-relay

# --- Verification ---
echo_step "Verifying node health..."
# Wait for socket to be created
MAX_RETRIES=10
RETRY_COUNT=0
until docker exec cardano-relay ls /ipc/node.socket &> /dev/null || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    echo "Waiting for node socket... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo_error "Node socket not found after 50s. Check logs with 'docker compose logs cardano-relay'"
else
    docker exec cardano-relay cardano-cli query tip --socket-path /ipc/node.socket --testnet-magic 2
    echo_success "Bootstrap complete! syncProgress will reach 1.00 shortly."
fi
