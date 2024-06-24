// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { ERC20 } from "../src/Add3Token.sol";

contract MockToken is ERC20("Mock", "MCK") {
    address public immutable bob = address(0xB0B);

    constructor() {
        _mint(bob, 1000000 ether);
    }
}
