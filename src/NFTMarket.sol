// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./ExtendedERC20.sol";
import "./MyNFT.sol";

/**
 * @title NFTMarket
 * @dev NFT市场合约，支持使用ERC20代币买卖NFT
 */
contract NFTMarket is IERC721Receiver, ITokenReceiver, ReentrancyGuard, Ownable {
    
    // 市场上架的NFT信息
    struct Listing {
        address seller;      // 卖家地址
        address nftContract; // NFT合约地址
        uint256 tokenId;     // NFT ID
        uint256 price;       // 价格（以ERC20代币计价）
        bool active;         // 是否活跃
    }
    
    // 支持的ERC20代币合约
    ExtendedERC20 public paymentToken;
    
    // NFT合约地址
    MyNFT public nftContract;
    
    // 上架列表 listingId => Listing
    mapping(uint256 => Listing) public listings;
    
    // NFT到上架ID的映射 nftContract => tokenId => listingId
    mapping(address => mapping(uint256 => uint256)) public nftToListing;
    
    // 上架ID计数器
    uint256 private _listingIdCounter;
    
    // 市场手续费率 (基点，10000 = 100%)
    uint256 public marketFeeRate = 250; // 2.5%
    
    // 累计的市场手续费
    uint256 public accumulatedFees;
    
    // 事件
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event NFTDelisted(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId
    );
    
    event MarketFeeRateUpdated(uint256 oldRate, uint256 newRate);
    
    /**
     * @dev 构造函数
     * @param _paymentToken 支付代币合约地址
     * @param _nftContract NFT合约地址
     */
    constructor(address _paymentToken, address _nftContract) Ownable(msg.sender) {
        require(_paymentToken != address(0), "Invalid payment token address");
        require(_nftContract != address(0), "Invalid NFT contract address");

        paymentToken = ExtendedERC20(_paymentToken);
        nftContract = MyNFT(_nftContract);
    }
    
    /**
     * @dev 上架NFT
     * @param tokenId NFT ID
     * @param price 价格（以ERC20代币计价）
     */
    function list(uint256 tokenId, uint256 price) external nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(nftContract.ownerOf(tokenId) == msg.sender, "You don't own this NFT");
        require(nftContract.getApproved(tokenId) == address(this) || 
                nftContract.isApprovedForAll(msg.sender, address(this)), 
                "Market not approved to transfer NFT");
        require(nftToListing[address(nftContract)][tokenId] == 0, "NFT already listed");
        
        uint256 listingId = ++_listingIdCounter;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: address(nftContract),
            tokenId: tokenId,
            price: price,
            active: true
        });
        
        nftToListing[address(nftContract)][tokenId] = listingId;
        
        // 将NFT转移到市场合约
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);
        
        emit NFTListed(listingId, msg.sender, address(nftContract), tokenId, price);
    }
    
    /**
     * @dev 购买NFT
     * @param listingId 上架ID
     */
    function buyNFT(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot buy your own NFT");
        
        uint256 totalPrice = listing.price;
        uint256 marketFee = (totalPrice * marketFeeRate) / 10000;
        uint256 sellerAmount = totalPrice - marketFee;
        
        require(paymentToken.balanceOf(msg.sender) >= totalPrice, "Insufficient token balance");
        require(paymentToken.allowance(msg.sender, address(this)) >= totalPrice, "Insufficient token allowance");
        
        // 转移代币
        require(paymentToken.transferFrom(msg.sender, listing.seller, sellerAmount), "Payment to seller failed");
        if (marketFee > 0) {
            require(paymentToken.transferFrom(msg.sender, address(this), marketFee), "Market fee payment failed");
            accumulatedFees += marketFee;
        }
        
        // 转移NFT
        nftContract.safeTransferFrom(address(this), msg.sender, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTSold(listingId, msg.sender, listing.seller, listing.nftContract, listing.tokenId, totalPrice);
    }
    
    /**
     * @dev 下架NFT
     * @param listingId 上架ID
     */
    function delist(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Only seller can delist");
        
        // 将NFT返还给卖家
        nftContract.safeTransferFrom(address(this), listing.seller, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTDelisted(listingId, listing.seller, listing.nftContract, listing.tokenId);
    }
    
    /**
     * @dev 实现tokensReceived接口，支持通过transferWithCallback购买NFT
     * @param from 发送者地址
     * @param amount 代币数量
     * @param data 附加数据，应包含listingId
     */
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(msg.sender == address(paymentToken), "Only payment token can call this");
        require(data.length >= 32, "Invalid data: missing listingId");
        
        // 从data中解析listingId
        uint256 listingId = abi.decode(data, (uint256));
        
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != from, "Cannot buy your own NFT");
        require(amount >= listing.price, "Insufficient payment amount");
        
        uint256 totalPrice = listing.price;
        uint256 marketFee = (totalPrice * marketFeeRate) / 10000;
        uint256 sellerAmount = totalPrice - marketFee;
        
        // 转移代币给卖家
        require(paymentToken.transfer(listing.seller, sellerAmount), "Payment to seller failed");
        
        // 处理市场手续费
        if (marketFee > 0) {
            accumulatedFees += marketFee;
        }
        
        // 如果支付金额超过价格，退还多余部分
        if (amount > totalPrice) {
            uint256 refund = amount - totalPrice;
            require(paymentToken.transfer(from, refund), "Refund failed");
        }
        
        // 转移NFT
        nftContract.safeTransferFrom(address(this), from, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTSold(listingId, from, listing.seller, listing.nftContract, listing.tokenId, totalPrice);
        
        return true;
    }
    
    /**
     * @dev 实现IERC721Receiver接口
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    /**
     * @dev 设置市场手续费率 - 只有合约拥有者可以调用
     * @param newRate 新的手续费率（基点）
     */
    function setMarketFeeRate(uint256 newRate) external onlyOwner {
        require(newRate <= 1000, "Fee rate cannot exceed 10%"); // 最大10%
        uint256 oldRate = marketFeeRate;
        marketFeeRate = newRate;
        emit MarketFeeRateUpdated(oldRate, newRate);
    }
    
    /**
     * @dev 提取累计的市场手续费 - 只有合约拥有者可以调用
     */
    function withdrawFees() external onlyOwner {
        uint256 fees = accumulatedFees;
        require(fees > 0, "No fees to withdraw");
        
        accumulatedFees = 0;
        require(paymentToken.transfer(owner(), fees), "Fee withdrawal failed");
    }
    
    /**
     * @dev 获取上架信息
     * @param listingId 上架ID
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @dev 获取当前上架ID计数器
     */
    function getCurrentListingId() external view returns (uint256) {
        return _listingIdCounter;
    }
}
