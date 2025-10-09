// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Pair.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../test/mocks/MockUniswap.sol';

/**
 * @title FlashSwapArbitrage
 * @dev Flash swap arbitrage between two different Uniswap pools
 */
contract FlashSwapArbitrage is IUniswapV2Callee, Ownable {
    
    struct ArbitrageParams {
        address factoryA;      // First Uniswap Factory address
        address factoryB;      // Second Uniswap Factory address
        address tokenA;        // Token A address
        address tokenB;        // Token B address
        uint256 amountIn;      // Input amount
        bool isToken0;         // Whether it's token0
    }
    
    event ArbitrageExecuted(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 profit
    );
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Start flash swap arbitrage
     * @param factoryA First Uniswap Factory address
     * @param factoryB Second Uniswap Factory address
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @param amountIn Amount to borrow
     */
    function startArbitrage(
        address factoryA,
        address factoryB,
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) external onlyOwner {
        // Get PoolA pair address
        address pairA = IUniswapV2Factory(factoryA).getPair(tokenA, tokenB);
        require(pairA != address(0), "PoolA pair does not exist");

        // Determine token0 and token1 order
        address token0 = IUniswapV2Pair(pairA).token0();
        address token1 = IUniswapV2Pair(pairA).token1();

        bool isToken0 = tokenA == token0;

        // Encode arbitrage parameters
        bytes memory data = abi.encode(ArbitrageParams({
            factoryA: factoryA,
            factoryB: factoryB,
            tokenA: tokenA,
            tokenB: tokenB,
            amountIn: amountIn,
            isToken0: isToken0
        }));

        // Start flash swap: borrow tokenA from PoolA
        if (isToken0) {
            IUniswapV2Pair(pairA).swap(amountIn, 0, address(this), data);
        } else {
            IUniswapV2Pair(pairA).swap(0, amountIn, address(this), data);
        }
    }
    
    /**
     * @dev Uniswap V2 flash swap callback function
     */
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        // Decode parameters
        ArbitrageParams memory params = abi.decode(data, (ArbitrageParams));

        // Verify caller is legitimate pair
        address pairA = IUniswapV2Factory(params.factoryA).getPair(params.tokenA, params.tokenB);
        require(msg.sender == pairA, "Invalid caller");
        require(sender == address(this), "Invalid sender");

        // Get borrowed amount
        uint256 amountBorrowed = params.isToken0 ? amount0 : amount1;
        require(amountBorrowed == params.amountIn, "Amount mismatch");

        // Execute arbitrage logic
        uint256 profit = _executeArbitrage(params, amountBorrowed);

        // Calculate amount to repay (including 0.3% fee)
        uint256 amountToRepay = _getAmountToRepay(amountBorrowed);

        // Ensure we have enough tokens to repay (more lenient check for testing)
        uint256 totalTokensNeeded = amountToRepay;
        uint256 totalTokensAvailable = IERC20(params.tokenA).balanceOf(address(this));
        require(totalTokensAvailable >= totalTokensNeeded, "Insufficient tokens to repay loan");

        // Repay flash loan
        IERC20(params.tokenA).transfer(pairA, amountToRepay);
        
        emit ArbitrageExecuted(
            params.tokenA,
            params.tokenB,
            amountBorrowed,
            amountToRepay,
            profit
        );
    }
    
    /**
     * @dev Execute arbitrage logic
     */
    function _executeArbitrage(
        ArbitrageParams memory params,
        uint256 amountBorrowed
    ) internal returns (uint256 profit) {
        // Get PoolB pair address
        address pairB = IUniswapV2Factory(params.factoryB).getPair(params.tokenA, params.tokenB);
        require(pairB != address(0), "PoolB pair does not exist");

        // Swap tokenA for tokenB in PoolB
        uint256 amountTokenB = _swapOnPoolB(pairB, params.tokenA, params.tokenB, amountBorrowed);

        // Swap tokenB back to tokenA in PoolA
        uint256 amountTokenAReceived = _swapOnPoolA(
            IUniswapV2Factory(params.factoryA).getPair(params.tokenA, params.tokenB),
            params.tokenB,
            params.tokenA,
            amountTokenB
        );

        // Calculate profit
        profit = amountTokenAReceived > amountBorrowed ?
                 amountTokenAReceived - amountBorrowed : 0;
        
        return profit;
    }
    
    /**
     * @dev Execute swap in PoolB
     */
    function _swapOnPoolB(
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Get reserves
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();

        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == token0 ?
            (reserve0, reserve1) : (reserve1, reserve0);

        // Calculate output amount
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        // Transfer token to pair
        IERC20(tokenIn).transfer(pair, amountIn);

        // Execute swap
        if (tokenIn == token0) {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), new bytes(0));
        } else {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), new bytes(0));
        }
        
        return amountOut;
    }
    
    /**
     * @dev Execute swap in PoolA
     */
    function _swapOnPoolA(
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // 获取储备量
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        
        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == token0 ? 
            (reserve0, reserve1) : (reserve1, reserve0);
        
        // 计算输出金额
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        
        // 转移token到pair
        IERC20(tokenIn).transfer(pair, amountIn);
        
        // 执行兑换
        if (tokenIn == token0) {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), new bytes(0));
        } else {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), new bytes(0));
        }
        
        return amountOut;
    }
    
    /**
     * @dev Calculate swap output amount (Uniswap V2 formula)
     */
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    /**
     * @dev Calculate amount to repay (including fee)
     */
    function _getAmountToRepay(uint256 amountBorrowed) internal pure returns (uint256) {
        // Uniswap V2 flash loan requires repayment of amountBorrowed * 1000 / 997
        return (amountBorrowed * 1000) / 997 + 1; // +1 for rounding
    }

    /**
     * @dev Withdraw tokens from contract (owner only)
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /**
     * @dev Withdraw ETH from contract (owner only)
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    /**
     * @dev Receive ETH
     */
    receive() external payable {}
}
