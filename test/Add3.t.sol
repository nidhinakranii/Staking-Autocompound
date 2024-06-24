// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import "../src/Add3Token.sol";

contract Add3Test is Test {
    Add3Token internal add3Token;

    address public immutable deployer = vm.addr(0x1);
    address public immutable alice = address(0xA71CE);
    address public immutable bob = address(0xB0B);

    uint256 public constant DEPLOYER_MINTING_AMOUNT = 100 ether;
    uint256 public constant ALICE_MINTING_AMOUNT = 2 ether;
    uint256 public constant ALICE_TRANSFER_AMOUNT = 2 ether;
    uint256 public constant BURN_AMOUNT = 0.3 ether;
    uint256 public constant APPROVAL_AMOUNT = 1 ether;

    // hardhat beforeEach -> setUp
    function setUp() public {
        vm.startPrank(deployer);
        add3Token = new Add3Token();
        vm.stopPrank();
    }

    function testName() public {
        assertEq("Add3Token", add3Token.name());
    }

    function testPauseAndUnpause() public {
        vm.startPrank(deployer);
        add3Token.pause();
        assertTrue(add3Token.paused());
        add3Token.unpause();
        assertFalse(add3Token.paused());
    }

    function testTransferWhilePaused() public {
        vm.startPrank(deployer);
        add3Token.pause();
        assertTrue(add3Token.paused());
        vm.expectRevert();
        add3Token.transfer(bob, 10);
        console.log(add3Token.balanceOf(bob));
    }

    function testSymbol() public {
        assertEq("ADD3", add3Token.symbol());
    }

    function testMint() public {
        vm.startPrank(deployer);
        add3Token.mint(deployer, DEPLOYER_MINTING_AMOUNT);
        add3Token.mint(alice, ALICE_MINTING_AMOUNT);
        assertEq(add3Token.totalSupply(), add3Token.balanceOf(deployer) + add3Token.balanceOf(alice));
    }

    function testBurn() public {
        testMint();

        uint256 balanceBeforeBurning = add3Token.balanceOf(deployer);
        uint256 supplyBeforeBurning = add3Token.totalSupply();

        add3Token.burn(BURN_AMOUNT);

        assertEq(add3Token.totalSupply(), supplyBeforeBurning - BURN_AMOUNT);
        assertEq(add3Token.balanceOf(deployer), balanceBeforeBurning - BURN_AMOUNT);
    }

    function testApprove() public {
        testMint();
        assertTrue(add3Token.approve(alice, 1 ether));
        assertEq(add3Token.allowance(deployer, alice), 1 ether);
    }

    function testIncreaseAllowance() external {
        testMint();
        assertEq(add3Token.allowance(deployer, alice), 0);
        assertTrue(add3Token.increaseAllowance(alice, 2 ether));
        assertEq(add3Token.allowance(deployer, alice), 2 ether);
    }

    function testDescreaseAllowance() external {
        testApprove();
        assertTrue(add3Token.decreaseAllowance(alice, 0.5 ether));
        assertEq(add3Token.allowance(deployer, alice), 0.5 ether);
    }

    function testTransfer() external {
        testMint();
        vm.stopPrank();
        vm.startPrank(alice);
        add3Token.transfer(bob, 0.5 ether);

        assertEq(add3Token.balanceOf(bob), 0.5 ether);
        assertEq(add3Token.balanceOf(alice), 1.5 ether);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        testMint();
        vm.stopPrank();

        vm.prank(alice);
        add3Token.approve(address(this), 1 ether);
        assertTrue(add3Token.transferFrom(alice, bob, 0.7 ether));
        assertEq(add3Token.allowance(alice, address(this)), 1 ether - 0.7 ether);
        assertEq(add3Token.balanceOf(alice), 2 ether - 0.7 ether);
        assertEq(add3Token.balanceOf(bob), 0.7 ether);
    }

    function testFailMintToZero() external {
        vm.prank(deployer);
        // vm.expectRevert();
        add3Token.mint(address(0), 1 ether);

        console.log("balance", add3Token.balanceOf(address(0)));
    }

    function testFailBurnInsufficientBalance() external {
        testMint();
        vm.prank(deployer);
        add3Token.burn(DEPLOYER_MINTING_AMOUNT + 1);
    }

    function testFailApproveToZeroAddress() external {
        vm.prank(deployer);
        add3Token.approve(address(0), APPROVAL_AMOUNT);
    }

    function testFailTransferToZeroAddress() external {
        testMint();
        vm.stopPrank();
        vm.prank(alice);
        add3Token.transfer(address(0), ALICE_TRANSFER_AMOUNT);
    }

    function testFailTransferInsufficientBalance() external {
        testMint();
        vm.stopPrank();
        vm.prank(alice);
        add3Token.transfer(bob, 3e18);
    }

    function testFailTransferFromInsufficientApprove() external {
        testMint();
        vm.prank(alice);
        add3Token.approve(address(this), APPROVAL_AMOUNT);
        add3Token.transferFrom(alice, bob, 2e18);
    }

    function testFailTransferFromInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        add3Token.approve(address(this), type(uint).max);
        add3Token.transferFrom(alice, bob, 3e18);
    }

    // /*****************************/
    // /*      Fuzz Testing         */
    // /*****************************/

    function testFuzzMint(address to, uint256 amount) external {
        vm.prank(deployer);
        vm.assume(to != address(0));
        add3Token.mint(to, amount);
        assertEq(add3Token.totalSupply(), add3Token.balanceOf(to));
    }

    function testFuzzApprove(address to, uint256 amount) external {
        vm.prank(deployer);
        vm.assume(to != address(0));
        assertTrue(add3Token.approve(to, amount));
        assertEq(add3Token.allowance(deployer, to), amount);
    }

    function testFuzzBurn(uint256 burnAmount) external {
        vm.assume(burnAmount < 100 wei);
        testMint();
        uint256 balance = add3Token.balanceOf(deployer);
        uint256 supply = add3Token.totalSupply();
        add3Token.burn(burnAmount);
        assertEq(add3Token.totalSupply(), supply - burnAmount);
        assertEq(add3Token.balanceOf(deployer), balance - burnAmount);
    }

    function testFuzzTransfer(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.assume(to != address(this));
        vm.assume(amount < 100 wei);
        testMint();
        uint256 toBalance = add3Token.balanceOf(to);
        assertTrue(add3Token.transfer(to, amount));
        assertEq(add3Token.balanceOf(address(this)), 0);
        assertEq(add3Token.balanceOf(to), toBalance + amount);
    }

    function testFuzzTransferFrom(address from, uint256 approvalAmount, address to, uint256 amount) external {
        vm.assume(from != address(0) && to != address(0) && to != from);
        vm.assume(approvalAmount >= amount && approvalAmount < type(uint128).max);
        vm.assume(amount < 100 wei);
        testMint();
        add3Token.mint(from, approvalAmount);

        vm.stopPrank();
        vm.prank(from);
        assertTrue(add3Token.approve(address(this), approvalAmount));
        vm.stopPrank();

        uint256 supplyBefore = add3Token.totalSupply();
        assertTrue(add3Token.transferFrom(from, to, amount));
        uint256 supplyAfter = add3Token.totalSupply();

        assertEq(supplyBefore, supplyAfter);
        assertEq(add3Token.allowance(from, address(this)), approvalAmount - amount);
    }

    function testFailFuzzBurnInsufficientBalance(uint256 burnAmount) external {
        vm.assume(burnAmount > 0);
        vm.prank(deployer);
        add3Token.burn(burnAmount);
    }

    function testFailTransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) external {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);
        vm.prank(deployer);
        add3Token.mint(address(this), mintAmount);
        add3Token.transfer(to, sendAmount);
    }

    function testFailFuzzTransferFromInsufficientApprove(
        address from,
        address to,
        uint256 approval,
        uint256 amount
    ) external {
        amount = bound(amount, approval + 1, type(uint256).max);
        vm.prank(deployer);
        add3Token.mint(from, amount);
        vm.prank(from);
        add3Token.approve(address(this), approval);
        add3Token.transferFrom(from, to, amount);
    }

    function testFailFuzzTransferFromInsufficientBalance(
        address from,
        address to,
        uint256 mintAmount,
        uint256 sentAmount
    ) external {
        sentAmount = bound(sentAmount, mintAmount + 1, type(uint256).max);
        add3Token.mint(from, mintAmount);
        vm.prank(from);
        add3Token.approve(address(this), type(uint256).max);
        add3Token.transferFrom(from, to, sentAmount);
    }
}
