// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MEMEToken} from "contract/MEMEToken.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract MEMEFactory is AccessControl {
    using SafeERC20 for IERC20;
    using Clones for address;
    
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    
    event TokenDeployed(
        address indexed token, 
        string name, 
        string symbol, 
        uint256 totalSupply, 
        address indexed tokenOwner
    );

    constructor(address _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(DEPLOYER_ROLE, _owner);
    }

    // 部署绑定曲线（需要预先批准代币）
    function deployBoundingCurve(
        address admin,
        address token,
        uint256 initialVirtualNative,
        uint256 initialVirtualToken,
        uint256 initialTokenReserve,
        uint256 feeNumerator,
        uint256 feeDenom,
        address feeReceiver
    ) external onlyRole(DEPLOYER_ROLE) returns (address) {
        require(boundingCurveLogic != address(0), "Curve logic not set");
        require(token != address(0), "Invalid token");
        
        // 1. 部署代理合约
        bytes32 salt = keccak256(abi.encodePacked(
            token, admin, initialVirtualNative, initialVirtualToken, block.timestamp
        ));
        
        address curveProxy = boundingCurveLogic.cloneDeterministic(salt);
        
        // 2. 调用者需要预先批准代币给工厂，工厂再转移给曲线合约
        // 注意：这是你当前MEMEBoundingCurve初始化函数的要求
        IERC20(token).safeTransferFrom(
            msg.sender,
            curveProxy,
            initialTokenReserve
        );
        
        // 3. 初始化曲线合约
        (bool success, ) = curveProxy.call(
            abi.encodeWithSignature(
                "initialize(address,address,uint256,uint256,uint256,uint256,uint256,address)",
                admin,
                token,
                initialVirtualNative,
                initialVirtualToken,
                initialTokenReserve,
                feeNumerator,
                feeDenom,
                feeReceiver
            )
        );
        require(success, "Curve init failed");
        
        allBoundingCurves.push(curveProxy);
        
        return curveProxy;
    }

    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner
    ) external onlyRole(DEPLOYER_ROLE) returns (address) {
        return _deployToken(name, symbol, totalSupply, tokenOwner);
    }

    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner
    ) external view returns (address) {
        return _predictTokenAddress(name, symbol, totalSupply, tokenOwner);
    }

    function grantDeployerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEPLOYER_ROLE, account);
    }

    function _deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner
    ) private returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, tokenOwner));
        
        MEMEToken token = new MEMEToken{salt: salt}(name, symbol, totalSupply, tokenOwner);
        emit TokenDeployed(address(token), name, symbol, totalSupply, tokenOwner);
        return address(token);
    }

    function _predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner
    ) private view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, tokenOwner));
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(type(MEMEToken).creationCode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }
}