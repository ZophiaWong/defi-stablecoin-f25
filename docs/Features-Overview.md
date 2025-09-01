# DeFi Stablecoin 项目核心流程（DSCEngine）

## Table of Contents

- [DeFi Stablecoin 项目核心流程（DSCEngine）](#defi-stablecoin-项目核心流程dscengine)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [A. Token 铸造流程 (Minting)](#a-token-铸造流程-minting)
  - [B. Health Factor 计算](#b-health-factor-计算)
  - [C. Liquidation (清算流程)](#c-liquidation-清算流程)

## Overview

## A. Token 铸造流程 (Minting)

```mermaid
sequenceDiagram
    participant User
    participant DSCEngine
    participant OracleLib
    participant DSC(ERC20)

    User->>DSCEngine: depositCollateralAndMintDsc(token, collateralAmt, dscAmt)
    DSCEngine->>DSCEngine: depositCollateral(token, collateralAmt)
    DSCEngine->>OracleLib: getUsdValue(token, amount)
    OracleLib-->>DSCEngine: 最新美元价格（检查陈旧性）
    DSCEngine->>DSCEngine: 更新 s_collateralDeposited[user][token]

    DSCEngine->>DSCEngine: mintDsc(dscAmt)
    DSCEngine->>DSCEngine: s_DSCMinted[user] += dscAmt
    DSCEngine->>DSCEngine: revertIfHealthFactorIsBroken(user)
    DSCEngine->>DSC(ERC20): mint(user, dscAmt)
    DSC(ERC20)-->>User: 获得 DSC 稳定币
```

## B. Health Factor 计算

```mermaid
flowchart TD
    A["getHealthFactor(user)"] --> B["getAccountCollateralValue<br>(user)"]
    B --> C["OracleLib 获取价格
    (带陈旧性检查)"]
    C --> D["计算总抵押 USD 值"]
    A --> E["s_DSCMinted[user]"]
    D --> F["HF = (collateralUsd<br>* LIQ_THRESHOLD) / debt"]
    E --> F
```

## C. Liquidation (清算流程)

```mermaid
sequenceDiagram
    participant Liquidator
    participant DSCEngine
    participant OracleLib
    participant DSC(ERC20)
    participant CollateralToken(WETH/WBTC)
    participant User(Victim)

    Liquidator->>DSCEngine: liquidate(collateralToken, user, debtToCover)
    DSCEngine->>DSCEngine: require(getHealthFactor(user) < 1)
    DSCEngine->>OracleLib: getUsdValue(collateralToken)
    OracleLib-->>DSCEngine: 抵押物最新价格
    DSCEngine->>DSCEngine: 计算需扣抵押 = debtToCover价值 * (1+清算奖励)

    Liquidator->>DSC(ERC20): transfer(debtToCover)
    DSC(ERC20)->>DSCEngine: DSC 收到
    DSCEngine->>DSC(ERC20): burn(debtToCover)
    DSCEngine->>User(Victim): 减少其债务
    DSCEngine->>CollateralToken: 转移抵押+奖励给 Liquidator
    CollateralToken-->>Liquidator: 获得抵押资产
```
