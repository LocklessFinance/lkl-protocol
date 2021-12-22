// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILKLStaking {
    function add(
        address _underlyingToken,
        uint256 _expiration,
        bool _needStake,
        bool _withUpdate
    ) external;

    function deposit(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external;

    function withdraw(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external;

    function poolLength() external view returns (uint256);
}
