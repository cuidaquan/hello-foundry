// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title MemeFactoryCompleteTest
 * @dev 完整的 MemeFactory 测试套件，包含所有关键功能验证
 * @author MemeFactory Team
 */
contract MemeFactoryCompleteTest is Test {
    // ============ Test Contracts ============
    
    MemeFactory public factory;
    MemeToken public implementation;
    
    // ============ Test Accounts ============
    
    address public projectOwner = address(0x1);
    address public creator1 = address(0x2);
    address public creator2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public user3 = address(0x6);
    
    // ============ Test Constants ============
    
    string constant TEST_SYMBOL = "DOGE";
    uint256 constant TEST_TOTAL_SUPPLY = 1000000 * 10**18;
    uint256 constant TEST_PER_MINT = 1000 * 10**18;
    uint256 constant TEST_PRICE = 0.001 ether;
    uint256 constant INITIAL_BALANCE = 100 ether;
    
    // ============ Events ============
    
    event MemeDeployed(address indexed tokenAddress, address indexed creator, string symbol, uint256 totalSupply, uint256 perMint, uint256 price);
    event MemeMinted(address indexed tokenAddress, address indexed minter, uint256 amount, uint256 fee, uint256 projectFee, uint256 creatorFee);
    
    // ============ Setup ============
    
    function setUp() public {
        // Deploy contracts
        implementation = new MemeToken();
        factory = new MemeFactory(address(implementation), projectOwner);
        
        // Fund all accounts
        vm.deal(projectOwner, INITIAL_BALANCE);
        vm.deal(creator1, INITIAL_BALANCE);
        vm.deal(creator2, INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);
    }
    
    // ============ 核心功能测试 ============
    
    function test_deployMeme_Success() public {
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        // 验证代币地址有效
        assertTrue(tokenAddr != address(0), "Token address should not be zero");
        
        // 验证代币已注册
        assertTrue(factory.isTokenDeployed(tokenAddr), "Token should be registered");
        
        // 验证代币信息
        (string memory symbol, uint256 totalSupply, uint256 currentSupply, 
         uint256 perMint, uint256 price, address creator) = factory.getTokenInfo(tokenAddr);
        
        assertEq(symbol, TEST_SYMBOL, "Symbol mismatch");
        assertEq(totalSupply, TEST_TOTAL_SUPPLY, "Total supply mismatch");
        assertEq(currentSupply, 0, "Initial current supply should be 0");
        assertEq(perMint, TEST_PER_MINT, "Per mint amount mismatch");
        assertEq(price, TEST_PRICE, "Price mismatch");
        assertEq(creator, creator1, "Creator mismatch");
        
        // 验证代币合约属性
        MemeToken token = MemeToken(tokenAddr);
        assertEq(token.name(), string(abi.encodePacked("Meme ", TEST_SYMBOL)), "Token name mismatch");
        assertEq(token.symbol(), TEST_SYMBOL, "Token symbol mismatch");
        assertEq(token.getTotalSupplyLimit(), TEST_TOTAL_SUPPLY, "Token total supply limit mismatch");
        assertEq(token.getCreator(), creator1, "Token creator mismatch");
        assertTrue(token.isInitialized(), "Token should be initialized");
    }
    
    // ============ 关键测试1: 费用按比例正确分配 ============
    
    function test_feeDistribution_Correct() public {
        // 部署代币
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        // 记录初始余额
        uint256 projectOwnerBalanceBefore = projectOwner.balance;
        uint256 creatorBalanceBefore = creator1.balance;
        uint256 userBalanceBefore = user1.balance;
        
        // 执行铸造
        vm.prank(user1);
        factory.mintMeme{value: TEST_PRICE}(tokenAddr);
        
        // 计算预期费用
        uint256 expectedProjectFee = (TEST_PRICE * factory.PROJECT_FEE_RATE()) / factory.FEE_DENOMINATOR();
        uint256 expectedCreatorFee = TEST_PRICE - expectedProjectFee;
        
        // 验证费用分配
        assertEq(
            projectOwner.balance - projectOwnerBalanceBefore, 
            expectedProjectFee, 
            "Project owner fee incorrect"
        );
        assertEq(
            creator1.balance - creatorBalanceBefore, 
            expectedCreatorFee, 
            "Creator fee incorrect"
        );
        assertEq(
            userBalanceBefore - user1.balance, 
            TEST_PRICE, 
            "User payment incorrect"
        );
        
        // 验证费用比例 (1% 项目方, 99% 创建者)
        assertEq(expectedProjectFee, TEST_PRICE / 100, "Project fee should be 1%");
        assertEq(expectedCreatorFee, TEST_PRICE * 99 / 100, "Creator fee should be 99%");
        
        console.log("=== Fee Distribution Test ===");
        console.log("Total Fee: %s wei", TEST_PRICE);
        console.log("Project Fee (1%%): %s wei", expectedProjectFee);
        console.log("Creator Fee (99%%): %s wei", expectedCreatorFee);
        console.log("Project Owner Balance Change: %s wei", projectOwner.balance - projectOwnerBalanceBefore);
        console.log("Creator Balance Change: %s wei", creator1.balance - creatorBalanceBefore);
    }
    
    function test_feeDistribution_MultipleTransactions() public {
        // 部署代币
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        uint256 projectOwnerBalanceBefore = projectOwner.balance;
        uint256 creatorBalanceBefore = creator1.balance;
        
        // 多次铸造
        uint256 mintCount = 5;
        for (uint i = 0; i < mintCount; i++) {
            address user = address(uint160(1000 + i));
            vm.deal(user, TEST_PRICE);
            vm.prank(user);
            factory.mintMeme{value: TEST_PRICE}(tokenAddr);
        }
        
        // 验证累计费用分配
        uint256 totalFees = TEST_PRICE * mintCount;
        uint256 expectedProjectFee = (totalFees * factory.PROJECT_FEE_RATE()) / factory.FEE_DENOMINATOR();
        uint256 expectedCreatorFee = totalFees - expectedProjectFee;
        
        assertEq(
            projectOwner.balance - projectOwnerBalanceBefore, 
            expectedProjectFee, 
            "Cumulative project fee incorrect"
        );
        assertEq(
            creator1.balance - creatorBalanceBefore, 
            expectedCreatorFee, 
            "Cumulative creator fee incorrect"
        );
    }
    
    // ============ 关键测试2: 每次发行数量正确，不超过totalSupply ============
    
    function test_mintAmount_Correct() public {
        // 部署代币
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        MemeToken token = MemeToken(tokenAddr);
        
        // 验证初始状态
        assertEq(token.totalSupply(), 0, "Initial total supply should be 0");
        assertEq(token.balanceOf(user1), 0, "Initial user balance should be 0");
        
        // 执行铸造
        vm.prank(user1);
        factory.mintMeme{value: TEST_PRICE}(tokenAddr);
        
        // 验证铸造数量
        assertEq(token.balanceOf(user1), TEST_PER_MINT, "User should receive exact perMint amount");
        assertEq(token.totalSupply(), TEST_PER_MINT, "Total supply should increase by perMint");
        
        // 验证工厂记录的当前供应量
        (, , uint256 currentSupply, , , ) = factory.getTokenInfo(tokenAddr);
        assertEq(currentSupply, TEST_PER_MINT, "Factory current supply tracking incorrect");
        
        console.log("=== Mint Amount Test ===");
        console.log("Per Mint Amount: %s tokens", TEST_PER_MINT / 10**18);
        console.log("User Balance After Mint: %s tokens", token.balanceOf(user1) / 10**18);
        console.log("Total Supply After Mint: %s tokens", token.totalSupply() / 10**18);
    }
    
    function test_totalSupply_NotExceeded() public {
        // 部署小供应量代币用于测试
        uint256 smallTotalSupply = TEST_PER_MINT * 3; // 只能铸造3次
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme("SMALL", smallTotalSupply, TEST_PER_MINT, TEST_PRICE);
        
        MemeToken token = MemeToken(tokenAddr);
        
        // 前3次铸造应该成功
        for (uint i = 0; i < 3; i++) {
            address user = address(uint160(2000 + i));
            vm.deal(user, TEST_PRICE);
            vm.prank(user);
            factory.mintMeme{value: TEST_PRICE}(tokenAddr);
            
            assertEq(token.balanceOf(user), TEST_PER_MINT, "Each user should receive perMint amount");
        }
        
        // 验证总供应量达到上限
        assertEq(token.totalSupply(), smallTotalSupply, "Total supply should reach limit");
        
        // 第4次铸造应该失败
        vm.deal(user3, TEST_PRICE);
        vm.prank(user3);
        vm.expectRevert("MemeFactory: exceeds total supply");
        factory.mintMeme{value: TEST_PRICE}(tokenAddr);
        
        // 验证供应量没有超过限制
        assertEq(token.totalSupply(), smallTotalSupply, "Total supply should not exceed limit");
        
        console.log("=== Supply Limit Test ===");
        console.log("Total Supply Limit: %s tokens", smallTotalSupply / 10**18);
        console.log("Final Total Supply: %s tokens", token.totalSupply() / 10**18);
        console.log("Supply limit enforced correctly");
    }
    
    function test_supplyTracking_Accurate() public {
        // 部署代币
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        // 多次铸造并验证供应量跟踪
        uint256 mintCount = 10;
        for (uint i = 0; i < mintCount; i++) {
            address user = address(uint160(3000 + i));
            vm.deal(user, TEST_PRICE);
            vm.prank(user);
            factory.mintMeme{value: TEST_PRICE}(tokenAddr);
            
            // 验证每次铸造后的供应量
            (, , uint256 currentSupply, , , ) = factory.getTokenInfo(tokenAddr);
            uint256 expectedSupply = TEST_PER_MINT * (i + 1);
            assertEq(currentSupply, expectedSupply, "Current supply tracking incorrect");
            assertEq(MemeToken(tokenAddr).totalSupply(), expectedSupply, "Token total supply incorrect");
        }
        
        console.log("=== Supply Tracking Test ===");
        console.log("Mints Performed: %s", mintCount);
        console.log("Expected Total Supply: %s tokens", (TEST_PER_MINT * mintCount) / 10**18);
        console.log("Actual Total Supply: %s tokens", MemeToken(tokenAddr).totalSupply() / 10**18);
    }
    
    // ============ 综合测试 ============
    
    function test_completeWorkflow() public {
        // 1. 部署代币
        vm.prank(creator1);
        address tokenAddr = factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
        
        // 2. 记录初始状态
        uint256 projectOwnerBalanceBefore = projectOwner.balance;
        uint256 creatorBalanceBefore = creator1.balance;
        
        // 3. 多用户铸造
        address[] memory users = new address[](5);
        for (uint i = 0; i < 5; i++) {
            users[i] = address(uint160(4000 + i));
            vm.deal(users[i], TEST_PRICE);
            vm.prank(users[i]);
            factory.mintMeme{value: TEST_PRICE}(tokenAddr);
            
            // 验证每个用户获得正确数量
            assertEq(MemeToken(tokenAddr).balanceOf(users[i]), TEST_PER_MINT, "User mint amount incorrect");
        }
        
        // 4. 验证总供应量
        assertEq(MemeToken(tokenAddr).totalSupply(), TEST_PER_MINT * 5, "Total supply incorrect");
        
        // 5. 验证费用分配
        uint256 totalFees = TEST_PRICE * 5;
        uint256 expectedProjectFee = (totalFees * factory.PROJECT_FEE_RATE()) / factory.FEE_DENOMINATOR();
        uint256 expectedCreatorFee = totalFees - expectedProjectFee;
        
        assertEq(projectOwner.balance - projectOwnerBalanceBefore, expectedProjectFee, "Project fee incorrect");
        assertEq(creator1.balance - creatorBalanceBefore, expectedCreatorFee, "Creator fee incorrect");
        
        // 6. 验证代币转账功能
        vm.prank(users[0]);
        MemeToken(tokenAddr).transfer(users[1], 500 * 10**18);
        assertEq(MemeToken(tokenAddr).balanceOf(users[0]), 500 * 10**18, "Transfer from balance incorrect");
        assertEq(MemeToken(tokenAddr).balanceOf(users[1]), 1500 * 10**18, "Transfer to balance incorrect");
        
        console.log("=== Complete Workflow Test ===");
        console.log("[OK] Token deployment successful");
        console.log("[OK] Multiple user minting successful");
        console.log("[OK] Fee distribution correct");
        console.log("[OK] Supply tracking accurate");
        console.log("[OK] Token transfer functional");
    }
    
    // ============ 边界条件测试 ============
    
    function test_edgeCases() public {
        // 测试最小价格
        vm.prank(creator1);
        address tokenAddr1 = factory.deployMeme("MIN", TEST_TOTAL_SUPPLY, TEST_PER_MINT, 1000); // 最小价格
        
        vm.deal(user1, 1000);
        vm.prank(user1);
        factory.mintMeme{value: 1000}(tokenAddr1);
        assertEq(MemeToken(tokenAddr1).balanceOf(user1), TEST_PER_MINT, "Min price mint failed");
        
        // 测试大数值
        uint256 largeSupply = 10**25;
        uint256 largePerMint = 10**24;
        vm.prank(creator2);
        address tokenAddr2 = factory.deployMeme("LARGE", largeSupply, largePerMint, 1 ether);
        
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        factory.mintMeme{value: 1 ether}(tokenAddr2);
        assertEq(MemeToken(tokenAddr2).balanceOf(user2), largePerMint, "Large value mint failed");
    }
    
    // ============ 辅助函数 ============
    
    function _deployTestToken() internal returns (address) {
        vm.prank(creator1);
        return factory.deployMeme(TEST_SYMBOL, TEST_TOTAL_SUPPLY, TEST_PER_MINT, TEST_PRICE);
    }
}
