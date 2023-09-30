![alt text](./assets//hero.png)

> **Warning**
> this code is new and will change in future versions. You should always read any scripts before running for security.

<div align="center">

# Deploy your own Ethereum PoS Testnet


[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![stability-experimental](https://img.shields.io/badge/stability-experimental-orange.svg)](https://github.com/mkenney/software-guides/blob/master/STABILITY-BADGES.md#experimental)

</div>

This deployment process allows you to setup and deploy your own local ethereum PoS networks.
This repository is targeted to developers who want to quickly modify client source code and deploy to a PoS network.
This setup can is can serve as a reference for building your own production deployments but better solutions exist for [that](https://docs.kurtosis.com/how-to-compose-your-own-testnet/) use case.


## Installation
This project utilizes Git submodules to reference the client code, notably Go-Ethereum and Prysm.

 **You will need Go 1.20 installed**. 

```bash
git clone --recursive https://github.com/rzmahmood/ethereum-pos-testnet.git
```

A helper script that builds the submodules, saving the binaries in a known path
```bash
./build-dependencies
```

## Running

Start testnet. This will start a test with a single validator. You should expect blocks to be produced. Logs are stored in `./network/logs`
Multi validator support coming soon. 
The script is idempotent and will clean up every time it is restarted.
```bash
./testnet.sh
```
![Generating a proof](./assets/runloop.gif)

Reach out to me on Twitter [@0xZorz](https://twitter.com/0xZorz) if you have any issues. DMs are open

## Acknowledgements

- The [work](https://github.com/OffchainLabs/eth-pos-devnet) of Raul Jordan was a great reference starting point. His setup will suffice requirements that don't demand signficant customization