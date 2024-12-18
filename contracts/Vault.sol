// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

contract Vault {
    mapping(address => uint256) public balances;

    address public player;

    constructor(address _player) public payable {
        player = _player;
    }

    function deposit(address _to) public payable {
        balances[_to] += msg.value;
    }

    function withdraw(uint256 _amount) public {
        if (balances[msg.sender] >= _amount) {
            (bool success,) = msg.sender.call{value: _amount}("");
            require(success, "call failed");
            balances[msg.sender] -= _amount;
        }
    }

    function balanceOf(address _who) public view returns (uint256 balance) {
        return balances[_who];
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}