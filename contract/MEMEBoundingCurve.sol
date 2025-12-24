// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMEMEBoundingCurve} from "./interface/IMEMEBoundingCurve.sol";

contract MEMEBoundingCurve is
    IMEMEBoundingCurve,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    uint256 public constant MIN_LIQUIDITY = 10 ether;
    uint256 private constant PRECISION = 1e18;

    // Bonding curve parameters
    address public tokenAddress;
    uint256 public tokenReserve;
    uint256 public nativeReserve;
    uint256 public virtualNative;
    uint256 public virtualToken;
    uint256 public constantProductK;

    // Fee parameters
    uint256 public feeRate;
    uint256 public feeDenominator;
    address public feeReceiver;

    // Unused parameters (kept for storage layout compatibility)
    uint256 public graduationPlatformFeeRate;
    uint256 public graduationCreatorFeeRate;

    function initialize(
        address admin,
        address token,
        uint256 initialVirtualNative,
        uint256 initialVirtualToken,
        uint256 initialTokenReserve,
        uint256 feeNumerator,
        uint256 feeDenom,
        address receiver
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        require(token != address(0), "Invalid token");
        require(receiver != address(0), "Invalid receiver");
        require(
            initialVirtualToken >= initialTokenReserve,
            "Virtual token < reserve"
        );

        _grantRole(ADMIN_ROLE, admin);

        // Transfer initial tokens
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            initialTokenReserve
        );

        // Set bonding curve parameters
        tokenAddress = token;
        tokenReserve = initialTokenReserve;
        nativeReserve = 0;
        virtualNative = initialVirtualNative;
        virtualToken = initialVirtualToken;
        constantProductK = initialVirtualNative * initialVirtualToken;

        // Set fee parameters
        feeRate = feeNumerator;
        feeDenominator = feeDenom;
        feeReceiver = receiver;
    }

    /// @notice Allows purchase of tokens with native currency
    function buy() external payable nonReentrant {
        uint256 nativeAmount = msg.value;
        require(nativeAmount > 0, "Zero amount");

        (uint256 tokenAmount, uint256 feeAmount) = calculateTokenOutput(
            nativeAmount
        );
        require(tokenAmount <= tokenReserve, "Insufficient token reserve");

        // Update reserves
        uint256 netNative = nativeAmount - feeAmount;
        virtualNative += netNative;
        virtualToken -= tokenAmount;
        nativeReserve += netNative;
        tokenReserve -= tokenAmount;

        // Transfer tokens to buyer
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);

        // Transfer fee
        if (feeAmount > 0) {
            (bool success, ) = feeReceiver.call{value: feeAmount}("");
            require(success, "Fee transfer failed");
        }

        emit TokensPurchased(msg.sender, nativeAmount, tokenAmount);
    }

    /// @notice Allows sale of tokens for native currency
    /// @param tokenAmount Amount of tokens to sell
    function sell(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Zero amount");

        (uint256 nativeAmount, uint256 feeAmount) = calculateNativeOutput(
            tokenAmount
        );
        require(nativeAmount <= nativeReserve, "Insufficient native reserve");

        // Update reserves
        virtualNative -= nativeAmount;
        virtualToken += tokenAmount;
        nativeReserve -= nativeAmount;
        tokenReserve += tokenAmount;

        // Transfer tokens from seller
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );

        // Transfer native to seller
        uint256 netNative = nativeAmount - feeAmount;
        (bool success, ) = msg.sender.call{value: netNative}("");
        require(success, "Native transfer failed");

        // Transfer fee
        if (feeAmount > 0) {
            (success, ) = feeReceiver.call{value: feeAmount}("");
            require(success, "Fee transfer failed");
        }

        emit TokensSold(msg.sender, tokenAmount, nativeAmount);
    }

    /// @notice Closes the bonding curve when liquidity is minimal
    function closeCurve() external onlyRole(ADMIN_ROLE) {
        require(nativeReserve <= MIN_LIQUIDITY, "Liquidity above minimum");

        address admin = msg.sender;

        // Transfer remaining native
        if (nativeReserve > 0) {
            (bool success, ) = admin.call{value: nativeReserve}("");
            require(success, "Native transfer failed");
        }

        // Transfer remaining tokens
        if (tokenReserve > 0) {
            IERC20(tokenAddress).safeTransfer(admin, tokenReserve);
        }

        emit CurveClosed(admin);
    }

    // ========== VIEW FUNCTIONS ==========

    /// @notice Calculate token output for given native input
    function calculateTokenOutput(
        uint256 nativeInput
    ) public view returns (uint256 tokenOutput, uint256 feeAmount) {
        feeAmount = (nativeInput * feeRate) / feeDenominator;
        uint256 netNative = nativeInput - feeAmount;
        tokenOutput = _calculateTokenOutput(netNative);
    }

    /// @notice Calculate native output for given token input
    function calculateNativeOutput(
        uint256 tokenInput
    ) public view returns (uint256 nativeOutput, uint256 feeAmount) {
        nativeOutput = _calculateNativeOutput(tokenInput);
        feeAmount = (nativeOutput * feeRate) / feeDenominator;
        nativeOutput -= feeAmount;
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}

    function _calculateTokenOutput(
        uint256 nativeInput
    ) private view returns (uint256) {
        uint256 newVirtualNative = virtualNative + nativeInput;
        uint256 newVirtualToken = constantProductK / newVirtualNative;
        return virtualToken - newVirtualToken;
    }

    function _calculateNativeOutput(
        uint256 tokenInput
    ) private view returns (uint256) {
        uint256 newVirtualToken = virtualToken + tokenInput;
        uint256 newVirtualNative = constantProductK / newVirtualToken;
        return virtualNative - newVirtualNative;
    }

    // ========== FALLBACK ==========
    receive() external payable {
        revert("Direct transfers not allowed");
    }
}
