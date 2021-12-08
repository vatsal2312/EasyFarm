// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.10;

interface IEasyFarmStrategy {
    function deposit(address _tokenAddr) external;
    function withdraw(address _tokenAddr, uint256 _amount) external;
    function claim(address _tokenAddr) external;
    function withdrawAll(address _tokenAddr) external;
    function emergencyWithdraw(address _tokenAddr) external;
}