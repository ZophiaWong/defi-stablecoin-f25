// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(ranToken)));
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/
    modifier mintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDsc(100 ether);
        vm.stopPrank();
        _;
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether;
        dscEngine.mintDsc(amountToMint);

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
        assertEq(dsc.balanceOf(USER), amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 10001 ether;
        uint256 healthFactor = dscEngine.getHealthFactor();
        console.log("healthFactor = ", healthFactor);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, 999900009999000099));
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public mintedDsc {
        vm.startPrank(USER);
        uint256 amountToBurn = 50 ether;

        dsc.approve(address(dscEngine), amountToBurn);

        dscEngine.burnDsc(amountToBurn);

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 50 ether);
        assertEq(dsc.balanceOf(USER), 50 ether);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountExceedsDscBalance() public mintedDsc {
        vm.startPrank(USER);
        uint256 amountToBurn = 101 ether;
        dsc.approve(address(dscEngine), amountToBurn);

        vm.expectRevert();
        dscEngine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToRedeem = 5 ether;
        dscEngine.redeemCollateral(weth, amountToRedeem);

        (, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL - amountToRedeem);

        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_USER_BALANCE - AMOUNT_COLLATERAL + amountToRedeem);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountExceedsDeposited() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToRedeem = AMOUNT_COLLATERAL + 1;
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorBrokenAfterRedeem() public mintedDsc {
        vm.startPrank(USER);
        uint256 amountToRedeem = 9.95 ether;

        vm.expectRevert(DSCEngine.DSCEngine__BreakHealthFactor.selector);
        dscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                DEPOSIT COLLATERAL AND MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/
    function testCanDepositAndMint() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        uint256 amountToMint = 100 ether;
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(totalDscMinted, amountToMint);
        assertEq(collateralValueInUsd, expectedCollateralValue);
        assertEq(dsc.balanceOf(USER), amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                REDEEM COLLATERAL FOR DSC TESTS
    //////////////////////////////////////////////////////////////*/
    function testCanRedeemCollateralForDsc() public mintedDsc {
        vm.startPrank(USER);
        uint256 amountToBurn = 50 ether;
        uint256 amountToRedeem = 5 ether;

        dsc.approve(address(dscEngine), amountToBurn);
        dscEngine.redeemCollateralForDsc(weth, amountToRedeem, amountToBurn);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL - amountToRedeem);

        assertEq(totalDscMinted, 50 ether);
        assertEq(collateralValueInUsd, expectedCollateralValue);
        assertEq(dsc.balanceOf(USER), 50 ether);
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_USER_BALANCE - AMOUNT_COLLATERAL + amountToRedeem);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATE TESTS
    //////////////////////////////////////////////////////////////*/
    address liquidator = makeAddr("liquidator");

    function testCannotLiquidateGoodHealthFactor() public mintedDsc {
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, 10 ether);
        vm.stopPrank();
    }

    function testCanLiquidate() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        uint256 amountToMint = 10000 ether;
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(price / 2);

        vm.startPrank(liquidator);
        uint256 debtToCover = 1000 ether;

        dsc.mint(liquidator, debtToCover);
        dsc.approve(address(dscEngine), debtToCover);

        uint256 liquidatorWethBalanceBefore = ERC20Mock(weth).balanceOf(liquidator);
        (uint256 userDscMintedBefore,) = dscEngine.getAccountInformation(USER);

        dscEngine.liquidate(weth, USER, debtToCover);

        uint256 liquidatorWethBalanceAfter = ERC20Mock(weth).balanceOf(liquidator);
        (uint256 userDscMintedAfter,) = dscEngine.getAccountInformation(USER);

        uint256 expectedWethForLiquidator = dscEngine.getTokenAmountFromUsd(weth, debtToCover);
        uint256 bonusCollateral = (expectedWethForLiquidator * 10) / 100;
        uint256 totalCollateralRedeemed = expectedWethForLiquidator + bonusCollateral;

        assertEq(liquidatorWethBalanceAfter - liquidatorWethBalanceBefore, totalCollateralRedeemed);
        assertEq(userDscMintedBefore - userDscMintedAfter, debtToCover);
        uint256 userWethBalanceAfter = dscEngine.getCollateralBalanceOfUser(weth, USER);
        assertEq(userWethBalanceAfter, AMOUNT_COLLATERAL - totalCollateralRedeemed);

        vm.stopPrank();
    }
}
