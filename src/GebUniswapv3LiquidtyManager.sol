pragma solidity ^0.6.7;

import "ds-math/math.sol";
import "../lib/geb/src/OracleRelayer.sol";
import { ERC20 } from "./erc20/ERC20.sol";
import { IUniswapV3Pool } from "./uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "./uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "./uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "./uni/libraries/TickMath.sol";

/**
 * @notice This contract is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapV3LiquidityManager is ERC20 {
  // --- Auth ---
  mapping(address => uint256) public authorizedAccounts;

  /**
   * @notice Add auth to an account
   * @param account Account to add auth to
   */
  function addAuthorization(address account) external isAuth {
    authorizedAccounts[account] = 1;
    emit AddAuthorization(account);
  }

  /**
   * @notice Remove auth from an account
   * @param account Account to remove auth from
   */
  function removeAuthorization(address account) external isAuth {
    authorizedAccounts[account] = 0;
    emit RemoveAuthorization(account);
  }

  /**
   * @notice Checks whether msg.sender can call an authed function
   * TODO chanhing this for now, because isAuthorized breaks the compiler due to a function with the same name on DSSTOP, which is inherited by DSToken
   **/

  modifier isAuth() {
    require(authorizedAccounts[msg.sender] == 1, "OracleRelayer/account-not-authorized");
    _;
  }

  /**
  Pool information
  **/
  address public token0;
  address public token1;
  uint24 public fee;
  int24 public tickSpacing;
  uint128 public maxLiquidityPerTick; //Still unsure how this could affect this contract if a lot of uniswap's liquitidy is managed through it.

  bool raiIsT0; // Flag to identify weather Rai is t0 or t1. Changes the tick range we're working with

  /**
  Constant values
  **/
  uint256 constant MAX_THRESHOLD = 10000000; //100% - Not really achievable, because it'll reach max and min ticks
  uint256 constant MIN_THRESHOLD = 10000; // 1%
  uint256 constant MAX_DELAY = 10 days;
  uint256 constant MIN_DELAY = 10 minutes;
  int24 public constant MAX_TICK = 887270;
  int24 public constant MIN_TICK = -887270;

  /**
  External contracts
  **/
  IUniswapV3Pool public pool;
  OracleRelayer public oracleRelayer;

  // Data structure to represent a position on uniswap pool
  struct Position {
    bytes32 id;
    int24 lowerTick;
    int24 upperTick;
    uint128 uniLiquidity;
  }

  //The threshold varies from 1000 to 10000000, meaning that 1000 = 0.1% and 10000000 = 100%. This is nice because each tick represents 0.1% diff in the price space, which makes the calculation quite easy
  // Threshold could be moved to inside the Position struct in an eventual multi-position pool
  uint256 public threshold;
  uint256 public delay;
  uint256 public lastRebalance;
  Position public position;

  /**
   Events
  **/
  event ModifyParameters(bytes32 parameter, uint256 val);
  event AddAuthorization(address account);
  event RemoveAuthorization(address account);

  /**
   * @notice Constructor that sets initial parameters for this contract
   * @param name_ The name of the ERC20 this contract will distribute
   * @param symbol_ The symbik of the ERC20 this contract will distribute
   * @param raiAddress The address of deployed RAI token
   * @param threshold_ The threshold to set liquidity from the redemption price
   * @param delay_ The minimum required time before rebalance can be called
   * @param pool_ Address of the already deployed univ3 pool this contract will manage
   * @param relayer_ Address of the already deployed the relayer to get prices from
   */
  constructor(
    string memory name_,
    string memory symbol_,
    address raiAddress,
    uint256 threshold_,
    uint256 delay_,
    address pool_,
    OracleRelayer relayer_
  ) public ERC20(name_, symbol_) {
    require(threshold_ >= MIN_THRESHOLD && threshold_ <= MAX_THRESHOLD, "GebUniswapv3LiquidtyManager/invalid-thresold");
    require(delay_ >= MIN_DELAY && delay_ <= MAX_DELAY, "GebUniswapv3LiquidtyManager/invalid-delay");
    pool = IUniswapV3Pool(pool_);

    //Getting Pool Information
    // We might want to save gas and takes this values straight from the constructor, trusting that they are correct
    token0 = pool.token0();
    token1 = pool.token1();
    fee = pool.fee();
    tickSpacing = pool.tickSpacing();
    maxLiquidityPerTick = pool.maxLiquidityPerTick();

    threshold = threshold_;
    delay = delay_;
    raiIsT0 = token0 == raiAddress ? true : false;
    oracleRelayer = relayer_;

    //Starting position
    (int24 _lower, int24 _upper) = getNextTicks();
    position = Position({ id: keccak256(abi.encodePacked(address(this), _lower, _upper)), lowerTick: _lower, upperTick: _upper, uniLiquidity: 0 });
  }

  /**
   * @notice Modify the adjustable parameters
   * @param parameter The variable to changes
   * @param data The value to set parameter as
   */
  function modifyParameters(bytes32 parameter, uint256 data) external isAuth {
    if (parameter == "threshold") {
      require(threshold > MIN_THRESHOLD && threshold < MAX_THRESHOLD, "GebUniswapv3LiquidtyManager/invalid-thresold");
      threshold = data;
    }
    if (parameter == "delay") {
      require(delay >= MIN_DELAY && delay <= MAX_DELAY, "GebUniswapv3LiquidtyManager/invalid-delay");
      delay = data;
    } else revert("GebUniswapv3LiquidtyManager/modify-unrecognized-param");
    emit ModifyParameters(parameter, data);
  }

  /**
   * @notice Add liquidity to this uniswap pool manager
   * @param newLiquidity The amount of liquidty that the user wish to add
   */
  function justDeposit(uint128 newLiquidity) external returns (uint256 mintAmount) {
    (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);

    uint128 previousLiquidity = position.uniLiquidity;

    _mintOnUniswap(_currentLowerTick, _currentUpperTick, newLiquidity, abi.encode(msg.sender, uint256(0), uint256(0)));

    //TODO double check this calculation
    uint256 __supply = _totalSupply;
    if (__supply == 0) {
      mintAmount = newLiquidity;
    } else {
      mintAmount = uint256(newLiquidity).mul(__supply).div(previousLiquidity);
    }
    // Mint users their tokens
    _mint(msg.sender, mintAmount);
  }

  /**
   * @notice Add liquidity to this uniswap pool manager
   * @param newLiquidity The amount of liquidty that the user wish to add
   */
  function deposit(uint128 newLiquidity) external returns (uint256 mintAmount) {
    //Since we'll mint a new position, why not burn and mint according to the desired range
    //Useful to benchmark the gas increase to the end user and possibly avoid to have to call rebalance at all.
    // In case of a multi tranche scenario, rebalancing all might be too expensive, but we could consider a round-robin
    (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);
    uint128 previousLiquidity = position.uniLiquidity;

    (int24 _nextLowerTick, int24 _nextUpperTick) = getNextTicks();
    uint128 compoundLiquidity = 0;
    //A possible optimization is only rebalance if the the tick diff is significant enough
    uint256 collected0 = 0;
    uint256 collected1 = 0;
    if (position.uniLiquidity > 0 && (_currentLowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick)) {
      (collected0, collected1) = _burnOnUniswap(_currentLowerTick, _currentUpperTick, position.uniLiquidity, address(this));

      //Figure how much liquity we can get from our current balances
      (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

      compoundLiquidity = LiquidityAmounts.getLiquidityForAmounts(
        sqrtRatioX96,
        TickMath.getSqrtRatioAtTick(_nextLowerTick),
        TickMath.getSqrtRatioAtTick(_nextUpperTick),
        collected0,
        collected1
      );
    }

    _mintOnUniswap(_nextLowerTick, _nextUpperTick, newLiquidity + compoundLiquidity, abi.encode(msg.sender, collected0, collected1));

    //TODO double check this calculation
    uint256 __supply = _totalSupply;
    if (__supply == 0) {
      mintAmount = newLiquidity;
    } else {
      mintAmount = uint256(newLiquidity).mul(__supply).div(previousLiquidity);
    }
    // Mint users their tokens
    _mint(msg.sender, mintAmount);
  }

  /**
   * @notice Remove liquidity and withdraw the underlying assests
   * @param liquidityAmount The amount of liquidity to withdraw
   */
  function withdraw(uint256 liquidityAmount)
    external
    returns (
      uint256 amount0,
      uint256 amount1,
      uint128 liquidityBurned
    )
  {
    (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);
    uint256 __supply = _totalSupply;

    _burn(msg.sender, liquidityAmount);

    uint256 _liquidityBurned = liquidityAmount.mul(__supply).div(position.uniLiquidity);
    require(_liquidityBurned < uint256(0 - 1));
    liquidityBurned = uint128(_liquidityBurned);

    (uint256 amount0, uint256 amount1) = _burnOnUniswap(_currentLowerTick, _currentUpperTick, liquidityBurned, msg.sender);
  }

  /**
   * @notice Public function to get both the redemption and ETH/USD price
   * @return redemptionPrice The redemption prince in usd
   * @return ethUsdPrice The eth/usd price
   */
  function getPrices() public returns (uint256 redemptionPrice, uint256 ethUsdPrice) {
    redemptionPrice = oracleRelayer.redemptionPrice();
    // TODO change to "ETH-A" for mainnet
    (OracleLike osm, , ) = oracleRelayer.collateralTypes(bytes32("ETH"));
    bool valid;
    (ethUsdPrice, valid) = osm.getResultWithValidity();
    require(valid, "GebUniswapv3LiquidtyManager/invalid-price-feed");
  }

  /**
   * @notice Function that returns the next target ticks based on the redemption price
   * @return _nLower The lower bound of the range
   * @return _nUpper The upper bound of the range
   */
  function getNextTicks() public returns (int24 _nLower, int24 _nUpper) {
    (uint256 redemptionPrice, uint256 ethUsdPrice) = getPrices();

    // we need to know beforeHand which of the two is token0 and which is token1, because that affects how price is calculated
    //4.From 3,get the sqrtPriceX96

    uint160 sqrtRedPriceX96;
    if (!raiIsT0) {
      sqrtRedPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
    } else {
      sqrtRedPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
    }

    //5. Calculate the tick that the redemption price is at
    int24 targetTick = TickMath.getTickAtSqrtRatio(sqrtRedPriceX96);
    int24 spacedTick = targetTick - (targetTick % tickSpacing);

    //5. Find + and - ticks according to threshold
    // Ticks are discrete so this calculation might give us a tick that is between two valid ticks. Still not sure about the consequences
    int24 lowerTick = spacedTick - int24(threshold) < MIN_TICK ? MIN_TICK : spacedTick - int24(threshold);
    int24 upperTick = spacedTick + int24(threshold) > MAX_TICK ? MAX_TICK : spacedTick + int24(threshold);

    return (lowerTick, upperTick);
  }

  /**
   * @notice Public function to rebalance the pool position to the correct threshold from the redemption price
   */
  function rebalance() external {
    require(block.timestamp - lastRebalance >= delay, "GebUniswapv3LiquidtyManager/too-soon");
    // Read all this from storage to minimize SLOADs
    (int24 _currentLowerTick, int24 _currentUpperTick) = (position.lowerTick, position.upperTick);

    (int24 _nextLowerTick, int24 _nextUpperTick) = getNextTicks();

    if (_currentLowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick) {
      // Get the fees
      (uint256 collected0, uint256 collected1) = _burnOnUniswap(_currentLowerTick, _currentUpperTick, position.uniLiquidity, address(this));

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
  }

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
    (uint256 amountDeposited0, uint256 amountDeposited1) = pool.mint(address(this), lowerTick, upperTick, totalLiquidity, callbackData);
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
    address recipient
  ) private returns (uint256 collected0, uint256 collected1) {
    // We can request MAX_INT, and Uniswap will just give whatever we're owed
    uint128 requestAmount0 = uint128(0) - 1;
    uint128 requestAmount1 = uint128(0) - 1;

    (uint256 _owed0, uint256 _owed1) = pool.burn(lowerTick, upperTick, burnedLiquidity);

    // If we're withdrawing for a specific user, then we only want to withdraw what they're owed
    if (recipient != address(this)) {
      // TODO: can we trust Uniswap and safely cast here?
      requestAmount0 = uint128(_owed0);
      requestAmount1 = uint128(_owed1);
    }
    // Collect all owed
    (collected0, collected1) = pool.collect(recipient, lowerTick, upperTick, requestAmount0, requestAmount1);
    //update position
    // All other factors are still the same
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
}
