// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMemeFactory
 * @dev Interface for the Meme Token Factory contract
 * @author MemeFactory Team
 */
interface IMemeFactory {
    // ============ Events ============
    
    /**
     * @dev Emitted when a new Meme token is deployed
     * @param tokenAddress Address of the deployed token
     * @param creator Address of the token creator
     * @param symbol Token symbol
     * @param totalSupply Total supply of the token
     * @param perMint Amount minted per mint operation
     * @param price Price per mint operation in wei
     */
    event MemeDeployed(
        address indexed tokenAddress,
        address indexed creator,
        string symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    );
    
    /**
     * @dev Emitted when tokens are minted
     * @param tokenAddress Address of the token
     * @param minter Address of the minter
     * @param amount Amount of tokens minted
     * @param fee Total fee paid
     * @param projectFee Fee paid to project owner
     * @param creatorFee Fee paid to token creator
     */
    event MemeMinted(
        address indexed tokenAddress,
        address indexed minter,
        uint256 amount,
        uint256 fee,
        uint256 projectFee,
        uint256 creatorFee
    );

    /**
     * @dev Emitted when liquidity is added to Uniswap
     * @param tokenAddress Address of the token
     * @param ethAmount Amount of ETH added to liquidity
     * @param tokenAmount Amount of tokens added to liquidity
     * @param liquidityTokens Amount of liquidity tokens received
     * @param pairAddress Address of the Uniswap pair
     */
    event LiquidityAdded(
        address indexed tokenAddress,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityTokens,
        address indexed pairAddress
    );

    /**
     * @dev Emitted when tokens are bought through Uniswap
     * @param tokenAddress Address of the token
     * @param buyer Address of the buyer
     * @param ethAmount Amount of ETH spent
     * @param tokenAmount Amount of tokens received
     */
    event MemeBought(
        address indexed tokenAddress,
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    
    // ============ Structs ============
    
    /**
     * @dev Token information structure
     */
    struct TokenInfo {
        string symbol;
        uint256 totalSupply;
        uint256 currentSupply;
        uint256 perMint;
        uint256 price;
        address creator;
        bool exists;
        bool liquidityAdded;
        address pairAddress;
        uint256 accumulatedFees;
    }
    
    // ============ Main Functions ============
    
    /**
     * @dev Deploy a new Meme token
     * @param symbol Token symbol (1-10 characters)
     * @param totalSupply Total supply of tokens (must be > 0)
     * @param perMint Amount of tokens minted per operation (must be > 0 and <= totalSupply)
     * @param price Price per mint operation in wei (must be >= 1000 wei)
     * @return tokenAddress Address of the deployed token
     */
    function deployMeme(
        string calldata symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    ) external returns (address tokenAddress);
    
    /**
     * @dev Mint tokens from a deployed Meme token
     * @param tokenAddr Address of the token to mint from
     */
    function mintMeme(address tokenAddr) external payable;

    /**
     * @dev Buy tokens through Uniswap when price is better than initial price
     * @param tokenAddr Address of the token to buy
     * @param minTokenAmount Minimum amount of tokens to receive
     */
    function buyMeme(address tokenAddr, uint256 minTokenAmount) external payable;
    
    // ============ View Functions ============
    
    /**
     * @dev Get token information
     * @param tokenAddr Address of the token
     * @return symbol Token symbol
     * @return totalSupply Total supply
     * @return currentSupply Current minted supply
     * @return perMint Amount per mint
     * @return accumulatedFees Accumulated project fees
     * @return creator Token creator address
     * @return liquidityAdded Whether liquidity has been added
     * @return pairAddress Uniswap pair address
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
    );
    
    /**
     * @dev Get the number of deployed tokens
     * @return count Number of deployed tokens
     */
    function getDeployedTokensCount() external view returns (uint256 count);
    
    /**
     * @dev Get deployed token address by index
     * @param index Index of the token
     * @return tokenAddress Address of the token
     */
    function getDeployedToken(uint256 index) external view returns (address tokenAddress);
    
    /**
     * @dev Check if a token was deployed by this factory
     * @param tokenAddr Address to check
     * @return deployed True if token was deployed by this factory
     */
    function isTokenDeployed(address tokenAddr) external view returns (bool deployed);
    
    /**
     * @dev Get the implementation contract address
     * @return implementation Address of the implementation contract
     */
    function implementation() external view returns (address implementation);
    
    /**
     * @dev Get the project owner address
     * @return projectOwner Address of the project owner
     */
    function projectOwner() external view returns (address projectOwner);
    
    /**
     * @dev Get the project fee rate (basis points)
     * @return feeRate Project fee rate (100 = 1%)
     */
    function PROJECT_FEE_RATE() external view returns (uint256 feeRate);
    
    /**
     * @dev Get the fee denominator
     * @return denominator Fee denominator (10000 = 100%)
     */
    function FEE_DENOMINATOR() external view returns (uint256 denominator);

    /**
     * @dev Get the Uniswap V2 Router address
     * @return router Address of the Uniswap V2 Router
     */
    function uniswapRouter() external view returns (address router);

    /**
     * @dev Get the current price of a token on Uniswap
     * @param tokenAddr Address of the token
     * @param ethAmount Amount of ETH to get token price for
     * @return tokenAmount Amount of tokens that can be bought with ethAmount
     */
    function getUniswapPrice(address tokenAddr, uint256 ethAmount) external view returns (uint256 tokenAmount);
}
