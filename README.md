# A Minimal Stablecoin

A brief one-sentence description of your project.

## Description

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

### Features

- Stablecoin Mechanism:
  1. Relative Stability: Anchored or Pegged -> $1.00
     1. Chainlink Price feed.
     2. Set a function to exchange ETH & BTC -> $$$
  2. Stability Mechanism (Minting): Algorithmic (Decentralized)
     1. Only can mint the stablecoin with enough collateral (coded)
  3. Collateral: Exogenous (Crypto)
     1. wETH
     2. wBTC
- State of the art fuzz testing methodologies
- Safe use of oracles
- multifaceted test suites
- integration and deployment through scripts
- As well as multiple [deploying scripts](#deploying) and [testing](#testing).

## Table of Contents

- [A Minimal Stablecoin](#a-minimal-stablecoin)
  - [Description](#description)
    - [Features](#features)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
    - [Prerequisites](#prerequisites)
    - [Steps](#steps)
      - [Quickstart](#quickstart)
  - [Usage](#usage)
    - [Configuration](#configuration)
    - [Deploying](#deploying)
    - [Testing](#testing)
        - [Test Coverage](#test-coverage)

## Installation

### Prerequisites

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

### Steps

#### Quickstart

```
git clone https://github.com/ZophiaWong/defi-stablecoin-f25
cd defi-stablecoin-f25
forge build
```

## Usage

### Configuration

Explain environment variables or config files.
| Variable | Description | Default |
| --- | --- | --- |
| qw | ad | default |

### Deploying

### Testing

4 test tiers：

1. Unit

1. Integration

1. Forked

1. Staging

##### Test Coverage

```
forge coverage
```

and for coverage based testing:

```
forge coverage --report debug
```
