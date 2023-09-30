#!/bin/bash

set -exu
set -o pipefail

NETWORK_DIR=./network
CHAIN_ID=32383
NUM_NODES=0 

# Reset
rm -rf "$NETWORK_DIR" || echo "no network directory"
mkdir -p $NETWORK_DIR/execution
mkdir -p $NETWORK_DIR/consensus
mkdir -p $NETWORK_DIR/logs
pkill geth || echo "No existing geth processes"

GETH_BINARY=./dependencies/go-ethereum/build/bin/geth
PRYSM_CTL_BINARY=./dependencies/prysm/out/prysmctl
PRYSM_BEACON_BINARY=./dependencies/prysm/out/beacon-chain
PRYSM_VALIDATOR_BINARY=./dependencies/prysm/out/validator

geth_pw_file="$NETWORK_DIR/geth_password.txt"
echo "" > "$geth_pw_file"

cp ./config.yml $NETWORK_DIR/consensus/config.yml
cp ./genesis.json $NETWORK_DIR/execution/genesis.json

$GETH_BINARY account new --datadir "$NETWORK_DIR/execution" --password "$geth_pw_file"

$PRYSM_CTL_BINARY testnet generate-genesis \
--fork=capella \
--num-validators=64 \
--output-ssz=$NETWORK_DIR/consensus/genesis.ssz \
--chain-config-file=$NETWORK_DIR/consensus/config.yml \
--geth-genesis-json-in=$NETWORK_DIR/execution/genesis.json \
--geth-genesis-json-out=$NETWORK_DIR/execution/genesis.json

$GETH_BINARY init \
  --datadir=$NETWORK_DIR/execution \
  $NETWORK_DIR/execution/genesis.json


  $GETH_BINARY \
  --http \
  --http.api=eth,net,web3 \
  --http.addr=0.0.0.0 \
  --http.corsdomain="*" \
  --ws \
  --ws.api=eth,net,web3 \
  --ws.addr=0.0.0.0 \
  --ws.origins="*" \
  --authrpc.vhosts="*" \
  --authrpc.addr=0.0.0.0 \
  --authrpc.jwtsecret=$NETWORK_DIR/execution/jwtsecret \
  --datadir=$NETWORK_DIR/execution \
  --password=$geth_pw_file \
  --nodiscover \
  --syncmode=full > "$NETWORK_DIR/logs/geth.out" 2>&1 &

  sleep 5

  $PRYSM_BEACON_BINARY \
  --datadir=$NETWORK_DIR/consensus/beacondata \
  --min-sync-peers=0 \
  --genesis-state=$NETWORK_DIR/consensus/genesis.ssz \
  --bootstrap-node= \
  --interop-eth1data-votes \
  --chain-config-file=$NETWORK_DIR/consensus/config.yml \
  --contract-deployment-block=0 \
  --chain-id=${CHAIN_ID:-32382} \
  --rpc-host=0.0.0.0 \
  --grpc-gateway-host=0.0.0.0 \
  --execution-endpoint=http://localhost:8551 \
  --accept-terms-of-use \
  --jwt-secret=$NETWORK_DIR/execution/jwtsecret \
  --suggested-fee-recipient=0x123463a4b065722e99115d6c222f267d9cabb524 \
  --minimum-peers-per-subnet=0 \
  --enable-debug-rpc-endpoints > "$NETWORK_DIR/logs/beacon.out" 2>&1 &

  $PRYSM_VALIDATOR_BINARY \
  --beacon-rpc-provider=localhost:4000 \
  --datadir=$NETWORK_DIR/consensus/validatordata \
  --accept-terms-of-use \
  --interop-num-validators=64 \
  --interop-start-index=0 \
  --chain-config-file=$NETWORK_DIR/consensus/config.yml > $NETWORK_DIR/logs/validator.out 2>&1 &

tail -f "$NETWORK_DIR/logs/geth.out"