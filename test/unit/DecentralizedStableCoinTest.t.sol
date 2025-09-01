// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    address owner = address(this);
    address user = address(1);
    uint256 constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        dsc = new DecentralizedStableCoin(owner);
        dsc.mint(owner, STARTING_BALANCE);
    }

    function testConstructor() public {
        assertEq(dsc.owner(), owner);
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function testMint() public {
        uint256 amount = 10 ether;
        dsc.mint(user, amount);
        assertEq(dsc.balanceOf(user), amount);
    }

    function testRevertsIfMintToZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 1);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(user, 0);
    }

    function testBurn() public {
        uint256 amount = 10 ether;
        dsc.burn(amount);
        assertEq(dsc.balanceOf(owner), STARTING_BALANCE - amount);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testRevertsIfBurnAmountExceedsBalance() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(STARTING_BALANCE + 1);
    }

    function testTransfer() public {
        uint256 amount = 10 ether;
        dsc.transfer(user, amount);
        assertEq(dsc.balanceOf(user), amount);
        assertEq(dsc.balanceOf(owner), STARTING_BALANCE - amount);
    }

    function testTransferFrom() public {
        uint256 amount = 10 ether;
        dsc.approve(user, amount);
        vm.prank(user);
        dsc.transferFrom(owner, user, amount);
        assertEq(dsc.balanceOf(user), amount);
        assertEq(dsc.balanceOf(owner), STARTING_BALANCE - amount);
    }

    function testApprove() public {
        uint256 amount = 10 ether;
        dsc.approve(user, amount);
        assertEq(dsc.allowance(owner, user), amount);
    }
}
