// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "../helpers/ERC20.sol";

contract Yield is
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ERC20,
    ReentrancyGuard
{
    event Deposit(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Withdraw(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event CollectFees(
        uint256 feesToVault0,
        uint256 feesToVault1,
        uint256 feesToProtocol0,
        uint256 feesToProtocol1
    );

    event Snapshot(int24 tick, uint256 totalAmount0, uint256 totalAmount1, uint256 totalSupply);

    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    int24 public immutable tickSpacing;

    uint256 public protocolFee;
    uint256 public maxTotalSupply;
    address public governance;
    address public pendingGovernance;

    int24 public lastTick;
    int24 public baseLower;
    int24 public baseUpper;
    uint256 public accruedProtocolFees0;
    uint256 public accruedProtocolFees1;

    address public player;

    constructor(
        address _player,
        address _pool,
        uint256 _protocolFee,
        uint256 _maxTotalSupply
    ) ERC20("Yield Vault", "YV") {
        player = _player;
        pool = IUniswapV3Pool(_pool);
        token0 = ERC20(IUniswapV3Pool(_pool).token0());
        token1 = ERC20(IUniswapV3Pool(_pool).token1());
        tickSpacing = IUniswapV3Pool(_pool).tickSpacing();

        protocolFee = _protocolFee;
        maxTotalSupply = _maxTotalSupply;
        governance = msg.sender;
        lastTick = type(int24).max;

        require(_protocolFee < 1e6, "protocolFee");
    }

    function isSolved() external view returns (bool) {
        return balanceOf[player] >= 15 ether;
    }

    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    )
        external
        nonReentrant
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Desired > 0 || amount1Desired > 0, "amount0Desired or amount1Desired");
        require(to != address(0) && to != address(this), "to");

        // Poke positions so vault's current holdings are up-to-date
        _poke(baseLower, baseUpper);

        // Calculate amounts proportional to vault's holdings
        (shares, amount0, amount1) = _calcSharesAndAmounts(amount0Desired, amount1Desired);
        require(shares > 0, "shares");
        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Pull in tokens from sender
        if (amount0 > 0) token0.transferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) token1.transferFrom(msg.sender, address(this), amount1);

        // Mint shares to recipient
        _mint(to, shares);
        emit Deposit(msg.sender, to, shares, amount0, amount1);
        require(totalSupply <= maxTotalSupply, "maxTotalSupply");
    }

    function _poke(int24 tickLower, int24 tickUpper) internal {
        (uint128 liquidity, , , , ) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
        }
    }

    function _calcSharesAndAmounts(uint256 amount0Desired, uint256 amount1Desired)
        internal
        view
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        (uint256 total0, uint256 total1) = getTotalAmounts();

        // If total supply > 0, vault can't be empty
        assert(totalSupply == 0 || total0 > 0 || total1 > 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = Math.max(amount0, amount1);
        } else if (total0 == 0) {
            amount1 = amount1Desired;
            shares = Math.mulDiv(amount1, totalSupply, total1);
        } else if (total1 == 0) {
            amount0 = amount0Desired;
            shares = Math.mulDiv(amount0, totalSupply, total0);
        } else {
            uint256 cross = Math.min(amount0Desired * total1, amount1Desired * total0);
            require(cross > 0, "cross");

            // Round up amounts
            amount0 = (cross - 1) / total1 + 1;
            amount1 = (cross - 1) / total0 + 1;
            shares = cross * totalSupply / total0 / total1;
        }
    }

    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(shares > 0, "shares");
        require(to != address(0) && to != address(this), "to");

        // Burn shares
        _burn(msg.sender, shares);

        // Calculate token amounts proportional to unused balances
        uint256 unusedAmount0 = Math.mulDiv(getBalance0(), shares, totalSupply);
        uint256 unusedAmount1 = Math.mulDiv(getBalance1(), shares, totalSupply);

        // Withdraw proportion of liquidity from Uniswap pool
        (uint256 baseAmount0, uint256 baseAmount1) =
            _burnLiquidityShare(baseLower, baseUpper, shares, totalSupply);

        // Sum up total amounts owed to recipient
        amount0 = unusedAmount0 + baseAmount0;
        amount1 = unusedAmount1 + baseAmount1;
        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Push tokens to recipient
        if (amount0 > 0) token0.transfer(to, amount0);
        if (amount1 > 0) token1.transfer(to, amount1);

        emit Withdraw(msg.sender, to, shares, amount0, amount1);
    }

    function _burnLiquidityShare(
        int24 tickLower,
        int24 tickUpper,
        uint256 shares,
        uint256 _totalSupply
    ) internal returns (uint256 amount0, uint256 amount1) {
        (uint128 totalLiquidity, , , , ) = _position(tickLower, tickUpper);
        uint256 liquidity = Math.mulDiv(uint256(totalLiquidity), shares, _totalSupply);

        if (liquidity > 0) {
            (uint256 burned0, uint256 burned1, uint256 fees0, uint256 fees1) =
                _burnAndCollect(tickLower, tickUpper, _toUint128(liquidity));

            // Add share of fees
            amount0 = burned0 + Math.mulDiv(fees0, shares, _totalSupply);
            amount1 = burned1 + Math.mulDiv(fees1, shares, _totalSupply);
        }
    }

    function rebalance() external nonReentrant {
        (, int24 tick, , , , , ) = pool.slot0();
        int24 diff = tick > lastTick ? tick - lastTick : lastTick - tick;
        require(diff >= 5 * tickSpacing, "price diff");

        int24 _baseLower = (tick - int24(10) * tickSpacing) / tickSpacing * tickSpacing > TickMath.MIN_TICK 
            ? (tick - int24(10) * tickSpacing) / tickSpacing * tickSpacing : TickMath.MIN_TICK;
        int24 _baseUpper = (tick + int24(10) * tickSpacing) / tickSpacing * tickSpacing < TickMath.MAX_TICK 
            ? (tick + int24(10) * tickSpacing) / tickSpacing * tickSpacing : TickMath.MAX_TICK;

        // Withdraw all current liquidity from Uniswap pool
        {
            (uint128 baseLiquidity, , , , ) = _position(baseLower, baseUpper);
            _burnAndCollect(baseLower, baseUpper, baseLiquidity);
        }

        // Emit snapshot to record balances and supply
        uint256 balance0 = getBalance0();
        uint256 balance1 = getBalance1();
        emit Snapshot(tick, balance0, balance1, totalSupply);

        // Place base order on Uniswap
        uint128 liquidity = _liquidityForAmounts(_baseLower, _baseUpper, balance0, balance1);
        _mintLiquidity(_baseLower, _baseUpper, liquidity);
        lastTick = tick;
        (baseLower, baseUpper) = (_baseLower, _baseUpper);
    }

    function _burnAndCollect(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        internal
        returns (
            uint256 burned0,
            uint256 burned1,
            uint256 feesToVault0,
            uint256 feesToVault1
        )
    {
        if (liquidity > 0) {
            (burned0, burned1) = pool.burn(tickLower, tickUpper, liquidity);
        }

        // Collect all owed tokens including earned fees
        (uint256 collect0, uint256 collect1) =
            pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );

        feesToVault0 = collect0 - burned0;
        feesToVault1 = collect1 - burned1;
        uint256 feesToProtocol0;
        uint256 feesToProtocol1;

        // Update accrued protocol fees
        uint256 _protocolFee = protocolFee;
        if (_protocolFee > 0) {
            feesToProtocol0 = Math.mulDiv(feesToVault0, _protocolFee, 1e6);
            feesToProtocol1 = Math.mulDiv(feesToVault1, _protocolFee, 1e6);
            feesToVault0 = feesToVault0 - feesToProtocol0;
            feesToVault1 = feesToVault1 - feesToProtocol1;
            accruedProtocolFees0 = accruedProtocolFees0 + feesToProtocol0;
            accruedProtocolFees1 = accruedProtocolFees1 + feesToProtocol1;
        }
        emit CollectFees(feesToVault0, feesToVault1, feesToProtocol0, feesToProtocol1);
    }

    function _mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal {
        if (liquidity > 0) {
            pool.mint(address(this), tickLower, tickUpper, liquidity, "");
        }
    }

    function getTotalAmounts() public view returns (uint256 total0, uint256 total1) {
        (uint256 baseAmount0, uint256 baseAmount1) = getPositionAmounts(baseLower, baseUpper);
        total0 = getBalance0() + baseAmount0;
        total1 = getBalance1() + baseAmount1;
    }

    function getPositionAmounts(int24 tickLower, int24 tickUpper)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) =
            _position(tickLower, tickUpper);
        (amount0, amount1) = _amountsForLiquidity(tickLower, tickUpper, liquidity);

        // Subtract protocol fees
        uint256 oneMinusFee = uint256(1e6) - protocolFee;
        amount0 = amount0 + (uint256(tokensOwed0) * oneMinusFee / 1e6);
        amount1 = amount1 + (uint256(tokensOwed1) * oneMinusFee / 1e6);
    }

    function getBalance0() public view returns (uint256) {
        return token0.balanceOf(address(this)) - accruedProtocolFees0;
    }

    function getBalance1() public view returns (uint256) {
        return token1.balanceOf(address(this)) - accruedProtocolFees1;
    }

    function _position(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (
            uint128,
            uint256,
            uint256,
            uint128,
            uint128
        )
    {
        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        return pool.positions(positionKey);
    }

    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint128) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount0,
                amount1
            );
    }

    function _toUint128(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) token0.transfer(msg.sender, amount0);
        if (amount1 > 0) token1.transfer(msg.sender, amount1);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pool));
        if (amount0Delta > 0) token0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) token1.transfer(msg.sender, uint256(amount1Delta));
    }

    function collectProtocol(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external onlyGovernance {
        accruedProtocolFees0 = accruedProtocolFees0 - amount0;
        accruedProtocolFees1 = accruedProtocolFees1 - amount1;
        if (amount0 > 0) token0.transfer(to, amount0);
        if (amount1 > 0) token1.transfer(to, amount1);
    }

    function sweep(
        IERC20 token,
        uint256 amount,
        address to
    ) external onlyGovernance {
        require(token != token0 && token != token1, "token");
        token.transfer(to, amount);
    }

    function setProtocolFee(uint256 _protocolFee) external onlyGovernance {
        require(_protocolFee < 1e6, "protocolFee");
        protocolFee = _protocolFee;
    }

    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyGovernance {
        maxTotalSupply = _maxTotalSupply;
    }

    function emergencyBurn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external onlyGovernance {
        pool.burn(tickLower, tickUpper, liquidity);
        pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "pendingGovernance");
        governance = msg.sender;
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "governance");
        _;
    }
}
