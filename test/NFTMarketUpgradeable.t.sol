// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyNFTUpgradeable} from "../src/MyNFTUpgradeable.sol";
import {NFTMarketUpgradeableV1} from "../src/NFTMarketUpgradeableV1.sol";
import {NFTMarketUpgradeableV2} from "../src/NFTMarketUpgradeableV2.sol";
import {ExtendedERC20} from "../src/ExtendedERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract NFTMarketUpgradeableTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    ExtendedERC20 internal token;
    MyNFTUpgradeable internal nft;
    NFTMarketUpgradeableV1 internal marketV1;
    ERC1967Proxy internal marketProxy;
    ERC1967Proxy internal nftProxy;

    address internal owner;
    address internal seller;
    uint256 internal sellerPrivateKey;
    address internal buyer;
    address internal buyer2;

    function setUp() public {
        owner = address(this);
        sellerPrivateKey = 0x1234;
        seller = vm.addr(sellerPrivateKey);
        buyer = makeAddr("buyer");
        buyer2 = makeAddr("buyer2");

        // 部署支付代币
        token = new ExtendedERC20("PAY", "PAY", 0);

        // 部署可升级的 NFT 合约
        MyNFTUpgradeable nftImpl = new MyNFTUpgradeable();
        bytes memory nftInitData = abi.encodeCall(MyNFTUpgradeable.initialize, ());
        nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        nft = MyNFTUpgradeable(address(nftProxy));

        // 部署可升级的 NFT Market V1
        NFTMarketUpgradeableV1 marketImpl = new NFTMarketUpgradeableV1();
        bytes memory marketInitData =
            abi.encodeCall(NFTMarketUpgradeableV1.initialize, (address(token), address(nft)));
        marketProxy = new ERC1967Proxy(address(marketImpl), marketInitData);
        marketV1 = NFTMarketUpgradeableV1(address(marketProxy));

        // 给买家发代币
        token.mint(buyer, 1_000_000 ether);
        token.mint(buyer2, 1_000_000 ether);

        // 给卖家铸造一个NFT并授权市场
        uint256 tokenId = nft.mint(seller, "ipfs://token-0");
        vm.prank(seller);
        nft.approve(address(marketV1), tokenId);
    }

    // ============ V1 基础功能测试 ============

    function test_V1_List_Success() public {
        uint256 tokenId = 0;
        uint96 price = 100 ether;

        vm.prank(seller);
        marketV1.list(tokenId, price);

        NFTMarketUpgradeableV1.Listing memory listing = marketV1.getListing(1);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(nft));
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, price);
        assertTrue(listing.active);
        assertEq(nft.ownerOf(tokenId), address(marketV1));
    }

    function test_V1_Buy_Success() public {
        uint256 tokenId = 0;
        uint96 price = 100 ether;

        vm.prank(seller);
        marketV1.list(tokenId, price);

        vm.prank(buyer);
        token.approve(address(marketV1), type(uint256).max);

        uint256 sellerBalanceBefore = token.balanceOf(seller);
        uint256 buyerBalanceBefore = token.balanceOf(buyer);

        vm.prank(buyer);
        marketV1.buyNFT(1);

        assertEq(nft.ownerOf(tokenId), buyer);

        uint256 fee = (price * marketV1.marketFeeRate()) / 10000;
        assertEq(token.balanceOf(seller), sellerBalanceBefore + price - fee);
        assertEq(token.balanceOf(buyer), buyerBalanceBefore - price);
        assertEq(token.balanceOf(address(marketV1)), fee);
    }

    function test_V1_Delist_Success() public {
        uint256 tokenId = 0;
        uint96 price = 100 ether;

        vm.prank(seller);
        marketV1.list(tokenId, price);

        vm.prank(seller);
        marketV1.delist(1);

        assertEq(nft.ownerOf(tokenId), seller);
        NFTMarketUpgradeableV1.Listing memory listing = marketV1.getListing(1);
        assertFalse(listing.active);
    }

    // ============ 升级测试 ============

    function test_Upgrade_StatePreserved() public {
        // V1: 上架一个 NFT
        uint256 tokenId = 0;
        uint96 price = 100 ether;

        vm.prank(seller);
        marketV1.list(tokenId, price);

        // 记录升级前的状态
        uint256 listingIdBefore = marketV1.getCurrentListingId();
        NFTMarketUpgradeableV1.Listing memory listingBefore = marketV1.getListing(1);
        uint256 marketFeeRateBefore = marketV1.marketFeeRate();
        uint256 accumulatedFeesBefore = marketV1.accumulatedFees();
        address ownerBefore = marketV1.owner();

        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        // 转换为 V2 接口
        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        // 验证状态保持一致
        assertEq(marketV2.getCurrentListingId(), listingIdBefore, "Listing ID should be preserved");
        assertEq(marketV2.marketFeeRate(), marketFeeRateBefore, "Market fee rate should be preserved");
        assertEq(marketV2.accumulatedFees(), accumulatedFeesBefore, "Accumulated fees should be preserved");
        assertEq(marketV2.owner(), ownerBefore, "Owner should be preserved");

        NFTMarketUpgradeableV2.Listing memory listingAfter = marketV2.getListing(1);
        assertEq(listingAfter.seller, listingBefore.seller, "Listing seller should be preserved");
        assertEq(listingAfter.nftContract, listingBefore.nftContract, "Listing nftContract should be preserved");
        assertEq(listingAfter.tokenId, listingBefore.tokenId, "Listing tokenId should be preserved");
        assertEq(listingAfter.price, listingBefore.price, "Listing price should be preserved");
        assertEq(listingAfter.active, listingBefore.active, "Listing active status should be preserved");

        // 验证 V1 功能仍然可用
        vm.prank(buyer);
        token.approve(address(marketV2), type(uint256).max);

        vm.prank(buyer);
        marketV2.buyNFT(1);

        assertEq(nft.ownerOf(tokenId), buyer, "NFT should be transferred to buyer after upgrade");
    }

    function test_Upgrade_NewFunctionality() public {
        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        // 测试 V2 的新功能：离线签名上架
        uint256 tokenId = nft.mint(seller, "ipfs://token-1");

        // 卖家授权市场（使用 setApprovalForAll）
        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        // 创建签名
        uint96 price = 200 ether;
        uint256 nonce = marketV2.getSignatureNonce(seller, tokenId);
        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, price, nonce));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 任何人都可以调用 listWithSignature 来上架
        marketV2.listWithSignature(tokenId, price, nonce, signature);

        uint256 listingId = marketV2.getCurrentListingId();
        NFTMarketUpgradeableV2.Listing memory listing = marketV2.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, price);
        assertTrue(listing.active);
        assertEq(nft.ownerOf(tokenId), address(marketV2));

        // 验证 nonce 已更新
        assertEq(marketV2.getSignatureNonce(seller, tokenId), nonce + 1);
    }

    function test_V2_SignatureListing_InvalidSignature() public {
        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        uint256 tokenId = nft.mint(seller, "ipfs://token-1");

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint96 price = 200 ether;
        uint256 nonce = marketV2.getSignatureNonce(seller, tokenId);

        // 使用错误的私钥签名
        uint256 wrongPrivateKey = 0x5678;
        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, price, nonce));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(bytes("Invalid signature"));
        marketV2.listWithSignature(tokenId, price, nonce, signature);
    }

    function test_V2_SignatureListing_InvalidNonce() public {
        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        uint256 tokenId = nft.mint(seller, "ipfs://token-1");

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint96 price = 200 ether;
        uint256 wrongNonce = 999; // 错误的 nonce

        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, price, wrongNonce));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(bytes("Invalid nonce"));
        marketV2.listWithSignature(tokenId, price, wrongNonce, signature);
    }

    function test_V2_SignatureListing_ReplayAttackPrevention() public {
        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        uint256 tokenId = nft.mint(seller, "ipfs://token-1");

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint96 price = 200 ether;
        uint256 nonce = marketV2.getSignatureNonce(seller, tokenId);
        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, price, nonce));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 第一次上架成功
        marketV2.listWithSignature(tokenId, price, nonce, signature);

        // 验证 nonce 已更新
        uint256 updatedNonce = marketV2.getSignatureNonce(seller, tokenId);
        assertEq(updatedNonce, nonce + 1);

        // 下架 NFT，让 seller 重新拥有 NFT
        uint256 listingId = marketV2.getCurrentListingId();
        vm.prank(seller);
        marketV2.delist(listingId);

        // 确认 NFT 已经回到 seller
        assertEq(nft.ownerOf(tokenId), seller);

        // 尝试使用相同的签名再次上架（应该失败，因为 nonce 已经更新）
        vm.expectRevert(bytes("Invalid nonce"));
        marketV2.listWithSignature(tokenId, price, nonce, signature);
    }

    function test_V2_MultipleSignatureListings() public {
        // 升级到 V2
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        marketV1.upgradeToAndCall(address(marketImplV2), "");

        NFTMarketUpgradeableV2 marketV2 = NFTMarketUpgradeableV2(address(marketProxy));

        // 给卖家授权市场
        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        // 铸造多个 NFT 并用签名上架
        for (uint256 i = 1; i <= 3; i++) {
            uint256 tokenId = nft.mint(seller, string(abi.encodePacked("ipfs://token-", i)));
            uint96 price = uint96(100 ether * i);
            uint256 nonce = marketV2.getSignatureNonce(seller, tokenId);

            bytes32 messageHash = keccak256(abi.encodePacked(tokenId, price, nonce));
            bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, ethSignedMessageHash);
            bytes memory signature = abi.encodePacked(r, s, v);

            marketV2.listWithSignature(tokenId, price, nonce, signature);

            uint256 currentListingId = marketV2.getCurrentListingId();
            NFTMarketUpgradeableV2.Listing memory listing = marketV2.getListing(currentListingId);
            assertEq(listing.tokenId, tokenId);
            assertEq(listing.price, price);
            assertTrue(listing.active);
        }
    }

    function test_Upgrade_OnlyOwner() public {
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();

        // 非 owner 尝试升级应该失败
        vm.prank(buyer);
        vm.expectRevert();
        marketV1.upgradeToAndCall(address(marketImplV2), "");
    }

    function test_V1_WithdrawFees() public {
        uint256 tokenId = 0;
        uint96 price = 100 ether;

        vm.prank(seller);
        marketV1.list(tokenId, price);

        vm.prank(buyer);
        token.approve(address(marketV1), type(uint256).max);
        vm.prank(buyer);
        marketV1.buyNFT(1);

        uint256 fees = marketV1.accumulatedFees();
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        marketV1.withdrawFees();

        assertEq(token.balanceOf(owner), ownerBalanceBefore + fees);
        assertEq(marketV1.accumulatedFees(), 0);
        assertEq(token.balanceOf(address(marketV1)), 0);
    }

    function test_V1_SetMarketFeeRate() public {
        uint16 newRate = 500; // 5%
        marketV1.setMarketFeeRate(newRate);
        assertEq(marketV1.marketFeeRate(), newRate);
    }

    function test_V1_SetMarketFeeRate_OnlyOwner() public {
        vm.prank(buyer);
        vm.expectRevert();
        marketV1.setMarketFeeRate(500);
    }
}
