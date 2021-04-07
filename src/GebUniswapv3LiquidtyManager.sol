pragma solidity ^0.6.7;

import "ds-math/math.sol";
import "geb/OracleRelayer.sol";
import { DSToken } from "ds-token";
import { IUniswapV3Pool } from "./uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "./uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "./uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "./uni/libraries/TickMath.sol";

abstract contract OracleLike {
  function getResultWithValidity() public view virtual returns (uint256, bool);
}

/**
 * @notice This contracrt is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapv3LiquidtyManager is DSToken {
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

  address public immutable token0;
  address public immutable token1;

  IUniswapV3Pool public pool;
  OracleRelayer public oracleRelayer;

  int24 public currentLowerTick;
  int24 public currentUpperTick;

  //The threshold varies from 1 - 1000, meaning than 1 = 0.1% and 1000 = 100%. This is nice because each tick represents 0.1% diff in the price space, which makes the calculation quite easy
  uint256 public threshold;
  uint256 public delay;
  uint256 public lastRebalance;

  event ModifyParameters(bytes32 parameter, uint256 val);
  event AddAuthorization(address account);
  event RemoveAuthorization(address account);

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 threshold_,
    uint256 delay_,
    address token0_,
    address token1_,
    address pool_
  ) public DSToken(name_, symbol_) {
    threshold = threshold_;
    delay = delay_;
    token0 = token0_;
    token1 = token1_;
    pool = IUniswapV3Pool(pool_);
  }

  //should I use auth imported from dsToken or other scheme?
  function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
    if (parameter == "threshold") {
      require(data > 0 && data < 1000, "GebUniswapv3LiquidtyManager/invalid-thresold");
      threshold = data;
    }
    if (parameter == "delay") {
      require(data >= 360 && data <= 3600, "GebUniswapv3LiquidtyManager/invalid-delay");
      threshold = data;
    } else revert("GebUniswapv3LiquidtyManager/modify-unrecognized-param");
    emit ModifyParameters(parameter, data);
  }

  // Users use to add liquidity to this pool
  // amount0 and amount1 can be calculated offchain and approved. This contract only performs calculations in terms of liquidity
  function deposit(uint128 newLiquidity) external returns (uint256 mintAmount) {
    (int24 _currentLowerTick, int24 _currentUpperTick) = (currentLowerTick, currentUpperTick);

    bytes32 positionID = keccak256(abi.encodePacked(address(this), _currentLowerTick, _currentUpperTick));
    (uint128 _liquidity, , , , ) = pool.positions(positionID);

    pool.mint(address(this), _currentLowerTick, _currentUpperTick, newLiquidity, abi.encode(msg.sender));

    uint256 __supply = _supply;
    if (__supply == 0) {
      mintAmount = newLiquidity;
    } else {
      mintAmount = DSMath.mul(uint256(newLiquidity), (_supply)) / _liquidity;
    }
    // Mint users his tokens
    mint(msg.sender, mintAmount);

    //We can either mint new liquidity right now or wait for the next rebalance
    _uniMint(_currentLowerTick, _currentUpperTick, newLiquidity);
  }

  // Users use to remove liquidity to this pool
  function withdraw(uint256 burnAmount)
    external
    returns (
      uint256 amount0,
      uint256 amount1,
      uint128 liquidityBurned
    )
  {
    (int24 _currentLowerTick, int24 _currentUpperTick) = (currentLowerTick, currentUpperTick);
    uint256 __supply = _supply;

    bytes32 positionID = keccak256(abi.encodePacked(address(this), _currentLowerTick, _currentUpperTick));
    (uint128 _liquidity, , , , ) = pool.positions(positionID);

    burn(msg.sender, burnAmount);

    uint256 _liquidityBurned = DSMath.mul(burnAmount, __supply) / _liquidity;
    require(_liquidityBurned < uint256(0 - 1));
    liquidityBurned = uint128(_liquidityBurned);

    (amount0, amount1) = pool.burn(_currentLowerTick, _currentUpperTick, liquidityBurned);

    // Withdraw tokens to user
    pool.collect(
      msg.sender,
      _currentLowerTick,
      _currentUpperTick,
      uint128(amount0), // cast can't overflow
      uint128(amount1) // cast can't overflow
    );
  }

  //TODO
  // This function read both redemption price and eth-usd price to calculate what the next tick should be
  function _getNextTicks() private returns (int24 _nLower, int24 _nUpper) {
    //1. Get current redemption Price in USD terms
    uint256 redPrice = orcl.redemptionPrice();
    //2. Get usd-eth price
    address osm = oracleRelayer.collateralTypes(bytes32("ETH-A")).orcl;
    (uint256 ethUsh, bool valid) = OracleLike(osm).getResultWithValidity();
    require(valid, "GebUniswapv3LiquidtyManager/invalid-price-feed");
    //3. Use 1 and 2 to get red price in eth terms
    // we need to know beforeHand which of the two is token0 and which is token1, because that affects how price is calculated
    //4.From 3,get the sqrtPriceX96
    // I'm not sure id this formula gives a trustable sqrtPrice
    // Somewhere in their code, I saw the formula:
    //uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    //Some further research is needed to comprehend the differences between both
    uint160 sqrtPriceX96 = uint160(sqrt(ethUsd / redPrice));
    //5. Calculate the tick that the redemption price is at
    int24 redemptionTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

    //5. Find + and - ticks according to threshold
    // Ticks are discrete so this calculation might give us a tick that is between two valid ticks. Still not sure about the consequences
    int24 lowerTick = redemptionTick - threshold;
    int24 upperTick = redemptionTick + threshold;
    return (lowerTick, upperTick);
  }

  function rebalance() external {
    require(block.timestamp - lastRebalance >= delay, "GebUniswapv3LiquidtyManager/too-soon");
    // Read all this from storage to minimize SLOADs
    (int24 _currentLowerTick, int24 _currentUpperTick) = (currentLowerTick, currentUpperTick);

    (int24 _nextLowerTick, int24 _nextUpperTick) = _getNextTicks();

    if (_currentLowerTick != _nextLowerTick || _currentUpperTick != _nextUpperTick) {
      // We're just adjusting ticks
      bytes32 positionID = keccak256(abi.encodePacked(address(this), _currentLowerTick, _currentUpperTick));
      (uint128 _liquidity, , , , ) = pool.positions(positionID);
      (uint256 collected0, uint256 collected1) = _uniBurn(_currentLowerTick, _currentUpperTick, _liquidity, address(this));

      // Store new ticks
      (currentLowerTick, currentUpperTick) = (_nextLowerTick, _nextUpperTick);

      //Figure how much liquity we can get from our current balances
      (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

      // First, deposit as much as we can
      uint128 compoundLiquidity =
        LiquidityAmounts.getLiquidityForAmounts(
          sqrtRatioX96,
          TickMath.getSqrtRatioAtTick(currentLowerTick),
          TickMath.getSqrtRatioAtTick(currentUpperTick),
          collected0,
          collected1
        );

      _uniMint(_nextLowerTick, _nextUpperTick, compoundLiquidity);
    }
  }

  function _uniMint(
    int24 lowerTick,
    int24 upperTick,
    uint128 newLiquidity
  ) private {
    (uint256 amountDeposited0, uint256 amountDeposited1) = pool.mint(address(this), lowerTick, upperTick, newLiquidity, abi.encode(address(this)));
    // There might be outstanding amount. What to do?
  }

  function _uniBurn(
    int24 lowerTick,
    int24 upperTick,
    uint128 liquidity,
    address recipient
  ) private returns (uint256 collected0, uint256 collected1) {
    // We can request MAX_INT, and Uniswap will just give whatever we're owed
    uint128 requestAmount0 = uint128(0) - 1;
    uint128 requestAmount1 = uint128(0) - 1;

    (uint256 _owed0, uint256 _owed1) = pool.burn(lowerTick, upperTick, liquidity);

    // If we're withdrawing for a specific user, then we only want to withdraw what they're owed
    if (recipient != address(this)) {
      // TODO: can we trust Uniswap and safely cast here?
      requestAmount0 = uint128(_owed0);
      requestAmount1 = uint128(_owed1);
    }
    // Collect all owed
    (collected0, collected1) = pool.collect(recipient, lowerTick, upperTick, requestAmount0, requestAmount1);
  }

  function uniswapV3MintCallback(
    uint256 amount0Owed,
    uint256 amount1Owed,
    bytes calldata data
  ) external {
    require(msg.sender == address(pool));

    address sender = abi.decode(data, (address));

    if (sender == address(this)) {
      if (amount0Owed > 0) {
        TransferHelper.safeTransfer(token0, msg.sender, amount0Owed);
      }
      if (amount1Owed > 0) {
        TransferHelper.safeTransfer(token1, msg.sender, amount1Owed);
      }
    } else {
      if (amount0Owed > 0) {
        TransferHelper.safeTransferFrom(token0, sender, msg.sender, amount0Owed);
      }
      if (amount1Owed > 0) {
        TransferHelper.safeTransferFrom(token1, sender, msg.sender, amount1Owed);
      }
    }
  }

  function sqrt(uint256 y) internal pure returns (uint256 z) {
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
