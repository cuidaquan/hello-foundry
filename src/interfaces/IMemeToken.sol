// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMemeToken
 * @dev Interface for Meme Token implementation contract
 * @author MemeFactory Team
 */
interface IMemeToken is IERC20 {
    // ============ Events ============
    
    /**
     * @dev Emitted when the token is initialized
     * @param name Token name
     * @param symbol Token symbol
     * @param totalSupplyLimit Maximum total supply
     * @param perMintAmount Amount per mint operation
     * @param mintPrice Price per mint operation
     * @param creator Token creator address
     * @param factory Factory contract address
     */
    event TokenInitialized(
        string name,
        string symbol,
        uint256 totalSupplyLimit,
        uint256 perMintAmount,
        uint256 mintPrice,
        address creator,
        address factory
    );
    
    /**
     * @dev Emitted when tokens are minted
     * @param to Recipient address
     * @param amount Amount minted
     */
    event TokenMinted(
        address indexed to,
        uint256 amount
    );
    
    // ============ Initialization ============
    
    /**
     * @dev Initialize the token (only called once by proxy)
     * @param name Token name
     * @param symbol Token symbol
     * @param totalSupplyLimit Maximum total supply
     * @param perMintAmount Amount per mint operation
     * @param mintPrice Price per mint operation in wei
     * @param creator Token creator address
     * @param factory Factory contract address
     */
    function initialize(
        string calldata name,
        string calldata symbol,
        uint256 totalSupplyLimit,
        uint256 perMintAmount,
        uint256 mintPrice,
        address creator,
        address factory
    ) external;
    
    // ============ Minting ============
    
    /**
     * @dev Mint tokens (only callable by factory)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;
    
    // ============ View Functions ============
    
    /**
     * @dev Get the total supply limit
     * @return limit Maximum total supply
     */
    function getTotalSupplyLimit() external view returns (uint256 limit);
    
    /**
     * @dev Get the per mint amount
     * @return amount Amount per mint operation
     */
    function getPerMintAmount() external view returns (uint256 amount);
    
    /**
     * @dev Get the mint price
     * @return price Price per mint operation in wei
     */
    function getMintPrice() external view returns (uint256 price);
    
    /**
     * @dev Get the token creator address
     * @return creator Creator address
     */
    function getCreator() external view returns (address creator);
    
    /**
     * @dev Get the factory contract address
     * @return factory Factory address
     */
    function getFactory() external view returns (address factory);
    
    /**
     * @dev Check if the token has been initialized
     * @return initialized True if initialized
     */
    function isInitialized() external view returns (bool initialized);
    
    // ============ Standard ERC20 Extensions ============
    
    /**
     * @dev Returns the name of the token
     * @return name Token name
     */
    function name() external view returns (string memory name);
    
    /**
     * @dev Returns the symbol of the token
     * @return symbol Token symbol
     */
    function symbol() external view returns (string memory symbol);
    
    /**
     * @dev Returns the number of decimals used to get its user representation
     * @return decimals Number of decimals
     */
    function decimals() external view returns (uint8 decimals);
}
