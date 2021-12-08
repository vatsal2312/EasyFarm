// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.10;

interface IEasyFarmCore {
    function getEFTAddr() external view returns(address);
    function getSwapRouter(string memory _name) external view returns(address);
}