#!/bin/bash

# This script is used in CI to test that the network is running

result=$(curl -s localhost:4100/eth/v2/beacon/blocks/head | jq -r ".data.message.body.execution_payload.block_number")
if [[ $result -gt 0 ]]; then
    echo "block number is increasing"
    exit 0  # exit with success
else
    echo "block number is not increasing"
    exit 1  # exit with failure
fi
