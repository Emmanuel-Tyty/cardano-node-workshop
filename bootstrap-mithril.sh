#!/bin/bash
set -e

# --- Configuration ---
AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
GENESIS_KEY_URL="https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey"
ANCILLARY_KEY_URL="https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/ancillary.vkey"
BIN_DIR="./bin"
MITHRIL_BIN="$BIN_DIR/mithril-client"

# --- Timing ---
START_TIME=$(date +%s)

elapsed() {
    local secs=$(( $(date +%s) - START_TIME ))
    printf "%dm%02ds" $(( secs / 60 )) $(( secs % 60 ))
}

step_elapsed() {
    local secs=$(( $(date +%s) - $1 ))
    printf "%dm%02ds" $(( secs / 60 )) $(( secs % 60 ))
}

# --- Output helpers ---
echo_step()    { echo -e "\n🚀 \033[1;34m$1\033[0m  [$(elapsed) elapsed]"; }
echo_success() { echo -e "✅ \033[1;32m$1\033[0m"; }
echo_error()   { echo -e "❌ \033[1;31m$1\033[0m"; }
echo_info()    { echo -e "   ℹ️  $1"; }

check_dep() {
    if ! command -v "$1" &> /dev/null; then
        echo_error "Missing dependency: $1"
        exit 1
    fi
}

# --- Initialization ---
echo_step "Starting Cardano Mithril Bootstrap"
echo_info "Started at: $(date)"

# Detect OS
OS_TYPE="linux"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
fi
echo_info "Detected OS: $OS_TYPE"

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
    STEP_START=$(date +%s)
    curl --proto '=https' --tlsv1.2 -sSf \
      https://raw.githubusercontent.com/input-output-hk/mithril/refs/heads/main/mithril-install.sh \
      | sh -s -- -c mithril-client -d latest -p "$BIN_DIR/"
    echo_success "Mithril client installed in $(step_elapsed $STEP_START)"
else
    echo_success "Mithril client is already installed."
fi

# Determine binary to use
if command -v mithril-client &> /dev/null; then
    RUN_MITHRIL="mithril-client"
else
    RUN_MITHRIL="$MITHRIL_BIN"
fi
echo_info "Using: $($RUN_MITHRIL --version 2>&1 | head -1)"

# --- Download Snapshot ---
export AGGREGATOR_ENDPOINT
export GENESIS_VERIFICATION_KEY=$(curl -fsSL "$GENESIS_KEY_URL")
export ANCILLARY_VERIFICATION_KEY=$(curl -fsSL "$ANCILLARY_KEY_URL")

echo_step "Downloading latest Cardano DB snapshot..."

if [ -d "db" ] && [ "$(ls -A db 2>/dev/null)" ]; then
    DB_SIZE=$(du -sh db 2>/dev/null | cut -f1 || echo "unknown")
    echo_info "Found existing 'db' directory ($DB_SIZE). Skipping download."
    echo_info "To force a fresh download: rm -rf db && bash bootstrap-mithril.sh"
else
    rm -rf db
    DOWNLOAD_START=$(date +%s)
    $RUN_MITHRIL cardano-db download latest --include-ancillary
    DB_SIZE=$(du -sh db 2>/dev/null | cut -f1 || echo "unknown")
    echo_success "Downloaded ${DB_SIZE} in $(step_elapsed $DOWNLOAD_START)"
fi

DB_SIZE=$(du -sh db 2>/dev/null | cut -f1 || echo "unknown")
echo_info "Snapshot size on disk: $DB_SIZE"

# --- Docker Volume Restoration ---
if ! docker ps &> /dev/null; then
    echo_error "Docker is not running or you don't have permissions."
    exit 1
fi

# Docker Compose prefixes volume names with the project name (defaults to directory name)
PROJECT_NAME=$(basename "$(pwd)")
echo_info "Docker Compose project: $PROJECT_NAME"

echo_step "Restoring database into Docker volumes..."
echo "   🛑 Stopping services..."
docker compose stop cardano-relay cardano-bp 2>/dev/null || true

restore_volume() {
    local vol_name="${PROJECT_NAME}_$1"
    local RESTORE_START=$(date +%s)
    echo_info "Restoring to $vol_name..."
    docker run --rm \
      -v "$vol_name":/data \
      -v "$(pwd)/db":/source \
      alpine sh -c "rm -rf /data/* && cp -r /source/* /data/"
    echo_success "Restored $vol_name in $(step_elapsed $RESTORE_START)"
}

restore_volume "cardano-relay-data"
restore_volume "cardano-bp-data"

echo_step "Starting relay node..."
docker compose up -d cardano-relay

# --- Verification ---
echo_step "Verifying node health..."
MAX_RETRIES=12
RETRY_COUNT=0
until docker exec cardano-relay ls /ipc/node.socket &> /dev/null || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    echo_info "Waiting for node socket... ($((RETRY_COUNT+1))/$MAX_RETRIES) [$(elapsed) elapsed]"
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo_error "Node socket not found after 60s. Check: docker compose logs cardano-relay"
    exit 1
fi

echo ""
docker exec cardano-relay cardano-cli query tip --socket-path /ipc/node.socket --testnet-magic 2
echo ""
echo_success "Bootstrap complete in $(elapsed)! syncProgress will reach 1.00 shortly."
