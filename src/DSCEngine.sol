// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Decentralized-Stable-Coin Engine
 * @author Zophia Poter
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * * This is a stablecoin with the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmic Stable
 *
 * It is similar to DAI if  DAI had no governance, no fees， and was backed by wETH and wBTC.
 * Our DSC system should always be "over-collateralized".
 * At no point. should the value of all the collateral < the $ backed value of all the USC.
 *
 * @notice The contract is the core of the Decentralized Stablecoin system.
 *  It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 *
 * @notice This contract is based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 State Variables
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Mapping of token address to its Chainlink price feed address.
     */
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    /**
     * @dev The DecentralizedStableCoin (DSC) token contract.
     */
    DecentralizedStableCoin private immutable i_dsc;
    /**
     * @dev Mapping from user address to another mapping of token address to the amount of collateral deposited.
     */
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    /**
     * @dev Mapping from user address to the amount of DSC they have minted.
     */
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    /**
     * @dev Array of addresses of tokens that can be used as collateral.
     */
    address[] private s_collateralTokens;

    /**
     * @dev The precision of the additional feed.
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    /**
     * @dev The precision for calculations.
     */
    uint256 private constant PRECISION = 1e18;
    /**
     * @dev The liquidation threshold, if a user's collateral value drops below this percentage of their debt, they can be liquidated.
     */
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    /**
     * @dev The precision for liquidation calculations.
     */
    uint256 private constant LIQUIDATION_PRECISION = 100;
    /**
     * @dev The minimum health factor a user must maintain to avoid liquidation.
     */
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    /**
     * @dev The bonus percentage given to liquidators as a reward.
     */
    uint256 private constant LIQUIDATION_BONUS = 10;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Modifier to check if an amount is greater than zero.
     * @param amount The amount to check.
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    /**
     * @dev Modifier to check if a token is allowed as collateral.
     * @param token The address of the token to check.
     */
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Event emitted when collateral is deposited.
     * @param user The user who deposited the collateral.
     * @param token The token that was deposited.
     * @param amount The amount of the token that was deposited.
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    /**
     * @dev Event emitted when collateral is redeemed.
     * @param redeemedFrom The user whose collateral was redeemed.
     * @param redeemedTo The user who received the redeemed collateral.
     * @param token The token that was redeemed.
     * @param amount The amount of the token that was redeemed.
     */
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes the contract with token addresses, price feed addresses, and the DSC address.
     * @param tokenAddresses An array of addresses of tokens that can be used as collateral.
     * @param priceFeedAddresses An array of addresses of the Chainlink price feeds for the corresponding tokens.
     * @param dscAddress The address of the DecentralizedStableCoin contract.
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // set up allowed token's addresses mapping to correspond priceFeeds address
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            // then store the token addresses
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////////////////////
    //   External Functions   //
    //////////////////////////////////////////
    /**
     *
     * @param tokenCollateralAddress The ERC20 token address of the collateral you are depositing
     * @param amountCollateral The amount of collateral you are depositing
     * @param amountDscToMint The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress: the collateral token address to redeem
     * @param amountCollateral: amount of collateral to redeem
     * @param amountToBurn: the amount of DSC to burn
     *
     * This function burns DSC and redeems underlying collateral in one transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn)
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        burnDsc(amountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is the collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR.
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
     * to work.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
     * anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralRedeemed);

        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////////////
    //   Private Functions                   //
    ///////////////////////////////////////////
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        console.log(
            "s_collateralDeposited[from][tokenCollateralAddress]: ", s_collateralDeposited[from][tokenCollateralAddress]
        );
        console.log("amountCollateral: ", amountCollateral);

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    ///////////////////////////////////////////
    //   Private & Internal View Functions   //
    ///////////////////////////////////////////
    /**
     *
     * @param user - the address of the user whose Health Factor to be checked
     * @return healthFactor - how close to liquidation a user is
     *  If a user goes below 1, then they can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        // assure that changes in a user's DSC or collateral balances don't result in the user's position being `under-collateralized`
        uint256 userHealthFactor = _healthFactor(user);
        console.log("user: ", user);
        console.log("healthFactor: ", userHealthFactor);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     *
     * @param tokenCollateralAddress The ERC20 token address of the collateral you are depositing
     * @param amountCollateral The amount of collateral you are depositing
     * @dev This function allows a user to deposit collateral into the system.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant /* safer but more gas-consuming */
    {
        // add the deposited collateral to our user's balance
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // wrap our token into ERC20 token
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param amountDscToMint The amount of DSC you want to mint
     * You can only mint DSC if you have enough collateral
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        // need to check if the account's collateral value supports the amount of `DSC` being minted.
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * the total USD value of a user's collateral
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256 amountInUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // return the latest price of our token, to 8 decimal places
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION);
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    // * View an account's `healthFactor`
    function getHealthFactor() external view returns (uint256) {
        //
        console.log("msg.sender: ", msg.sender);
        return _healthFactor(msg.sender);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address token, address user) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
