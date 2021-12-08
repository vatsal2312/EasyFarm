// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./EasyFarmToken.sol";
import "./interface/IEasyFarmStrategy.sol";

contract EasyFarmCore is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    address public constant ETH_ADDR = address(1);
    uint256 public constant BASE_NUMBER = 1e18;

    EasyFarmToken public eft;

    address public gover;

    address public devAddr;
    uint256 public devPercents;

    address public marketAddr;
    uint256 public marketPercents;

    uint256 public startBlock;
    uint256 public lockBlock;

    uint256 public totalReardPerBlock;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 lastRewardBlock;
        uint256 rewardDebt;
        uint256 locked;
    }

    // Info of each pool.
    struct PoolInfo {
        address depositToken;
        uint256 rewardPerBlock;
        uint256 accTokenPerShare;
        uint256 totalDeposited;
        uint256 lastUpdateBlock;
        uint256 earnThreshold;
    }

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    PoolInfo[] public poolInfo;

    mapping(uint256 => address) public tokenStrategy; // pid=>strategy

    event Deposit(address user, address token, uint256 amount);
    event Withdraw(address user, address token, uint256 amount);
    event Claim(address user, uint256 pending, uint256 released);
    event Earn(address token, address strategy, uint256 amount);
    event UpdatePool( uint256 incReward, uint256 devReward, uint256 marketReward);

    constructor(
        EasyFarmToken _eft,
        address _gover,
        address _devAddr,
        address _marketAddr,
        uint256 _devPercents,
        uint256 _marketPercents,
        uint256 _startBlock,
        uint256 _lockBlock
    ) {
        eft = _eft;
        gover = _gover;
        devAddr = _devAddr;
        marketAddr = _marketAddr;
        devPercents = _devPercents;
        marketPercents = _marketPercents;
        startBlock = _startBlock;
        lockBlock = _lockBlock;
    }

    modifier onlyAuth() {
        require(msg.sender == devAddr || msg.sender == marketAddr, "permission denied");
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gover, "not gover");
        _;
    }

    modifier validatePid(uint256 _pid) {
        require(_pid < poolInfo.length, "pid not exist");
        _;
    }

    receive() external payable {}

    function add(address _depositToken, uint256 _rewardPerBlock, uint256 _earnThreshold) external onlyOwner {
        uint256 _lastUpdateBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(
            PoolInfo({
                depositToken: _depositToken,
                rewardPerBlock: _rewardPerBlock,
                accTokenPerShare: 0,
                totalDeposited: 0,
                lastUpdateBlock: _lastUpdateBlock,
                earnThreshold: _earnThreshold
            })
        );
        totalReardPerBlock = totalReardPerBlock.add(_rewardPerBlock);
    }

    function deposit(uint256 _pid, uint256 _amount) external payable nonReentrant {
        if(msg.value > 0){
            _amount = msg.value;
        }
        _deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        _withdraw(msg.sender, _pid, _amount);
    }

    function withdrawAll(uint256 _pid) external nonReentrant {
        _withdraw(msg.sender, _pid, userInfo[_pid][msg.sender].amount);
    }

    function claim(uint256 _pid) external nonReentrant {
        _claim(msg.sender, _pid);
    }

    function claimAll() public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            _claim(msg.sender, i);
        }
    }

    function _claim(address _userAddr, uint256 _pid) internal validatePid(_pid) {
        updatePool(_pid);
        (uint256 pending, uint256 released, ) = pendingReward(_pid, _userAddr);
        UserInfo storage user = userInfo[_pid][_userAddr];
        PoolInfo storage pool = poolInfo[_pid];
        user.locked = user.locked.add(pending).sub(released);
        user.lastRewardBlock = block.number;
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(BASE_NUMBER);
        if(released > 0){
            _safeEFTTransfer(_userAddr, released);
        }
        address strategyAddr = tokenStrategy[_pid];
        if(strategyAddr != address(0)){
            IEasyFarmStrategy(strategyAddr).claim(pool.depositToken);
        }
        emit Claim(_userAddr, pending, released);
    }

    function _deposit(address _userAddr, uint256 _pid, uint256 _amount) internal validatePid(_pid) {
        _claim(_userAddr, _pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddr];
        if (pool.depositToken != ETH_ADDR) {
            IERC20(pool.depositToken).safeTransferFrom(_userAddr, address(this), _amount);
        }
        pool.totalDeposited = pool.totalDeposited.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(BASE_NUMBER);
        // earn
        earn(_pid);
        emit Deposit(_userAddr, pool.depositToken, _amount);
    }

    function _withdraw(address _userAddr, uint256 _pid, uint256 _amount) internal validatePid(_pid) {
        _claim(_userAddr, _pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddr];
        if(_amount > user.amount){
            _amount = user.amount;
        }
        pool.totalDeposited = pool.totalDeposited.sub(_amount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(BASE_NUMBER);
        // withdraw
        uint256 bal = IERC20(pool.depositToken).balanceOf(address(this));
        if(bal < _amount){
            address strategyAddr = tokenStrategy[_pid];
            if (strategyAddr != address(0)) {
                IEasyFarmStrategy(strategyAddr).withdraw(pool.depositToken, _amount.sub(bal));
            }
        }
        // transfer
        if (pool.depositToken != ETH_ADDR) {
            IERC20(pool.depositToken).safeTransfer(_userAddr, _amount);
        } else {
            payable(_userAddr).transfer(_amount);
        }
        emit Withdraw(_userAddr, pool.depositToken, _amount);
    }

    function earn(uint256 _pid) public {
        address strategyAddr = tokenStrategy[_pid];
        if (strategyAddr != address(0)) {
            PoolInfo storage pool = poolInfo[_pid];
            uint256 bal;
            if (pool.depositToken != ETH_ADDR) {
                bal = IERC20(pool.depositToken).balanceOf(address(this));
                if(bal >= pool.earnThreshold){
                    IERC20(pool.depositToken).safeTransfer(strategyAddr, bal);
                    IEasyFarmStrategy(strategyAddr).deposit(pool.depositToken);
                }
            } else {
                bal = address(this).balance;
                if(bal >= pool.earnThreshold){
                    payable(strategyAddr).transfer(bal);
                    IEasyFarmStrategy(strategyAddr).deposit(pool.depositToken);
                }
            }
            emit Earn(pool.depositToken, strategyAddr, bal);
        }
    
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastUpdateBlock) {
            return;
        }
        if (pool.totalDeposited == 0) {
            pool.lastUpdateBlock = block.number;
            return;
        }
        uint256 incReward = _incReward(pool.lastUpdateBlock, block.number, pool.rewardPerBlock);
        eft.mint(address(this), incReward);
        // dev & market reward
        uint256 devReward = incReward.mul(devPercents).div(BASE_NUMBER);
        eft.mint(devAddr, devReward);
        uint256 marketReward = incReward.mul(marketPercents).div(BASE_NUMBER);
        eft.mint(marketAddr, marketReward);
        pool.accTokenPerShare = pool.accTokenPerShare.add(
            incReward.mul(BASE_NUMBER).div(pool.totalDeposited)
        );
        pool.lastUpdateBlock = block.number;
        emit UpdatePool(incReward, devReward, marketReward);
    }

    function pendingAll(address _userAddr) external view returns (uint256 totalPending, uint256 totalReleased, uint256 totalLocked){
        for (uint256 i = 0; i < poolInfo.length; i++) {
            (uint256 pending, uint256 released, uint256 locked) = pendingReward(i, _userAddr);
            totalPending = totalPending.add(pending);
            totalReleased = totalReleased.add(released);
            totalLocked = totalLocked.add(locked);
        }
    }

    function pendingReward(uint256 _pid, address _userAddr) public view returns (uint256 pending, uint256 released, uint256 locked) {
        UserInfo storage user = userInfo[_pid][_userAddr];
        if(user.lastRewardBlock > 0){
            PoolInfo storage pool = poolInfo[_pid];
            if (user.amount > 0) {
                uint256 accTokenPerShare = pool.accTokenPerShare;
                uint256 incReward = _incReward(pool.lastUpdateBlock, block.number,  pool.rewardPerBlock);
                accTokenPerShare = accTokenPerShare.add(incReward.mul(BASE_NUMBER).div(pool.totalDeposited));
                pending = user.amount.mul(accTokenPerShare).div(BASE_NUMBER).sub(user.rewardDebt);
            }

            locked = user.locked;
            if (locked > 0) {
                uint256 lastRewardBlock = user.lastRewardBlock;
                if (block.number >= lastRewardBlock.add(lockBlock)) {
                    released = locked;
                } else {
                    released = locked.mul(block.number.sub(lastRewardBlock)).div(lockBlock);
                }
            }
        }
    }

    // total reward from start to now
    function _incReward(uint256 _fromBlock, uint256 _endBlock, uint256 _rewardPerBlock) internal view returns (uint256 reward) {
        uint256 fromBlock;
        if (_endBlock <= startBlock) {
            return 0;
        } else if (_fromBlock < startBlock) {
            fromBlock = startBlock;
        } else {
            fromBlock = _fromBlock;
        }
        reward = _rewardPerBlock.mul(_endBlock.sub(fromBlock));
    }

    function getPoolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }

    function getUserInfo(uint256 _pid, address _user)
        external
        view
        returns (UserInfo memory)
    {
        return userInfo[_pid][_user];
    }

    function getTotalRewardPerBlock() external view returns (uint256) {
        return totalReardPerBlock;
    }

    function setStartBlock(uint256 _startBlock) external onlyOwner {
        startBlock = _startBlock;
    }

    function setLockBlock(uint256 _lockBlock) external onlyOwner {
        lockBlock = _lockBlock;
    }

    function setStrategy(uint256 _pid, address _tokenAddr, address _strategyAddr) external onlyOwner {
        require(poolInfo[_pid].depositToken == _tokenAddr, "token err");
        address _oldStrategy = tokenStrategy[_pid];
        if (_oldStrategy != address(0)) {
            IEasyFarmStrategy(_oldStrategy).withdrawAll(_tokenAddr);
        }
        tokenStrategy[_pid] = _strategyAddr;
    }

    function emergencyWithdrawStrategy(uint256 _pid) external onlyOwner {
        address strategyAddr = tokenStrategy[_pid];
        require(strategyAddr != address(0), "no strategy");
        IEasyFarmStrategy(strategyAddr).emergencyWithdraw(poolInfo[_pid].depositToken);
        tokenStrategy[_pid] = address(0);
    }

    function setRewardPerBlock(uint256 _pid, uint256 _rewardPerBlock, bool _withUpdate) external onlyGov {
        if (_withUpdate) {
            updatePool(_pid);
        }
        PoolInfo storage pool = poolInfo[_pid];
        totalReardPerBlock = totalReardPerBlock.sub(pool.rewardPerBlock);
        pool.rewardPerBlock = _rewardPerBlock;
        totalReardPerBlock = totalReardPerBlock.add(pool.rewardPerBlock);
    }

    function setEarnThreshold(uint256 _pid, uint256 _earnThreshold) external onlyGov {
        PoolInfo storage pool = poolInfo[_pid];
        pool.earnThreshold = _earnThreshold;
    }

    function setDevPercents(uint256 _devPercents) external onlyGov {
        devPercents = _devPercents;
    }

    function setMarketPercents(uint256 _marketPercents) external onlyGov {
        marketPercents = _marketPercents;
    }

    function setGover(address _gover) external onlyGov {
        gover = _gover;
    }

    function setDev(address _devAddr) external onlyAuth {
        devAddr = _devAddr;
    }

    function setMarket(address _marketAddr) external onlyAuth {
        marketAddr = _marketAddr;
    }

    function _safeEFTTransfer(address _to, uint256 _amount) internal {
        uint256 eftBal = eft.balanceOf(address(this));
        if (_amount > eftBal) {
            eft.transfer(_to, eftBal);
        } else {
            eft.transfer(_to, _amount);
        }
    }
}
