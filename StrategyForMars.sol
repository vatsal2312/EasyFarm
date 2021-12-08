// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.10;

import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./EasyFarmToken.sol";

import "./IEasyFarmStrategy.sol";
import "./IMars.sol";
import "./ISwapRouter.sol";

contract StrategyForMars is Ownable, IEasyFarmStrategy {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    address public easyFarmCore;
    address public easyFarmToken;

    address public farmPool;
    address public claimPool;
    address public xmsAddr;

    uint256 public swapThreshold;
    uint256 public claimThreshold;

    address public swapRouter0;
    address[] public path0;
    address public swapRouter1;
    address[] public path1;

    mapping(address => uint256) public tokenPid;

    constructor(
        address _easyFarmCore,
        address _easyFarmToken,
        address _xmsAddr,
        address _farmPool,
        address _claimPool,
        uint256 _swapThreshold,
        uint256 _claimThreshold,
        address _swapRouter0,
        address[] memory _path0,
        address _swapRouter1,
        address[] memory _path1
    ) {
        easyFarmCore = _easyFarmCore;
        easyFarmToken = _easyFarmToken;
        xmsAddr = _xmsAddr;
        farmPool = _farmPool;
        claimPool = _claimPool;
        swapThreshold = _swapThreshold;
        claimThreshold = _claimThreshold;
        swapRouter0 = _swapRouter0;
        path0 = _path0;
        swapRouter1 = _swapRouter1;
        path1 = _path1;
        doApprove();
    }

    modifier onlyCore() {
        require(msg.sender == easyFarmCore, "permission denied");
        _;
    }

    receive() external payable {}

    function deposit(address _tokenAddr) external override onlyCore {
        uint256 bal = IERC20(_tokenAddr).balanceOf(address(this));
        if (bal > 0) {
            IERC20(_tokenAddr).safeIncreaseAllowance(farmPool, bal);
            IMars(farmPool).deposit(tokenPid[_tokenAddr], bal);
        }
        claim(_tokenAddr);
    }

    function withdraw(address _tokenAddr, uint256 _amount)
        external
        override
        onlyCore
    {
        IMars(farmPool).withdraw(tokenPid[_tokenAddr], _amount);
        IERC20(_tokenAddr).safeTransfer(easyFarmCore, _amount);
        claim(_tokenAddr);
    }

    function withdrawAll(address _tokenAddr) external override onlyCore {
        IMars(farmPool).withdrawAll(tokenPid[_tokenAddr]);
        uint256 bal = IERC20(_tokenAddr).balanceOf(address(this));
        IERC20(_tokenAddr).safeTransfer(easyFarmCore, bal);
        claim(_tokenAddr);
    }

    function emergencyWithdraw(address _tokenAddr) external override onlyCore {
        IMars(farmPool).emergencyWithdraw(tokenPid[_tokenAddr]);
        uint256 bal = IERC20(_tokenAddr).balanceOf(address(this));
        IERC20(_tokenAddr).safeTransfer(easyFarmCore, bal);
        claim(_tokenAddr);
    }

    function claim(address) public override {
        (, uint256 claimable) = IMars(farmPool).getVestingAmount();
        if (claimable > claimThreshold) {
            IMars(claimPool).claim();
            doSwap();
        } 
    }

    function doSwap() public {
        uint256 input0 = IERC20(xmsAddr).balanceOf(address(this));
        if (input0 > swapThreshold) {
            ISwapRouter(swapRouter0).swapExactTokensForTokens(
                input0,
                0,
                path0,
                address(this),
                block.timestamp.add(500)
            );
            if (path1.length > 0) {
                uint256 input1 = IERC20(path1[0]).balanceOf(address(this));
                ISwapRouter(swapRouter1).swapExactTokensForTokens(
                    input1,
                    0,
                    path1,
                    address(this),
                    block.timestamp.add(500)
                );
            }
            burnEFT();
        }
    }

    function burnEFT() public {
        uint256 eftBal = EasyFarmToken(easyFarmToken).balanceOf(address(this));
        if (eftBal > 0) {
            EasyFarmToken(easyFarmToken).burn(eftBal);
        }
    }

    function doApprove() public {
        IERC20(path0[0]).safeApprove(swapRouter0, 0);
        IERC20(path0[0]).safeApprove(swapRouter0, type(uint256).max);

        if (path1.length > 0) {
            IERC20(path1[0]).safeApprove(swapRouter1, 0);
            IERC20(path1[0]).safeApprove(swapRouter1, type(uint256).max);
        }
    }

    function setTokenPid(address _tokenAddr, uint256 _pid) external onlyOwner {
        tokenPid[_tokenAddr] = _pid;
    }

    function setEasyFarmCore(address _easyFarmCore) external onlyOwner {
        easyFarmCore = _easyFarmCore;
    }

    function setEasyFarmToken(address _easyFarmToken) external onlyOwner {
        easyFarmToken = _easyFarmToken;
    }

    function setXmsAddr(address _xmsAddr) external onlyOwner {
        xmsAddr = _xmsAddr;
    }

    function setFarmPool(address _farmPool) external onlyOwner {
        farmPool = _farmPool;
    }

    function setClaimPool(address _claimPool) external onlyOwner {
        claimPool = _claimPool;
    }

    function setSwapThreshold(uint256 _swapThreshold) external onlyOwner {
        swapThreshold = _swapThreshold;
    }

    function setClaimThreshold(uint256 _claimThreshold) external onlyOwner {
        claimThreshold = _claimThreshold;
    }

    function setSwapRouters(address _swapRouter0, address _swapRouter1)
        external
        onlyOwner
    {
        swapRouter0 = _swapRouter0;
        swapRouter1 = _swapRouter1;
        doApprove();
    }

    function setPaths(address[] memory _path0, address[] memory _path1)
        external
        onlyOwner
    {
        path0 = _path0;
        path1 = _path1;
        doApprove();
    }
}
