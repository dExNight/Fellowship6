// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface SwapCallback {
    function doSwap() external;
}

contract Setup {
    Exchange public immutable exchange = new Exchange();

    uint256 balance1 = 300_000;
    uint256 balance2 = 300_000;
    uint256 balance3 = 600_000;

    Token public token1 = new Token(balance1);
    Token public token2 = new Token(balance2);
    Token public token3 = new Token(balance3);

    constructor() {
        exchange.addToken(address(token1));
        exchange.addToken(address(token2));
        exchange.addToken(address(token3));

        token1.approve(address(exchange), balance1);
        token2.approve(address(exchange), balance2);
        token3.approve(address(exchange), balance3);

        exchange.addLiquidity(address(token1), address(token2), balance1 / 3, balance2 / 3);

        exchange.addLiquidity(address(token1), address(token3), balance1 / 3, balance3 / 3);

        exchange.addLiquidity(address(token2), address(token3), balance2 / 3, balance3 / 3);
    }

    function isSolved() public view returns (bool) {
        return (
            Token(token1).balanceOf(address(exchange)) == 0 && Token(token2).balanceOf(address(exchange)) == 0
                && Token(token3).balanceOf(address(exchange)) == 0
        );
    }
}

contract Exchange {
    struct Pool {
        uint256 leftReserves;
        uint256 rightReserves;
    }

    struct SavedBalance {
        bool initiated;
        uint256 balance;
    }

    struct SwapState {
        bool hasBegun;
        uint256 unsettledTokens;
        mapping(address => int256) positions;
        mapping(address => SavedBalance) savedBalances;
    }

    address public admin;
    uint256 nonce = 0;
    mapping(address => bool) public allowedTokens;
    mapping(uint256 => SwapState) private swapStates;
    mapping(address => mapping(address => Pool)) private pools;

    constructor() {
        admin = msg.sender;
    }

    function addToken(address token) public {
        require(msg.sender == admin, "not admin");
        allowedTokens[token] = true;
    }

    modifier duringSwap() {
        require(swapStates[nonce].hasBegun, "swap not in progress");
        _;
    }

    function getSwapState() internal view returns (SwapState storage) {
        return swapStates[nonce];
    }

    function getPool(address tokenA, address tokenB)
        internal
        view
        returns (address left, address right, Pool storage pool)
    {
        require(tokenA != tokenB);

        if (tokenA < tokenB) {
            left = tokenA;
            right = tokenB;
        } else {
            left = tokenB;
            right = tokenA;
        }

        pool = pools[left][right];
    }

    function getReserves(address token, address other) public view returns (uint256) {
        (address left,, Pool storage pool) = getPool(token, other);
        return token == left ? pool.leftReserves : pool.rightReserves;
    }

    function setReserves(address token, address other, uint256 amount) internal {
        (address left,, Pool storage pool) = getPool(token, other);

        if (token == left) pool.leftReserves = amount;
        else pool.rightReserves = amount;
    }

    function getLiquidity(address left, address right) public view returns (uint256) {
        (,, Pool storage pool) = getPool(left, right);
        return pool.leftReserves * pool.rightReserves;
    }

    function addLiquidity(address left, address right, uint256 amountLeft, uint256 amountRight) public {
        require(allowedTokens[left], "token not allowed");
        require(allowedTokens[right], "token not allowed");

        Token(left).transferFrom(msg.sender, address(this), amountLeft);
        Token(right).transferFrom(msg.sender, address(this), amountRight);

        setReserves(left, right, getReserves(left, right) + amountLeft);
        setReserves(right, left, getReserves(right, left) + amountRight);
    }

    function swap() external {
        SwapState storage swapState = getSwapState();

        require(!swapState.hasBegun, "swap already in progress");
        swapState.hasBegun = true;

        SwapCallback(msg.sender).doSwap();

        require(swapState.unsettledTokens == 0, "not settled");
        nonce += 1;
    }

    function updatePosition(address token, int256 amount) internal {
        require(allowedTokens[token], "token not allowed");

        SwapState storage swapState = getSwapState();

        int256 currentPosition = swapState.positions[token];
        int256 newPosition = currentPosition + amount;

        if (newPosition == 0) swapState.unsettledTokens -= 1;
        else if (currentPosition == 0) swapState.unsettledTokens += 1;

        swapState.positions[token] = newPosition;
    }

    function withdraw(address token, uint256 amount) public duringSwap {
        require(allowedTokens[token], "token not allowed");

        Token(token).transfer(msg.sender, amount);
        updatePosition(token, -int256(amount));
    }

    function initiateTransfer(address token) public duringSwap {
        require(allowedTokens[token], "token not allowed");

        SwapState storage swapState = getSwapState();
        SavedBalance storage state = swapState.savedBalances[token];

        require(!state.initiated, "transfer already initiated");

        state.initiated = true;
        state.balance = Token(token).balanceOf(address(this));
    }

    function finalizeTransfer(address token) public duringSwap {
        require(allowedTokens[token], "token not allowed");

        SwapState storage swapState = getSwapState();
        SavedBalance storage state = swapState.savedBalances[token];

        require(state.initiated, "transfer not initiated");

        uint256 balance = Token(token).balanceOf(address(this));
        uint256 amount = balance - state.balance;

        state.initiated = false;
        updatePosition(token, int256(amount));
    }

    function swapTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) public duringSwap {
        require(allowedTokens[tokenIn], "token not allowed");
        require(allowedTokens[tokenOut], "token not allowed");

        uint256 liquidityBefore = getLiquidity(tokenIn, tokenOut);

        require(liquidityBefore > 0, "no liquidity");

        uint256 newReservesIn = getReserves(tokenIn, tokenOut) + amountIn;
        uint256 newReservesOut = getReserves(tokenOut, tokenIn) - amountOut;

        setReserves(tokenIn, tokenOut, newReservesIn);
        setReserves(tokenOut, tokenIn, newReservesOut);

        uint256 liquidityAfter = getLiquidity(tokenIn, tokenOut);

        updatePosition(tokenIn, -int256(amountIn));
        updatePosition(tokenOut, int256(amountOut));

        require(liquidityAfter >= liquidityBefore, "insufficient liquidity");
    }
}

contract Token {
    uint256 public totalSupply;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    constructor(uint256 _initialAmount) {
        balances[msg.sender] = _initialAmount;
        totalSupply = _initialAmount;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        require(balances[msg.sender] >= _value);
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(allowed[_from][msg.sender] >= _value);
        require(balances[_from] >= _value);
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        return true;
    }
}