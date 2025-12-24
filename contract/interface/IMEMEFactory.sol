// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

interface IMEMEFactory {
    event TokenDeployed(
        address token,
        string name,
        string symbol,
        uint256 totalSupply,
        address owner
    );

    function owner() external view returns (address);

    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address owner
    ) external returns (address);

    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address owner
    ) external view returns (address);

    function grantDeployerRole(address account) external;
}
