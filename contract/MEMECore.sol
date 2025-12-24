// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMEMEFactory} from "contract/interface/IMEMEFactory.sol";
import {IMEMEVesting} from "contract/interface/IMEMEVesting.sol";
import {IMEMEBoundingCurve} from "contract/MEMEBoundingCurve.sol";
import {MEMEBoundingCurve} from "./MEMEBoundingCurve.sol";

contract MEMECore is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public creationFee;
    uint256 public preBuyFeeRate;
    uint256 public tradingFeeRate;
    uint256 public graduationPlatformFeeRate;
    uint256 public graduationCreatorFeeRate;
    uint256 public minLockTime;
    address public graduateFeeReceiver;

    // Contract dependencies
    address public platformFeeReceiver;
    address public marginReceiver; // Address to receive margin deposits
    uint256 public CHAIN_ID;
    IMEMEFactory public factory;
    IMEMEVesting public vesting;
    mapping (address => IMEMEBoundingCurve) curve;

    /**
     * @dev Initialize the XXXCore contract
     * @param _factory Address of the XXXFactory contract
     * @param _signer Address authorized to sign creation requests
     * @param _platformFeeReceiver Address to receive platform fees
     * @param _admin Admin address with full control
     */
    function initialize(
        address _factory,
        address _signer,
        address _platformFeeReceiver,
        address _marginReceiver,
        address _graduateFeeReceiver,
        address _admin
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        CHAIN_ID = block.chainid;
        factory = IMEMEFactory(_factory);
        platformFeeReceiver = _platformFeeReceiver;
        marginReceiver = _marginReceiver;
        graduateFeeReceiver = _graduateFeeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(SIGNER_ROLE, _signer);
        _grantRole(DEPLOYER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        creationFee = 0.05 ether;
        preBuyFeeRate = 300;
        tradingFeeRate = 100;
        graduationPlatformFeeRate = 550;
        graduationCreatorFeeRate = 250;
        minLockTime = 86400;
    }

    struct CreateTokenParams {
        string name; // Token name
        string symbol; // Token symbol
        uint256 totalSupply; // Total supply
        uint256 saleAmount; // Token amount for sale
        uint256 virtualBNBReserve; // Initial virtual BNB reserve
        uint256 virtualTokenReserve; // Initial virtual Token reserve
        uint256 launchTime; // Launch time (0 means immediate)
        address creator; // Creator address
        uint256 timestamp; // Request timestamp
        bytes32 requestId; // Unique request ID
        uint256 nonce; // Nonce
        uint256 initialBuyPercentage; // Initial buy percentage in basis points (0-9990 = 0%-99.9%)
        uint256 marginBnb; // Margin amount in BNB
        uint256 marginTime; // Margin lock time (seconds)
        VestingAllocation[] vestingAllocations; // Vesting allocations for initial buy
    }

    function createToken(
        bytes calldata data,
        bytes calldata signature
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (address tokenAddress)
    {
        if (!_validSig(data, signature)) revert InvalidSigner();
        CreateTokenParams params = abi.decode(data, (CreateTokenParams));
                // 3. Validate request
        if (block.timestamp > params.timestamp + REQUEST_EXPIRY) revert RequestExpired();
        if (usedRequestIds[params.requestId]) revert RequestAlreadyProcessed();

        // Validate token parameters
        if (params.saleAmount > params.totalSupply) revert InvalidSaleParameters();
        if (params.saleAmount == 0) revert InvalidSaleParameters();
        if (params.saleAmount < params.totalSupply * params.initialBuyPercentage / 10000) revert InvalidSaleParameters();

        // Validate initial buy percentage
        if (params.initialBuyPercentage > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidInitialBuyPercentage();

        // 4. Calculate total payment required
        uint256 totalPaymentRequired = creationFee;
        uint256 initialTokens = 0;
        uint256 initialBNB = 0;
        uint256 adjustedBNBReserve = params.virtualBNBReserve;
        uint256 adjustedTokenReserve = params.virtualTokenReserve;
        uint256 preBuyFee;

        new 
    }

    function _validSig(
        bytes calldata data,
        bytes calldata signature
    ) pure returns (bool) {
        byte32 messageHash = keccak256(
            abi.encodePacked(data, CHAIN_ID, address(this))
        );
        address signer = messageHash.recover(signature);
        if (!hasRole(SIGNER_ROLE, signer)) return false;
        return true;
    }

    // function addLiquidity(address tokenAmount, uint256 nativeAmount) {
    //     require(tokenAmount != 0 && nativeAmount != 0);
    //     IERC20(token).approve(PANCAKE_V2_ROUTER, tokenAmount);
    //     IPancakeRouter02.addLiquidityETH{value: nativeAmount}(
    //         token,
    //         tokenAmount,
    //         tokenAmount * 95 / 100,
    //         nativeAmount * 95 / 100,
    //         block.timestamp + 300,
    //         true
    //     )
    // }
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}

    receive() external payable {}
}
