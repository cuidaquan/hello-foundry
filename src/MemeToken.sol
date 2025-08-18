// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IMemeToken.sol";

/**
 * @title MemeToken
 * @dev ERC20 token implementation for Meme tokens with proxy support
 * @author MemeFactory Team
 */
contract MemeToken is ERC20, Initializable, IMemeToken {
    // ============ State Variables ============
    
    /// @dev Maximum total supply for this token
    uint256 private _totalSupplyLimit;
    
    /// @dev Amount of tokens minted per mint operation
    uint256 private _perMintAmount;
    
    /// @dev Price per mint operation in wei
    uint256 private _mintPrice;
    
    /// @dev Address of the token creator
    address private _creator;
    
    /// @dev Address of the factory contract
    address private _factory;
    
    /// @dev Flag to track initialization status
    bool private _initialized;
    
    // ============ Modifiers ============
    
    /**
     * @dev Modifier to restrict access to factory only
     */
    modifier onlyFactory() {
        require(msg.sender == _factory, "MemeToken: caller is not the factory");
        _;
    }
    
    /**
     * @dev Modifier to ensure token is initialized
     */
    modifier whenInitialized() {
        require(_initialized, "MemeToken: not initialized");
        _;
    }
    
    // ============ Constructor ============
    
    /**
     * @dev Constructor for implementation contract
     * @notice This constructor is only called for the implementation contract
     * Proxy contracts will use initialize() instead
     */
    constructor() ERC20("", "") {
        // Disable initialization for implementation contract
        _disableInitializers();
    }
    
    // ============ Initialization ============
    
    /**
     * @inheritdoc IMemeToken
     */
    function initialize(
        string calldata name,
        string calldata symbol,
        uint256 totalSupplyLimit,
        uint256 perMintAmount,
        uint256 mintPrice,
        address creator,
        address factory
    ) external initializer {
        require(bytes(name).length > 0, "MemeToken: empty name");
        require(bytes(symbol).length > 0, "MemeToken: empty symbol");
        require(totalSupplyLimit > 0, "MemeToken: zero total supply limit");
        require(perMintAmount > 0, "MemeToken: zero per mint amount");
        require(perMintAmount <= totalSupplyLimit, "MemeToken: per mint exceeds total supply");
        require(mintPrice > 0, "MemeToken: zero mint price");
        require(creator != address(0), "MemeToken: zero creator address");
        require(factory != address(0), "MemeToken: zero factory address");
        
        // Initialize ERC20
        _name = name;
        _symbol = symbol;
        
        // Set token parameters
        _totalSupplyLimit = totalSupplyLimit;
        _perMintAmount = perMintAmount;
        _mintPrice = mintPrice;
        _creator = creator;
        _factory = factory;
        _initialized = true;
        
        emit TokenInitialized(
            name,
            symbol,
            totalSupplyLimit,
            perMintAmount,
            mintPrice,
            creator,
            factory
        );
    }
    
    // ============ Minting Functions ============
    
    /**
     * @inheritdoc IMemeToken
     */
    function mint(address to, uint256 amount) external onlyFactory whenInitialized {
        require(to != address(0), "MemeToken: mint to zero address");
        require(amount > 0, "MemeToken: zero amount");
        require(totalSupply() + amount <= _totalSupplyLimit, "MemeToken: exceeds total supply limit");
        
        _mint(to, amount);
        
        emit TokenMinted(to, amount);
    }
    
    // ============ View Functions ============
    
    /**
     * @inheritdoc IMemeToken
     */
    function getTotalSupplyLimit() external view returns (uint256) {
        return _totalSupplyLimit;
    }
    
    /**
     * @inheritdoc IMemeToken
     */
    function getPerMintAmount() external view returns (uint256) {
        return _perMintAmount;
    }
    
    /**
     * @inheritdoc IMemeToken
     */
    function getMintPrice() external view returns (uint256) {
        return _mintPrice;
    }
    
    /**
     * @inheritdoc IMemeToken
     */
    function getCreator() external view returns (address) {
        return _creator;
    }
    
    /**
     * @inheritdoc IMemeToken
     */
    function getFactory() external view returns (address) {
        return _factory;
    }
    
    /**
     * @inheritdoc IMemeToken
     */
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
    
    // ============ ERC20 Overrides ============
    
    /**
     * @dev Override to ensure token is initialized before transfers
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20, IERC20) whenInitialized returns (bool) {
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Override to ensure token is initialized before transfers
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override(ERC20, IERC20) whenInitialized returns (bool) {
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Override to ensure token is initialized before approvals
     */
    function approve(address spender, uint256 amount) public virtual override(ERC20, IERC20) whenInitialized returns (bool) {
        return super.approve(spender, amount);
    }
    
    // ============ Internal Variables Access ============
    
    /// @dev Internal storage for token name (for proxy compatibility)
    string private _name;
    
    /// @dev Internal storage for token symbol (for proxy compatibility)
    string private _symbol;
    
    /**
     * @dev Override name() to use internal storage
     */
    function name() public view virtual override(ERC20, IMemeToken) returns (string memory) {
        return _name;
    }
    
    /**
     * @dev Override symbol() to use internal storage
     */
    function symbol() public view virtual override(ERC20, IMemeToken) returns (string memory) {
        return _symbol;
    }
    
    /**
     * @dev Override decimals() to return standard 18 decimals
     */
    function decimals() public view virtual override(ERC20, IMemeToken) returns (uint8) {
        return 18;
    }
}
