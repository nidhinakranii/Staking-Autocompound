// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20, ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * A Burnable, Mintable and PausableERC20 Smart Contract.
 * The ERC20 Smart Contract allows only the owner to:
 * a) Mint an input amount of tokens to an arbitrary wallet.
 * b) Burn an input amount of only ERC20 Smart Contract owner’s tokens (to be clear: the smart contract
 * has to allow only the tokens of the smart contract owner to be burnt )
 * c) Pause the contract (by default the contract is not paused)
 */

contract Add3Token is ERC20("Add3Token", "ADD3"), ERC20Burnable, Pausable, Ownable {
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    ///@dev Warning: Possible attack vector due to centralization via access control on this function

    function mint(address to, uint256 amount) external whenNotPaused onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override whenNotPaused onlyOwner {
        _burn(owner(), amount);
    }

    ///@dev Warning: Possible attack vector due to centralization via access control on this function
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}
