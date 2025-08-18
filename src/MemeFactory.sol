// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMemeFactory.sol";
import "./interfaces/IMemeToken.sol";
import "./MemeToken.sol";

/**
 * @title MemeFactory
 * @dev Factory contract for deploying and managing Meme tokens using minimal proxy pattern
 * @author MemeFactory Team
 */
contract MemeFactory is IMemeFactory, ReentrancyGuard {
    // ============ Constants ============
    
    /// @dev Project fee rate in basis points (100 = 1%)
    uint256 public constant PROJECT_FEE_RATE = 100;
    
    /// @dev Fee denominator (10000 = 100%)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // ============ State Variables ============
    
    /// @dev Address of the MemeToken implementation contract
    address public immutable implementation;
    
    /// @dev Address of the project owner (receives project fees)
    address public immutable projectOwner;
    
    /// @dev Mapping from token address to token information
    mapping(address => TokenInfo) public tokenInfos;
    
    /// @dev Array of all deployed token addresses
    address[] public deployedTokens;
    
    // ============ Constructor ============
    
    /**
     * @dev Constructor
     * @param _implementation Address of the MemeToken implementation contract
     * @param _projectOwner Address of the project owner
     */
    constructor(address _implementation, address _projectOwner) {
        require(_implementation != address(0), "MemeFactory: zero implementation address");
        require(_projectOwner != address(0), "MemeFactory: zero project owner address");
        
        implementation = _implementation;
        projectOwner = _projectOwner;
    }
    
    // ============ Main Functions ============
    
    /**
     * @inheritdoc IMemeFactory
     */
    function deployMeme(
        string calldata symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    ) external returns (address tokenAddress) {
        // Validate parameters
        _validateDeployParams(symbol, totalSupply, perMint, price);
        
        // Create proxy contract
        address clone = Clones.clone(implementation);
        
        // Generate token name
        string memory name = string(abi.encodePacked("Meme ", symbol));
        
        // Initialize the proxy contract
        IMemeToken(clone).initialize(
            name,
            symbol,
            totalSupply,
            perMint,
            price,
            msg.sender,
            address(this)
        );
        
        // Store token information
        tokenInfos[clone] = TokenInfo({
            symbol: symbol,
            totalSupply: totalSupply,
            currentSupply: 0,
            perMint: perMint,
            price: price,
            creator: msg.sender,
            exists: true
        });
        
        // Add to deployed tokens array
        deployedTokens.push(clone);
        
        // Emit event
        emit MemeDeployed(clone, msg.sender, symbol, totalSupply, perMint, price);
        
        return clone;
    }
    
    /**
     * @inheritdoc IMemeFactory
     */
    function mintMeme(address tokenAddr) external payable nonReentrant {
        TokenInfo storage info = tokenInfos[tokenAddr];
        
        // Validate token exists
        require(info.exists, "MemeFactory: token not found");
        
        // Validate payment amount
        require(msg.value == info.price, "MemeFactory: incorrect payment amount");
        
        // Check supply limit
        require(
            info.currentSupply + info.perMint <= info.totalSupply,
            "MemeFactory: exceeds total supply"
        );
        
        // Update current supply
        info.currentSupply += info.perMint;
        
        // Calculate and distribute fees
        (uint256 projectFee, uint256 creatorFee) = _calculateFees(msg.value);
        _distributeFees(msg.value, info.creator, projectFee, creatorFee);
        
        // Mint tokens
        IMemeToken(tokenAddr).mint(msg.sender, info.perMint);
        
        // Emit event
        emit MemeMinted(
            tokenAddr,
            msg.sender,
            info.perMint,
            msg.value,
            projectFee,
            creatorFee
        );
    }
    
    // ============ View Functions ============
    
    /**
     * @inheritdoc IMemeFactory
     */
    function getTokenInfo(address tokenAddr) external view returns (
        string memory symbol,
        uint256 totalSupply,
        uint256 currentSupply,
        uint256 perMint,
        uint256 price,
        address creator
    ) {
        TokenInfo storage info = tokenInfos[tokenAddr];
        require(info.exists, "MemeFactory: token not found");
        
        return (
            info.symbol,
            info.totalSupply,
            info.currentSupply,
            info.perMint,
            info.price,
            info.creator
        );
    }
    
    /**
     * @inheritdoc IMemeFactory
     */
    function getDeployedTokensCount() external view returns (uint256) {
        return deployedTokens.length;
    }
    
    /**
     * @inheritdoc IMemeFactory
     */
    function getDeployedToken(uint256 index) external view returns (address) {
        require(index < deployedTokens.length, "MemeFactory: index out of bounds");
        return deployedTokens[index];
    }
    
    /**
     * @inheritdoc IMemeFactory
     */
    function isTokenDeployed(address tokenAddr) external view returns (bool) {
        return tokenInfos[tokenAddr].exists;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev Validate deployment parameters
     * @param symbol Token symbol
     * @param totalSupply Total supply
     * @param perMint Per mint amount
     * @param price Mint price
     */
    function _validateDeployParams(
        string calldata symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    ) internal pure {
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 10, "MemeFactory: invalid symbol length");
        require(totalSupply > 0 && totalSupply <= 10**30, "MemeFactory: invalid total supply");
        require(perMint > 0 && perMint <= totalSupply, "MemeFactory: invalid per mint amount");
        require(price >= 1000, "MemeFactory: price too low"); // Minimum 1000 wei to avoid precision issues
    }
    
    /**
     * @dev Calculate project and creator fees
     * @param totalFee Total fee amount
     * @return projectFee Fee for project owner
     * @return creatorFee Fee for token creator
     */
    function _calculateFees(uint256 totalFee) internal pure returns (uint256 projectFee, uint256 creatorFee) {
        projectFee = (totalFee * PROJECT_FEE_RATE) / FEE_DENOMINATOR;
        creatorFee = totalFee - projectFee;
    }
    
    /**
     * @dev Distribute fees to project owner and creator
     * @param totalFee Total fee amount
     * @param creator Token creator address
     * @param projectFee Fee for project owner
     * @param creatorFee Fee for token creator
     */
    function _distributeFees(
        uint256 totalFee,
        address creator,
        uint256 projectFee,
        uint256 creatorFee
    ) internal {
        require(projectFee + creatorFee == totalFee, "MemeFactory: fee calculation error");
        
        // Transfer project fee
        if (projectFee > 0) {
            (bool success1, ) = payable(projectOwner).call{value: projectFee}("");
            require(success1, "MemeFactory: project fee transfer failed");
        }
        
        // Transfer creator fee
        if (creatorFee > 0) {
            (bool success2, ) = payable(creator).call{value: creatorFee}("");
            require(success2, "MemeFactory: creator fee transfer failed");
        }
    }
}
