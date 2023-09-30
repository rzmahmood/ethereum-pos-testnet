#!/bin/bash

set -exu
set -o pipefail

NETWORK_DIR=./network
CHAIN_ID=32383
NUM_NODES=2 # Change this number for your desired number of nodes

# Port information. All ports will be incremented upon
# with more validators
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

# Reset
rm -rf "$NETWORK_DIR" || echo "no network directory"
mkdir -p $NETWORK_DIR
pkill geth || echo "No existing geth processes"

GETH_BINARY=./dependencies/go-ethereum/build/bin/geth
PRYSM_CTL_BINARY=./dependencies/prysm/out/prysmctl
PRYSM_BEACON_BINARY=./dependencies/prysm/out/beacon-chain
PRYSM_VALIDATOR_BINARY=./dependencies/prysm/out/validator

for (( i=0; i<$NUM_NODES; i++ )); do
    NODE_DIR=$NETWORK_DIR/node-$i
    mkdir -p $NODE_DIR/execution
    mkdir -p $NODE_DIR/consensus
    mkdir -p $NODE_DIR/logs

    geth_pw_file="$NODE_DIR/geth_password.txt"
    echo "" > "$geth_pw_file"

    cp ./config.yml $NODE_DIR/consensus/config.yml
    cp ./genesis.json $NODE_DIR/execution/genesis.json

    $GETH_BINARY account new --datadir "$NODE_DIR/execution" --password "$geth_pw_file"

    $PRYSM_CTL_BINARY testnet generate-genesis \
    --fork=capella \
    --num-validators=64 \
    --output-ssz=$NODE_DIR/consensus/genesis.ssz \
    --chain-config-file=$NODE_DIR/consensus/config.yml \
    --geth-genesis-json-in=$NODE_DIR/execution/genesis.json \
    --geth-genesis-json-out=$NODE_DIR/execution/genesis.json

    # Initialize geth for this node
    $GETH_BINARY init \
      --datadir=$NODE_DIR/execution \
      $NODE_DIR/execution/genesis.json

    # Start geth for this node
    $GETH_BINARY \
      --networkid=$CHAIN_ID \
      --http \
      --http.api=eth,net,web3 \
      --http.addr=0.0.0.0 \
      --http.corsdomain="*" \
      --http.port=$((GETH_HTTP_PORT + i)) \
      --port=$((GETH_NETWORK_PORT + i)) \
      --metrics.port=$((GETH_METRICS_PORT + i)) \
      --ws \
      --ws.api=eth,net,web3 \
      --ws.addr=0.0.0.0 \
      --ws.origins="*" \
      --ws.port=$((GETH_WS_PORT + i)) \
      --authrpc.vhosts="*" \
      --authrpc.addr=0.0.0.0 \
      --authrpc.jwtsecret=$NODE_DIR/execution/jwtsecret \
      --authrpc.port=$((GETH_AUTH_RPC_PORT + i)) \
      --datadir=$NODE_DIR/execution \
      --password=$geth_pw_file \
      --nodiscover \
      --syncmode=full > "$NODE_DIR/logs/geth.out" 2>&1 &

    sleep 5

    # Start prysm beacon for this node
    $PRYSM_BEACON_BINARY \
      --datadir=$NODE_DIR/consensus/beacondata \
      --min-sync-peers=0 \
      --genesis-state=$NODE_DIR/consensus/genesis.ssz \
      --bootstrap-node= \
      --interop-eth1data-votes \
      --chain-config-file=$NODE_DIR/consensus/config.yml \
      --contract-deployment-block=0 \
      --chain-id=${CHAIN_ID:-32382} \
      --rpc-host=0.0.0.0 \
      --rpc-port=$((PRYSM_BEACON_RPC_PORT + i)) \
      --grpc-gateway-host=0.0.0.0 \
      --grpc-gateway-port=$((PRYSM_BEACON_GRPC_GATEWAY_PORT + i)) \
      --execution-endpoint=http://localhost:$((GETH_AUTH_RPC_PORT + i)) \
      --accept-terms-of-use \
      --jwt-secret=$NODE_DIR/execution/jwtsecret \
      --suggested-fee-recipient=0x123463a4b065722e99115d6c222f267d9cabb524 \
      --minimum-peers-per-subnet=0 \
      --p2p-tcp-port=$((PRYSM_BEACON_P2P_TCP_PORT + i)) \
      --p2p-udp-port=$((PRYSM_BEACON_P2P_UDP_PORT + i)) \
      --monitoring-port=$((PRYSM_BEACON_MONITORING_PORT + i)) \
      --enable-debug-rpc-endpoints > "$NODE_DIR/logs/beacon.out" 2>&1 &

    # Start prysm validator for this node
    $PRYSM_VALIDATOR_BINARY \
      --beacon-rpc-provider=localhost:$((PRYSM_BEACON_RPC_PORT + i)) \
      --datadir=$NODE_DIR/consensus/validatordata \
      --accept-terms-of-use \
      --interop-num-validators=64 \
      --interop-start-index=0 \
      --rpc-port=$((PRYSM_VALIDATOR_RPC_PORT + i)) \
      --grpc-gateway-port=$((PRYSM_VALIDATOR_GRPC_GATEWAY_PORT + i)) \
      --monitoring-port=$((PRYSM_VALIDATOR_MONITORING_PORT + i)) \
      --chain-config-file=$NODE_DIR/consensus/config.yml > "$NODE_DIR/logs/validator.out" 2>&1 &
done

# You might want to change this if you want to tail logs for other nodes
tail -f "$NETWORK_DIR/node-0/logs/geth.out"
