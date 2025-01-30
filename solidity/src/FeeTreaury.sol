// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract FeeTreasury is Ownable, ReentrancyGuard, Pausable {
    // Treasury controllers
    mapping(address => bool) public controllers;
    
    // Fee shares for different addresses
    mapping(address => uint256) public feeShares;
    
    // Last withdrawal timestamps
    mapping(address => uint256) public lastWithdrawal;
    
    // Constants
    uint256 public constant WITHDRAWAL_DELAY = 24 hours;
    uint256 public constant MAX_WITHDRAWAL = 100 ether;
    uint256 public constant TOTAL_SHARES = 100;

    // Events
    event FeeReceived(address indexed from, uint256 amount);
    event FeeWithdrawn(address indexed to, uint256 amount);
    event SharesUpdated(address indexed account, uint256 shares);
    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);

    constructor(address[] memory _controllers, address[] memory _shareHolders, uint256[] memory _shares) {
        require(_shareHolders.length == _shares.length, "Invalid shares setup");
        
        uint256 totalShares;
        for(uint i = 0; i < _shareHolders.length; i++) {
            require(_shareHolders[i] != address(0), "Invalid address");
            feeShares[_shareHolders[i]] = _shares[i];
            totalShares += _shares[i];
            emit SharesUpdated(_shareHolders[i], _shares[i]);
        }
        require(totalShares == TOTAL_SHARES, "Invalid total shares");

        for(uint i = 0; i < _controllers.length; i++) {
            controllers[_controllers[i]] = true;
            emit ControllerAdded(_controllers[i]);
        }
    }

    modifier onlyController() {
        require(controllers[msg.sender], "Not controller");
        _;
    }

    // Receive fees
    receive() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }

 

    // Add controller
    function addController(address controller) external onlyOwner {
        require(!controllers[controller], "Already controller");
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    // Remove controller
    function removeController(address controller) external onlyOwner {
        require(controllers[controller], "Not a controller");
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    // Withdraw fees with delay and limit
    function withdrawFees() external nonReentrant whenNotPaused {
        require(feeShares[msg.sender] > 0, "No fee shares");
        require(block.timestamp >= lastWithdrawal[msg.sender] + WITHDRAWAL_DELAY, "Too soon");
        
        uint256 balance = address(this).balance;
        uint256 share = (balance * feeShares[msg.sender]) / TOTAL_SHARES;
        require(share > 0, "Nothing to withdraw");
        
        // Apply maximum withdrawal limit
        uint256 withdrawAmount = share > MAX_WITHDRAWAL ? MAX_WITHDRAWAL : share;
        
        lastWithdrawal[msg.sender] = block.timestamp;
        
        (bool success, ) = msg.sender.call{value: withdrawAmount}("");
        require(success, "Transfer failed");
        
        emit FeeWithdrawn(msg.sender, withdrawAmount);
    }

    // Emergency withdrawal by multiple controllers
    function emergencyWithdraw(address payable to, uint256 amount) external onlyController {
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FeeWithdrawn(to, amount);
    }

    // View functions
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getShareHolders() public view returns (address[] memory) {
        uint256 count;
        for(uint i = 0; i < 100; i++) {
            address holder = address(uint160(i));
            if(feeShares[holder] > 0) count++;
        }
        
        address[] memory holders = new address[](count);
        uint256 index;
        for(uint i = 0; i < 100; i++) {
            address holder = address(uint160(i));
            if(feeShares[holder] > 0) {
                holders[index] = holder;
                index++;
            }
        }
        return holders;
    }

    // Emergency controls
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}