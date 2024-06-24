// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { Add3Staking as Staking } from "../src/Add3Staking.sol";
import { Add3Token } from "../src/Add3Token.sol";
import { MockToken } from "./MockToken.sol";

contract DynamicStakingTest is Test {
    /* ------------------- STATE VARS ------------------- */
    Staking public staking;
    Add3Token public add3Token;
    MockToken internal mockToken;

    address public immutable deployer = vm.addr(0x1);
    address public immutable alice = address(0xA71CE);
    address public immutable bob = address(0xB0B);
    address public immutable whale = address(0xB16);
    address public immutable degen = address(0xDe6e4);

    uint256 internal constant STAKING_CONTRACT_BALANCE = 100_000 ether;
    uint256 internal constant INITIAL_BALANCE = 100 ether;
    uint256 internal constant ALICE_STAKING_AMOUNT = 10 ether;
    uint256 internal constant BOB_STAKING_AMOUNT = 0.3 ether;

    uint256 internal constant REWARD_RATE = 10;
    uint256 internal constant STAKING_DURATION = 365 days;
    uint256 internal constant MINIMUM_LOCK_TIME = 60 days;
    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint128).max;

    enum StakingType {
        Static,
        Dynamic
    }

    /* ----------------------- HELPERS ---------------------- */

    function _tenPercent(uint256 amount) internal pure returns (uint256) {
        return (amount * 10) / 100;
    }

    function _logBalances() internal view {
        console.log("");
        uint256 aliceBalance = add3Token.balanceOf(alice);
        uint256 bobBalance = add3Token.balanceOf(bob);
        console.log("Alice balance:", aliceBalance);
        console.log("Bob balance:", bobBalance);
        console.log("");
    }

    /* --------------------- SETUP --------------------- */

    function setUp() public {
        vm.startPrank(deployer);
        add3Token = new Add3Token();
        staking = new Staking();
        mockToken = new MockToken();
        staking.initialize(
            address(add3Token),
            Staking.StakingType.Dynamic,
            REWARD_RATE,
            STAKING_DURATION,
            MINIMUM_LOCK_TIME,
            MAX_TOTAL_SUPPLY
        );

        deal(address(add3Token), address(staking), STAKING_CONTRACT_BALANCE);
        deal(address(add3Token), alice, INITIAL_BALANCE);
        deal(address(add3Token), bob, INITIAL_BALANCE);
        deal(address(add3Token), whale, MAX_TOTAL_SUPPLY + 1);
        deal(alice, 10 ether);
        deal(bob, 10 ether);
        vm.stopPrank();
    }

    function testStakingTypeIsCorrectlySet() public view {
        assert(staking.stakingType() == Staking.StakingType.Dynamic);
    }

    function testStakingCanBeChangedByOwnerOnly() public {
        vm.startPrank(deployer);
        assert(staking.stakingType() == Staking.StakingType.Dynamic);
        staking.changeStakingType(Staking.StakingType.Static);
        assert(staking.stakingType() == Staking.StakingType.Static);
    }

    function testAliceCanStake() public {
        vm.startPrank(alice);
        add3Token.approve(address(staking), INITIAL_BALANCE);
        staking.stake(ALICE_STAKING_AMOUNT);
        assertEq(staking.balances(alice), ALICE_STAKING_AMOUNT);
        assertEq(staking.totalSupply(), ALICE_STAKING_AMOUNT);
    }

    function testStakingContractGeneratesRewards() public {
        testAliceCanStake();
        skip(30 days);
        uint256 aliceAvailableRewards = staking.availableRewards(alice);
        assert(aliceAvailableRewards > 0);
    }

    function testAliceCanUnstakeHalfAndCompoundEarnings() public {
        testAliceCanStake();
        skip(60 days);
        staking.unstake(ALICE_STAKING_AMOUNT / 2);
        uint256 aliceStakingBalanceAfterUnstaking = staking.balances(alice);
        // at this point the balance should be half + compounded rewards
        assert(aliceStakingBalanceAfterUnstaking >= ALICE_STAKING_AMOUNT / 2);
    }

    function testAliceCanClaimRewards() public {
        testAliceCanStake();
        skip(60 days);
        uint256 aliceBalanceBeforeClaiming = add3Token.balanceOf(alice);
        staking.claimRewards();
        uint256 aliceBalanceAfterClaiming = add3Token.balanceOf(alice);
        assert(aliceBalanceAfterClaiming > aliceBalanceBeforeClaiming);
        uint256 lastClaimedRewards = staking.lastClaimedRewards(alice);
        assert(lastClaimedRewards == block.timestamp);
    }

    function testAliceCanWithdrawAllAndGetRewards() public {
        testAliceCanStake();
        skip(60 days);
        staking.withdrawAll();
        uint256 aliceBalanceAfterWithdrawing = add3Token.balanceOf(alice);
        assert(aliceBalanceAfterWithdrawing > ALICE_STAKING_AMOUNT);
    }

    function testAliceShouldNotBeAbleToUnstakeMoreThanStaked() public {
        testAliceCanStake();
        skip(60 days);

        vm.expectRevert();
        staking.unstake(ALICE_STAKING_AMOUNT + 1);
    }

    function testAliceCantClaimRewardsBeforeTimelock() public {
        testAliceCanStake();
        skip(55 days);
        uint256 aliceBalanceBeforeClaiming = add3Token.balanceOf(alice);
        vm.expectRevert();
        staking.claimRewards();
        uint256 aliceBalanceAfterClaiming = add3Token.balanceOf(alice);
        assert(aliceBalanceAfterClaiming == aliceBalanceBeforeClaiming);
    }

    function testAliceDoesntGetOvercompensatedWhenOverstaking() public {
        testAliceCanStake();
        //eventhough she's staked for more than a year, she's not getting more rewards than the stipulated
        skip(1536 days);

        uint256 aliceBalanceBeforeWithdrawing = add3Token.balanceOf(alice);
        staking.withdrawAll();
        uint256 aliceBalanceAfterWithdrawing = add3Token.balanceOf(alice);

        assert(
            aliceBalanceAfterWithdrawing ==
                aliceBalanceBeforeWithdrawing + ALICE_STAKING_AMOUNT + _tenPercent(ALICE_STAKING_AMOUNT)
        );
    }

    function testDegensThatHaventStakedShouldNotWIthdraw() public {
        vm.startPrank(degen);
        uint256 degenBalanceBeforeWithdrawing = add3Token.balanceOf(degen);
        staking.withdrawAll();
        uint256 degenBalanceAfterWithdrawing = add3Token.balanceOf(degen);
        assert(degenBalanceAfterWithdrawing == degenBalanceBeforeWithdrawing);
    }

    function testBobCanStakeSeveralTimesToCompound() public {
        vm.startPrank(bob);
        add3Token.approve(address(staking), INITIAL_BALANCE);
        staking.stake(BOB_STAKING_AMOUNT);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 2);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 3);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 4);
    }

    function testBobCanCompoundWhenStakingTimeIsDone() public {
        vm.startPrank(bob);
        add3Token.approve(address(staking), INITIAL_BALANCE);
        staking.stake(BOB_STAKING_AMOUNT);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 2);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 3);

        skip(30 days);
        staking.stake(BOB_STAKING_AMOUNT);
        assert(staking.balances(bob) > BOB_STAKING_AMOUNT * 4);

        skip(365 days);
        vm.expectRevert();
        staking.stake(BOB_STAKING_AMOUNT);
    }

    function testSendingEth() public {
        vm.prank(bob);
        vm.expectRevert();
        address(staking).call{ value: 1 ether }("");
    }

    function testRecoverTokens() public {
        vm.prank(bob);
        mockToken.transfer(address(staking), 1000);
        assertEq(mockToken.balanceOf(address(staking)), 1000);
        vm.stopPrank();
        vm.startPrank(deployer);
        staking.rescueTokens(address(mockToken));
        assertEq(mockToken.balanceOf(deployer), 1000);
    }

    function testCantStakeMoreThanMaxCap() public {
        vm.prank(whale);
        uint balance = add3Token.balanceOf(whale);
        add3Token.approve(address(staking), balance);
        vm.expectRevert();
        staking.stake(balance);
    }
}
