#!/bin/bash

# NOTE: THIS SCRIPT WAS TESTED WITH GOLANG 1.20 installed

set -exu
set -o pipefail

PRYSM_DIR=./dependencies/prysm
GETH_DIR=./dependencies/go-ethereum

( cd $PRYSM_DIR && go build -o=./out/beacon-chain ./cmd/beacon-chain && go build -o=./out/validator ./cmd/validator && go build -o=./out/prysmctl ./cmd/prysmctl )

( cd $GETH_DIR && make )