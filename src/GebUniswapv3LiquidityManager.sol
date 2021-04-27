pragma solidity ^0.6.7;

import { ERC20 } from "./erc20/ERC20.sol";
import { IUniswapV3Pool } from "./uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "./uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "./uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "./uni/libraries/TickMath.sol";

abstract contract OracleLike {
    function getResultsWithValidity()
        public
        virtual
        returns (
            uint256,
            uint256,
            bool
        );
}

/**
 * @notice This contract is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapV3LiquidityManager is ERC20 {
    // --- Pool Variables ---
    // The address of pool's token0
    address public token0;
    // The address of pool's token1
    address public token1;
    // The pool's fee
    uint24 public fee;
    // The pool's tickSpacing
    int24 public tickSpacing;
    // The pool's maximum liquisity per tick
    uint128 public maxLiquidityPerTick;
    // Flag to identify whether the system coin is token0 or token1. Needed for correct tick calculation
    bool systemCoinIsT0;

    // --- Variables ---
    // The threshold bounded by MIN_THRESHOLD(1000) and MIN_THRESHOLD(10000000), meaning that 1000 = 0.1% and 10000000 = 100%.
    uint256 public threshold;
    // The minimum delay required to perform a rebalance. Bounded to be between MINIMUM_DELAY and MAXIMUM_DELAY
    uint256 public delay;
    // The timestamp of the last rebalance
    uint256 public lastRebalance;
    // The last used price for rebalance
    int24 public lastRebalancePrice;
    // Collateral whose price to read from the oracle relayer
    bytes32 public collateralType;
    // This contracts' position in the Uniswap V3 pool
    Position public position;

    // --- External Contracts ---
    // Address of the Uniswap v3 pool
    IUniswapV3Pool public pool;
    // Address of oracle relayer to get prices from
    OracleLike public oracle;

    // --- Constants ---
    // Used to get the max amount of tokens per liquidity burned
    uint128 constant MAX_UINT128 = uint128(0 - 1);
    // 100% - Not really achievable, because it'll reach max and min ticks
    uint256 constant MAX_THRESHOLD = 10000000;
    // 1% - Quite dangerous because the market price can easily move beyond the threshold
    uint256 constant MIN_THRESHOLD = 10000; // 1%
    // A week is the maximum time allowed without a rebalance
    uint256 constant MAX_DELAY = 7 days;
    // 1 hour is the absolute minimum delay for a rebalance. Could be less through deposits
    uint256 constant MIN_DELAY = 60 minutes;
    // Absolutes ticks, (MAX_TICK % tickSpacing == 0) and (MIN_TICK % tickSpacing == 0)
    int24 public constant MAX_TICK = 887270;
    int24 public constant MIN_TICK = -887270;

    // --- Struct ---
    struct Position {
        bytes32 id;
        int24 lowerTick;
        int24 upperTick;
        uint128 uniLiquidity;
    }

    // --- Events ---
    event ModifyParameters(bytes32 parameter, uint256 val);
    event ModifyParameters(bytes32 parameter, address val);
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event Deposit(address sender, address recipient, uint256 liquidityAdded);
    event Withdraw(address sender, address recipient, uint256 liquidityAdded);
    event Rebalance(address sender, uint256 timestamp);

    // --- Auth ---
    mapping(address => uint256) public authorizedAccounts;

    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }

    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }

    /**
     * @notice Checks whether msg.sender can call an authed function
     **/

    modifier isAuthorized() {
        require(authorizedAccounts[msg.sender] == 1, "GebUniswapV3LiquidityManager/account-not-authorized");
        _;
    }

    /**
     * @notice Constructor that sets initial parameters for this contract
     * @param name_ The name of the ERC20 this contract will distribute
     * @param symbol_ The symbol of the ERC20 this contract will distribute
     * @param systemCoinAddress_ The address of the system coin
     * @param threshold_ The liquidity threshold around the redemption price
     * @param delay_ The minimum required time before rebalance() can be called
     * @param pool_ Address of the already deployed Uniswap v3 pool that this contract will manage
     * @param oracle_ Address of the already deployed oracle that provides both prices
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address systemCoinAddress_,
        uint256 threshold_,
        uint256 delay_,
        address pool_,
        bytes32 collateralType_,
        OracleLike oracle_
    ) public ERC20(name_, symbol_) {
        require(threshold_ >= MIN_THRESHOLD && threshold_ <= MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
        require(delay_ >= MIN_DELAY && delay_ <= MAX_DELAY, "GebUniswapv3LiquidityManager/invalid-delay");

        authorizedAccounts[msg.sender] = 1;

        // Getting pool information
        pool = IUniswapV3Pool(pool_);

        // We might want to save gas so this takes values straight from the pool, trusting that they are correct
        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
        tickSpacing = pool.tickSpacing();
        maxLiquidityPerTick = pool.maxLiquidityPerTick();

        require(threshold_ % uint256(tickSpacing) == 0, "GebUniswapv3LiquidityManager/threshold-incompatible-w/-tickSpacing");

        // Setting variables
        threshold = threshold_;
        delay = delay_;
        systemCoinIsT0 = token0 == systemCoinAddress_ ? true : false;
        collateralType = collateralType_;
        oracle = oracle_;

        // Starting position
        (int24 _lower, int24 _upper, ) = getNextTicks();
        position = Position({ id: keccak256(abi.encodePacked(address(this), _lower, _upper)), lowerTick: _lower, upperTick: _upper, uniLiquidity: 0 });
    }

    // --- Math ---
    /**
     * @notice Calculates the sqrt of a number
     * @param y The number to calculate the square root of
     * @return z The result of the calculation
     */
    function sqrt(uint256 y) public pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // --- Administration ---
    /**
     * @notice Modify the adjustable parameters
     * @param parameter The variable to change
     * @param data The value to set for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external {
        if (parameter == "threshold") {
            require(threshold > MIN_THRESHOLD && threshold < MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
            require(data % uint256(tickSpacing) == 0, "GebUniswapv3LiquidityManager/threshold-incompatible-w/-tickSpacing");
            threshold = data;
        } else if (parameter == "delay") {
            require(delay >= MIN_DELAY && delay <= MAX_DELAY, "GebUniswapv3LiquidityManager/invalid-delay");
            delay = data;
        } else revert("GebUniswapv3LiquidityManager/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    /**
     * @notice Modify adjustable parameters
     * @param parameter The variable to change
     * @param data The value to set for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        if (parameter == "oracle") {
            oracle = OracleLike(data);
        }
        emit ModifyParameters(parameter, data);
    }

    // --- Getters ---
    /**
     * @notice Public function to get both the redemption price for the system coin and the other token's price
     * @return redemptionPrice The redemption price
     * @return tokenPrice The other token's price
     */
    function getPrices() public returns (uint256 redemptionPrice, uint256 tokenPrice) {
        bool valid;
        (redemptionPrice, tokenPrice, valid) = oracle.getResultsWithValidity();
        require(valid, "GebUniswapv3LiquidityManager/invalid-price");
    }

    /**
     * @notice Function that returns the next target ticks based on the redemption price
     * @return _nextLower The lower bound of the range
     * @return _nextUpper The upper bound of the range
     */
    function getNextTicks()
        public
        returns (
            int24 _nextLower,
            int24 _nextUpper,
            int24 spacedTick
        )
    {
        // 1. Get prices from the oracle relayer
        (uint256 redemptionPrice, uint256 ethUsdPrice) = getPrices();

        // 2. Calculate the price ratio
        uint160 sqrtPriceX96;
        if (!systemCoinIsT0) {
            sqrtPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
        } else {
            sqrtPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
        }

        // 3. Calculate the tick that the ratio is at
        int24 targetTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        // 4. Adjust to comply to tickSpacing
        int24 spacedTick = targetTick - (targetTick % tickSpacing);

        // 5. Find lower and upper bounds for the next position
        _nextLower = spacedTick - int24(threshold) < MIN_TICK ? MIN_TICK : spacedTick - int24(threshold);
        _nextUpper = spacedTick + int24(threshold) > MAX_TICK ? MAX_TICK : spacedTick + int24(threshold);
    }

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param liquidity The amount of liquidity to withdraw
     * @return amount0 The amount of token1 received for the liquidity
     */
    function getToken0FromLiquidity(uint128 liquidity) public view returns (uint256 amount0) {
        uint256 poolLiquidity = uint256(liquidity).mul(position.uniLiquidity).div(_totalSupply);
        amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            uint128(poolLiquidity)
        );
    }

    /**
     * @notice Returns the current amount of token1 for a given liquidity amount
     * @param liquidity The amount of liquidity to withdraw
     * @return amount1 The amount of token1 received for the liquidity
     */
    function getToken1FromLiquidity(uint128 liquidity) public view returns (uint256 amount1) {
        uint256 poolLiquidity = uint256(liquidity).mul(position.uniLiquidity).div(_totalSupply);
        amount1 = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            uint128(poolLiquidity)
        );
    }

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param token0Amount The amount of token0 to check
     * @return liquidity The amount received
     */
    function getLiquidityFromToken0(uint256 token0Amount) public view returns (uint128 liquidity) {
        uint128 liq =
            LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.upperTick),
                token0Amount
            );
        liquidity = uint128(uint256(liq).mul(_totalSupply).div(position.uniLiquidity));
    }

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param token1Amount The amount of token0 to check
     * @return liquidity The amount received
     */
    function getLiquidityFromToken1(uint256 token1Amount) public view returns (uint128 liquidity) {
        uint128 liq =
            LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.upperTick),
                token1Amount
            );
        liquidity = uint128(uint256(liq).mul(_totalSupply).div(position.uniLiquidity));
    }

    /**
     * @notice Add liquidity to this uniswap pool manager
     * @param newLiquidity The amount of liquidty that the user wishes to add
     * @param recipient The address that will receive ERC20 wrapper tokens for the provided liquidity
     * @dev In case of a multi-tranche scenario, rebalancing all three might be too expensive for the ende user.
     *      A round robin could be done where in each deposit only one of the pool's positions is rebalanced
     */
    function deposit(uint128 newLiquidity, address recipient) external returns (uint256 mintAmount) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");
        // Loading to stack to save on SLOADs
        (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);
        uint128 previousLiquidity = position.uniLiquidity;

        //Ugly, but avoid stack too deep error
        (int24 _nextLowerTick, int24 _nextUpperTick) = (0, 0);
        {
            int24 price = 0;
            (_nextLowerTick, _nextUpperTick, price) = getNextTicks();
            lastRebalancePrice = price;
        }

        uint128 compoundLiquidity = 0;
        uint256 collected0 = 0;
        uint256 collected1 = 0;

        // A possible optimization is to only rebalance if the tick diff is significant enough
        if (previousLiquidity > 0 && (_currentLowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick)) {
            // 1.Burn and collect all liquidity
            (collected0, collected1) = _burnOnUniswap(_currentLowerTick, _currentUpperTick, previousLiquidity, address(this), MAX_UINT128, MAX_UINT128);

            // 2.Figure how much liquity we can get from our current balances
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

            compoundLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_nextLowerTick),
                TickMath.getSqrtRatioAtTick(_nextUpperTick),
                collected0 + 1,
                collected1 + 1
            );

            emit Rebalance(msg.sender, block.timestamp);
        }

        // 3.Mint our new position on Uniswap
        require(newLiquidity + compoundLiquidity >= newLiquidity, "GebUniswapv3LiquidityManager/liquidity-overflow");
        _mintOnUniswap(_nextLowerTick, _nextUpperTick, newLiquidity + compoundLiquidity, abi.encode(msg.sender, collected0, collected1));
        lastRebalance = block.timestamp;

        // 4.Calculate and mint a user's ERC20 liquidity tokens
        {
            uint256 __supply = _totalSupply;
            if (__supply == 0) {
                mintAmount = newLiquidity;
            } else {
                mintAmount = uint256(newLiquidity).mul(_totalSupply).div(previousLiquidity);
            }

            _mint(recipient, mintAmount);
        }

        emit Deposit(msg.sender, recipient, newLiquidity);
    }

    /**
     * @notice Remove liquidity and withdraw the underlying assets
     * @param liquidityAmount The amount of liquidity to withdraw
     * @param recipient The address that will receive token0 and token1 tokens
     * @param amount0Requested Minimum amount of token0 requested
     * @param amount1Requested Minimum amount of token1 requested
     * @return amount0 The amount of token0 requested from the pool
     * @return amount1 The amount of token1 requested from the pool
     */
    function withdraw(
        uint256 liquidityAmount,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint256 amount0, uint256 amount1) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");
        require(liquidityAmount != 0, "GebUniswapv3LiquidityManager/burning-zero-amount");
        uint256 __supply = _totalSupply;
        _burn(msg.sender, liquidityAmount);

        uint256 _liquidityBurned = liquidityAmount.mul(position.uniLiquidity).div(__supply);
        require(_liquidityBurned < uint256(0 - 1));

        (amount0, amount1) = _burnOnUniswap(position.lowerTick, position.upperTick, uint128(_liquidityBurned), recipient, amount0Requested, amount1Requested);
        emit Withdraw(msg.sender, recipient, liquidityAmount);
    }

    /**
     * @notice Public function to move liquidity to the correct threshold from the redemption price
     */
    function rebalance() external {
        require(block.timestamp.sub(lastRebalance) >= delay, "GebUniswapv3LiquidityManager/too-soon");
        // Read all this from storage to minimize SLOADs
        (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);
        (uint160 sqr6, , , , , , ) = pool.slot0();

        (int24 _nextLowerTick, int24 _nextUpperTick, int24 price) = getNextTicks();
        lastRebalancePrice = price;

        if (_currentLowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick) {
            // Get the fees
            (uint256 collected0, uint256 collected1) =
                _burnOnUniswap(_currentLowerTick, _currentUpperTick, position.uniLiquidity, address(this), MAX_UINT128, MAX_UINT128);

            //Figure how much liquity we can get from our current balances
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

            uint128 compoundLiquidity =
                LiquidityAmounts.getLiquidityForAmounts(
                    sqrtRatioX96,
                    TickMath.getSqrtRatioAtTick(_nextLowerTick),
                    TickMath.getSqrtRatioAtTick(_nextUpperTick),
                    collected0 + 1,
                    collected1 + 1
                );

            _mintOnUniswap(_nextLowerTick, _nextUpperTick, compoundLiquidity, abi.encode(msg.sender, collected0, collected1));
        }

        // Even if there's no change, we still update the time
        lastRebalance = block.timestamp;
        emit Rebalance(msg.sender, block.timestamp);
    }

    // --- Uniswap Related Functions ---
    /**
     * @notice Helper function to mint a position
     * @param lowerTick The lower bound of the range to deposit the liquidity to
     * @param upperTick The upper bound of the range to deposit the liquidity to
     * @param totalLiquidity The total amount of liquidity to mint
     */
    function _mintOnUniswap(
        int24 lowerTick,
        int24 upperTick,
        uint128 totalLiquidity,
        bytes memory callbackData
    ) private {
        pool.mint(address(this), lowerTick, upperTick, totalLiquidity, callbackData);
        position.lowerTick = lowerTick;
        position.upperTick = upperTick;

        bytes32 id = keccak256(abi.encodePacked(address(this), lowerTick, upperTick));
        (uint128 _liquidity, , , , ) = pool.positions(id);
        position.id = id;
        position.uniLiquidity = _liquidity;
    }

    /**
     * @notice Helper function to burn a position
     * @param lowerTick The lower bound of the range to deposit the liquidity to
     * @param upperTick The upper bound of the range to deposit the liquidity to
     * @param burnedLiquidity The amount of liquidity to burn
     * @param recipient The address to send the tokens to
     * @return collected0 The amount of token0 requested from the pool
     * @return collected1 The amount of token1 requested from the pool
     */
    function _burnOnUniswap(
        int24 lowerTick,
        int24 upperTick,
        uint128 burnedLiquidity,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) private returns (uint256 collected0, uint256 collected1) {
        // Amount owed migth be more than requested. What do we do?
        (uint256 _owed0, uint256 _owed1) = pool.burn(lowerTick, upperTick, burnedLiquidity);

        // Collect all owed
        (collected0, collected1) = pool.collect(recipient, lowerTick, upperTick, amount0Requested, amount1Requested);

        // Update position. All other factors are still the same
        (uint128 _liquidity, , , , ) = pool.positions(position.id);
        position.uniLiquidity = _liquidity;
    }

    /**
     * @notice Callback used to transfer tokens to the pool. Tokens need to be aproved before calling mint or deposit.
     * @param amount0Owed The amount of token0 necessary to send to pool
     * @param amount1Owed The amount of token1 necessary to send to pool
     * @param data Arbitrary data to use in the function
     */
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        require(msg.sender == address(pool));

        (address sender, uint256 amt0FromThis, uint256 amt1FromThis) = abi.decode(data, (address, uint256, uint256));

        // Pay what this contract owes
        if (amt0FromThis > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, amt0FromThis);
        }
        if (amt1FromThis > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, amt1FromThis);
        }

        // Pay what the sender owes
        if (amount0Owed > amt0FromThis) {
            TransferHelper.safeTransferFrom(token0, sender, msg.sender, amount0Owed - amt0FromThis);
        }
        if (amount1Owed > amt1FromThis) {
            TransferHelper.safeTransferFrom(token1, sender, msg.sender, amount1Owed - amt1FromThis);
        }
    }
}
