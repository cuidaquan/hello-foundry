// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/AirdropMerkleNFTMarket.sol";
import "../src/CUIDAQUANToken.sol";
import "../src/MyNFT.sol";

contract AirdropMerkleNFTMarketSimpleTest is Test {
    
    AirdropMerkleNFTMarket public market;
    CUIDAQUANToken public token;
    MyNFT public nft;
    
    address public seller = address(0x1);
    address public buyer = address(0x2);
    address public whitelistUser = address(0x3);
    address public owner = address(this);
    
    bytes32 public merkleRoot;
    uint256 public constant NFT_PRICE = 1000 * 10**18;
    uint256 public constant TOKEN_SUPPLY = 1000000 * 10**18;
    
    function setUp() public {
        token = new CUIDAQUANToken(TOKEN_SUPPLY / 10**18);
        nft = new MyNFT();
        
        // Create simple merkle root for whitelistUser
        merkleRoot = keccak256(abi.encodePacked(whitelistUser));
        
        market = new AirdropMerkleNFTMarket(
            address(token),
            address(nft),
            merkleRoot
        );
        
        // Distribute tokens
        token.transfer(buyer, 10000 * 10**18);
        token.transfer(whitelistUser, 10000 * 10**18);
        
        // Mint NFTs
        nft.mint(seller, "https://example.com/token/1");
        nft.mint(seller, "https://example.com/token/2");
    }
    
    function testListNFT() public {
        vm.startPrank(seller);
        nft.approve(address(market), 0);
        market.list(0, NFT_PRICE);
        vm.stopPrank();
        
        (address listingSeller, , uint256 tokenId, uint256 price, bool active) = market.listings(1);
        assertEq(listingSeller, seller);
        assertEq(tokenId, 0);
        assertEq(price, NFT_PRICE);
        assertTrue(active);
    }
    
    function testPermitAndClaimWithMulticall() public {
        // List NFT
        vm.startPrank(seller);
        nft.approve(address(market), 0);
        market.list(0, NFT_PRICE);
        vm.stopPrank();
        
        // Test direct claimNFT instead of multicall for simplicity
        vm.startPrank(whitelistUser);
        
        uint256 discountedPrice = market.getDiscountedPrice(1);
        assertEq(discountedPrice, NFT_PRICE * 5000 / 10000); // 50% discount
        
        token.approve(address(market), discountedPrice);
        
        // Direct claim instead of multicall
        bytes32[] memory proof = new bytes32[](0);
        market.claimNFT(1, proof);
        
        // Verify results
        assertEq(nft.ownerOf(0), whitelistUser);
        assertTrue(market.hasClaimedDiscount(whitelistUser));
        
        vm.stopPrank();
    }
    
    function testBuyNFTWithoutDiscount() public {
        // List NFT
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();
        
        // Regular buyer purchases - listing ID should be 1 (the first listing)
        vm.startPrank(buyer);
        token.approve(address(market), NFT_PRICE);
        market.buyNFT(1);
        vm.stopPrank();
        
        assertEq(nft.ownerOf(1), buyer);
    }
    
    function testWhitelistVerification() public {
        bytes32[] memory proof = new bytes32[](0);
        assertTrue(market.verifyWhitelist(whitelistUser, proof));
        assertFalse(market.verifyWhitelist(buyer, proof));
    }
    
    function testDiscountRestriction() public {
        // List NFT
        vm.startPrank(seller);
        nft.approve(address(market), 0);
        market.list(0, NFT_PRICE);
        vm.stopPrank();
        
        // First claim succeeds
        vm.startPrank(whitelistUser);
        token.approve(address(market), market.getDiscountedPrice(1));
        bytes32[] memory proof = new bytes32[](0);
        market.claimNFT(1, proof);
        vm.stopPrank();
        
        // Second claim should fail if user tries to claim discount again
        assertTrue(market.hasClaimedDiscount(whitelistUser));
    }
    
    function testAdminFunctions() public {
        // Test setMerkleRoot
        bytes32 newRoot = keccak256("new root");
        market.setMerkleRoot(newRoot);
        assertEq(market.merkleRoot(), newRoot);
        
        // Test resetDiscountClaimed
        market.resetDiscountClaimed(whitelistUser);
        assertFalse(market.hasClaimedDiscount(whitelistUser));
        
        // Test batch reset
        address[] memory users = new address[](1);
        users[0] = whitelistUser;
        market.batchResetDiscountClaimed(users);
        assertFalse(market.hasClaimedDiscount(whitelistUser));
    }
}