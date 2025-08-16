// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {CUIDAQUANToken} from "src/CUIDAQUANToken.sol";
import {TokenBankWithPermit} from "src/TokenBankWithPermit.sol";
import {NFTMarketWithWhitelist} from "src/NFTMarketWithWhitelist.sol";
import {CUIDAQUANNFT} from "src/CUIDAQUANNFT.sol";

contract CUIDAQUANIntegrationTest is Test {
    CUIDAQUANToken internal token;
    TokenBankWithPermit internal bank;
    NFTMarketWithWhitelist internal market;
    CUIDAQUANNFT internal nft;

    uint256 internal ownerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 internal user1PrivateKey = 0x2345678901234567890123456789012345678901234567890123456789012345;
    uint256 internal user2PrivateKey = 0x3456789012345678901234567890123456789012345678901234567890123456;
    uint256 internal sellerPrivateKey = 0x4567890123456789012345678901234567890123456789012345678901234567;

    address internal owner = vm.addr(ownerPrivateKey);
    address internal user1 = vm.addr(user1PrivateKey);
    address internal user2 = vm.addr(user2PrivateKey);
    address internal seller = vm.addr(sellerPrivateKey);

    function setUp() public {
        // 设置测试账户
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(seller, 100 ether);

        // 部署合约
        vm.startPrank(owner);
        
        // 部署 CUIDAQUAN Token (初始供应量 1000万)
        token = new CUIDAQUANToken(10_000_000);
        
        // 部署 TokenBank
        bank = new TokenBankWithPermit(address(token));
        
        // 部署 NFT 合约
        nft = new CUIDAQUANNFT();
        
        // 部署 NFT 市场
        market = new NFTMarketWithWhitelist(address(token));
        
        vm.stopPrank();

        // 给用户分发代币
        vm.startPrank(owner);
        token.transfer(user1, 1000 * 10**18);
        token.transfer(user2, 1000 * 10**18);
        token.transfer(seller, 1000 * 10**18);
        vm.stopPrank();

        // 给卖家铸造NFT
        vm.startPrank(owner);
        nft.mint(seller, "https://example.com/nft/1");
        nft.mint(seller, "https://example.com/nft/2");
        vm.stopPrank();
    }

    // ============ Token Permit 存款测试 ============
    
    function test_PermitDeposit_Success() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // 生成 permit 签名
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            user1,
            address(bank),
            depositAmount,
            token.nonces(user1),
            deadline
        ));
        
        bytes32 hash = keccak256(abi.encodePacked(
            "\x19\x01",
            token.DOMAIN_SEPARATOR(),
            structHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, hash);
        
        // 记录存款前余额
        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 bankBalanceBefore = bank.getBalance(user1);
        
        // 执行 permit 存款
        vm.prank(user1);
        bank.permitDeposit(depositAmount, deadline, v, r, s);
        
        // 验证结果
        assertEq(token.balanceOf(user1), userBalanceBefore - depositAmount, "User token balance should decrease");
        assertEq(bank.getBalance(user1), bankBalanceBefore + depositAmount, "Bank balance should increase");
        assertEq(token.balanceOf(address(bank)), depositAmount, "Bank contract should hold tokens");
        
        console.log("Permit deposit successful:");
        console.log("  - User deposited:", depositAmount / 10**18, "CUIDAQUAN tokens");
        console.log("  - Bank balance:", bank.getBalance(user1) / 10**18, "CUIDAQUAN tokens");
    }

    function test_TraditionalDeposit_Success() public {
        uint256 depositAmount = 50 * 10**18;
        
        // 传统方式：先 approve 再 deposit
        vm.startPrank(user2);
        token.approve(address(bank), depositAmount);
        bank.deposit(depositAmount);
        vm.stopPrank();
        
        // 验证结果
        assertEq(bank.getBalance(user2), depositAmount, "Traditional deposit should work");
        
        console.log("Traditional deposit successful:");
        console.log("  - User deposited:", depositAmount / 10**18, "CUIDAQUAN tokens");
    }

    // ============ NFT 白名单购买测试 ============
    
    function test_WhitelistNFTPurchase_Success() public {
        uint256 tokenId = 0;
        uint256 price = 200 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 12345;
        
        // 卖家上架NFT（仅限白名单）
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price, true); // whitelistOnly = true
        vm.stopPrank();
        
        uint256 listingId = market.getCurrentListingId();
        
        // 买家准备购买资金
        vm.startPrank(user1);
        token.approve(address(market), price);
        vm.stopPrank();
        
        // 项目方（owner）为买家生成白名单签名
        bytes32 structHash = keccak256(abi.encode(
            keccak256("WhitelistSignature(address buyer,uint256 listingId,uint256 deadline,uint256 nonce)"),
            user1,
            listingId,
            deadline,
            nonce
        ));
        
        bytes32 hash = keccak256(abi.encodePacked(
            "\x19\x01",
            market.DOMAIN_SEPARATOR(),
            structHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 记录购买前余额
        uint256 buyerTokensBefore = token.balanceOf(user1);
        uint256 sellerTokensBefore = token.balanceOf(seller);
        address nftOwnerBefore = nft.ownerOf(tokenId);
        
        // 执行白名单购买
        vm.prank(user1);
        market.permitBuy(listingId, deadline, nonce, signature);
        
        // 验证结果
        assertEq(nft.ownerOf(tokenId), user1, "NFT should be transferred to buyer");
        assertEq(nftOwnerBefore, address(market), "NFT was held by market before purchase");
        
        // 验证代币转移（考虑市场手续费）
        uint256 marketFee = (price * market.marketFeeRate()) / 10000;
        uint256 sellerAmount = price - marketFee;
        
        assertEq(token.balanceOf(user1), buyerTokensBefore - price, "Buyer should pay full price");
        assertEq(token.balanceOf(seller), sellerTokensBefore + sellerAmount, "Seller should receive amount minus fee");
        assertEq(market.accumulatedFees(), marketFee, "Market should accumulate fees");
        
        console.log("Whitelist NFT purchase successful:");
        console.log("  - NFT transferred from seller to buyer");
        console.log("  - Price paid:", price / 10**18, "CUIDAQUAN tokens");
        console.log("  - Market fee:", marketFee / 10**18, "CUIDAQUAN tokens");
        console.log("  - Seller received:", sellerAmount / 10**18, "CUIDAQUAN tokens");
    }

    function test_RegularNFTPurchase_Success() public {
        uint256 tokenId = 1;
        uint256 price = 150 * 10**18;
        
        // 卖家上架NFT（非白名单）
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price, false); // whitelistOnly = false
        vm.stopPrank();
        
        uint256 listingId = market.getCurrentListingId();
        
        // 买家购买
        vm.startPrank(user2);
        token.approve(address(market), price);
        market.buyNFT(listingId);
        vm.stopPrank();
        
        // 验证结果
        assertEq(nft.ownerOf(tokenId), user2, "NFT should be transferred to buyer");
        
        console.log("Regular NFT purchase successful:");
        console.log("  - NFT transferred to buyer without whitelist requirement");
    }

    function test_WhitelistRequired_ShouldRevert() public {
        uint256 tokenId = 0;
        uint256 price = 200 * 10**18;
        
        // 卖家上架NFT（仅限白名单）
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price, true); // whitelistOnly = true
        vm.stopPrank();
        
        uint256 listingId = market.getCurrentListingId();
        
        // 买家尝试普通购买（应该失败）
        vm.startPrank(user1);
        token.approve(address(market), price);
        
        vm.expectRevert("This NFT requires whitelist permission");
        market.buyNFT(listingId);
        vm.stopPrank();
        
        console.log("Whitelist requirement enforced correctly");
    }

    // ============ 综合流程测试 ============
    
    function test_CompleteWorkflow() public {
        console.log("Starting complete workflow test...");

        // 1. 用户使用 permit 存款到银行
        _testPermitDeposit();

        // 2. 用户从银行提取部分资金用于购买NFT
        uint256 withdrawAmount = 250 * 10**18;
        vm.prank(user1);
        bank.withdraw(withdrawAmount);
        console.log("  Step 2: User withdrew tokens from bank");

        // 3. 卖家上架白名单NFT
        uint256 tokenId = 0;
        uint256 price = 200 * 10**18;

        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price, true);
        vm.stopPrank();
        console.log("  Step 3: Seller listed NFT with whitelist requirement");

        // 4. 用户使用白名单签名购买NFT
        _testWhitelistPurchase(tokenId, price);

        // 验证最终状态
        assertEq(nft.ownerOf(tokenId), user1, "User should own the NFT");
        console.log("Complete workflow test passed!");
    }

    function _testPermitDeposit() internal {
        uint256 depositAmount = 300 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = keccak256(abi.encodePacked(
            "\x19\x01",
            token.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user1,
                address(bank),
                depositAmount,
                token.nonces(user1),
                deadline
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, permitHash);

        vm.prank(user1);
        bank.permitDeposit(depositAmount, deadline, v, r, s);
        console.log("  Step 1: User deposited tokens using permit");
    }

    function _testWhitelistPurchase(uint256 tokenId, uint256 price) internal {
        uint256 listingId = market.getCurrentListingId();
        uint256 nonce = 54321;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 whitelistHash = keccak256(abi.encodePacked(
            "\x19\x01",
            market.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                keccak256("WhitelistSignature(address buyer,uint256 listingId,uint256 deadline,uint256 nonce)"),
                user1,
                listingId,
                deadline,
                nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, whitelistHash);
        bytes memory whitelistSig = abi.encodePacked(r, s, v);

        vm.startPrank(user1);
        token.approve(address(market), price);
        market.permitBuy(listingId, deadline, nonce, whitelistSig);
        vm.stopPrank();
        console.log("  Step 4: User purchased NFT using whitelist signature");
    }
}
