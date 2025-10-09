// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IUniswapV2Router.sol";
import "../../src/interfaces/IUniswapV2Factory.sol";
import "../../src/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}



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

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

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

        // Create new pair contract
        MockUniswapV2Pair newPair = new MockUniswapV2Pair();
        newPair.initialize(token0, token1);
        pair = address(newPair);

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
        blockTimestampLast = uint32(block.timestamp);
    }

    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, 'MockUniswapV2Pair: FORBIDDEN');
        token0 = _token0;
        token1 = _token1;
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        // Update cumulative prices before changing reserves
        _updateCumulativePrices();

        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }

    function _updateCumulativePrices() internal {
        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            // Calculate price ratios in UQ112x112 format
            price0CumulativeLast += uint256((uint224(reserve1) << 112) / reserve0) * timeElapsed;
            price1CumulativeLast += uint256((uint224(reserve0) << 112) / reserve1) * timeElapsed;
        }
    }

    function simulateTimeAndPriceChange(uint32 timeElapsed, uint112 newReserve0, uint112 newReserve1) external {
        // Update cumulative prices with current reserves
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            price0CumulativeLast += uint256((uint224(reserve1) << 112) / reserve0) * timeElapsed;
            price1CumulativeLast += uint256((uint224(reserve0) << 112) / reserve1) * timeElapsed;
        }

        // Update reserves and timestamp
        reserve0 = newReserve0;
        reserve1 = newReserve1;
        blockTimestampLast = uint32(block.timestamp + timeElapsed);

        emit Sync(reserve0, reserve1);
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
    

    
    function burn(address to) external override returns (uint amount0, uint amount1) {
        // Mock implementation
        amount0 = 100 * 10**18;
        amount1 = 1 ether;
        emit Burn(msg.sender, amount0, amount1, to);
    }
    
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external override {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        require(amount0Out < reserve0 && amount1Out < reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) IERC20(_token0).transfer(to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) IERC20(_token1).transfer(to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        // Very lenient K check for testing - allow flash swaps to work
        if (amount0In > 0 || amount1In > 0) {
            // Only check if we have significant input amounts to prevent abuse
            if (amount0In > 1000 || amount1In > 1000) {
                uint balance0Adjusted = balance0 * 1000 - amount0In * 3;
                uint balance1Adjusted = balance1 * 1000 - amount1In * 3;
                // Very lenient K check
                require(balance0Adjusted * balance1Adjusted >= uint(reserve0) * reserve1 * 900**2, 'UniswapV2: K');
            }
        }
        }

        _update(balance0, balance1, reserve0, reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // Simplified price calculation for testing
            price0CumulativeLast += uint((_reserve1 * 2**112) / _reserve0) * timeElapsed;
            price1CumulativeLast += uint((_reserve0 * 2**112) / _reserve1) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }
    
    function skim(address to) external override {}
    
    function sync() external override {
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external returns (uint liquidity) {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - reserve0;
        uint amount1 = balance1 - reserve1;

        if (totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1) - 1000; // MINIMUM_LIQUIDITY
            totalSupply += 1000; // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1);
        }

        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        emit Transfer(address(0), to, liquidity);

        _update(balance0, balance1, reserve0, reserve1);
        emit Mint(msg.sender, amount0, amount1);
        return liquidity;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
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
        // Get or create pair
        address pair = IUniswapV2Factory(_factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IUniswapV2Factory(_factory).createPair(tokenA, tokenB);
        }

        // Transfer tokens from sender to pair
        IERC20(tokenA).transferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountBDesired);

        // Call mint on the pair to add liquidity
        MockUniswapV2Pair(pair).mint(to);

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
