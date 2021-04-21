pragma solidity ^0.6.7;

import "../../../lib/geb/src/OracleRelayer.sol";
import { ERC20 } from "../.././erc20/ERC20.sol";
import { IUniswapV3Pool } from "../.././uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "../.././uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "../.././uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "../.././uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "../.././uni/libraries/TickMath.sol";

/**
 * @notice This contract is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapV3LiquidityManagerFuzz is ERC20 {
    // --- Pool Variables ---
    //The address of pool's token0
    address public token0;
    //The address of pool's token1
    address public token1;
    //The pool's fee
    uint24 public fee;
    //The pool's tickSpacing
    int24 public tickSpacing;
    //The pool's maximum liquisity per tick
    uint128 public maxLiquidityPerTick;
    // Flag to identify weather protocol is t0 or t1. Needed for correct tick calculation
    bool protocolTokenIsT0;

    // --- Variables ---
    //The threshold bounded by MIN_THRESHOLD(1000) and MIN_THRESHOLD(10000000), meaning that 1000 = 0.1% and 10000000 = 100%.
    uint256 public threshold;
    //The minimum delay required to perform a rebalance. Bounded to be between MINIMUM_DELAY and MAXIMUM_DELAY
    uint256 public delay;
    //The timestamp of the last rebalance
    uint256 public lastRebalance;
    // Collateral to read prices from oracleRelayer
    bytes32 public collateralType;
    //This constract position on uniswap v3 pool
    Position public position;

    // --- External Contracts ---
    // Address of uniswap v3 pool
    IUniswapV3Pool public pool;
    // Address of oracleRelayer to get prices from
    OracleRelayer public oracleRelayer;

    // --- Constants ---
    //Used to get the max amount of tokens per liquidity burned
    uint128 constant MAX_UINT128 = uint128(0 - 1);
    //100% - Not really achievable, because it'll reach max and min ticks
    uint256 constant MAX_THRESHOLD = 10000000;
    // 1% - Quite dangerous because the market price can easily outsing the threshold
    uint256 constant MIN_THRESHOLD = 10000; // 1%
    // A week is the maximum time without a rebalance
    uint256 constant MAX_DELAY = 7 days;
    // 1 hour is the absolute minimum delay for rebalance. But could be less through deposits
    uint256 constant MIN_DELAY = 60 minutes;
    // Absolutes ticks, (MAX_TICK % tickSpacing == 0) and (MIN_TICK % tickSpacing == 0) are required
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
        require(authorizedAccounts[msg.sender] == 1, "OracleRelayer/account-not-authorized");
        _;
    }

    /**
     * @notice Constructor that sets initial parameters for this contract
     * @param name_ The name of the ERC20 this contract will distribute
     * @param symbol_ The symbik of the ERC20 this contract will distribute
     * @param protocolTokenAddress_ The address of deployed RAI token
     * @param threshold_ The threshold to set liquidity from the redemption price
     * @param delay_ The minimum required time before rebalance can be called
     * @param pool_ Address of the already deployed univ3 pool this contract will manage
     * @param relayer_ Address of the already deployed the relayer to get prices from
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address protocolTokenAddress_,
        uint256 threshold_,
        uint256 delay_,
        address pool_,
        bytes32 collateralType_,
        OracleRelayer relayer_
    ) public ERC20(name_, symbol_) {
        require(threshold_ >= MIN_THRESHOLD && threshold_ <= MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
        require(delay_ >= MIN_DELAY && delay_ <= MAX_DELAY, "GebUniswapv3LiquidityManager/invalid-delay");

        //Getting Pool Information
        pool = IUniswapV3Pool(pool_);

        // We might want to save gas and takes this values straight from the constructor, trusting that they are correct
        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
        tickSpacing = pool.tickSpacing();
        maxLiquidityPerTick = pool.maxLiquidityPerTick();

        // Setting needed variables
        threshold = threshold_;
        delay = delay_;
        protocolTokenIsT0 = token0 == protocolTokenAddress_ ? true : false;
        collateralType = collateralType_;
        oracleRelayer = relayer_;

        //Starting position
        (int24 _lower, int24 _upper) = getNextTicks();
        position = Position({ id: keccak256(abi.encodePacked(address(this), _lower, _upper)), lowerTick: _lower, upperTick: _upper, uniLiquidity: 0 });
    }

    // --- Math ---
    /**
     * @notice Calculates the sqrt of number
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
     * @param parameter The variable to changes
     * @param data The value to set parameter as
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "threshold") {
            require(threshold > MIN_THRESHOLD && threshold < MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
            threshold = data;
        }
        if (parameter == "delay") {
            require(delay >= MIN_DELAY && delay <= MAX_DELAY, "GebUniswapv3LiquidityManager/invalid-delay");
            delay = data;
        } else revert("GebUniswapv3LiquidityManager/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    /**
     * @notice Modify the adjustable parameters
     * @param parameter The variable to changes
     * @param data The value to set parameter as
     */
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        if (parameter == "oracleRelayer") {
            oracleRelayer = OracleRelayer(data);
        }
        emit ModifyParameters(parameter, data);
    }

    // --- Getters ---
    /**
     * @notice Public function to get both the redemption and ETH/USD price
     * @return redemptionPrice The redemption prince in usd
     * @return ethUsdPrice The eth/usd price
     */
    function getPrices() public returns (uint256 redemptionPrice, uint256 ethUsdPrice) {
        redemptionPrice = oracleRelayer.redemptionPrice();
        (OracleLike osm, , ) = oracleRelayer.collateralTypes(collateralType);
        bool valid;
        (ethUsdPrice, valid) = osm.getResultWithValidity();
        require(valid, "GebUniswapv3LiquidityManager/invalid-price-feed");
    }

    /**
     * @notice Function that returns the next target ticks based on the redemption price
     * @return _nextLower The lower bound of the range
     * @return _nextUpper The upper bound of the range
     */
    function getNextTicks() public returns (int24 _nextLower, int24 _nextUpper) {
        //1. Get prices from oracleRelayer
        (uint256 redemptionPrice, uint256 ethUsdPrice) = getPrices();

        //2. Calculate the price ratio
        uint160 sqrtPriceX96;
        if (!protocolTokenIsT0) {
            sqrtPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
        } else {
            sqrtPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
        }

        //3. Calculate the tick that the ratio is at
        int24 targetTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        //4. Adjust to comply to tickSpacing
        int24 spacedTick = targetTick - (targetTick % tickSpacing);

        //5. Find lower and upper bounds of next position
        _nextLower = spacedTick - int24(threshold) < MIN_TICK ? MIN_TICK : spacedTick - int24(threshold);
        _nextUpper = spacedTick + int24(threshold) > MAX_TICK ? MAX_TICK : spacedTick + int24(threshold);
    }

    /**
     * @notice Returns the current amount of token 0 for given liquidity
     * @param liquidity The amount of liquidity
     */
    function getToken0FromLiquidity(uint128 liquidity) public view returns (uint256 amount0) {
        amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            liquidity
        );
    }

    /**
     * @notice Returns the current amount of token 0 for given liquidity
     * @param liquidity The amount of liquidity
     */
    function getToken1FromLiquidity(uint128 liquidity) public view returns (uint256 amount1) {
        amount1 = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            liquidity
        );
    }

    /**
     * @notice Add liquidity to this uniswap pool manager
     * @param newLiquidity The amount of liquidty that the user wish to add
     * @dev In case of a multi-tranche scenario, rebalancing all three might be too expensive for the ende user.
     * A round robind could be done where in each deposit only one of the pool's position is rebalanced
     */
    function deposit(uint128 newLiquidity, address recipient) external returns (uint256 mintAmount) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");
        // Loading to stack to save on sloads
        (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);
        uint128 previousLiquidity = position.uniLiquidity;

        (int24 _nextLowerTick, int24 _nextUpperTick) = getNextTicks();

        uint128 compoundLiquidity = 0;
        uint256 collected0 = 0;
        uint256 collected1 = 0;

        //A possible optimization is only rebalance if the the tick diff is significant enough
        if (position.uniLiquidity > 0 && (position.lowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick)) {
            //1.Burn and collect all that we have
            (collected0, collected1) = _burnOnUniswap(_currentLowerTick, _currentUpperTick, position.uniLiquidity, address(this), MAX_UINT128, MAX_UINT128);

            //2.Figure how much liquity we can get from our current balances
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

            compoundLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_nextLowerTick),
                TickMath.getSqrtRatioAtTick(_nextUpperTick),
                collected0,
                collected1
            );
            emit Rebalance(msg.sender, block.timestamp);
        }

        // 3.Mint our new position on uniswap
        _mintOnUniswap(_nextLowerTick, _nextUpperTick, newLiquidity + compoundLiquidity, abi.encode(msg.sender, collected0, collected1));
        lastRebalance = block.timestamp;

        // 4.Calculate and mint user's erc20 liquidity tokens
        uint256 __supply = _totalSupply;
        if (__supply == 0) {
            mintAmount = newLiquidity;
        } else {
            mintAmount = uint256(newLiquidity).mul(_totalSupply).div(previousLiquidity);
        }

        _mint(recipient, mintAmount);

        Deposit(msg.sender, recipient, newLiquidity);
    }

    /**
     * @notice Remove liquidity and withdraw the underlying assests
     * @param liquidityAmount The amount of liquidity to withdraw
     */
    function withdraw(
        uint256 liquidityAmount,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityBurned
        )
    {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");
        uint256 __supply = _totalSupply;
        _burn(msg.sender, liquidityAmount);

        uint256 _liquidityBurned = liquidityAmount.mul(__supply).div(position.uniLiquidity);
        require(_liquidityBurned < uint256(0 - 1));
        liquidityBurned = uint128(_liquidityBurned);

        (amount0, amount1) = _burnOnUniswap(position.lowerTick, position.upperTick, liquidityBurned, recipient, amount0Requested, amount1Requested);
        emit Withdraw(msg.sender, recipient, liquidityAmount);
    }

    /**
     * @notice Public function to rebalance the pool position to the correct threshold from the redemption price
     */
    function rebalance() external {
        require(block.timestamp.sub(lastRebalance) >= delay, "GebUniswapv3LiquidityManager/too-soon");
        // Read all this from storage to minimize SLOADs
        (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);

        (int24 _nextLowerTick, int24 _nextUpperTick) = getNextTicks();

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
                    collected0,
                    collected1
                );

            // Mint this new liquidity. _mintOnUniswap updates the position storage
            //Due to roundings, we get different amounts from LiquidityAmounts.getLiquidityForAmounts and the actual amountOwed we get in the callback
            //We need to find a resonable workaround
            _mintOnUniswap(_nextLowerTick, _nextUpperTick, compoundLiquidity, abi.encode(address(this), collected0, collected1));
        }
        //Even if there's no change, we update the time anyway
        lastRebalance = block.timestamp;
        emit Rebalance(msg.sender, block.timestamp);
    }

    // --- Uniswap Related Functions ---
    /**
     * @notice Helper function to mint a new position on uniswap pool
     * @param lowerTick The lower bound of the range to deposit the liquidity
     * @param upperTick The upper bound of the range to deposit the liquidity
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
     * @notice Helper function to mint a new position on uniswap pool
     * @param lowerTick The lower bound of the range to deposit the liquidity
     * @param upperTick The upper bound of the range to deposit the liquidity
     * @param burnedLiquidity The amount of liquidity to burn
     * @param recipient The address to receive the collected amounts
     */
    function _burnOnUniswap(
        int24 lowerTick,
        int24 upperTick,
        uint128 burnedLiquidity,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) private returns (uint256 collected0, uint256 collected1) {
        (uint256 _owed0, uint256 _owed1) = pool.burn(lowerTick, upperTick, burnedLiquidity);

        //Copying to stack variables to avoid modifying function parameters
        (uint128 amt0, uint128 amt1) = (amount0Requested, amount1Requested);

        // If we're withdrawing for a specific user, then we only want to withdraw what they're owed
        if (recipient != address(this)) {
            // TODO: can we trust Uniswap and safely cast here?
            amt0 = uint128(_owed0);
            amt1 = uint128(_owed1);
        }
        // Collect all owed
        (collected0, collected1) = pool.collect(recipient, lowerTick, upperTick, amt0, amt1);

        // Update position. All other factors are still the same
        (uint128 _liquidity, , , , ) = pool.positions(position.id);
        position.uniLiquidity = _liquidity;
    }

    /**
     * @notice Callback used to transfer tokens to uniswap pool. Tokens need to be aproved before calling mint or deposit.
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
        //Pay what this contract owns
        if (amt0FromThis > 0) {
            if (sender == address(this)) {
                TransferHelper.safeTransfer(token0, msg.sender, amount0Owed);
            } else {
                TransferHelper.safeTransfer(token0, msg.sender, amt0FromThis);
            }
        }
        if (amt1FromThis > 0) {
            if (sender == address(this)) {
                TransferHelper.safeTransfer(token1, msg.sender, amount1Owed);
            } else {
                TransferHelper.safeTransfer(token1, msg.sender, amt1FromThis);
            }
        }
        //Pay what sender owns
        if (amount0Owed > amt0FromThis) {
            TransferHelper.safeTransferFrom(token0, sender, msg.sender, amount0Owed - amt0FromThis);
        }
        if (amount1Owed > amt1FromThis) {
            TransferHelper.safeTransferFrom(token1, sender, msg.sender, amount1Owed - amt1FromThis);
        }
    }

    // --- Echidna Assertions ---
    function echidna_check_supply() public returns (bool) {
        (uint128 _liquidity, , , , ) = pool.positions(position.id);
        return _totalSupply <= uint256(_liquidity);
    }
}
