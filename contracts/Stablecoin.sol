// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library ProtocolMath {
    uint256 internal constant ONE = 1e18;
    uint256 internal constant MINUTES_1000_YEARS = 525_600_000;

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * ONE) / b;
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        } else {
            return (((a * ONE) - 1) / b) + 1;
        }
    }

    function _decMul(uint256 x, uint256 y) internal pure returns (uint256 decProd) {
        decProd = (x * y + ONE / 2) / ONE;
    }

    function _decPow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) {
            return ONE;
        }

        uint256 y = ONE;
        uint256 x = base;
        uint256 n = Math.min(exponent, MINUTES_1000_YEARS);

        while (n > 1) {
            if (n % 2 != 0) {
                y = _decMul(x, y);
            }
            x = _decMul(x, x);
            n /= 2;
        }

        return _decMul(x, y);
    }

    function _computeHealth(uint256 collateral, uint256 debt, uint256 price) internal pure returns (uint256) {
        return debt > 0 ? collateral * price / debt : type(uint256).max;
    }
}

abstract contract ManagerAccess {
    address public immutable manager;

    error Unauthorized(address caller);

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    constructor(address _manager) {
        manager = _manager;
    }
}

contract PriceFeed {
    function fetchPrice() external pure returns (uint256, uint256) {
        return (2207 ether, 0.01 ether);
    }
}

contract Token is ERC20, ManagerAccess {
    constructor(address _manager, string memory _id) ERC20(_id, _id) ManagerAccess(_manager) {}

    function mint(address to, uint256 amount) external onlyManager {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyManager {
        _burn(from, amount);
    }
}

contract ERC20Signal is ERC20, ManagerAccess {
    using ProtocolMath for uint256;

    uint256 public signal;

    constructor(address _manager, uint256 _signal, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ManagerAccess(_manager)
    {
        signal = _signal;
    }

    function mint(address to, uint256 amount) external onlyManager {
        _mint(to, amount.divUp(signal));
    }

    function burn(address from, uint256 amount) external onlyManager {
        _burn(from, amount == type(uint256).max ? ERC20.balanceOf(from) : amount.divUp(signal));
    }

    function setSignal(uint256 backingAmount) external onlyManager {
        uint256 supply = ERC20.totalSupply();
        uint256 newSignal = (backingAmount == 0 && supply == 0) ? ProtocolMath.ONE : backingAmount.divUp(supply);
        signal = newSignal;
    }

    function totalSupply() public view override returns (uint256) {
        return ERC20.totalSupply().mulDown(signal);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return ERC20.balanceOf(account).mulDown(signal);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert();
    }

    function allowance(address, address) public view virtual override returns (uint256) {
        revert();
    }

    function approve(address, uint256) public virtual override returns (bool) {
        revert();
    }

    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert();
    }

    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert();
    }

    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert();
    }
}

contract Manager is Ownable {
    using SafeERC20 for IERC20;
    using ProtocolMath for uint256;

    uint256 public constant MIN_DEBT = 3000e18;
    uint256 public constant MIN_CR = 130 * ProtocolMath.ONE / 100; // 130%
    uint256 public constant DECAY_FACTOR = 999_027_758_833_783_000;

    Token public immutable mim;

    mapping(address => IERC20) public positionCollateral;
    mapping(IERC20 => Collateral) public collateralData;

    struct Collateral {
        ERC20Signal protocolCollateralToken;
        ERC20Signal protocolDebtToken;
        PriceFeed priceFeed;
        uint256 operationTime;
        uint256 baseRate;
    }

    error NothingToLiquidate();
    error CannotLiquidateLastPosition();
    error RedemptionSpreadOutOfRange();
    error NoCollateralOrDebtChange();
    error InvalidPosition();
    error NewICRLowerThanMCR(uint256 newICR);
    error NetDebtBelowMinimum(uint256 netDebt);
    error FeeExceedsMaxFee(uint256 fee, uint256 amount, uint256 maxFeePercentage);
    error PositionCollateralTokenMismatch();
    error CollateralTokenAlreadyAdded();
    error CollateralTokenNotAdded();
    error SplitLiquidationCollateralCannotBeZero();
    error WrongCollateralParamsForFullRepayment();

    constructor() {
        mim = new Token(address(this), "MIM");
    }

    function manage(
        IERC20 token,
        uint256 collateralDelta,
        bool collateralIncrease,
        uint256 debtDelta,
        bool debtIncrease
    ) external returns (uint256, uint256) {
        if (address(collateralData[token].protocolCollateralToken) == address(0)) {
            revert CollateralTokenNotAdded();
        }

        if (positionCollateral[msg.sender] != IERC20(address(0)) && positionCollateral[msg.sender] != token) {
            revert PositionCollateralTokenMismatch();
        }

        if (collateralDelta == 0 && debtDelta == 0) {
            revert NoCollateralOrDebtChange();
        }

        Collateral memory collateralTokenInfo = collateralData[token];
        ERC20Signal protocolCollateralToken = collateralTokenInfo.protocolCollateralToken;
        ERC20Signal protocolDebtToken = collateralTokenInfo.protocolDebtToken;

        uint256 debtBefore = protocolDebtToken.balanceOf(msg.sender);
        if (!debtIncrease && (debtDelta == type(uint256).max || (debtBefore != 0 && debtDelta == debtBefore))) {
            if (collateralDelta != 0 || collateralIncrease) {
                revert WrongCollateralParamsForFullRepayment();
            }
            collateralDelta = protocolCollateralToken.balanceOf(msg.sender);
            debtDelta = debtBefore;
        }

        _updateDebt(token, protocolDebtToken, debtDelta, debtIncrease);
        _updateCollateral(token, protocolCollateralToken, collateralDelta, collateralIncrease);

        uint256 debt = protocolDebtToken.balanceOf(msg.sender);
        uint256 collateral = protocolCollateralToken.balanceOf(msg.sender);

        if (debt == 0) {
            if (collateral != 0) {
                revert InvalidPosition();
            }
            _closePosition(protocolCollateralToken, protocolDebtToken, msg.sender, false);
        } else {
            _checkPosition(token, debt, collateral);

            if (debtBefore == 0) {
                positionCollateral[msg.sender] = token;
            }
        }
        return (collateralDelta, debtDelta);
    }

    function liquidate(address liquidatee) external {
        IERC20 token = positionCollateral[liquidatee];

        if (address(token) == address(0)) {
            revert NothingToLiquidate();
        }

        Collateral memory collateralTokenInfo = collateralData[token];
        ERC20Signal protocolCollateralToken = collateralTokenInfo.protocolCollateralToken;
        ERC20Signal protocolDebtToken = collateralTokenInfo.protocolDebtToken;

        uint256 wholeCollateral = protocolCollateralToken.balanceOf(liquidatee);
        uint256 wholeDebt = protocolDebtToken.balanceOf(liquidatee);

        (uint256 price,) = collateralTokenInfo.priceFeed.fetchPrice();
        uint256 health = ProtocolMath._computeHealth(wholeCollateral, wholeDebt, price);

        if (health >= MIN_CR) {
            revert NothingToLiquidate();
        }

        uint256 totalDebt = protocolDebtToken.totalSupply();
        if (wholeDebt == totalDebt) {
            revert CannotLiquidateLastPosition();
        }

        if (!(health <= ProtocolMath.ONE)) {
            mim.burn(msg.sender, wholeDebt);
            totalDebt -= wholeDebt;
        }

        token.safeTransfer(msg.sender, wholeCollateral);

        _closePosition(protocolCollateralToken, protocolDebtToken, liquidatee, true);

        _updateSignals(token, protocolCollateralToken, protocolDebtToken, totalDebt);
    }

    function addCollateralToken(IERC20 token, PriceFeed priceFeed, uint256 collateralSignal, uint256 debtSignal)
        external
        onlyOwner
    {
        ERC20Signal protocolCollateralToken = new ERC20Signal(
            address(this),
            collateralSignal,
            string(bytes.concat("MIM ", bytes(IERC20Metadata(address(token)).name()), " collateral")),
            string(bytes.concat("mim", bytes(IERC20Metadata(address(token)).symbol()), "-c"))
        );
        ERC20Signal protocolDebtToken = new ERC20Signal(
            address(this),
            debtSignal,
            string(bytes.concat("MIM ", bytes(IERC20Metadata(address(token)).name()), " debt")),
            string(bytes.concat("mim", bytes(IERC20Metadata(address(token)).symbol()), "-d"))
        );

        if (address(collateralData[token].protocolCollateralToken) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }

        Collateral memory protocolCollateralTokenInfo;
        protocolCollateralTokenInfo.protocolCollateralToken = protocolCollateralToken;
        protocolCollateralTokenInfo.protocolDebtToken = protocolDebtToken;
        protocolCollateralTokenInfo.priceFeed = priceFeed;

        collateralData[token] = protocolCollateralTokenInfo;
    }

    function _updateDebt(IERC20 token, ERC20Signal protocolDebtToken, uint256 debtDelta, bool debtIncrease) internal {
        if (debtDelta == 0) {
            return;
        }

        if (debtIncrease) {
            _decayRate(token);

            protocolDebtToken.mint(msg.sender, debtDelta);
            mim.mint(msg.sender, debtDelta);
        } else {
            protocolDebtToken.burn(msg.sender, debtDelta);
            mim.burn(msg.sender, debtDelta);
        }
    }

    function _updateCollateral(
        IERC20 token,
        ERC20Signal protocolCollateralToken,
        uint256 collateralDelta,
        bool collateralIncrease
    ) internal {
        if (collateralDelta == 0) {
            return;
        }

        if (collateralIncrease) {
            protocolCollateralToken.mint(msg.sender, collateralDelta);
            token.safeTransferFrom(msg.sender, address(this), collateralDelta);
        } else {
            protocolCollateralToken.burn(msg.sender, collateralDelta);
            token.safeTransfer(msg.sender, collateralDelta);
        }
    }

    function _updateSignals(
        IERC20 token,
        ERC20Signal protocolCollateralToken,
        ERC20Signal protocolDebtToken,
        uint256 totalDebtForCollateral
    ) internal {
        protocolDebtToken.setSignal(totalDebtForCollateral);
        protocolCollateralToken.setSignal(token.balanceOf(address(this)));
    }

    function updateSignal(ERC20Signal token, uint256 signal) external onlyOwner {
        token.setSignal(signal);
    }

    function _closePosition(
        ERC20Signal protocolCollateralToken,
        ERC20Signal protocolDebtToken,
        address position,
        bool burn
    ) internal {
        positionCollateral[position] = IERC20(address(0));

        if (burn) {
            protocolDebtToken.burn(position, type(uint256).max);
            protocolCollateralToken.burn(position, type(uint256).max);
        }
    }

    function _decayRate(IERC20 token) internal {
        uint256 decayedRate = _calcDecayedRate(token);
        require(decayedRate <= ProtocolMath.ONE);

        collateralData[token].baseRate = decayedRate;

        _updateOperationTime(token);
    }

    function _updateOperationTime(IERC20 token) internal {
        uint256 pastTime = block.timestamp - collateralData[token].operationTime;

        if (1 minutes <= pastTime) {
            collateralData[token].operationTime = block.timestamp;
        }
    }

    function _calcDecayedRate(IERC20 token) internal view returns (uint256) {
        uint256 pastMinutes = (block.timestamp - collateralData[token].operationTime) / 1 minutes;
        uint256 decay = ProtocolMath._decPow(DECAY_FACTOR, pastMinutes);

        return collateralData[token].baseRate.mulDown(decay);
    }

    function _checkPosition(IERC20 token, uint256 debt, uint256 collateral) internal view {
        if (debt < MIN_DEBT) {
            revert NetDebtBelowMinimum(debt);
        }

        (uint256 price,) = collateralData[token].priceFeed.fetchPrice();
        uint256 health = ProtocolMath._computeHealth(collateral, debt, price);
        if (health < MIN_CR) {
            revert NewICRLowerThanMCR(health);
        }
    }

    receive() external payable {}
}

contract Stablecoin {
    Token public immutable mim;
    Token public immutable eth;
    Manager public immutable manager;
    address public player;

    constructor(address _player, Token _mim, Token _eth, Manager _manager) {
        player = _player;
        mim = _mim;
        eth = _eth;
        manager = _manager;
    }

    function isSolved() external view returns (bool) {
        return mim.balanceOf(player) == 50_000_000 ether;
    }
}