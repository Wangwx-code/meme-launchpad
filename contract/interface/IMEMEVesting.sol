// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

interface IMEMEVesting {
    enum VestingMode {
        CLIFF,
        LINEAR
    }

    enum AllocationStatus {
        ACTIVE,
        CANCELLED,
        COMPLETED
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

    function allocations(
        address token,
        address beneficiary,
        uint256 index
    )
        external
        view
        returns (
            uint256 amount,
            uint256 claimedAmount,
            uint256 start,
            uint256 end,
            address granter,
            VestingMode mode,
            AllocationStatus status
        );

    function initialize(address admin) external;

    function createVestingSchedules(
        address token,
        address beneficiary,
        uint256 amount,
        uint256 start,
        uint256 end,
        VestingMode mode
    ) external;

    function claim(address token) external;

    function revoke(address token, address beneficiary, uint256 index) external;

    function getPendingAmount(
        address token,
        address beneficiary
    ) external view returns (uint256);
}
