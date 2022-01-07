// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Lynkey is ERC20Burnable, Pausable, Ownable {
	address ecosystemWallet; 
	address crowdsaleWallet; 
	address stakingRewardWallet;
	address reserveLiquidityWallet;
	address teamWallet;
	address partnerWallet;
	
    // #tokens at at issuance; actual token supply tokenSupply() may be less due to possible future token burning 
	uint256 private totalSupplyAtBirth = 1000000000; 

    uint256 tokenPublicListingTime = 0; // will be set to the time of public exchange listing 
    
    struct LockItem {
        uint256  releaseTime;
        uint256  amount;
    }
    mapping (address => LockItem[]) public lockList;
    address [] private listOfAddressesWithLockedFund; // list of addresses that have some fund currently or previously locked
    
    function decimals() public pure override returns (uint8) {
        return 8;
    }
    function renounceOwnership() public override onlyOwner {
        // for safety of this contract, do not allow renounceOwnership
    }
    
	constructor(
	    address _crowdsaleWallet,
	    address _ecosystemWallet,
	    address _stakingRewardWallet,
	    address _reserveLiquidityWallet,
	    address _teamWallet,
	    address _partnerWallet) ERC20("Lynkey", "LYNK") {  
	        
        require(
            _crowdsaleWallet != address(0) && 
            _ecosystemWallet != address(0) &&
            _stakingRewardWallet != address(0) &&
            _reserveLiquidityWallet != address(0) &&
            _teamWallet != address(0) &&
            _partnerWallet != address(0)
        );

	    _mint(owner(), totalSupplyAtBirth * 10 ** uint256(decimals())); 
       
        crowdsaleWallet = _crowdsaleWallet;
	    ecosystemWallet = _ecosystemWallet;
	    stakingRewardWallet = _stakingRewardWallet;
	    reserveLiquidityWallet = _reserveLiquidityWallet;
	    teamWallet = _teamWallet;
	    partnerWallet = _partnerWallet;
	        
        ERC20.transfer(crowdsaleWallet, totalSupplyAtBirth * 10 ** uint256(decimals()) * 25/100); //25% allocation
        
        transferAndLockLinearly(ecosystemWallet,  totalSupplyAtBirth * 10 ** uint256(decimals())* 20/100, block.timestamp, 36, 2629800); // releasing equally for the next 36 30-day periods (3 years)
        transferAndLockLinearly(reserveLiquidityWallet, totalSupplyAtBirth * 10 ** uint256(decimals()) * 23/100, block.timestamp, 36, 2629800); // releasing equally for the next 36 30-day periods (3 years)
        
        _pause();
    }
    
    /**
     * @dev transfer fund and lock to release periodically
     */
    function transferAndLockLinearly(address _wallet, uint256 _amountSum, uint256 _startTime, uint8 _forHowManyPeriods, uint256 _periodInSeconds) public {
        require(isAdminWallet(msg.sender), "No permission to transfer and lock. Sender must be an Admin address");
        
        transfer(_wallet, _amountSum);
        
         if (lockList[_wallet].length==0) listOfAddressesWithLockedFund.push(_wallet);
         uint256 amount = _amountSum/_forHowManyPeriods;
         
         for(uint8 i = 0; i< _forHowManyPeriods; i++) {
            uint256 releaseTime = _startTime + uint256(i)*_periodInSeconds; 
            if (i==_forHowManyPeriods-1) {
                // last month
                amount += (balanceOf(_wallet) - amount * _forHowManyPeriods); // all the rest
            }
    	    lockFund(_wallet, amount, releaseTime);
         }
    }
	
	function startTokenPublicListing() external onlyOwner {
	    // can only call 1 time: when token is ready for public sale on exchange
	    require(tokenPublicListingTime == 0, "Token public listing already started"); 
	    
	    tokenPublicListingTime = block.timestamp;
	    
	    // now is the time to transfer fund to Team, Partner, Reward Wallets
	    // but lock these wallets, and only release monthly equally for the next 36 30-day periods (3 years)
        transferAndLockLinearly(teamWallet, totalSupplyAtBirth * 10 ** uint256(decimals()) * 12/100, tokenPublicListingTime, 36, 2629800); 
        transferAndLockLinearly(partnerWallet, totalSupplyAtBirth * 10 ** uint256(decimals()) * 10/100, tokenPublicListingTime, 36, 2629800); 
        transferAndLockLinearly(stakingRewardWallet, totalSupplyAtBirth * 10 ** uint256(decimals()) * 10/100, tokenPublicListingTime, 36, 2629800); 

        _unpause();
    }
	
	receive () payable external {   
        revert();
    }
    
    fallback () payable external {   
        revert();
    }
    
    
    /**
     * @dev check if this address is one of the system's reserve wallets
     * @return the bool true if success.
     * @param _addr The address to verify.
     */
    function isAdminWallet(address _addr) private view returns (bool) {
        return (
            _addr == crowdsaleWallet || 
            _addr == ecosystemWallet ||
            _addr == stakingRewardWallet ||
            _addr == reserveLiquidityWallet ||
            _addr == teamWallet ||
            _addr == partnerWallet ||
            _addr == owner()
        );
    }
    
     /**
     * @dev transfer of token to another address.
     * always require the sender has enough balance
     * @return the bool true if success. 
     * @param _receiver The address to transfer to.
     * @param _amount The amount to be transferred.
     */
     
	function transfer(address _receiver, uint256 _amount) public override returns (bool) {
	    require(!paused() || isAdminWallet(msg.sender), "cannot transfer during this time");
	    require(_amount > 0, "amount must be larger than 0");
        require(_receiver != address(0), "cannot send to the zero address");
        require(msg.sender != _receiver, "receiver cannot be the same as sender");
	    require(_amount <= getAvailableBalance(msg.sender), "not enough enough fund to transfer");
        return ERC20.transfer(_receiver, _amount);
	}
	
	/**
     * @dev transfer of token on behalf of the owner to another address. 
     * always require the owner has enough balance and the sender is allowed to transfer the given amount
     * @return the bool true if success. 
     * @param _from The address to transfer from.
     * @param _receiver The address to transfer to.
     * @param _amount The amount to be transferred.
     */
    function transferFrom(address _from, address _receiver, uint256 _amount) public override  returns (bool) {
        require(!paused() || isAdminWallet(msg.sender), "cannot transfer during this time");
        require(_amount > 0, "amount must be larger than 0");
        require(_receiver != address(0), "cannot send to the zero address");
        require(_from != _receiver, "receiver cannot be the same as sender");
        require(_amount <= getAvailableBalance(_from), "not enough enough fund to transfer");
        return ERC20.transferFrom(_from, _receiver, _amount);
    }

    /**
     * @dev transfer to a given address a given amount and lock this fund until a given time
     * used for sending fund to team members, partners, or for owner to lock service fund over time
     * @return the bool true if success.
     * @param _receiver The address to transfer to.
     * @param _amount The amount to transfer.
     * @param _releaseTime The date to release token.
     */
	
	function transferAndLock(address _receiver, uint256 _amount, uint256 _releaseTime) public  returns (bool) {
	    require(isAdminWallet(msg.sender), "no permission to transfer and lock");
	    require(_amount > 0, "amount must be larger than 0");
        require(_receiver != address(0), "cannot send to the zero address");
        require(msg.sender != _receiver, "receiver cannot be the same as sender");
        require(_amount <= getAvailableBalance(msg.sender), "not enough enough fund to transfer");
        
	    ERC20.transfer(_receiver,_amount);
    	lockFund(_receiver, _amount, _releaseTime);
		
        return true;
	}
	
	
	
	/**
     * @dev set a lock to free a given amount only to release at given time
     */
	function lockFund(address _addr, uint256 _amount, uint256 _releaseTime) private {
	    if (lockList[_addr].length==0) listOfAddressesWithLockedFund.push(_addr);
    	LockItem memory item = LockItem({amount:_amount, releaseTime:_releaseTime});
		lockList[_addr].push(item);
	} 
	
	
    /**
     * @return the total amount of locked funds of a given address.
     * @param lockedAddress The address to check.
     */
	function getLockedAmount(address lockedAddress) private view returns(uint256) {
	    uint256 lockedAmount =0;
	    for(uint256 j = 0; j<lockList[lockedAddress].length; j++) {
	        if(block.timestamp < lockList[lockedAddress][j].releaseTime) {
	            uint256 temp = lockList[lockedAddress][j].amount;
	            lockedAmount += temp;
	        }
	    }
	    return lockedAmount;
	}
	
	/**
     * @return the total amount of locked funds of a given address.
     * @param lockedAddress The address to check.
     */
	function getAvailableBalance(address lockedAddress) public view returns(uint256) {
	    uint256 bal = balanceOf(lockedAddress);
	    uint256 locked = getLockedAmount(lockedAddress);
        if (bal <= locked) return 0;
	    return bal-locked;
	}

	    
}


