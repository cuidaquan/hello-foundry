// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title CUIDAQUANToken
 * @dev ERC20 token with EIP2612 permit functionality for gasless approvals
 */
contract CUIDAQUANToken is ERC20, ERC20Permit, Ownable {
    
    /**
     * @dev Constructor that initializes the token with name, symbol and initial supply
     * @param initialSupply The initial supply of tokens to mint to the deployer
     */
    constructor(uint256 initialSupply) 
        ERC20("CUIDAQUAN Token", "CUIDAQUAN") 
        ERC20Permit("CUIDAQUAN Token")
        Ownable(msg.sender) 
    {
        _mint(msg.sender, initialSupply * 10**decimals());
    }
    
    /**
     * @dev Mint new tokens - only owner can call this
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @dev Burn tokens from caller's balance
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Burn tokens from a specific address (requires allowance)
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) public {
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        
        _approve(from, msg.sender, currentAllowance - amount);
        _burn(from, amount);
    }
}
