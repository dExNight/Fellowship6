// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOracle {
    event AssetAdded(uint256 indexed assetId, address indexed token);
    event Deposit(address indexed user, uint256 indexed assetId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed assetId, uint256 amount);
    event Borrow(address indexed user, uint256 indexed assetId, uint256 amount);
    event Repay(address indexed user, uint256 indexed assetId, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        uint256 indexed assetId,
        uint256 amount,
        uint256 collateralAssetId,
        uint256 collateralAmount
    );

    struct Asset {
        IERC20 token;
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 baseRate;
    }

    struct UserAccount {
        mapping(uint256 => uint256) deposited;
        mapping(uint256 => uint256) borrowed;
        mapping(uint256 => uint256) lastInterestBlock;
    }

    // 

    function deposit(uint256 _assetId, uint256 _amount) external;
    function borrow(uint256 _assetId, uint256 _amount) external;
    function liquidate(
        address _borrower, 
        uint256 _assetId, 
        uint256 _amount, 
        uint256 _collateralAssetId
    ) external;

    function getUserAccount(
        address user, 
        uint256 depositAssetId, 
        uint256 borrowAssetId, 
        uint256 interestAssetId
    ) external view returns (uint256, uint256, uint256);
    function calculateHealthFactor(address _user) external view returns (uint256);
    function getAssetPrice(uint256 _assetId) external view returns (uint256);
    function getInterestRate(uint256 _assetId) external view returns (uint256);

    function addAsset(address _token, uint256 _baseRate) external;
    function setPriceOracle(uint256 _assetId, address _priceOracle) external;
    function isSolved() external view returns (bool);

    function assets(uint256 _assetId) external view returns (
        IERC20 token,
        uint256 totalDeposited,
        uint256 totalBorrowed,
        uint256 baseRate
    );
    
    function assetCount() external view returns (uint256);
    
    function player() external view returns (address);
    
    function priceOracles(uint256 _assetId) external view returns (address);

    function LIQUIDATION_CLOSE_FACTOR() external pure returns (uint256);  // 100
    function PRECISION() external pure returns (uint256);                 // 1e18
    function MAX_LOOPS() external pure returns (uint256);                 // 10
    function BAD_DEBT_RATIO() external pure returns (uint256);           // 110
    function MIN_HEALTH_FACTOR() external pure returns (uint256);  
}

interface IPriceOracle {
    function getAssetPrice(uint256 _assetId) external view returns (uint256);
}

interface ICurvePriceOracle is IPriceOracle {
    function curvePool() external view returns (address);
    function idx() external view returns (uint256);
    function getSpotPrice() external view returns (uint256);
}

interface ISimplePriceOracle is IPriceOracle {
    function price() external view returns (uint256);
    function owner() external view returns (address);
    function setPrice(uint256 _price) external;
}

interface ICurve {
    // Основные функции ликвидности
    function add_liquidity(
        uint256[] calldata amounts,
        uint256 min_mint_amount
    ) external returns (uint256);
    
    function remove_liquidity(
        uint256 amount,
        uint256[] calldata min_amounts
    ) external returns (uint256[] memory);
    
    function remove_liquidity_imbalance(
        uint256[] calldata amounts,
        uint256 max_burn_amount
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        uint256 token_amount,
        int128 i,
        uint256 min_amount
    ) external returns (uint256);

    // Функции обмена
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    // Функции просмотра цен
    function get_virtual_price() external view returns (uint256);
    function price_oracle(uint256 idx) external view returns (uint256);
    function last_price(uint256 idx) external view returns (uint256);
    
    // Функции просмотра состояния пула
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
    
    function balances(uint256 i) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
}