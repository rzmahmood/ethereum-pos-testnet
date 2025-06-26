# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Local Ethereum Proof-of-Stake (PoS) Testnet deployment tool for developers who want to quickly set up and deploy their own local Ethereum PoS networks with multiple nodes. It's useful for testing modifications to Ethereum client source code, simulating blockchain reorganizations, testing Byzantine behavior, and developing Ethereum applications.

## Key Commands

### Building Dependencies
```bash
# Build Go-Ethereum and Prysm from submodules
./build-dependencies.sh

# Build only Geth (from dependencies/go-ethereum directory)
cd dependencies/go-ethereum && make geth

# Build Prysm components (from dependencies/prysm directory)
cd dependencies/prysm
bazel build //cmd/beacon-chain:beacon-chain
bazel build //cmd/validator:validator
```

### Running the Testnet
```bash
# Start testnet with default 2 validators
./testnet.sh

# Check if blocks are being produced
./healthcheck.sh
```

### Development Commands for Go-Ethereum
From `dependencies/go-ethereum/`:
```bash
make test      # Run tests
make lint      # Run linters  
make fmt       # Format Go code
```

## Architecture

The testnet consists of:
- **Execution Layer**: Go-Ethereum (Geth) nodes
- **Consensus Layer**: Prysm beacon chain and validator clients
- **Configuration**: `config.yml` (consensus) and `genesis.json` (execution)

Each node runs both layers with incrementing ports:
- Geth HTTP: 8000, 8001, 8002...
- Beacon RPC: 4000, 4001, 4002...
- Beacon Gateway: 4100, 4101, 4102...

## Key Files and Modifications

1. **testnet.sh**: Main orchestration script that:
   - Sets up network directories
   - Initializes validator keys
   - Starts Geth and Prysm processes
   - Contains NUM_NODES variable to control validator count

2. **config.yml**: Beacon chain configuration
   - Fork epochs (Altair, Bellatrix, Capella, Deneb, Electra)
   - 2-second slots for faster finalization
   - Network parameters

3. **genesis.json**: Execution layer genesis
   - Pre-funded addresses in the `alloc` section
   - Chain ID and initial parameters

## Working with Submodules

The project uses Git submodules for Ethereum clients:
- `dependencies/go-ethereum` - Geth execution client
- `dependencies/prysm` - Prysm consensus client

When making changes to these dependencies, remember they are separate Git repositories.

## Testing Modifications

To test changes to Ethereum clients:
1. Make modifications in `dependencies/go-ethereum` or `dependencies/prysm`
2. Run `./build-dependencies.sh` to rebuild
3. Run `./testnet.sh` to test with your changes
4. Check logs in `./network/node-*/logs/`

## Network Data

All runtime data is stored in `./network/`:
- `node-0/`, `node-1/`, etc. - Individual node data
- Logs are in `./network/node-*/logs/`
- The network directory is cleaned on each run for idempotent deployments