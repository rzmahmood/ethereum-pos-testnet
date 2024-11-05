#!/bin/bash

set -exu
set -o pipefail

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq first."
    exit 1
fi
# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install curl first."
    exit 1
fi

# NETWORK_DIR is where all files for the testnet will be stored,
# including logs and storage
NETWORK_DIR=./network

# Port information. All ports will be incremented upon
# with more validators to prevent port conflicts on a single machine


trap 'echo "Error on line $LINENO"; exit 1' ERR
# Function to handle the cleanup
cleanup() {
    echo "Caught Ctrl+C. Killing active background processes and exiting."
    kill $(jobs -p)  # Kills all background processes started in this script
    exit
}
# Trap the SIGINT signal and call the cleanup function when it's caught
trap 'cleanup' SIGINT

# # Reset the data from any previous runs and kill any hanging runtimes
# rm -rf "$NETWORK_DIR" || echo "no network directory"
# mkdir -p $NETWORK_DIR
# pkill geth || echo "No existing geth processes"
# pkill beacon-chain || echo "No existing beacon-chain processes"
# pkill validator || echo "No existing validator processes"
# pkill bootnode || echo "No existing bootnode processes"

# Set Paths for your binaries. Configure as you wish, particularly
# if you're developing on a local fork of reth/lighthouse
RETH_BINARY=../reth/target/release/reth
LIGHTHOUSE_BINARY=lighthouse

# Create the validators in a loop
NODE_DIR=$NETWORK_DIR/node-0
mkdir -p $NODE_DIR/execution
mkdir -p $NODE_DIR/consensus
mkdir -p $NODE_DIR/logs


# Start reth execution client for this node
$RETH_BINARY node \
    --chain sepolia \
    --http \
    --authrpc.jwtsecret=./secrets/jwt.hex \
    --full \
    --datadir=$NODE_DIR/execution \
    --authrpc.addr 127.0.0.1 \
    --authrpc.port 8551 \
    -vvvv > "$NODE_DIR/logs/reth.log" 2>&1 &

    sleep 5

# Start lighthouse consensus client for this node
$LIGHTHOUSE_BINARY bn \
    --network sepolia \
    --http \
    --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io \
    --datadir=$NODE_DIR/consensus/beacondata \
    --execution-endpoint http://localhost:8551 \
    --execution-jwt ./secrets/jwt.hex \
    --disable-deposit-contract-sync \
    --debug-level debug > "$NODE_DIR/logs/lighthouse.log" 2>&1 &

# You might want to change this if you want to tail logs for other nodes
# Logs for all nodes can be found in `./network/node-*/logs`
tail -f "$NETWORK_DIR/node-0/logs/reth.log"
