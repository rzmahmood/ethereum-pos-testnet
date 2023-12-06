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

# Change this number for your desired number of nodes
NUM_RPC_NODES=1

# Port information. All ports will be incremented upon
# with more validators to prevent port conflicts on a single machine
GETH_BOOTNODE_PORT=30301

GETH_HTTP_PORT=8000
GETH_WS_PORT=8100
GETH_AUTH_RPC_PORT=8200
GETH_METRICS_PORT=8300
GETH_NETWORK_PORT=8400


trap 'echo "Error on line $LINENO"; exit 1' ERR
# Function to handle the cleanup
cleanup() {
    echo "Caught Ctrl+C. Killing active background processes and exiting."
    kill $(jobs -p)  # Kills all background processes started in this script
    exit
}
# Trap the SIGINT signal and call the cleanup function when it's caught
trap 'cleanup' SIGINT

# Reset the data from any previous runs and kill any hanging runtimes
rm -rf "$NETWORK_DIR" || echo "no network directory"
mkdir -p $NETWORK_DIR
pkill geth || echo "No existing geth processes"
pkill bootnode || echo "No existing bootnode processes"

# Set Paths for your binaries. Configure as you wish, particularly
# if you're developing on a local fork of geth/prysm
GETH_BINARY=../../imtbl-go-ethereum/build/bin/geth
GETH_BOOTNODE_BINARY=../../imtbl-go-ethereum/build/bin/bootnode

# Create the bootnode for execution client peer discovery. 
# Not a production grade bootnode. Does not do peer discovery for consensus client
mkdir -p $NETWORK_DIR/bootnode

$GETH_BOOTNODE_BINARY -genkey $NETWORK_DIR/bootnode/nodekey

$GETH_BOOTNODE_BINARY \
    -nodekey $NETWORK_DIR/bootnode/nodekey \
    -addr=:$GETH_BOOTNODE_PORT \
    -verbosity=5 > "$NETWORK_DIR/bootnode/bootnode.log" 2>&1 &

sleep 2
# Get the ENODE from the first line of the logs for the bootnode
bootnode_enode=$(head -n 1 $NETWORK_DIR/bootnode/bootnode.log)
# Check if the line begins with "enode"
if [[ "$bootnode_enode" == enode* ]]; then
    echo "bootnode enode is: $bootnode_enode"
else
    echo "The bootnode enode was not found. Exiting."
    exit 1
fi


# Create the Validator
NODE_DIR=$NETWORK_DIR/validator
mkdir -p $NODE_DIR/execution
mkdir -p $NODE_DIR/consensus
mkdir -p $NODE_DIR/logs
# We use an empty password. Do not do this in production
geth_pw_file="$NODE_DIR/geth_password.txt"
echo "" > "$geth_pw_file"
# Create the secret keys for this node and other account details
# Run the geth command and capture its output
output=$($GETH_BINARY account new --datadir "$NODE_DIR/execution" --password "$geth_pw_file")

# Extract the public address using grep and awk
public_address_original=$(echo "$output" | grep -o 'Public address of the key:   0x[a-zA-Z0-9]*' | awk '{print $6}')

# Now you can use the public_address variable in your script
echo "The public address for the validator is: $public_address_original"

# Remove the '0x' prefix and convert to lower case
public_address=$(echo $public_address_original | tr '[:upper:]' '[:lower:]')
public_address=${public_address#0x}

# Format the address with 32 zero bytes before (64 zero characters) and 65 zero bytes after (130 zero characters)
formatted_address=0x$(printf '0%.0s' {1..64})$public_address$(printf '0%.0s' {1..130})

# Update the extradata field in the genesis file (clique specific)
jq --arg address "$formatted_address" '.extraData = $address' "./genesis.json" > tmp.json && mv tmp.json "./genesis.json"

cp ./genesis.json $NETWORK_DIR/genesis.json

# Copy the same genesis and inital config the node's directories
# All nodes must have the same genesis otherwise they will reject eachother
cp $NETWORK_DIR/genesis.json $NODE_DIR/execution/genesis.json

# Initialize geth for this node. Geth uses the genesis.json to write some initial state
$GETH_BINARY init \
    --datadir=$NODE_DIR/execution \
    $NODE_DIR/execution/genesis.json

# Start geth execution client for this node
    $GETH_BINARY \
    --networkid=${CHAIN_ID:-32382} \
    --port=$GETH_NETWORK_PORT \
    --metrics.port=$GETH_METRICS_PORT \
    --authrpc.vhosts="*" \
    --authrpc.addr=127.0.0.1 \
    --authrpc.jwtsecret=$NODE_DIR/execution/jwtsecret \
    --authrpc.port=$GETH_AUTH_RPC_PORT \
    --datadir=$NODE_DIR/execution \
    --password=$geth_pw_file \
    --bootnodes=$bootnode_enode \
    --identity=node-0 \
    --maxpendpeers=$((NUM_RPC_NODES + 1)) \
    --verbosity=3 \
    --mine \
    --miner.etherbase=$public_address_original \
    --unlock=$public_address_original \
    --syncmode=full > "$NODE_DIR/logs/geth.log" 2>&1 &

sleep 5

# Create the RPC nodes
for (( i=1; i<$((NUM_RPC_NODES + 1)); i++ )); do
    NODE_DIR=$NETWORK_DIR/node-$i
    mkdir -p $NODE_DIR/execution
    mkdir -p $NODE_DIR/consensus
    mkdir -p $NODE_DIR/logs

    # We use an empty password. Do not do this in production
    geth_pw_file="$NODE_DIR/geth_password.txt"
    echo "" > "$geth_pw_file"

    # Copy the same genesis and inital config the node's directories
    # All nodes must have the same genesis otherwise they will reject eachother
    cp $NETWORK_DIR/genesis.json $NODE_DIR/execution/genesis.json

    # Create the secret keys for this node and other account details
    $GETH_BINARY account new --datadir "$NODE_DIR/execution" --password "$geth_pw_file"

    # Initialize geth for this node. Geth uses the genesis.json to write some initial state
    $GETH_BINARY init \
      --datadir=$NODE_DIR/execution \
      $NODE_DIR/execution/genesis.json

    # Start geth execution client for this node
    $GETH_BINARY \
      --networkid=${CHAIN_ID:-32382} \
      --http \
      --http.api=eth,net,web3 \
      --http.addr=127.0.0.1 \
      --http.corsdomain="*" \
      --http.port=$((GETH_HTTP_PORT + i)) \
      --port=$((GETH_NETWORK_PORT + i)) \
      --metrics.port=$((GETH_METRICS_PORT + i)) \
      --ws \
      --ws.api=eth,net,web3 \
      --ws.addr=127.0.0.1 \
      --ws.origins="*" \
      --ws.port=$((GETH_WS_PORT + i)) \
      --authrpc.vhosts="*" \
      --authrpc.addr=127.0.0.1 \
      --authrpc.jwtsecret=$NODE_DIR/execution/jwtsecret \
      --authrpc.port=$((GETH_AUTH_RPC_PORT + i)) \
      --datadir=$NODE_DIR/execution \
      --password=$geth_pw_file \
      --bootnodes=$bootnode_enode \
      --identity=node-$i \
      --maxpendpeers=$((NUM_RPC_NODES + 1)) \
      --verbosity=3 \
      --syncmode=full > "$NODE_DIR/logs/geth.log" 2>&1 &
done

# You might want to change this if you want to tail logs for other nodes
tail -f "$NETWORK_DIR/validator/logs/geth.log"
