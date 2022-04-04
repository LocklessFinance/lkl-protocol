pragma solidity ^0.7.0;

// SPDX-License-Identifier: UNLICENSED

interface ICCPool {
    function getPoolId() external view returns (bytes32);

    function getVault() external view returns (address);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint256);

    function underlying() external view returns (uint256);

    function bond() external view returns (uint256);

    function base() external view returns (uint256);

    function unitSeconds() external view returns (uint256);

    function expiration() external view returns (uint256);

    function underlyingDecimals() external view returns (uint256);
}
