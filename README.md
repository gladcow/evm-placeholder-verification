# EVM Placeholder Proof System Verifier 

[![Discord](https://img.shields.io/discord/969303013749579846.svg?logo=discord&style=flat-square)](https://discord.gg/KmTAEjbmM3)
[![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=flat-square&logo=telegram&logoColor=dark)](https://t.me/nilfoundation)
[![Twitter](https://img.shields.io/twitter/follow/nil_foundation)](https://twitter.com/nil_foundation)

This repository contains the smart contracts for validating zero knowledge proofs 
generated in placeholder proof system in EVM. 

## Dependencies

- [Hardhat](https://hardhat.org/)
- [nodejs](https://nodejs.org/en/) >= 16.0


## Clone
```
git clone git@github.com:NilFoundation/evm-placeholder-verification.git
cd evm-placeholder-verification
```

## Install dependency packages
```
npm i
```

## Compile contracts
```
npx hardhat compile
```

## Test
```
npx hardhat test #Execute tests
REPORT_GAS=true npx hardhat test # Test with gas reporting
```

## Deploy

Launch a local-network using the following
```
npx hardhat node
```

To deploy to test environment (ex: Ganache)
```
npx hardhat deploy  --network localhost 
```

Hardhat re-uses old deployments, to force re-deploy add the `--reset` flag above

## ZKLLVM output check

Place folder with ZKLLVM circuit transpilation output to `contracts/zkllvm` directory.

ZKLLVM circuit transpilation output folder format
```
* proof.bin -- placeholder proof file
* circuit_params.json -- parameters JSON file
* public_input.json -- public input JSON file
* linked_libs_list.json -- list of external libraries, have to be deployed for gate argument computation.
* gate_argument.sol, gate0.sol, ... gateN.sol -- solidity files with gate argument computation
```

Deploy contracts
```
npx hardhat deploy
```

Verify one folder from `contracts/zkllvm` directory
```
npx hardhat verify-circuit-proof folder-name
```

Verify all folders from `contracts/zkllvm` director
```
npx hardhat verify-circuit-proof-all
```

## Community

Issue reports are preferred to be done with Github Issues in here: https://github.com/NilFoundation/evm-placeholder-verification/issues.

Usage and development questions are preferred to be asked in a Telegram chat: https://t.me/nilfoundation or in Discord (https://discord.gg/KmTAEjbmM3)