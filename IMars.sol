// SPDX-License-Identifier: GPL-v3

pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;

interface IMars {

    function deposit(uint256 _pid, uint256 _wantAmt) external;

    function withdraw(uint256 _pid, uint256 _wantAmt) external;

    function withdrawAll(uint256 _pid) external;

    function claim() external;

    function getVestingAmount() external view returns (uint256 _lockAmount, uint256 _claimableAmount);
}