// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";
import { Add3Token } from "../src/Add3Token.sol";
import { Add3Staking } from "../src/Add3Staking.sol";

contract DeploymentScript is Script {
    uint256 internal constant REWARD_RATE = 10;
    uint256 internal constant STAKING_DURATION = 365 days;
    uint256 internal constant MINIMUM_LOCK_TIME = 60 days;
    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint128).max;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PK");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Add3 token
        Add3Token add3Token = new Add3Token();

        // Deploy Staking Contract
        Add3Staking add3Staking = new Add3Staking();

        // Initialize Staking Contract
        add3Staking.initialize(
            address(add3Token),
            Add3Staking.StakingType.Dynamic,
            REWARD_RATE,
            STAKING_DURATION,
            MINIMUM_LOCK_TIME,
            MAX_TOTAL_SUPPLY
        );

        // Mint tokens to staking contract
        add3Token.mint(address(add3Staking), 1_000_000 ether);

        console2.log("Add3Token deployed to:", address(add3Token));
        console2.log("Add3Staking deployed to:", address(add3Staking));
        console2.log("Balance of Staking contract is:", add3Token.balanceOf(address(add3Staking)));

        vm.stopBroadcast();
    }
}
