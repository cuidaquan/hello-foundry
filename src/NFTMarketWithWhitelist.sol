// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title NFTMarketWithWhitelist
 * @dev NFT市场合约，支持EIP712白名单签名购买功能
 */
contract NFTMarketWithWhitelist is IERC721Receiver, ReentrancyGuard, Ownable, EIP712 {
    using ECDSA for bytes32;
    
    // 白名单签名结构
    struct WhitelistSignature {
        address buyer;
        uint256 listingId;
        uint256 deadline;
        uint256 nonce;
    }
    
    // 市场上架的NFT信息
    struct Listing {
        address seller;      // 卖家地址
        address nftContract; // NFT合约地址
        uint256 tokenId;     // NFT ID
        uint256 price;       // 价格（以ERC20代币计价）
        bool active;         // 是否活跃
        bool whitelistOnly;  // 是否仅限白名单购买
    }
    
    // 支持的ERC20代币合约
    IERC20 public paymentToken;
    
    // 上架列表 listingId => Listing
    mapping(uint256 => Listing) public listings;
    
    // NFT到上架ID的映射 nftContract => tokenId => listingId
    mapping(address => mapping(uint256 => uint256)) public nftToListing;
    
    // 白名单签名nonce跟踪
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    
    // 上架ID计数器
    uint256 private _listingIdCounter;
    
    // 市场手续费率 (基点，10000 = 100%)
    uint256 public marketFeeRate = 250; // 2.5%
    
    // 累计的市场手续费
    uint256 public accumulatedFees;
    
    // EIP712 类型哈希
    bytes32 private constant WHITELIST_TYPEHASH = keccak256(
        "WhitelistSignature(address buyer,uint256 listingId,uint256 deadline,uint256 nonce)"
    );
    
    // 事件
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price,
        bool whitelistOnly
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
    
    event WhitelistPurchase(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 nonce
    );
    
    /**
     * @dev 构造函数
     * @param _paymentToken 支付代币合约地址
     */
    constructor(address _paymentToken) 
        Ownable(msg.sender) 
        EIP712("NFTMarketWithWhitelist", "1") 
    {
        require(_paymentToken != address(0), "Invalid payment token address");
        paymentToken = IERC20(_paymentToken);
    }
    
    /**
     * @dev 上架NFT
     * @param nftContract NFT合约地址
     * @param tokenId NFT ID
     * @param price 价格（以ERC20代币计价）
     * @param whitelistOnly 是否仅限白名单购买
     */
    function list(
        address nftContract, 
        uint256 tokenId, 
        uint256 price, 
        bool whitelistOnly
    ) external nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "You don't own this NFT");
        require(IERC721(nftContract).getApproved(tokenId) == address(this) || 
                IERC721(nftContract).isApprovedForAll(msg.sender, address(this)), 
                "Market not approved to transfer NFT");
        require(nftToListing[nftContract][tokenId] == 0, "NFT already listed");
        
        uint256 listingId = ++_listingIdCounter;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true,
            whitelistOnly: whitelistOnly
        });
        
        nftToListing[nftContract][tokenId] = listingId;
        
        // 将NFT转移到市场合约
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        
        emit NFTListed(listingId, msg.sender, nftContract, tokenId, price, whitelistOnly);
    }
    
    /**
     * @dev 普通购买NFT（仅限非白名单商品）
     * @param listingId 上架ID
     */
    function buyNFT(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot buy your own NFT");
        require(!listing.whitelistOnly, "This NFT requires whitelist permission");
        
        _executePurchase(listingId, msg.sender);
    }
    
    /**
     * @dev 使用白名单签名购买NFT
     * @param listingId 上架ID
     * @param deadline 签名截止时间
     * @param nonce 防重放攻击的随机数
     * @param signature 项目方的白名单签名
     */
    function permitBuy(
        uint256 listingId,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Signature expired");
        require(!usedNonces[msg.sender][nonce], "Nonce already used");
        
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot buy your own NFT");
        require(listing.whitelistOnly, "This NFT does not require whitelist");
        
        // 验证白名单签名
        WhitelistSignature memory whitelistSig = WhitelistSignature({
            buyer: msg.sender,
            listingId: listingId,
            deadline: deadline,
            nonce: nonce
        });
        
        bytes32 structHash = keccak256(abi.encode(
            WHITELIST_TYPEHASH,
            whitelistSig.buyer,
            whitelistSig.listingId,
            whitelistSig.deadline,
            whitelistSig.nonce
        ));
        
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        require(signer == owner(), "Invalid whitelist signature");
        
        // 标记nonce为已使用
        usedNonces[msg.sender][nonce] = true;
        
        emit WhitelistPurchase(listingId, msg.sender, nonce);
        
        _executePurchase(listingId, msg.sender);
    }
    
    /**
     * @dev 执行购买逻辑
     * @param listingId 上架ID
     * @param buyer 买家地址
     */
    function _executePurchase(uint256 listingId, address buyer) internal {
        Listing storage listing = listings[listingId];
        
        uint256 totalPrice = listing.price;
        uint256 marketFee = (totalPrice * marketFeeRate) / 10000;
        uint256 sellerAmount = totalPrice - marketFee;
        
        require(paymentToken.balanceOf(buyer) >= totalPrice, "Insufficient token balance");
        require(paymentToken.allowance(buyer, address(this)) >= totalPrice, "Insufficient token allowance");
        
        // 转移代币
        require(paymentToken.transferFrom(buyer, listing.seller, sellerAmount), "Payment to seller failed");
        if (marketFee > 0) {
            require(paymentToken.transferFrom(buyer, address(this), marketFee), "Market fee payment failed");
            accumulatedFees += marketFee;
        }
        
        // 转移NFT
        IERC721(listing.nftContract).safeTransferFrom(address(this), buyer, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTSold(listingId, buyer, listing.seller, listing.nftContract, listing.tokenId, totalPrice);
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
        IERC721(listing.nftContract).safeTransferFrom(address(this), listing.seller, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTDelisted(listingId, listing.seller, listing.nftContract, listing.tokenId);
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
        marketFeeRate = newRate;
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

    /**
     * @dev 获取 EIP712 域分隔符
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
