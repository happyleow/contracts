// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    struct SaleInfo {
        uint256 stableTokenAmount;
        uint256 loopTokenAmount;
    }

    mapping(address => bool) public whitelists;
    mapping(address => SaleInfo) public presaleList;
    mapping(address => bool) public acceptTokens;

    bool private isPause;
    uint8 public constant maxDecimals = 18;

    address public immutable loopAddress;
    uint256 public immutable saleStartTime;
    uint256 public immutable saleEndTime;
    uint256 public immutable fcfsMinutes;
    uint256 public immutable tokenPrice;
    uint256 public immutable allowedTokenAmount;
    uint256 public saledToken;
    uint256 public immutable presaleTokenAmount;

    event TokenPurchased(address userAddress, uint256 purchasedAmount);
    event TokenClaimed(address userAddress, uint256 purchasedAmount);

    constructor(
        address _loopAddress, 
        uint256 _saleStartTime, 
        uint256 _saleEndTime, 
        uint256 _fcfsMinutes, 
        uint256 _tokenPrice, 
        uint256 _allowedTokenAmount,
        address[] memory _acceptTokens,
        uint256 _presaleTokenAmount
        ) {
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        fcfsMinutes = _fcfsMinutes;
        tokenPrice = _tokenPrice;
        allowedTokenAmount = _allowedTokenAmount;
        loopAddress = _loopAddress;
        for (uint i = 0; i < _acceptTokens.length; i ++) {
            acceptTokens[_acceptTokens[i]] = true;
        }
        presaleTokenAmount = _presaleTokenAmount;
        isPause = false;
    }

    modifier executable() {
        require(!isPause, "Contract is paused");
        _;
    }

    modifier checkEventTime() {
        require(block.timestamp >= saleStartTime && block.timestamp <= saleEndTime, "Out of presale period");
        _;
    }

    modifier checkAfterTime() {
        require(block.timestamp > saleEndTime, "Presale not finished");
        _;
    }

    function getSaledToken() public view returns(uint) {
        return saledToken;
    }

    function stopContract(bool _pause) external onlyOwner {
        isPause = _pause;
    }
    
    function getPauseStatus() external view returns(bool) {
        return isPause;
    }
    
    function addWhitelist(address whiteAddress) external executable onlyOwner {
        whitelists[whiteAddress] = true;
    }

    function removeWhitelist(address whiteAddress) external executable onlyOwner {
        whitelists[whiteAddress] = false;
    }

    function buyToken(address stableTokenAddress, uint256 amount) external executable checkEventTime {
        require(whitelists[msg.sender] == true, "Not whitelist address");
        require(acceptTokens[stableTokenAddress] == true, "Not stableToken address");
        SaleInfo storage saleInfo = presaleList[msg.sender];
        uint8 tokenDecimal = ERC20(stableTokenAddress).decimals();
        uint256 tokenAmount = amount;
        if (tokenDecimal < maxDecimals) {
            tokenAmount = tokenAmount * 10 ** (maxDecimals - tokenDecimal);
        }
        uint256 loopTokenAmount = tokenAmount * 10 ** ERC20(loopAddress).decimals() / tokenPrice;
        require(saledToken + loopTokenAmount <= presaleTokenAmount, "All Loop Tokens are sold out");
        if (block.timestamp >= saleEndTime - fcfsMinutes * 1 minutes) {
            require(saleInfo.stableTokenAmount + tokenAmount <= allowedTokenAmount * 2, 
                "Exceeding presale token limit during FCFS period");
        } else if (block.timestamp < saleEndTime - fcfsMinutes * 1 minutes) {
            require(saleInfo.stableTokenAmount + tokenAmount <= allowedTokenAmount, 
                "Exceeding presale token limit during round1 period");
        }
        saleInfo.stableTokenAmount = saleInfo.stableTokenAmount + tokenAmount;
        saleInfo.loopTokenAmount = saleInfo.loopTokenAmount + loopTokenAmount;
        saledToken = saledToken + loopTokenAmount;
        IERC20(stableTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        emit TokenPurchased(msg.sender, loopTokenAmount);
    }
    
    function claimToken() external executable checkAfterTime {
        SaleInfo storage saleInfo = presaleList[msg.sender];
        require(saleInfo.loopTokenAmount > 0, "No claimToken amount");

        uint loopTokenAmount = saleInfo.loopTokenAmount;
        saleInfo.stableTokenAmount = 0;
        saleInfo.loopTokenAmount = 0;
        uint balance = IERC20(loopAddress).balanceOf(address(this));
        require(balance > 0, "Insufficient balance");
        if (balance < loopTokenAmount) {
            loopTokenAmount = balance;
        }
        IERC20(loopAddress).safeTransfer(msg.sender, loopTokenAmount);
        emit TokenClaimed(msg.sender, loopTokenAmount);
    }

    function withdrawAllToken(address withdrawAddress, address[] calldata stableTokens) external executable onlyOwner checkAfterTime {
        uint loopTokenAmount = IERC20(loopAddress).balanceOf(address(this));
        IERC20(loopAddress).safeTransfer(withdrawAddress, loopTokenAmount);
        for (uint i = 0; i < stableTokens.length; i ++) {
            uint stableTokenAmount = IERC20(stableTokens[i]).balanceOf(address(this));
            IERC20(stableTokens[i]).safeTransfer(withdrawAddress, stableTokenAmount);
        }
    }

    function giveBackToken(address withdrawAddress, address tokenAddress) external executable onlyOwner checkAfterTime {
        require(acceptTokens[tokenAddress] == false, "Can not withdraw stable tokens");
        require(loopAddress != tokenAddress, "Can not withdraw loop tokens");
        uint tokenAmount = IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).safeTransfer(withdrawAddress, tokenAmount);
    }
}
