// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IUniswapV2Router.sol";
import "../../src/interfaces/IUniswapV2Factory.sol";
import "../../src/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock Uniswap Contracts for Testing
 * @dev Mock implementations of Uniswap V2 contracts for testing purposes
 */

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract MockUniswapV2Factory is IUniswapV2Factory {
    address public override feeTo;
    address public override feeToSetter;
    
    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;
    
    // For testing purposes
    address private mockPair;
    
    function setPair(address _mockPair) external {
        mockPair = _mockPair;
    }
    
    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }
    
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS");
        
        // Return mock pair for testing
        pair = mockPair;
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }
    
    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}

contract MockUniswapV2Pair is IUniswapV2Pair {
    string public constant override name = "Uniswap V2";
    string public constant override symbol = "UNI-V2";
    uint8 public constant override decimals = 18;
    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;
    
    bytes32 public constant override PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public override nonces;
    
    uint public constant override MINIMUM_LIQUIDITY = 10**3;
    bytes32 public override DOMAIN_SEPARATOR;
    
    address public override factory;
    address public override token0;
    address public override token1;
    
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    
    uint public override price0CumulativeLast;
    uint public override price1CumulativeLast;
    uint public override kLast;
    
    constructor() {
        factory = msg.sender;
    }
    
    function getReserves() public view override returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function approve(address spender, uint value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transfer(address to, uint value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] -= value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }
    
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        // Mock implementation
    }
    
    function mint(address to) external override returns (uint liquidity) {
        // Mock implementation - return some liquidity tokens
        liquidity = 1000 * 10**18;
        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        emit Transfer(address(0), to, liquidity);
        emit Mint(msg.sender, 0, 0);
    }
    
    function burn(address to) external override returns (uint amount0, uint amount1) {
        // Mock implementation
        amount0 = 100 * 10**18;
        amount1 = 1 ether;
        emit Burn(msg.sender, amount0, amount1, to);
    }
    
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external override {
        emit Swap(msg.sender, 0, 0, amount0Out, amount1Out, to);
    }
    
    function skim(address to) external override {}
    
    function sync() external override {
        emit Sync(reserve0, reserve1);
    }
    
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }
}

contract MockUniswapV2Router is IUniswapV2Router {
    address private _factory;
    address private _WETH;

    // For testing purposes
    uint256[] private mockAmountsOut;

    constructor(address factory_, address WETH_) {
        _factory = factory_;
        _WETH = WETH_;
    }

    function factory() external pure override returns (address) {
        return address(0); // Mock implementation
    }

    function WETH() external pure override returns (address) {
        return address(0); // Mock implementation
    }

    function setAmountsOut(uint256 amount) external {
        mockAmountsOut = new uint256[](2);
        mockAmountsOut[0] = 0; // ETH amount
        mockAmountsOut[1] = amount; // Token amount
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override returns (uint amountA, uint amountB, uint liquidity) {
        // Mock implementation
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = 1000 * 10**18;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable override returns (uint amountToken, uint amountETH, uint liquidity) {
        // Mock implementation
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = 1000 * 10**18;

        // Transfer tokens from sender
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        override
        returns (uint[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = mockAmountsOut.length > 1 ? mockAmountsOut[1] : amountOutMin;

        // Mock token transfer to recipient
        // In real implementation, this would swap ETH for tokens
    }

    function getAmountsOut(uint amountIn, address[] calldata path)
        external
        view
        override
        returns (uint[] memory amounts) {
        if (mockAmountsOut.length > 0) {
            amounts = mockAmountsOut;
            amounts[0] = amountIn;
        } else {
            amounts = new uint256[](path.length);
            amounts[0] = amountIn;
            // Default mock behavior
            for (uint i = 1; i < path.length; i++) {
                amounts[i] = amountIn * 1000; // Mock 1000x return
            }
        }
    }

    // Simplified implementations for other functions
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external override returns (uint[] memory amounts) {
        amounts = new uint256[](2);
    }

    function swapTokensForExactTokens(uint, uint, address[] calldata, address, uint) external override returns (uint[] memory amounts) {
        amounts = new uint256[](2);
    }

    function swapTokensForExactETH(uint, uint, address[] calldata, address, uint) external override returns (uint[] memory amounts) {
        amounts = new uint256[](2);
    }

    function swapExactTokensForETH(uint, uint, address[] calldata, address, uint) external override returns (uint[] memory amounts) {
        amounts = new uint256[](2);
    }

    function swapETHForExactTokens(uint, address[] calldata, address, uint) external payable override returns (uint[] memory amounts) {
        amounts = new uint256[](2);
    }

    function getAmountOut(uint, uint, uint) external pure override returns (uint) {
        return 0;
    }

    function getAmountIn(uint, uint, uint) external pure override returns (uint) {
        return 0;
    }

    function getAmountsIn(uint, address[] calldata path) external pure override returns (uint[] memory amounts) {
        amounts = new uint256[](path.length);
    }
}
