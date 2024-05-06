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
NUM_NODES=2

# Port information. All ports will be incremented upon
# with more validators to prevent port conflicts on a single machine
GETH_BOOTNODE_PORT=30301

GETH_HTTP_PORT=8000
GETH_WS_PORT=8100
GETH_AUTH_RPC_PORT=8200
GETH_METRICS_PORT=8300
GETH_NETWORK_PORT=8400

ERIGON_TORRENT_PORT=8500
ERIGON_PRIVATE_API_PORT=8600
ERIGON_P2P_PROTOCOL_PORT=8700

PRYSM_BEACON_RPC_PORT=4000
PRYSM_BEACON_GRPC_GATEWAY_PORT=4100
PRYSM_BEACON_P2P_TCP_PORT=4200
PRYSM_BEACON_P2P_UDP_PORT=4300
PRYSM_BEACON_MONITORING_PORT=4400

PRYSM_VALIDATOR_RPC_PORT=7000
PRYSM_VALIDATOR_GRPC_GATEWAY_PORT=7100
PRYSM_VALIDATOR_MONITORING_PORT=7200


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
pkill beacon-chain || echo "No existing beacon-chain processes"
pkill validator || echo "No existing validator processes"
pkill bootnode || echo "No existing bootnode processes"

# Set Paths for your binaries. Configure as you wish, particularly
# if you're developing on a local fork of geth/prysm
GETH_BINARY=./dependencies/go-ethereum/build/bin/geth
GETH_BOOTNODE_BINARY=./dependencies/go-ethereum/build/bin/bootnode

ERIGON_BINARY=../erigon-zero/build/bin/erigon

PRYSM_CTL_BINARY=../ethBFT/bazel-bin/cmd/prysmctl/prysmctl_/prysmctl
PRYSM_BEACON_BINARY=../ethBFT/build/beacon-chain
PRYSM_VALIDATOR_BINARY=../ethBFT/bazel-bin/cmd/validator/validator_/validator

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


# Generate the genesis. This will generate validators based
# on https://github.com/ethereum/eth2.0-pm/blob/a085c9870f3956d6228ed2a40cd37f0c6580ecd7/interop/mocked_start/README.md
$PRYSM_CTL_BINARY testnet generate-genesis \
--fork=deneb \
--num-validators=$NUM_NODES \
--chain-config-file=./config.yml \
--geth-genesis-json-in=./genesis.json \
--output-ssz=$NETWORK_DIR/genesis.ssz \
--geth-genesis-json-out=$NETWORK_DIR/genesis.json


# The prysm bootstrap node is set after the first loop, as the first
# node is the bootstrap node. This is used for consensus client discovery
PRYSM_BOOTSTRAP_NODE=

# Calculate how many nodes to wait for to be in sync with. Not a hard rule
MIN_SYNC_PEERS=$((NUM_NODES/2))
echo $MIN_SYNC_PEERS is minimum number of synced peers required

# Create the validators in a loop
for (( i=0; i<$NUM_NODES; i++ )); do
    NODE_DIR=$NETWORK_DIR/node-$i
    mkdir -p $NODE_DIR/execution
    mkdir -p $NODE_DIR/consensus
    mkdir -p $NODE_DIR/logs

    # We use an empty password. Do not do this in production
    geth_pw_file="$NODE_DIR/geth_password.txt"
    echo "" > "$geth_pw_file"

    # Copy the same genesis and inital config the node's directories
    # All nodes must have the same genesis otherwise they will reject eachother
    cp ./config.yml $NODE_DIR/consensus/config.yml
    cp $NETWORK_DIR/genesis.ssz $NODE_DIR/consensus/genesis.ssz
    cp $NETWORK_DIR/genesis.json $NODE_DIR/execution/genesis.json

    # Create the secret keys for this node and other account details
    $GETH_BINARY account new --datadir "$NODE_DIR/execution" --password "$geth_pw_file"

    # for all nodes after the first, make them erigon nodes
    if [ $i -gt 0 ]; then
        # Initialize erigon for this node. Erigon uses the genesis.json to write some initial state
        $ERIGON_BINARY init \
            --datadir=$NODE_DIR/execution \
            $NODE_DIR/execution/genesis.json

        # Start erigon execution client for this node
        $ERIGON_BINARY \
            --networkid=${CHAIN_ID:-32382} \
            --http \
            --http.api=eth,net,web3 \
            --http.addr=127.0.0.1 \
            --http.corsdomain="*" \
            --http.port=$((GETH_HTTP_PORT + i)) \
            --port=$((GETH_NETWORK_PORT + i)) \
            --metrics.port=$((GETH_METRICS_PORT + i)) \
            --authrpc.vhosts="*" \
            --authrpc.addr=127.0.0.1 \
            --authrpc.jwtsecret=$NODE_DIR/execution/jwtsecret \
            --authrpc.port=$((GETH_AUTH_RPC_PORT + i)) \
            --datadir=$NODE_DIR/execution \
            --bootnodes=$bootnode_enode \
            --identity=node-$i \
            --torrent.port=$((ERIGON_TORRENT_PORT + i)) \
            --private.api.addr=127.0.0.1:$((ERIGON_PRIVATE_API_PORT + i)) \
            --verbosity=4 > "$NODE_DIR/logs/geth.log" 2>&1 &
    else
        # Initialize geth for this node. Geth uses the genesis.json to write some initial state
        $GETH_BINARY init \
            --datadir=$NODE_DIR/execution \
            $NODE_DIR/execution/genesis.json

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
            --maxpendpeers=$NUM_NODES \
            --verbosity=3 \
            --syncmode=full > "$NODE_DIR/logs/geth.log" 2>&1 &
    fi

    sleep 5

    # Start prysm consensus client for this node
    $PRYSM_BEACON_BINARY \
      --datadir=$NODE_DIR/consensus/beacondata \
      --min-sync-peers=$MIN_SYNC_PEERS \
      --genesis-state=$NODE_DIR/consensus/genesis.ssz \
      --bootstrap-node=$PRYSM_BOOTSTRAP_NODE \
      --interop-eth1data-votes \
      --chain-config-file=$NODE_DIR/consensus/config.yml \
      --contract-deployment-block=0 \
      --chain-id=${CHAIN_ID:-32382} \
      --rpc-host=127.0.0.1 \
      --rpc-port=$((PRYSM_BEACON_RPC_PORT + i)) \
      --grpc-gateway-host=127.0.0.1 \
      --grpc-gateway-port=$((PRYSM_BEACON_GRPC_GATEWAY_PORT + i)) \
      --execution-endpoint=http://localhost:$((GETH_AUTH_RPC_PORT + i)) \
      --accept-terms-of-use \
      --jwt-secret=$NODE_DIR/execution/jwtsecret \
      --suggested-fee-recipient=0x123463a4b065722e99115d6c222f267d9cabb524 \
      --minimum-peers-per-subnet=0 \
      --p2p-tcp-port=$((PRYSM_BEACON_P2P_TCP_PORT + i)) \
      --p2p-udp-port=$((PRYSM_BEACON_P2P_UDP_PORT + i)) \
      --monitoring-port=$((PRYSM_BEACON_MONITORING_PORT + i)) \
      --verbosity=info \
      --slasher \
      --enable-debug-rpc-endpoints > "$NODE_DIR/logs/beacon.log" 2>&1 &
done

# You might want to change this if you want to tail logs for other nodes
# Logs for all nodes can be found in `./network/node-*/logs`
tail -f "$NETWORK_DIR/node-0/logs/geth.log"
