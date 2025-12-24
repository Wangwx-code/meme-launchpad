// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

interface IMEMEToken {
    enum TransferMode {
        MODE_NORMAL,
        MODE_TRANSFER_RESTRICTED,
        MODE_TRANSFER_CONTROLLED
    }

    event TransferModeChanged(TransferMode oldMode, TransferMode newMode);
    event VestingContractChanged(address vestingContract);
    event PairChanged(address pair);

    error TransferRestricted();
    error TransferToTokenNotAllowed();
    error TransferNotAllowedToPair();
    error TransferNotAllowed();
    error onlyOwnerCall();
    error ZeroAddress();

    function transferMode() external view returns (TransferMode);

    function vestingContract() external view returns (address);

    function pair() external view returns (address);

    function owner() external view returns (address);

    function setTransferMode(TransferMode _mode) external;

    function setVestingContract(address _vestingContract) external;

    function setPair(address _pair) external;

    // ERC20 functions
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    // Burnable functions
    function burn(uint256 value) external;

    function burnFrom(address account, uint256 value) external;
}
