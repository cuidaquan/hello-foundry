// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMemeFactory.sol";
import "./interfaces/IMemeToken.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./MemeToken.sol";

/**
 * @title MemeFactory
 * @dev Factory contract for deploying and managing Meme tokens using minimal proxy pattern
 * @author MemeFactory Team
 */
contract MemeFactory is IMemeFactory, ReentrancyGuard {
    // ============ Constants ============
    
    /// @dev Project fee rate in basis points (500 = 5%)
    uint256 public constant PROJECT_FEE_RATE = 500;
    
    /// @dev Fee denominator (10000 = 100%)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // ============ State Variables ============
    
    /// @dev Address of the MemeToken implementation contract
    address public immutable implementation;

    /// @dev Address of the project owner (receives project fees)
    address public immutable projectOwner;

    /// @dev Address of the Uniswap V2 Router
    address public immutable uniswapRouter;
    
    /// @dev Mapping from token address to token information
    mapping(address => TokenInfo) public tokenInfos;
    
    /// @dev Array of all deployed token addresses
    address[] public deployedTokens;
    
    // ============ Constructor ============
    
    /**
     * @dev Constructor
     * @param _implementation Address of the MemeToken implementation contract
     * @param _projectOwner Address of the project owner
     * @param _uniswapRouter Address of the Uniswap V2 Router
     */
    constructor(address _implementation, address _projectOwner, address _uniswapRouter) {
        require(_implementation != address(0), "MemeFactory: zero implementation address");
        require(_projectOwner != address(0), "MemeFactory: zero project owner address");
        require(_uniswapRouter != address(0), "MemeFactory: zero uniswap router address");

        implementation = _implementation;
        projectOwner = _projectOwner;
        uniswapRouter = _uniswapRouter;
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
            exists: true,
            liquidityAdded: false,
            pairAddress: address(0),
            accumulatedFees: 0
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

        // Calculate and distribute fees (fees are taken from the price)
        (uint256 projectFee, uint256 creatorFee) = _calculateFees(msg.value);

        // Accumulate project fees for liquidity
        info.accumulatedFees += projectFee;

        // Check if we should add liquidity (when accumulated fees reach threshold)
        bool shouldAddLiquidity = !info.liquidityAdded && _shouldAddLiquidity(info);

        if (shouldAddLiquidity) {
            _addLiquidity(tokenAddr, info);
        } else {
            // Distribute fees normally if not adding liquidity
            _distributeFees(msg.value, info.creator, projectFee, creatorFee);
        }

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
        uint256 accumulatedFees,
        address creator,
        bool liquidityAdded,
        address pairAddress
    ) {
        TokenInfo storage info = tokenInfos[tokenAddr];
        require(info.exists, "MemeFactory: token not found");

        return (
            info.symbol,
            info.totalSupply,
            info.currentSupply,
            info.perMint,
            info.accumulatedFees,
            info.creator,
            info.liquidityAdded,
            info.pairAddress
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

    /**
     * @dev Check if liquidity should be added
     * @param info Token information
     * @return shouldAdd True if liquidity should be added
     */
    function _shouldAddLiquidity(TokenInfo storage info) internal view returns (bool shouldAdd) {
        // Add liquidity when accumulated fees reach a threshold (e.g., 1 ETH worth)
        return info.accumulatedFees >= 1 ether;
    }

    /**
     * @dev Add liquidity to Uniswap
     * @param tokenAddr Address of the token
     * @param info Token information
     */
    function _addLiquidity(address tokenAddr, TokenInfo storage info) internal {
        uint256 ethAmount = info.accumulatedFees;
        uint256 tokenAmount = (ethAmount * 10**18) / info.price; // Calculate tokens based on mint price

        // Mint tokens for liquidity
        IMemeToken(tokenAddr).mint(address(this), tokenAmount);

        // Approve router to spend tokens
        IMemeToken(tokenAddr).approve(uniswapRouter, tokenAmount);

        // Add liquidity
        IUniswapV2Router router = IUniswapV2Router(uniswapRouter);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            tokenAddr,
            tokenAmount,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            address(this), // LP tokens go to factory
            block.timestamp + 300 // 5 minutes deadline
        );

        // Get pair address
        address factory = router.factory();
        address weth = router.WETH();
        address pairAddress = IUniswapV2Factory(factory).getPair(tokenAddr, weth);

        // Update token info
        info.liquidityAdded = true;
        info.pairAddress = pairAddress;
        info.accumulatedFees = 0; // Reset accumulated fees

        // Emit event
        emit LiquidityAdded(tokenAddr, amountETH, amountToken, liquidity, pairAddress);
    }

    /**
     * @dev Buy tokens through Uniswap
     * @param tokenAddr Address of the token to buy
     * @param minTokenAmount Minimum amount of tokens to receive
     */
    function buyMeme(address tokenAddr, uint256 minTokenAmount) external payable nonReentrant {
        TokenInfo storage info = tokenInfos[tokenAddr];
        require(info.exists, "MemeFactory: token not found");
        require(info.liquidityAdded, "MemeFactory: liquidity not added yet");
        require(msg.value > 0, "MemeFactory: zero ETH amount");

        // Check if Uniswap price is better than mint price
        uint256 uniswapTokenAmount = getUniswapPrice(tokenAddr, msg.value);
        uint256 mintTokenAmount = (msg.value * 10**18) / info.price;

        require(uniswapTokenAmount > mintTokenAmount, "MemeFactory: mint price is better");
        require(uniswapTokenAmount >= minTokenAmount, "MemeFactory: insufficient output amount");

        // Swap ETH for tokens
        IUniswapV2Router router = IUniswapV2Router(uniswapRouter);
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = tokenAddr;

        uint256[] memory amounts = router.swapExactETHForTokens{value: msg.value}(
            minTokenAmount,
            path,
            msg.sender,
            block.timestamp + 300
        );

        emit MemeBought(tokenAddr, msg.sender, msg.value, amounts[1]);
    }

    /**
     * @dev Get the current price of a token on Uniswap
     * @param tokenAddr Address of the token
     * @param ethAmount Amount of ETH to get token price for
     * @return tokenAmount Amount of tokens that can be bought with ethAmount
     */
    function getUniswapPrice(address tokenAddr, uint256 ethAmount) public view returns (uint256 tokenAmount) {
        TokenInfo storage info = tokenInfos[tokenAddr];
        if (!info.exists || !info.liquidityAdded) {
            return 0;
        }

        try IUniswapV2Router(uniswapRouter).getAmountsOut(ethAmount, _getPath(tokenAddr)) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            return 0;
        }
    }

    /**
     * @dev Get trading path for ETH -> Token
     * @param tokenAddr Address of the token
     * @return path Trading path array
     */
    function _getPath(address tokenAddr) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = IUniswapV2Router(uniswapRouter).WETH();
        path[1] = tokenAddr;
    }
}
