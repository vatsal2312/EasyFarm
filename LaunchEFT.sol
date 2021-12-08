// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./EasyFarmToken.sol";

contract LaunchEFT is Ownable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant BASE_NUMBER = 1e18;

    address public busdAddr;
    address public eftAddr;

    struct UserInfo {
        address referral;
        uint256 invited;
        uint256 supported;
        uint256 totalLock;
        uint256 claimDebt;
        uint256 lastClaim;
    }

    mapping(address => UserInfo) private userInfo;

    uint256 private startBlock;
    uint256 private endBlock;
    uint256 private lockBlock;

    uint256 private totalLaunch;
    uint256 private remainLaunch;
    uint256 private burnLaunch;

    uint256 private extraRemain;
    uint256 private extraRate;
    mapping(address => bool) public isExtraRewarded;

    uint256 private minSupport;
    uint256 private totalSupport;

    uint256[] public inviteLevel;
    uint256[] public inviteDiscount;

    event Support(address referral, address userAddr, uint256 amount, uint256 price, uint256 newLock, uint256 extraReward);
    event Claim(address userAddr, uint256 released);
    event BurnRemain(address userAddr, uint256 burnLaunch, uint256 remainLaunch);
    event Withdraw(address userAddr, uint256 amount);

    constructor(
        address _busdAddr, 
        address _eftAddr, 
        uint256 _totalLaunch,
        uint256 _minSupport, 
        uint256 _startBlockOffset, 
        uint256 _endBlockOffset, 
        uint256 _lockBlock,
        uint256 _extraRemain,
        uint256 _extraRate,
        uint256[] memory _inviteLevel,
        uint256[] memory _inviteDiscount
    ) 
    {
        require(inviteLevel.length == inviteDiscount.length, "invite set err");
        busdAddr = _busdAddr;
        eftAddr = _eftAddr;
        totalLaunch = _totalLaunch;
        remainLaunch = _totalLaunch;
        minSupport = _minSupport;
        startBlock = block.number.add(_startBlockOffset);
        endBlock = block.number.add(_endBlockOffset);
        lockBlock = _lockBlock;
        extraRemain = _extraRemain;
        extraRate = _extraRate;
        inviteLevel = _inviteLevel;
        inviteDiscount = _inviteDiscount;
    }


    function support(address _referral, uint256 _amount) public {
        require(block.number >= startBlock && block.number <= endBlock, "ended");
        require(_amount >= minSupport, "amount err");
        require(remainLaunch > 0, "filled");
        UserInfo storage user = userInfo[msg.sender];
        if(userInfo[_referral].supported >= minSupport && _referral != msg.sender && user.referral == address(0)){
            user.referral = _referral;
            userInfo[_referral].invited = userInfo[_referral].invited.add(1);
        }
        IERC20(busdAddr).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 price = getPrice(msg.sender);
        uint256 newLock = _amount.mul(BASE_NUMBER).div(price);
        uint256 extraReward;
        if(extraRemain > 0 && isExtraRewarded[msg.sender] == false){
            extraReward = newLock.mul(extraRate).div(BASE_NUMBER);
            newLock = newLock.add(extraReward);
            isExtraRewarded[msg.sender] = true;
            extraRemain = extraRemain.sub(1);
        }
        if(newLock > remainLaunch){
            uint256 refund = _amount.sub(_amount.mul(remainLaunch).div(newLock));
            newLock = remainLaunch;
            IERC20(busdAddr).safeTransfer(msg.sender, refund);
        }
        remainLaunch = remainLaunch.sub(newLock);
        totalSupport = totalSupport.add(_amount);
        user.totalLock = user.totalLock.add(newLock);
        user.supported = user.supported.add(_amount);
        if(user.lastClaim == 0){
            user.lastClaim = endBlock;
        }

        emit Support(user.referral, msg.sender, _amount, price, newLock, extraReward);
    }

    function claim() public {
        require(block.number > endBlock, "too early");
        UserInfo storage user = userInfo[msg.sender];
        require(user.supported > 0, "not support");
        (uint256 released,) = pending(msg.sender);
        user.lastClaim = block.number;
        user.claimDebt = user.claimDebt.add(released);
        IERC20(eftAddr).safeTransfer(msg.sender, released);
        emit Claim(msg.sender, released);
    }

    function pending(address _userAddr) public view returns(uint256 released, uint256 locked) {
        UserInfo storage user = userInfo[_userAddr];
        locked = user.totalLock.sub(user.claimDebt);
        if(block.number > endBlock && locked > 0){
            released = user.totalLock.mul(block.number.sub(user.lastClaim)).div(lockBlock);
            if(released > locked){
                released = locked;
            }
        }
    }

    function burnRemain() public {
        require(block.number > endBlock, "not end");
        if(remainLaunch > 0){
            EasyFarmToken(eftAddr).burn(remainLaunch);
            burnLaunch = remainLaunch;
            remainLaunch = 0;
        }
        emit BurnRemain(msg.sender, burnLaunch, remainLaunch);
    }

    function getPrice(address _userAddr) public view returns(uint256){
        UserInfo storage user = userInfo[_userAddr];
        uint256 price = BASE_NUMBER.mul(3).div(100);
        for(uint256 i = inviteLevel.length; i > 0; i--){
            if(user.invited >= inviteLevel[i-1]){
                price = price.mul(inviteDiscount[i-1]).div(100);
                break;
            }
        }
        return price;
    }

    function getUserReferral(address _userAddr) external view returns(address) {
        return userInfo[_userAddr].referral;
    }

    function getUserInfo(address _userAddr) external view returns(UserInfo memory) {
        return userInfo[_userAddr];
    }

    function getLaunchInfos() external view returns(uint256[10] memory infos){
        infos[0] = startBlock;
        infos[1] = endBlock;
        infos[2] = lockBlock;
        infos[3] = minSupport;
        infos[4] = totalSupport;
        infos[5] = extraRemain;
        infos[6] = extraRate;
        infos[7] = totalLaunch;
        infos[8] = remainLaunch;
        infos[9] = burnLaunch;
    }

    function setEndBlock(uint256 _endBlock) external onlyOwner {
        endBlock = _endBlock;
    }

    function setLockBlock(uint256 _lockBlock) external onlyOwner {
        lockBlock = _lockBlock;
    }

    function setMinSupport(uint256 _minSupport) external onlyOwner {
        minSupport = _minSupport;
    }

    function setExtraInfo(uint256 _extraRemain, uint256 _extraRate) external onlyOwner {
        extraRemain = _extraRemain;
        extraRate = _extraRate;
    }

    function setTotalLaunch(uint256 _totalLaunch) external onlyOwner {
        totalLaunch = _totalLaunch;
    }

    function setInviteInfo(uint256[] memory _inviteLevel, uint256[] memory _inviteDiscount) external onlyOwner {
        require(_inviteLevel.length == _inviteDiscount.length, "invite set err");
        inviteLevel = _inviteLevel;
        inviteDiscount = _inviteDiscount;
    }

    function withdraw() external onlyOwner {
        uint256 bal = IERC20(busdAddr).balanceOf(address(this));
        IERC20(busdAddr).safeTransfer(msg.sender, bal);
        emit Withdraw(msg.sender, bal);
    }
}
