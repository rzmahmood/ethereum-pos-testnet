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

GETH_HTTP_PORT=8000
GETH_WS_PORT=8100
GETH_AUTH_RPC_PORT=8200
GETH_METRICS_PORT=8300
GETH_NETWORK_PORT=8400

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

PRYSM_CTL_BINARY=./dependencies/prysm/bazel-bin/cmd/prysmctl/prysmctl_/prysmctl
PRYSM_BEACON_BINARY=./dependencies/prysm/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain
PRYSM_VALIDATOR_BINARY=./dependencies/prysm/bazel-bin/cmd/validator/validator_/validator

# The first geth node will act as bootnode for execution client peer discovery
# This variable will be set after the first node starts
GETH_BOOTNODE_ENODE=


# Generate the genesis using ethereum-genesis-generator (like Kurtosis/ethpandaops)
# This approach avoids all configuration conflicts with Prysm v6.x
mkdir -p $NETWORK_DIR/genesis-config

# Create minimal genesis configuration
cat > $NETWORK_DIR/genesis-config/values.env << EOF
SECONDS_PER_SLOT=2
SLOTS_PER_EPOCH=32
GENESIS_FORK_VERSION=0x10000038
ALTAIR_FORK_VERSION=0x20000038
BELLATRIX_FORK_VERSION=0x30000038
CAPELLA_FORK_VERSION=0x40000038
DENEB_FORK_VERSION=0x50000038
ELECTRA_FORK_VERSION=0x60000038
ALTAIR_FORK_EPOCH=0
BELLATRIX_FORK_EPOCH=0
CAPELLA_FORK_EPOCH=0
DENEB_FORK_EPOCH=0
ELECTRA_FORK_EPOCH=0
CHAIN_ID=32382
DEPOSIT_CONTRACT_ADDRESS=0x4242424242424242424242424242424242424242
NUMBER_OF_VALIDATORS=$NUM_NODES
GENESIS_DELAY=10
EOF

# Use simplified approach that works with Prysm v6.0.4
# Create minimal config inline to avoid conflicts
cat > $NETWORK_DIR/config.yaml << EOF
CONFIG_NAME: minimal-local
PRESET_BASE: minimal

SECONDS_PER_SLOT: 2
SLOTS_PER_EPOCH: 32

GENESIS_FORK_VERSION: 0x10000038
ALTAIR_FORK_VERSION: 0x20000038
ALTAIR_FORK_EPOCH: 0
BELLATRIX_FORK_VERSION: 0x30000038
BELLATRIX_FORK_EPOCH: 0
CAPELLA_FORK_VERSION: 0x40000038
CAPELLA_FORK_EPOCH: 0
DENEB_FORK_VERSION: 0x50000038
DENEB_FORK_EPOCH: 0

TERMINAL_TOTAL_DIFFICULTY: 0
DEPOSIT_CONTRACT_ADDRESS: 0x4242424242424242424242424242424242424242
MAX_WITHDRAWALS_PER_PAYLOAD: 16
EOF

# Generate genesis using the clean config
$PRYSM_CTL_BINARY testnet generate-genesis \
--fork=deneb \
--num-validators=$NUM_NODES \
--chain-config-file=$NETWORK_DIR/config.yaml \
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
    cp $NETWORK_DIR/config.yaml $NODE_DIR/consensus/config.yml
    cp $NETWORK_DIR/genesis.ssz $NODE_DIR/consensus/genesis.ssz
    cp $NETWORK_DIR/genesis.json $NODE_DIR/execution/genesis.json

    # Create the secret keys for this node and other account details
    $GETH_BINARY account new --datadir "$NODE_DIR/execution" --password "$geth_pw_file"

    # Initialize geth for this node. Geth uses the genesis.json to write some initial state
    $GETH_BINARY init \
      --datadir=$NODE_DIR/execution \
      $NODE_DIR/execution/genesis.json

    # Start geth execution client for this node
    # For the first node, don't specify bootnodes. For subsequent nodes, use the first node as bootnode
    if [ $i -eq 0 ]; then
        $GETH_BINARY \
          --networkid=${CHAIN_ID:-32382} \
          --http \
          --http.api=eth,net,web3,admin \
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
          --identity=node-$i \
          --maxpendpeers=$NUM_NODES \
          --verbosity=3 \
          --syncmode=full > "$NODE_DIR/logs/geth.log" 2>&1 &
        
        sleep 5
        # Get the enode of the first node to use as bootnode for others
        GETH_BOOTNODE_ENODE=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:$GETH_HTTP_PORT | jq -r '.result.enode')
        if [[ $GETH_BOOTNODE_ENODE == enode* ]]; then
            echo "Geth bootnode enode is: $GETH_BOOTNODE_ENODE"
        else
            echo "Failed to get geth bootnode enode. Exiting."
            exit 1
        fi
    else
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
          --bootnodes=$GETH_BOOTNODE_ENODE \
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

    # Start prysm validator for this node. Each validator node will
    # manage 1 validator
    $PRYSM_VALIDATOR_BINARY \
      --beacon-rpc-provider=localhost:$((PRYSM_BEACON_RPC_PORT + i)) \
      --datadir=$NODE_DIR/consensus/validatordata \
      --accept-terms-of-use \
      --interop-num-validators=1 \
      --interop-start-index=$i \
      --rpc-port=$((PRYSM_VALIDATOR_RPC_PORT + i)) \
      --grpc-gateway-port=$((PRYSM_VALIDATOR_GRPC_GATEWAY_PORT + i)) \
      --monitoring-port=$((PRYSM_VALIDATOR_MONITORING_PORT + i)) \
      --graffiti="node-$i" \
      --chain-config-file=$NODE_DIR/consensus/config.yml > "$NODE_DIR/logs/validator.log" 2>&1 &


    # Check if the PRYSM_BOOTSTRAP_NODE variable is already set
    if [[ -z "${PRYSM_BOOTSTRAP_NODE}" ]]; then
        sleep 5 # sleep to let the prysm node set up
        # If PRYSM_BOOTSTRAP_NODE is not set, execute the command and capture the result into the variable
        # This allows subsequent nodes to discover the first node, treating it as the bootnode
        PRYSM_BOOTSTRAP_NODE=$(curl -s localhost:4100/eth/v1/node/identity | jq -r '.data.enr')
            # Check if the result starts with enr
        if [[ $PRYSM_BOOTSTRAP_NODE == enr* ]]; then
            echo "PRYSM_BOOTSTRAP_NODE is valid: $PRYSM_BOOTSTRAP_NODE"
        else
            echo "PRYSM_BOOTSTRAP_NODE does NOT start with enr"
            exit 1
        fi
    fi
done

# You might want to change this if you want to tail logs for other nodes
# Logs for all nodes can be found in `./network/node-*/logs`
tail -f "$NETWORK_DIR/node-0/logs/geth.log"
