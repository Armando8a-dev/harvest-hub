// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title HarvestHub
/// @notice A multi-pool yield farm. Each pool stakes a different ERC20 and emits
///         a shared reward token at its own per-second rate. Rewards accrue with
///         the classic MasterChef accounting: a per-share accumulator plus a
///         per-user reward debt, so staking/withdrawing is O(1) regardless of how
///         many users a pool has.
/// @dev    Single-pool staking was Block 7 (YieldGarden). This is the multi-pool
///         generalization. Pool ids are keccak256(abi.encodePacked(token, rate,
///         timestamp, chainid)) — all fixed-length args, so the packing is
///         collision-free (see the hash-forge repo, Block 14, for why that matters).
contract HarvestHub is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @dev 1e18 fixed-point scale for the per-share accumulator.
    uint256 private constant ACC_PRECISION = 1e18;

    struct Pool {
        address stakeToken;          // asset users stake in this pool
        uint256 totalStaked;         // total staked across all users
        uint256 rewardRate;          // reward tokens emitted per second
        uint256 lastUpdateTime;      // last time accRewardPerShare was updated
        uint256 accRewardPerShare;   // accumulated reward per staked token, ×1e18
        bool isActive;
    }

    struct UserInfo {
        uint256 amount;              // how much this user has staked
        uint256 rewardDebt;          // amount × accRewardPerShare at last action
    }

    /// @notice The reward token emitted by every pool.
    IERC20 public immutable rewardToken;

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo;
    bytes32[] public poolIds;

    event PoolCreated(bytes32 indexed poolId, address indexed stakeToken, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardPaid(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardRateUpdated(bytes32 indexed poolId, uint256 newRewardRate);

    constructor(address rewardToken_) Ownable(msg.sender) {
        require(rewardToken_ != address(0), "Invalid reward token");
        rewardToken = IERC20(rewardToken_);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Owner: pool management
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Create a new staking pool for `stakeToken` at `rewardRate` per second.
    /// @dev    The id packs only fixed-length values, so it cannot collide.
    function createPool(address stakeToken, uint256 rewardRate)
        external
        onlyOwner
        returns (bytes32 poolId)
    {
        require(stakeToken != address(0), "Invalid stake token");
        require(rewardRate > 0, "Reward rate must be positive");

        poolId = keccak256(
            abi.encodePacked(stakeToken, rewardRate, block.timestamp, block.chainid)
        );
        require(pools[poolId].stakeToken == address(0), "Pool already exists");

        pools[poolId] = Pool({
            stakeToken: stakeToken,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            accRewardPerShare: 0,
            isActive: true
        });
        poolIds.push(poolId);

        emit PoolCreated(poolId, stakeToken, rewardRate);
    }

    /// @notice Change a pool's emission rate. Accrues rewards at the old rate first.
    function setRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {
        require(pools[poolId].stakeToken != address(0), "Unknown pool");
        _updatePool(poolId);
        pools[poolId].rewardRate = newRewardRate;
        emit RewardRateUpdated(poolId, newRewardRate);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Users: stake / withdraw / harvest
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Stake `amount` of the pool's token. Auto-harvests pending rewards.
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool is not active");
        require(amount > 0, "Amount must be positive");

        _updatePool(poolId);
        UserInfo storage user = userInfo[poolId][msg.sender];

        _payPending(poolId, user, pool);

        IERC20(pool.stakeToken).safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        pool.totalStaked += amount;

        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;
        emit Staked(poolId, msg.sender, amount);
    }

    /// @notice Withdraw `amount` of staked tokens. Auto-harvests pending rewards.
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];
        require(user.amount >= amount, "Insufficient staked amount");

        _updatePool(poolId);
        _payPending(poolId, user, pool);

        user.amount -= amount;
        pool.totalStaked -= amount;
        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;

        IERC20(pool.stakeToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(poolId, msg.sender, amount);
    }

    /// @notice Claim pending rewards without touching the staked balance.
    function harvest(bytes32 poolId) external nonReentrant {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        _updatePool(poolId);
        uint256 paid = _payPending(poolId, user, pool);
        require(paid > 0, "No rewards to claim");

        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Views (for the frontend)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Pending, unclaimed rewards for `account` in `poolId` right now.
    function pendingRewards(bytes32 poolId, address account) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][account];

        uint256 acc = pool.accRewardPerShare;
        if (pool.totalStaked > 0) {
            uint256 elapsed = block.timestamp - pool.lastUpdateTime;
            acc += (elapsed * pool.rewardRate * ACC_PRECISION) / pool.totalStaked;
        }
        return user.amount * acc / ACC_PRECISION - user.rewardDebt;
    }

    function poolCount() external view returns (uint256) {
        return poolIds.length;
    }

    function allPoolIds() external view returns (bytes32[] memory) {
        return poolIds;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Internal accounting
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Bring a pool's accumulator up to the current timestamp.
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = pools[poolId];
        if (pool.totalStaked > 0) {
            uint256 elapsed = block.timestamp - pool.lastUpdateTime;
            pool.accRewardPerShare +=
                (elapsed * pool.rewardRate * ACC_PRECISION) / pool.totalStaked;
        }
        pool.lastUpdateTime = block.timestamp;
    }

    /// @dev Pay out whatever `user` has accrued so far. Returns the amount paid.
    ///      Caps at the contract's reward balance so a shortfall can't brick the pool.
    function _payPending(bytes32 poolId, UserInfo storage user, Pool storage pool)
        internal
        returns (uint256 paid)
    {
        if (user.amount == 0) return 0;
        uint256 pending = user.amount * pool.accRewardPerShare / ACC_PRECISION - user.rewardDebt;
        if (pending == 0) return 0;

        uint256 balance = rewardToken.balanceOf(address(this));
        paid = pending > balance ? balance : pending;
        if (paid > 0) {
            rewardToken.safeTransfer(msg.sender, paid);
            emit RewardPaid(poolId, msg.sender, paid);
        }
    }
}
