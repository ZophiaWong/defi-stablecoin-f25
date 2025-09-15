# DSCEngine Design Document

## 1. Overview

The `DSCEngine` is the core smart contract of the Decentralized Stablecoin (DSC) system. It manages all logic related to collateralization, minting, burning, and liquidation. The primary goal of this engine is to maintain the stability of the DSC token, ensuring it remains pegged to $1 USD by requiring all minted DSC to be over-collateralized.

This system is inspired by MakerDAO's DAI but aims for a simpler, governance-minimized model.

## 2. Core Components & Concepts

### 2.1. Collateralization

- **Exogenous Collateral**: The system uses external crypto assets as collateral, specifically `wETH` and `wBTC`.
- **Over-collateralization**: Users must deposit collateral worth significantly more than the value of the DSC they wish to mint.
- **Allowed Tokens**: A whitelist of ERC20 tokens are accepted as collateral. Each token is mapped to a Chainlink price feed to determine its USD value.

### 2.2. Health Factor

The Health Factor is a critical metric that represents the financial health of a user's position (or "vault"). It is calculated as:

```
Health Factor = (Total Collateral Value in USD * Liquidation Threshold) / Total DSC Minted
```

- A Health Factor below `1` indicates that the user's position is undercollateralized and eligible for liquidation.
- The `LIQUIDATION_THRESHOLD` is set to `50%`. This means that for every $1 of DSC minted, a user must have at least $2 worth of collateral to maintain a Health Factor of 1.

### 2.3. Minting & Burning

- **Minting (`mintDsc`)**: Users can mint new DSC tokens against their deposited collateral, as long as their Health Factor remains above the minimum threshold (`MIN_HEALTH_FACTOR` of 1).
- **Burning (`burnDsc`)**: Users can repay their debt by burning DSC tokens they hold. This increases their Health Factor.

### 2.4. Liquidation

- **Trigger**: If a user's Health Factor drops below `1`, any other user (a "liquidator") can trigger a liquidation.
- **Process**: A liquidator repays a portion of the undercollateralized user's DSC debt. In return, the liquidator receives an equivalent amount of the user's collateral, plus a `LIQUIDATION_BONUS` (set to 10%).
- **Purpose**: Liquidation is the primary mechanism to ensure the system remains solvent and the DSC token remains fully backed by collateral, even during asset price volatility.

## 3. Contract Interactions

- **`DecentralizedStableCoin.sol`**: The `DSCEngine` has the exclusive right to mint and burn DSC tokens. It holds ownership of the `DecentralizedStableCoin` contract.
- **ERC20 Collateral Tokens**: The `DSCEngine` interacts with the ERC20 contracts of the collateral tokens (`wETH`, `wBTC`) to transfer them to and from users.
- **Chainlink Price Feeds**: The engine relies on `AggregatorV3Interface` contracts from Chainlink to get real-time, reliable price data for collateral assets.

## 4. Key Functions

### User-Facing Functions:

- `depositCollateral(token, amount)`: Deposits collateral into the system.
- `redeemCollateral(token, amount)`: Withdraws collateral, but only if the user's Health Factor remains above 1.
- `mintDsc(amount)`: Mints DSC against the user's collateral.
- `burnDsc(amount)`: Burns DSC to pay down debt.
- `liquidate(collateral, user, debtToCover)`: Allows a third party to liquidate an unhealthy position.

### Convenience Functions:

- `depositCollateralAndMintDsc(...)`: A single transaction to deposit collateral and mint DSC.
- `redeemCollateralForDsc(...)`: A single transaction to burn DSC and redeem collateral.

## 5. Security Considerations & Risks

- **Reentrancy**: The contract uses OpenZeppelin's `ReentrancyGuard` on key functions (`depositCollateral`, `mintDsc`, `redeemCollateral`, `liquidate`) to prevent reentrancy attacks.
- **Oracle Manipulation**: The system's safety is heavily dependent on the reliability and security of the Chainlink price oracles. A manipulated or failed oracle could lead to incorrect pricing and catastrophic failure of the system.
- **Flash Crashes**: A sudden, sharp drop in the price of collateral assets could potentially leave the system under-collateralized if liquidations cannot occur quickly enough. This is a known risk in any collateralized debt position system.
- **Input Validation**: Modifiers like `moreThanZero` and `isAllowedToken` are used to ensure that function inputs are valid and prevent common errors.
