// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TWAPOracle
 * @dev Oracle contract to get Time-Weighted Average Price (TWAP) from Uniswap V2
 * @notice This contract calculates TWAP based on Uniswap V2 cumulative prices
 */
contract TWAPOracle is Ownable {
    using FixedPoint for *;

    // ============ Constants ============
    
    /// @dev Minimum time period for TWAP calculation (10 minutes)
    uint256 public constant MIN_PERIOD = 10 minutes;
    
    /// @dev Maximum time period for TWAP calculation (24 hours)
    uint256 public constant MAX_PERIOD = 24 hours;

    // ============ State Variables ============
    
    /// @dev Uniswap V2 Factory address
    address public immutable uniswapFactory;
    
    /// @dev WETH address
    address public immutable WETH;

    // ============ Structs ============
    
    /**
     * @dev Price observation structure
     */
    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    /**
     * @dev Pair information structure
     */
    struct PairInfo {
        address pair;
        address token0;
        address token1;
        bool isToken0WETH;
        Observation[] observations;
        uint256 observationIndex;
    }

    // ============ Mappings ============
    
    /// @dev Mapping from token address to pair information
    mapping(address => PairInfo) public pairInfos;
    
    /// @dev Mapping to track if a token is supported
    mapping(address => bool) public supportedTokens;

    // ============ Events ============
    
    event TokenAdded(address indexed token, address indexed pair);
    event ObservationUpdated(address indexed token, uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative);
    event TWAPCalculated(address indexed token, uint256 twapPrice, uint256 period);

    // ============ Errors ============
    
    error TokenNotSupported();
    error PairNotFound();
    error InsufficientObservations();
    error InvalidPeriod();
    error ObservationTooOld();

    // ============ Constructor ============
    
    constructor(address _uniswapFactory, address _WETH) Ownable(msg.sender) {
        uniswapFactory = _uniswapFactory;
        WETH = _WETH;
    }

    // ============ External Functions ============
    
    /**
     * @dev Add a token to be tracked for TWAP calculation
     * @param token Address of the token to track
     */
    function addToken(address token) external onlyOwner {
        require(token != address(0), "TWAPOracle: zero address");
        require(!supportedTokens[token], "TWAPOracle: token already supported");

        // Get pair address from factory
        address pair = IUniswapV2Factory(uniswapFactory).getPair(token, WETH);
        if (pair == address(0)) {
            revert PairNotFound();
        }

        // Get token order in the pair
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        bool isToken0WETH = token0 == WETH;

        // Initialize pair info
        PairInfo storage pairInfo = pairInfos[token];
        pairInfo.pair = pair;
        pairInfo.token0 = token0;
        pairInfo.token1 = token1;
        pairInfo.isToken0WETH = isToken0WETH;
        pairInfo.observationIndex = 0;

        // Add initial observation
        _updateObservation(token);

        supportedTokens[token] = true;
        emit TokenAdded(token, pair);
    }

    /**
     * @dev Update price observation for a token
     * @param token Address of the token to update
     */
    function updateObservation(address token) external {
        if (!supportedTokens[token]) {
            revert TokenNotSupported();
        }
        _updateObservation(token);
    }

    /**
     * @dev Get TWAP price for a token over a specified period
     * @param token Address of the token
     * @param period Time period in seconds for TWAP calculation
     * @return twapPrice TWAP price in WETH terms (18 decimals)
     */
    function getTWAP(address token, uint256 period) external view returns (uint256 twapPrice) {
        if (!supportedTokens[token]) {
            revert TokenNotSupported();
        }
        
        if (period < MIN_PERIOD || period > MAX_PERIOD) {
            revert InvalidPeriod();
        }

        PairInfo storage pairInfo = pairInfos[token];
        
        if (pairInfo.observations.length < 2) {
            revert InsufficientObservations();
        }

        // Find the observation closest to the target time
        uint32 targetTime = uint32(block.timestamp - period);
        Observation memory oldObservation = _getObservationAt(pairInfo, targetTime);
        
        // Get current cumulative prices
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _getCurrentCumulativePrices(pairInfo.pair);
        
        // Calculate time elapsed
        uint32 timeElapsed = blockTimestamp - oldObservation.timestamp;
        
        if (timeElapsed == 0) {
            revert ObservationTooOld();
        }

        // Calculate TWAP
        if (pairInfo.isToken0WETH) {
            // Token is token1, WETH is token0
            // Price = (price1Cumulative_now - price1Cumulative_old) / timeElapsed
            twapPrice = (price1Cumulative - oldObservation.price1Cumulative) / timeElapsed;
        } else {
            // Token is token0, WETH is token1  
            // Price = (price0Cumulative_now - price0Cumulative_old) / timeElapsed
            twapPrice = (price0Cumulative - oldObservation.price0Cumulative) / timeElapsed;
        }

        // Convert from UQ112x112 to standard decimal format
        twapPrice = (twapPrice * 1e18) >> 112;
    }

    /**
     * @dev Get the latest observation for a token
     * @param token Address of the token
     * @return observation Latest observation
     */
    function getLatestObservation(address token) external view returns (Observation memory observation) {
        if (!supportedTokens[token]) {
            revert TokenNotSupported();
        }

        PairInfo storage pairInfo = pairInfos[token];
        if (pairInfo.observations.length == 0) {
            revert InsufficientObservations();
        }

        uint256 latestIndex = pairInfo.observations.length - 1;
        return pairInfo.observations[latestIndex];
    }

    /**
     * @dev Get all observations for a token
     * @param token Address of the token
     * @return observations Array of all observations
     */
    function getAllObservations(address token) external view returns (Observation[] memory observations) {
        if (!supportedTokens[token]) {
            revert TokenNotSupported();
        }

        return pairInfos[token].observations;
    }

    // ============ Internal Functions ============
    
    /**
     * @dev Update price observation for a token
     * @param token Address of the token
     */
    function _updateObservation(address token) internal {
        PairInfo storage pairInfo = pairInfos[token];
        
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _getCurrentCumulativePrices(pairInfo.pair);
        
        // Add new observation
        pairInfo.observations.push(Observation({
            timestamp: blockTimestamp,
            price0Cumulative: price0Cumulative,
            price1Cumulative: price1Cumulative
        }));

        emit ObservationUpdated(token, blockTimestamp, price0Cumulative, price1Cumulative);
    }

    /**
     * @dev Get current cumulative prices from a Uniswap pair
     * @param pair Address of the Uniswap pair
     * @return price0Cumulative Current cumulative price for token0
     * @return price1Cumulative Current cumulative price for token1
     * @return blockTimestamp Current block timestamp
     */
    function _getCurrentCumulativePrices(address pair) internal view returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = uint32(block.timestamp);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // If time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        
        if (blockTimestampLast != blockTimestamp && blockTimestamp > blockTimestampLast) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;

            // Only update if reserves are non-zero to avoid division by zero
            if (reserve0 > 0 && reserve1 > 0) {
                // Addition overflow is desired
                price0Cumulative += uint256(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
                price1Cumulative += uint256(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
            }
        }
    }

    /**
     * @dev Find observation closest to target time
     * @param pairInfo Pair information
     * @param targetTime Target timestamp
     * @return observation Closest observation
     */
    function _getObservationAt(PairInfo storage pairInfo, uint32 targetTime) internal view returns (Observation memory observation) {
        Observation[] storage observations = pairInfo.observations;
        uint256 length = observations.length;
        
        if (length == 0) {
            revert InsufficientObservations();
        }

        // Binary search for the closest observation
        uint256 left = 0;
        uint256 right = length - 1;
        
        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (observations[mid].timestamp <= targetTime) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        
        // Return the observation at or before the target time
        if (left > 0) {
            return observations[left - 1];
        } else {
            return observations[0];
        }
    }
}

/**
 * @title FixedPoint
 * @dev Library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
 */
library FixedPoint {
    // Range: [0, 2**112 - 1]
    // Resolution: 1 / 2**112
    struct uq112x112 {
        uint224 _x;
    }

    // Returns a UQ112x112 which represents the ratio of the numerator to the denominator
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112((uint224(numerator) << 112) / denominator);
    }
}
