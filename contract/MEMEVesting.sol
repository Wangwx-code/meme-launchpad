// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MEMEVesting is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // token => beneficiary => Allocation[]
    mapping(address => mapping(address => Allocation[])) public allocations;

    enum VestingMode {
        CLIFF,
        LINEAR
    }

    enum AllocationStatus {
        ACTIVE, // 0 - 活跃中
        CANCELLED, // 1 - 已取消
        COMPLETED // 2 - 已完成
    }

    struct Allocation {
        uint256 amount;
        uint256 claimedAmount;
        uint256 start;
        uint256 end;
        address granter;
        VestingMode mode;
        AllocationStatus status;
    }

    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 amount,
        VestingMode mode,
        uint256 start,
        uint256 end
    );
    event Claimed(address indexed beneficiary, uint256 amount);

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function _authorizeUpgrade(
        address newImpl
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function createVestingSchedules(
        address token,
        address beneficiary,
        uint256 amount,
        uint256 start,
        uint256 end,
        VestingMode mode
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(start < end, "Start must be < end");
        require(block.timestamp <= start, "Cannot start in the past"); // 添加合理性检查

        allocations[token][beneficiary].push(
            Allocation({
                amount: amount,
                claimedAmount: 0,
                start: start,
                end: end,
                mode: mode,
                granter: msg.sender,
                status: AllocationStatus.ACTIVE
            })
        );

        // 将transferFrom放到最后，遵循checks-effects-interactions模式
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit VestingScheduleCreated(beneficiary, amount, mode, start, end);
    }

    function claim(address token) external nonReentrant {
        address beneficiary = msg.sender;
        Allocation[] storage userAllocs = allocations[token][beneficiary];
        uint256 totalPending = 0;
        uint256 allocCount = userAllocs.length; // 缓存数组长度

        for (uint256 i = 0; i < allocCount; ++i) {
            Allocation storage alloc = userAllocs[i];

            // 添加快速跳过条件
            if (alloc.status != AllocationStatus.ACTIVE) continue;
            if (block.timestamp < alloc.start) continue;

            uint256 pending = _calcPending(alloc);

            if (pending > 0) {
                unchecked {
                    // 使用unchecked进行安全算术运算
                    alloc.claimedAmount += pending;
                    totalPending += pending;
                }
            }
        }

        require(totalPending > 0, "Nothing to claim");

        IERC20(token).safeTransfer(beneficiary, totalPending);
        emit Claimed(beneficiary, totalPending);
    }

    function revoke(
        address token,
        address beneficiary,
        uint256 index
    ) external nonReentrant {
        _revoke(token, beneficiary, index);
    }

    function _revoke(
        address token,
        address beneficiary,
        uint256 index
    ) private {
        Allocation storage alloc = allocations[token][beneficiary][index];
        require(alloc.status == AllocationStatus.ACTIVE, "Not active");
        require(block.timestamp < alloc.end, "Already ended");
        require(alloc.amount > alloc.claimedAmount, "Nothing to revoke");
        require(msg.sender == alloc.granter, "Only granter can revoke");
        alloc.status = AllocationStatus.CANCELLED;
        uint256 pending = _calcPending(alloc);
        if (pending > 0) {
            alloc.claimedAmount += pending;
            IERC20(token).safeTransfer(beneficiary, pending);
        }
        uint256 unclaimed = alloc.amount - alloc.claimedAmount;
        if (unclaimed > 0) {
            IERC20(token).safeTransfer(alloc.granter, unclaimed);
        }
    }

    // 无状态函数
    function _calcPending(
        Allocation storage alloc
    ) internal view returns (uint256) {
        return
            _calcPending(
                alloc.amount,
                alloc.claimedAmount,
                alloc.start,
                alloc.end,
                block.timestamp,
                alloc.mode
            );
    }

    function _calcPending(
        uint256 amount,
        uint256 claimedAmount,
        uint256 start,
        uint256 end,
        uint256 current,
        VestingMode mode
    ) internal pure returns (uint256) {
        if (current < start || amount == 0) return 0;

        uint256 totalUnlock = _calcTotalUnlock(
            amount,
            start,
            end,
            current,
            mode
        );

        unchecked {
            // 避免underflow检查
            return
                totalUnlock > claimedAmount ? totalUnlock - claimedAmount : 0;
        }
    }

    function _calcTotalUnlock(
        uint256 amount,
        uint256 start,
        uint256 end,
        uint256 current,
        VestingMode mode
    ) internal pure returns (uint256) {
        // 提前返回检查
        if (amount == 0 || current < start) return 0;
        if (current >= end) return amount; // 改为>=，包含边界情况

        if (mode == VestingMode.CLIFF) return 0;

        // 使用 unchecked 避免安全检查开销
        unchecked {
            return (amount * (current - start)) / (end - start);
        }
    }

    function getPendingAmount(
        address token,
        address beneficiary
    ) external view returns (uint256) {
        Allocation[] storage userAllocs = allocations[token][beneficiary];
        uint256 totalPending = 0;
        uint256 current = block.timestamp; // 缓存当前时间戳

        for (uint256 i = 0; i < userAllocs.length; ++i) {
            Allocation storage alloc = userAllocs[i];

            // 快速跳过无效分配
            if (alloc.status != AllocationStatus.ACTIVE) continue;
            if (current < alloc.start) continue;

            totalPending += _calcPending(
                alloc.amount,
                alloc.claimedAmount,
                alloc.start,
                alloc.end,
                current,
                alloc.mode
            );
        }

        return totalPending;
    }
}
