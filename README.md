# Lockless Protocol

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/LocklessFinance/lkl-protocol/blob/main/LICENSE)

The Lockless Protocol is a DeFi primitive which runs on the Polygon blockchain. The Protocol, at its core, allows a tokenized yield bearing position (USDT, DAI, USDC, etc) to be split into two separate tokens, the 1) principal token, and the 2) yield token. The principal tokens are redeemable for the deposited principal and the yield tokens are redeemable for the yield earned over the term period. This splitting mechanism allows users to sell their principal as a fixed-rate income position, further leveraging or increasing exposure to interest without any liquidation risk.

This repository contains the smart contracts which enable the functionality described above, including a custom AMM implementation based on the YieldSpace [paper](https://yield.is/YieldSpace.pdf), designed as an integration with the Balancer V2 system.

Lockless is a community driven protocol and there are many ways to contribute to it, we encourage you to jump in and improve and use this code.

For a technical contract overview please read our [specification](https://github.com/LocklessFinance/lkl-protocol/blob/main/SPECIFICATION.md).

## Integrations and Code Contributions

We welcome new contributors and code contributions with open arms! Please be sure to follow our contribution [guidelines](https://github.com/LocklessFinance/lkl-protocol/blob/main/CONTRIBUTING.md) when proposing any new code.

## Build and Testing

### 1. Getting Started (Prerequisites)

- [Install npm](https://nodejs.org/en/download/)

### 2. Setup

```
git clone git@github.com:LocklessFinance/lkl-protocol.git
```

```
cd lkl-protocol
npm install
npm run load-contracts
```

### 3. Build

```
npm run build
```

### 4. Test

```
npm run test
```
