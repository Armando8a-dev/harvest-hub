// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {HarvestHub} from "../src/HarvestHub.sol";
import {FarmToken} from "../src/FarmToken.sol";

contract HarvestHubTest is Test {
    HarvestHub hub;
    FarmToken reward;   // emitted by every pool
    FarmToken seed;     // stake token, pool A
    FarmToken corn;     // stake token, pool B

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant RATE_A = 1 ether;   // 1 reward/sec
    uint256 constant RATE_B = 5 ether;   // 5 reward/sec

    bytes32 poolA;
    bytes32 poolB;

    function setUp() public {
        reward = new FarmToken("Harvest", "HRV");
        seed = new FarmToken("Seed", "SEED");
        corn = new FarmToken("Corn", "CORN");

        hub = new HarvestHub(address(reward));
        // Fund the hub well above any payout the fuzz range can produce
        // (max = 365 days × 1 reward/sec ≈ 31.5M), so accrual tests measure the
        // accounting, not the balance cap. The cap has its own test below.
        reward.mint(address(hub), 100_000_000 ether);

        poolA = hub.createPool(address(seed), RATE_A);
        poolB = hub.createPool(address(corn), RATE_B);

        // give alice and bob stakeable tokens
        seed.mint(alice, 1000 ether);
        seed.mint(bob, 1000 ether);
        corn.mint(alice, 1000 ether);
    }

    function _stake(address who, bytes32 pool, FarmToken token, uint256 amount) internal {
        vm.startPrank(who);
        token.approve(address(hub), amount);
        hub.stake(pool, amount);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Pool creation
    // ─────────────────────────────────────────────────────────────────────

    function test_CreatePool_RegistersTwoPools() public view {
        assertEq(hub.poolCount(), 2);
        assertTrue(poolA != poolB, "distinct pool ids");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Single-user accrual over time
    // ─────────────────────────────────────────────────────────────────────

    function test_SingleStaker_AccruesAtRate() public {
        _stake(alice, poolA, seed, 100 ether);

        vm.warp(block.timestamp + 10); // 10 seconds
        // alice is the only staker → she earns the full emission: 10 × RATE_A
        assertEq(hub.pendingRewards(poolA, alice), 10 * RATE_A);
    }

    function test_Harvest_PaysPendingAndResets() public {
        _stake(alice, poolA, seed, 100 ether);
        vm.warp(block.timestamp + 10);

        uint256 before = reward.balanceOf(alice);
        vm.prank(alice);
        hub.harvest(poolA);

        assertEq(reward.balanceOf(alice) - before, 10 * RATE_A, "paid 10 seconds of rewards");
        assertEq(hub.pendingRewards(poolA, alice), 0, "pending reset after harvest");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Two users split rewards by stake share
    // ─────────────────────────────────────────────────────────────────────

    function test_TwoStakers_SplitProportionally() public {
        _stake(alice, poolA, seed, 100 ether); // 25%
        _stake(bob, poolA, seed, 300 ether);   // 75%

        vm.warp(block.timestamp + 100); // 100s × 1 reward = 100 rewards total

        uint256 aliceP = hub.pendingRewards(poolA, alice);
        uint256 bobP = hub.pendingRewards(poolA, bob);

        assertApproxEqAbs(aliceP, 25 ether, 1e6, "alice ~25%");
        assertApproxEqAbs(bobP, 75 ether, 1e6, "bob ~75%");
        assertApproxEqAbs(aliceP + bobP, 100 ether, 1e6, "total ~100 emitted");
    }

    /// @dev The core MasterChef guarantee: a user who stakes LATE must not collect
    ///      rewards that accrued before they joined.
    function test_LateStaker_DoesNotStealEarlierRewards() public {
        _stake(alice, poolA, seed, 100 ether);
        vm.warp(block.timestamp + 50); // alice alone for 50s → 50 rewards

        _stake(bob, poolA, seed, 100 ether); // bob joins now
        // at the moment of joining, bob is owed nothing
        assertEq(hub.pendingRewards(poolA, bob), 0, "late staker starts at zero");
        // alice has banked her 50 seconds
        assertApproxEqAbs(hub.pendingRewards(poolA, alice), 50 ether, 1e6, "alice kept her 50");

        vm.warp(block.timestamp + 50); // next 50s split 50/50
        assertApproxEqAbs(hub.pendingRewards(poolA, bob), 25 ether, 1e6, "bob earns only post-join share");
        assertApproxEqAbs(hub.pendingRewards(poolA, alice), 75 ether, 1e6, "alice 50 + 25");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Multiple pools accrue independently at their own rates
    // ─────────────────────────────────────────────────────────────────────

    function test_Pools_AccrueIndependently() public {
        _stake(alice, poolA, seed, 100 ether); // rate 1/s
        _stake(alice, poolB, corn, 100 ether); // rate 5/s

        vm.warp(block.timestamp + 10);
        assertEq(hub.pendingRewards(poolA, alice), 10 * RATE_A, "pool A: 10s at rate 1");
        assertEq(hub.pendingRewards(poolB, alice), 10 * RATE_B, "pool B: 10s at rate 5");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Withdraw returns principal and auto-harvests
    // ─────────────────────────────────────────────────────────────────────

    function test_Withdraw_ReturnsPrincipalAndRewards() public {
        _stake(alice, poolA, seed, 100 ether);
        vm.warp(block.timestamp + 10);

        uint256 rewardBefore = reward.balanceOf(alice);
        vm.prank(alice);
        hub.withdraw(poolA, 100 ether);

        assertEq(seed.balanceOf(alice), 1000 ether, "principal fully returned");
        assertEq(reward.balanceOf(alice) - rewardBefore, 10 * RATE_A, "rewards auto-harvested");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Reward shortfall caps the payout instead of bricking the pool
    // ─────────────────────────────────────────────────────────────────────

    function test_RewardShortfall_CapsPayoutAtBalance() public {
        // A fresh, under-funded hub: only 5 reward tokens available.
        FarmToken poorReward = new FarmToken("Poor", "POOR");
        HarvestHub poorHub = new HarvestHub(address(poorReward));
        poorReward.mint(address(poorHub), 5 ether);
        bytes32 p = poorHub.createPool(address(seed), 1 ether); // 1 reward/sec

        vm.startPrank(alice);
        seed.approve(address(poorHub), 100 ether);
        poorHub.stake(p, 100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100); // theoretical pending = 100, balance = 5

        assertEq(poorHub.pendingRewards(p, alice), 100 ether, "view shows full theoretical accrual");

        uint256 before = poorReward.balanceOf(alice);
        vm.prank(alice);
        poorHub.harvest(p);
        // payout is capped at the hub's balance; the pool doesn't revert
        assertEq(poorReward.balanceOf(alice) - before, 5 ether, "payout capped at available balance");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  pendingRewards view matches what harvest actually pays (well-funded)
    // ─────────────────────────────────────────────────────────────────────

    function testFuzz_ViewMatchesPaid(uint96 stakeAmt, uint32 secs) public {
        vm.assume(stakeAmt > 0 && stakeAmt <= 1000 ether);
        vm.assume(secs > 0 && secs <= 365 days);

        seed.mint(alice, stakeAmt);
        _stake(alice, poolA, seed, stakeAmt);
        vm.warp(block.timestamp + secs);

        uint256 quoted = hub.pendingRewards(poolA, alice);
        uint256 before = reward.balanceOf(alice);
        vm.prank(alice);
        if (quoted == 0) {
            vm.expectRevert("No rewards to claim");
            hub.harvest(poolA);
        } else {
            hub.harvest(poolA);
            assertEq(reward.balanceOf(alice) - before, quoted, "view matches payout");
        }
    }
}
