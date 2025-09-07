// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title AirdropMerkleNFTMarket
 * @dev NFT市场合约，支持白名单用户通过Merkle树验证享受50%折扣，使用permit授权和multicall
 */
contract AirdropMerkleNFTMarket is IERC721Receiver, ReentrancyGuard, Ownable {
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }
    
    // 合约状态变量
    IERC20 public paymentToken;
    IERC20Permit public permitToken;
    IERC721 public nftContract;
    bytes32 public merkleRoot;
    
    // 存储
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => uint256)) public nftToListing;
    mapping(address => bool) public hasClaimedDiscount;
    uint256 private _listingIdCounter;
    
    // 手续费相关
    uint256 public constant DISCOUNT_RATE = 5000; // 50% 折扣 (10000 = 100%)
    uint256 public marketFeeRate = 250; // 2.5%
    uint256 public accumulatedFees;
    
    // 事件
    event NFTListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
    event NFTSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price, bool discounted);
    event MerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    
    constructor(
        address _paymentToken,
        address _nftContract,
        bytes32 _merkleRoot
    ) Ownable(msg.sender) {
        require(_paymentToken != address(0), "Invalid payment token");
        require(_nftContract != address(0), "Invalid NFT contract");
        
        paymentToken = IERC20(_paymentToken);
        permitToken = IERC20Permit(_paymentToken);
        nftContract = IERC721(_nftContract);
        merkleRoot = _merkleRoot;
    }
    
    /**
     * @dev 上架NFT
     */
    function list(uint256 tokenId, uint256 price) external nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(nftContract.getApproved(tokenId) == address(this) || 
                nftContract.isApprovedForAll(msg.sender, address(this)), 
                "Market not approved");
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
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);
        
        emit NFTListed(listingId, msg.sender, address(nftContract), tokenId, price);
    }
    
    /**
     * @dev Permit预支付函数 - 用于multicall
     */
    function permitPrePay(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        permitToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
    }
    
    /**
     * @dev 通过Merkle树验证白名单并购买NFT - 用于multicall
     */
    function claimNFT(
        uint256 listingId,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot buy own NFT");
        
        // 验证Merkle证明
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");
        require(!hasClaimedDiscount[msg.sender], "Discount already claimed");
        
        // 计算折扣价格
        uint256 originalPrice = listing.price;
        uint256 discountedPrice = (originalPrice * DISCOUNT_RATE) / 10000;
        uint256 marketFee = (discountedPrice * marketFeeRate) / 10000;
        uint256 sellerAmount = discountedPrice - marketFee;
        
        // 检查授权和余额
        require(paymentToken.balanceOf(msg.sender) >= discountedPrice, "Insufficient balance");
        require(paymentToken.allowance(msg.sender, address(this)) >= discountedPrice, "Insufficient allowance");
        
        // 标记已使用折扣
        hasClaimedDiscount[msg.sender] = true;
        
        // 转账
        require(paymentToken.transferFrom(msg.sender, listing.seller, sellerAmount), "Payment failed");
        if (marketFee > 0) {
            require(paymentToken.transferFrom(msg.sender, address(this), marketFee), "Fee payment failed");
            accumulatedFees += marketFee;
        }
        
        // 转移NFT
        nftContract.safeTransferFrom(address(this), msg.sender, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTSold(listingId, msg.sender, listing.seller, discountedPrice, true);
    }
    
    /**
     * @dev Multicall功能 - 使用delegatecall执行多个函数调用
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall: call failed");
            results[i] = result;
        }
        return results;
    }
    
    /**
     * @dev 普通购买NFT（无折扣）
     */
    function buyNFT(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot buy own NFT");
        
        uint256 totalPrice = listing.price;
        uint256 marketFee = (totalPrice * marketFeeRate) / 10000;
        uint256 sellerAmount = totalPrice - marketFee;
        
        require(paymentToken.balanceOf(msg.sender) >= totalPrice, "Insufficient balance");
        require(paymentToken.allowance(msg.sender, address(this)) >= totalPrice, "Insufficient allowance");
        
        // 转账
        require(paymentToken.transferFrom(msg.sender, listing.seller, sellerAmount), "Payment failed");
        if (marketFee > 0) {
            require(paymentToken.transferFrom(msg.sender, address(this), marketFee), "Fee payment failed");
            accumulatedFees += marketFee;
        }
        
        // 转移NFT
        nftContract.safeTransferFrom(address(this), msg.sender, listing.tokenId);
        
        // 更新状态
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
        
        emit NFTSold(listingId, msg.sender, listing.seller, totalPrice, false);
    }
    
    /**
     * @dev 下架NFT
     */
    function delist(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Only seller can delist");
        
        nftContract.safeTransferFrom(address(this), msg.sender, listing.tokenId);
        
        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];
    }
    
    /**
     * @dev 更新Merkle根 - 仅owner
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(oldRoot, _merkleRoot);
    }
    
    /**
     * @dev 提取手续费 - 仅owner
     */
    function withdrawFees() external onlyOwner {
        uint256 fees = accumulatedFees;
        require(fees > 0, "No fees to withdraw");
        
        accumulatedFees = 0;
        require(paymentToken.transfer(owner(), fees), "Fee withdrawal failed");
    }
    
    /**
     * @dev 重置用户的折扣使用状态 - 仅owner（用于新一轮airdrop）
     */
    function resetDiscountClaimed(address user) external onlyOwner {
        hasClaimedDiscount[user] = false;
    }
    
    /**
     * @dev 批量重置折扣状态
     */
    function batchResetDiscountClaimed(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            hasClaimedDiscount[users[i]] = false;
        }
    }
    
    /**
     * @dev 验证用户是否在白名单中
     */
    function verifyWhitelist(address user, bytes32[] calldata merkleProof) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }
    
    /**
     * @dev 获取折扣后价格
     */
    function getDiscountedPrice(uint256 listingId) external view returns (uint256) {
        require(listings[listingId].active, "Listing not active");
        return (listings[listingId].price * DISCOUNT_RATE) / 10000;
    }
    
    /**
     * @dev ERC721接收器
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    /**
     * @dev 获取当前listing计数
     */
    function getCurrentListingId() external view returns (uint256) {
        return _listingIdCounter;
    }
}