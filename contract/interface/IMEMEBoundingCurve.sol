// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

interface IMEMEBoundingCurve {
    event TokensPurchased(
        address indexed buyer,
        uint256 nativeAmount,
        uint256 tokenAmount
    );
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 nativeAmount
    );
    event CurveClosed(address indexed admin);

    function tokenAddress() external view returns (address);

    function tokenReserve() external view returns (uint256);

    function nativeReserve() external view returns (uint256);

    function virtualNative() external view returns (uint256);

    function virtualToken() external view returns (uint256);

    function constantProductK() external view returns (uint256);

    function feeRate() external view returns (uint256);

    function feeDenominator() external view returns (uint256);

    function feeReceiver() external view returns (address);

    function graduationPlatformFeeRate() external view returns (uint256);

    function graduationCreatorFeeRate() external view returns (uint256);

    function initialize(
        address admin,
        address token,
        uint256 initialVirtualNative,
        uint256 initialVirtualToken,
        uint256 initialTokenReserve,
        uint256 feeNumerator,
        uint256 feeDenom,
        address receiver
    ) external;

    function buy() external payable;

    function sell(uint256 tokenAmount) external;

    function closeCurve() external;

    function calculateTokenOutput(
        uint256 nativeInput
    ) external view returns (uint256 tokenOutput, uint256 feeAmount);

    function calculateNativeOutput(
        uint256 tokenInput
    ) external view returns (uint256 nativeOutput, uint256 feeAmount);
}
