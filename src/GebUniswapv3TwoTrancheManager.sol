pragma solidity 0.6.7;

import "./GebUniswapV3ManagerBase.sol";

/**
 * @notice This contract is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapV3TwoTrancheManager is GebUniswapV3ManagerBase {


    // --- Variables ---

    // Manager positions on uniswap pool
    Position[2] public positions;
    // Ratio for each pool in relation to the total capital, in percents. 1 == 1%
    uint128 ratio1;
    uint128 ratio2;

    /**
     * @notice Constructor that sets initial parameters for this contract
     * @param name_ The name of the ERC20 this contract will distribute
     * @param symbol_ The symbol of the ERC20 this contract will distribute
     * @param systemCoinAddress_ The address of the system coin
     * @param threshold_1 The liquidity threshold around the redemption price
     * @param threshold_2 The liquidity threshold around the redemption price
     * @param delay_ The minimum required time before rebalance() can be called
     * @param pool_ Address of the already deployed Uniswap v3 pool that this contract will manage
     * @param oracle_ Address of the already deployed oracle that provides both prices
     */
    constructor(
      string memory name_,
      string memory symbol_,
      address systemCoinAddress_,
      uint256 delay_,
      uint256 threshold_1,
      uint256 threshold_2,
      uint128 ratio_1,
      uint128 ratio_2,
      address pool_,
      OracleForUniswapLike oracle_,
      PoolViewer poolViewer_
    ) public GebUniswapV3ManagerBase(name_, symbol_,systemCoinAddress_,delay_,pool_,oracle_,poolViewer_) {
        require(threshold_1 >= MIN_THRESHOLD && threshold_1 <= MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
        require(threshold_1 % uint256(tickSpacing) == 0, "GebUniswapv3LiquidityManager/threshold-incompatible-w/-tickSpacing");
        
        require(threshold_2 >= MIN_THRESHOLD && threshold_2 <= MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-thresold");
        require(threshold_2 % uint256(tickSpacing) == 0, "GebUniswapv3LiquidityManager/threshold-incompatible-w/-tickSpacing");

        require(ratio_1.add(ratio_2) == 100,"GebUniswapv3LiquidityManager/invalid-ratios");

        ratio1 = ratio_1;
        ratio2 = ratio_2;
        
        // Initializing Starting positions
        int24 target = getTargetTick();
        (int24 lower_1, int24 upper_1) = getTicksWithThreshold(target, threshold_1);
        positions[0] = Position({
          id: keccak256(abi.encodePacked(address(this), lower_1, upper_1)),
          lowerTick: lower_1,
          upperTick: upper_1,
          uniLiquidity: 0,
          threshold: threshold_1
        });

        (int24 lower_2, int24 upper_2) = getTicksWithThreshold(target, threshold_2);
        positions[1] = Position({
          id: keccak256(abi.encodePacked(address(this), lower_2, upper_2)),
          lowerTick: lower_2,
          upperTick: upper_2,
          uniLiquidity: 0,
          threshold: threshold_2
        });
    }


    // --- Helper ---
    function getAmountFromRatio(uint128 _amount, uint128 _ratio) internal pure returns (uint128){
      return _amount.mul(_ratio).div(100);
    }

    // --- Getters ---

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount0 The amount of token0 received for the liquidity
     * @return amount1 The amount of token0 received for the liquidity
     */
    function getTokenAmountsFromLiquidity(uint128 _liquidity) public returns (uint256 amount0, uint256 amount1) {
        uint256 __supply = _totalSupply;
        uint128 _liquidityBurned = uint128(uint256(_liquidity).mul(positions[0].uniLiquidity + positions[1].uniLiquidity).div(__supply));
        (uint256 am0_pos0, uint256 am1_pos0) = _getTokenAmountsFromLiquidity(positions[0], _liquidityBurned);
        (uint256 am0_pos1, uint256 am1_pos1) = _getTokenAmountsFromLiquidity(positions[1], _liquidityBurned);
        (amount0, amount1) = (am0_pos0.add(am0_pos1), am1_pos0.add(am1_pos1));
    }

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount0 The amount of token0 received for the liquidity
     */
    function getToken0FromLiquidity(uint128 _liquidity) public returns (uint256 amount0) {
        if (_liquidity == 0) return 0;
        (uint256 am0_pos0, ) = _getTokenAmountsFromLiquidity(positions[0], _liquidity);
        (uint256 am0_pos1, ) = _getTokenAmountsFromLiquidity(positions[1], _liquidity);
        amount0 = am0_pos0.add(am0_pos1);
    }

    /**
     * @notice Returns the current amount of token1 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount1 The amount of token1 received for the liquidity
     */
    function getToken1FromLiquidity(uint128 _liquidity) public returns (uint256 amount1) {
        (,uint256 am1_pos0) = _getTokenAmountsFromLiquidity(positions[0], _liquidity);
        (,uint256 am1_pos1 ) = _getTokenAmountsFromLiquidity(positions[1], _liquidity);
        amount1 = am1_pos0.add(am1_pos1);
    }

    /**
     * @notice Add liquidity to this Uniswap pool manager
     * @param newLiquidity The amount of liquidty that the user wishes to add
     * @param recipient The address that will receive ERC20 wrapper tokens for the provided liquidity
     * @dev In case of a multi-tranche scenario, rebalancing all three might be too expensive for the ende user.
     *      A round robin could be done where in each deposit only one of the pool's positions is rebalanced
     */
    function deposit(uint128 newLiquidity, address recipient) external returns (uint256 mintAmount) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");

        uint128 totalLiquidity = positions[0].uniLiquidity + positions[1].uniLiquidity;
        int24 target= getTargetTick();

        uint256 mint1 = _deposit(positions[0], getAmountFromRatio(newLiquidity, ratio1), target);
        uint256 mint2 = _deposit(positions[1], getAmountFromRatio(newLiquidity, ratio2), target);

        mintAmount = mint1 + mint2;

        uint256 __supply = _totalSupply;
        if (__supply == 0) {
          mintAmount = newLiquidity;
        } else {
          mintAmount = uint256(newLiquidity).mul(_totalSupply).div(totalLiquidity);
        }

          _mint(recipient, mintAmount);

        emit Deposit(msg.sender, recipient, newLiquidity);
    }


    /**
     * @notice Remove liquidity and withdraw the underlying assets
     * @param liquidityAmount The amount of liquidity to withdraw
     * @param recipient The address that will receive token0 and token1 tokens
     * @return amount0 The amount of token0 requested from the pool
     * @return amount1 The amount of token1 requested from the pool
     */
    function withdraw(uint128 liquidityAmount, address recipient) external returns (uint256 amount0, uint256 amount1) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");
        require(liquidityAmount != 0, "GebUniswapv3LiquidityManager/burning-zero-amount");

        uint128 __supply = uint128(_totalSupply);
        require(_totalSupply < uint128(0 - 1));
        _burn(msg.sender, liquidityAmount);
        uint128 totalLiquidity = positions[0].uniLiquidity + positions[1].uniLiquidity;

        uint128 _liquidityBurned = liquidityAmount.mul(totalLiquidity).div(__supply);

        (uint256 am0_pos0, uint256 am1_pos0 ) = _withdraw(positions[0], getAmountFromRatio(_liquidityBurned, ratio1), recipient);
        (uint256 am0_pos1, uint256 am1_pos1 ) = _withdraw(positions[1], getAmountFromRatio(_liquidityBurned, ratio2), recipient);

        (amount0, amount1) = (am0_pos0.add(am0_pos1), am1_pos0.add(am1_pos1));
        emit Withdraw(msg.sender, recipient, liquidityAmount);
    }


    /**
     * @notice Public function to move liquidity to the correct threshold from the redemption price
     */
    function rebalance() external {
        require(block.timestamp.sub(lastRebalance) >= delay, "GebUniswapv3LiquidityManager/too-soon");

        int24 target= getTargetTick();

        // Cheaper calling twice than adding a for loop
        _rebalance(positions[0], target);
        _rebalance(positions[1], target);

        // Even if there's no change, we still update the time
        lastRebalance = block.timestamp;
        emit Rebalance(msg.sender, block.timestamp);
    }
}
