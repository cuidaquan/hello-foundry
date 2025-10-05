// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/TokenVesting.sol";
import "../src/MockERC20.sol";

contract TokenVestingTest is Test {
    TokenVesting public vesting;
    MockERC20 public token;

    address public owner = address(1);
    address public beneficiary = address(2);

    uint256 public constant TOTAL_TOKENS = 1_000_000 * 1e18; // 100万代币
    uint256 public constant CLIFF_DURATION = 360 days; // 12个月
    uint256 public constant VESTING_DURATION = 720 days; // 24个月

    function setUp() public {
        vm.startPrank(owner);

        // 部署代币合约
        token = new MockERC20("Test Token", "TEST");

        // 部署 Vesting 合约
        vesting = new TokenVesting(beneficiary, address(token), TOTAL_TOKENS);

        // 转入100万代币到 Vesting 合约
        token.transfer(address(vesting), TOTAL_TOKENS);

        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(vesting.beneficiary(), beneficiary);
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.totalTokens(), TOTAL_TOKENS);
        assertEq(vesting.releasedTokens(), 0);
        assertEq(vesting.getBalance(), TOTAL_TOKENS);
    }

    function testCannotReleaseBeforeCliff() public {
        // 在cliff期内尝试释放代币
        vm.warp(block.timestamp + 180 days); // 6个月后

        assertEq(vesting.releasableAmount(), 0);

        vm.expectRevert("No tokens available for release");
        vesting.release();
    }

    function testCannotReleaseAtCliffEnd() public {
        // 正好在cliff结束时
        vm.warp(block.timestamp + CLIFF_DURATION);

        // cliff刚结束时，vesting时间为0，所以可释放量为0
        assertEq(vesting.releasableAmount(), 0);
    }

    function testReleaseAfter1MonthFromCliff() public {
        // 第13个月（cliff结束后1个月）
        vm.warp(block.timestamp + CLIFF_DURATION + 30 days);

        uint256 expectedVested = (TOTAL_TOKENS * 30 days) / VESTING_DURATION;
        uint256 releasable = vesting.releasableAmount();

        // 允许一定的误差（由于30天不是精确的1/24）
        assertApproxEqRel(releasable, expectedVested, 0.01e18); // 1% 误差范围

        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), beneficiaryBalanceBefore + releasable);
        assertEq(vesting.releasedTokens(), releasable);
    }

    function testReleaseAfter6MonthsFromCliff() public {
        // 第18个月（cliff结束后6个月）
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);

        uint256 expectedVested = (TOTAL_TOKENS * 180 days) / VESTING_DURATION;
        uint256 releasable = vesting.releasableAmount();

        // 大约应该是 6/24 = 1/4 的代币
        assertApproxEqRel(releasable, TOTAL_TOKENS / 4, 0.02e18);
        assertApproxEqRel(releasable, expectedVested, 0.02e18);

        vesting.release();
        assertEq(vesting.releasedTokens(), releasable);
    }

    function testReleaseAfter12MonthsFromCliff() public {
        // 第24个月（cliff结束后12个月，vesting进行到一半）
        vm.warp(block.timestamp + CLIFF_DURATION + 360 days);

        uint256 expectedVested = (TOTAL_TOKENS * 360 days) / VESTING_DURATION;
        uint256 releasable = vesting.releasableAmount();

        // 应该是 1/2 的代币
        assertEq(releasable, TOTAL_TOKENS / 2);
        assertEq(releasable, expectedVested);

        vesting.release();
        assertEq(vesting.releasedTokens(), releasable);
    }

    function testReleaseAfterFullVesting() public {
        // 第36个月（cliff + vesting 全部结束）
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        uint256 releasable = vesting.releasableAmount();
        assertEq(releasable, TOTAL_TOKENS);

        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL_TOKENS);
        assertEq(vesting.releasedTokens(), TOTAL_TOKENS);
        assertEq(vesting.getBalance(), 0);
    }

    function testMultipleReleases() public {
        // 第13个月释放一次
        vm.warp(block.timestamp + CLIFF_DURATION + 30 days);
        uint256 firstRelease = vesting.releasableAmount();
        vesting.release();

        // 第18个月再释放一次
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);
        uint256 secondRelease = vesting.releasableAmount();
        vesting.release();

        // 验证总释放量
        assertEq(vesting.releasedTokens(), firstRelease + secondRelease);
        assertEq(token.balanceOf(beneficiary), firstRelease + secondRelease);
    }

    function testCannotReleaseTwiceInSameBlock() public {
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);

        vesting.release();

        vm.expectRevert("No tokens available for release");
        vesting.release();
    }

    function testLinearVestingEvery30Days() public {
        uint256 previousBalance = 0;

        // 测试从第13个月到第36个月，每30天释放一次
        for (uint256 i = 1; i <= 24; i++) {
            vm.warp(block.timestamp + CLIFF_DURATION + (i * 30 days));

            uint256 releasable = vesting.releasableAmount();
            if (releasable > 0) {
                vesting.release();
            }

            uint256 currentBalance = token.balanceOf(beneficiary);

            // 每次释放的量应该是递增的
            if (i < 24) {
                assertGt(currentBalance, previousBalance);
            }

            previousBalance = currentBalance;
        }

        // 最后应该接近或等于总量
        assertApproxEqRel(token.balanceOf(beneficiary), TOTAL_TOKENS, 0.02e18);
    }

    function testVestingAfterFullPeriod() public {
        // 超过完整的vesting期限
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION + 365 days);

        uint256 releasable = vesting.releasableAmount();
        assertEq(releasable, TOTAL_TOKENS);

        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL_TOKENS);
    }

    function testVestedAmountView() public {
        // 测试 vestedAmount 视图函数
        vm.warp(block.timestamp + CLIFF_DURATION + 360 days);

        uint256 vested = vesting.vestedAmount();
        assertEq(vested, TOTAL_TOKENS / 2);
    }

    function testReleasableAmountView() public {
        // 测试 releasableAmount 视图函数
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);

        uint256 releasable = vesting.releasableAmount();
        assertGt(releasable, 0);

        vesting.release();

        // 释放后，releasableAmount 应该为 0
        assertEq(vesting.releasableAmount(), 0);
    }
}
