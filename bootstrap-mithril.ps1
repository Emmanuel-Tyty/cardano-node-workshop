# Cardano Mithril Bootstrap for Windows
$ErrorActionPreference = "Stop"

# --- Configuration ---
$AGGREGATOR_ENDPOINT = "https://aggregator.pre-release-preview.api.mithril.network/aggregator"
$GENESIS_KEY_URL = "https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey"
$ANCILLARY_KEY_URL = "https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/ancillary.vkey"
$BIN_DIR = Join-Path $PSScriptRoot "bin"
$MITHRIL_BIN = Join-Path $BIN_DIR "mithril-client.exe"

Write-Host "`n🚀 Starting Cardano Mithril Bootstrap (Windows)" -ForegroundColor Cyan

# --- Initialization ---
if (!(Test-Path "docker-compose.yml")) {
    Write-Host "❌ Error: Please run this script from the workshop directory." -ForegroundColor Red
    exit 1
}

# Dependency check
if (!(Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Error: Docker is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

if (!(Test-Path $BIN_DIR)) { New-Item -ItemType Directory -Path $BIN_DIR | Out-Null }

# --- Install Mithril Client ---
if (!(Get-Command "mithril-client" -ErrorAction SilentlyContinue) -and !(Test-Path $MITHRIL_BIN)) {
    Write-Host "📦 Downloading Mithril client..." -ForegroundColor Yellow
    # We download the zip directly from GitHub for Windows
    $releaseUrl = "https://github.com/input-output-hk/mithril/releases/latest/download/mithril-client-latest-windows-x64.zip"
    $zipFile = Join-Path $env:TEMP "mithril.zip"
    Invoke-WebRequest -Uri $releaseUrl -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath $BIN_DIR -Force
    Remove-Item $zipFile
}

$RUN_MITHRIL = if (Get-Command "mithril-client" -ErrorAction SilentlyContinue) { "mithril-client" } else { $MITHRIL_BIN }

# --- Download Snapshot ---
$env:AGGREGATOR_ENDPOINT = $AGGREGATOR_ENDPOINT
$env:GENESIS_VERIFICATION_KEY = Invoke-RestMethod -Uri $GENESIS_KEY_URL
$env:ANCILLARY_VERIFICATION_KEY = Invoke-RestMethod -Uri $ANCILLARY_KEY_URL

Write-Host "📥 Downloading latest Cardano DB snapshot..." -ForegroundColor Yellow
if (Test-Path "db" -and (Get-ChildItem "db")) {
    Write-Host "Found existing 'db' directory. Skipping download."
} else {
    if (Test-Path "db") { Remove-Item "db" -Recurse -Force }
    & $RUN_MITHRIL cardano-db download latest --include-ancillary
}

# --- Docker Volume Restoration ---
Write-Host "🏗️ Restoring database into Docker volumes..." -ForegroundColor Yellow
docker compose stop cardano-relay cardano-bp

function Restore-Volume($volName) {
    Write-Host "Restoring to $volName..."
    $currentPath = (Get-Location).Path -replace '\\', '/'
    # Fix for Windows paths in Docker
    if ($currentPath -match '^[A-Z]:') {
        $currentPath = "/" + $currentPath[0].ToString().ToLower() + $currentPath.Substring(2)
    }
    
    docker run --rm `
      -v "${volName}:/data" `
      -v "${currentPath}/db:/source" `
      alpine sh -c "rm -rf /data/* && cp -r /source/* /data/"
}

Restore-Volume "cardano-relay-data"
Restore-Volume "cardano-bp-data"

Write-Host "✅ Databases restored. Starting relay..." -ForegroundColor Green
docker compose up -d cardano-relay

# --- Verification ---
Write-Host "📊 Verifying node health..." -ForegroundColor Cyan
Start-Sleep -Seconds 10
docker exec cardano-relay cardano-cli query tip --socket-path /ipc/node.socket --testnet-magic 2

Write-Host "`n🎉 Done! syncProgress will reach 1.00 shortly." -ForegroundColor Green
