pragma solidity 0.6.7;

import "./GebUniswapV3ManagerBase.sol";


/**
 * @notice This contract is based on https://github.com/dmihal/uniswap-liquidity-dao/blob/master/contracts/MetaPool.sol
 */
contract GebUniswapV3LiquidityManager is GebUniswapV3ManagerBase {

    // This contracts' position in the Uniswap V3 pool
    Position public position;
    // Last price used for rebalancing
    int24 lastRebalancePrice;

    /**
     * @notice Constructor that sets initial parameters for this contract
     * @param name_ The name of the ERC20 this contract will distribute
     * @param symbol_ The symbol of the ERC20 this contract will distribute
     * @param systemCoinAddress_ The address of the system coin
     * @param threshold_ The liquidity threshold around the redemption price
     * @param delay_ The minimum required time before rebalance() can be called
     * @param pool_ Address of the already deployed Uniswap v3 pool that this contract will manage
     * @param oracle_ Address of the already deployed oracle that provides both token prices
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address systemCoinAddress_,
        uint256 threshold_,
        uint256 delay_,
        address pool_,
        bytes32 collateralType_,
        OracleForUniswapLike oracle_,
        PoolViewer poolViewer_
    ) public GebUniswapV3ManagerBase(name_, symbol_,systemCoinAddress_,delay_,pool_,oracle_,poolViewer_) {
        require(threshold_ >= MIN_THRESHOLD && threshold_ <= MAX_THRESHOLD, "GebUniswapv3LiquidityManager/invalid-threshold");
        require(threshold_ % uint256(tickSpacing) == 0, "GebUniswapv3LiquidityManager/threshold-incompatible-w/-tick-spacing");
        require(delay_ >= MIN_DELAY && delay_ <= MAX_DELAY, "GebUniswapv3LiquidityManager/invalid-delay");

        int24 target = getTargetTick();
        (int24 lower, int24 upper) = getTicksWithThreshold(target, threshold_);

        position = Position({ id: keccak256(abi.encodePacked(address(this), lower, upper)), lowerTick: lower, upperTick: upper, uniLiquidity: 0, threshold: threshold_ });
    }


    // --- Getters ---

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount0 The amount of token0 received for the liquidity amount
     * @return amount1 The amount of token0 received for the liquidity amount
     */
    function getTokenAmountsFromLiquidity(uint128 _liquidity) public returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = _getTokenAmountsFromLiquidity(position, _liquidity);
    }

    /**
     * @notice Returns the current amount of token0 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount0 The amount of token0 received for the liquidity amount
     */
    function getToken0FromLiquidity(uint128 _liquidity) public returns (uint256 amount0) {
        if (_liquidity == 0) return 0;
        (amount0, ) = _getTokenAmountsFromLiquidity(position, _liquidity);
    }

    /**
     * @notice Returns the current amount of token1 for a given liquidity amount
     * @param _liquidity The amount of liquidity to withdraw
     * @return amount1 The amount of token1 received for the liquidity amount
     */
    function getToken1FromLiquidity(uint128 _liquidity) public returns (uint256 amount1) {
        if (_liquidity == 0) return 0;
        (, amount1) = _getTokenAmountsFromLiquidity(position, _liquidity);
    }

    /**
     * @notice Add liquidity to this pool manager
     * @param newLiquidity The amount of liquidty that the user wishes to add
     * @param recipient The address that will receive ERC20 wrapper tokens for the provided liquidity
     * @dev In case of a multi-tranche scenario, rebalancing all tranches might be too expensive for the end user.
     *      A round robin could be done where, in each deposit, only one of the pool's positions is rebalanced
     */
    function deposit(uint128 newLiquidity, address recipient) external returns (uint256 mintAmount) {
        require(recipient != address(0), "GebUniswapv3LiquidityManager/invalid-recipient");


        uint128 totalLiquidity = position.uniLiquidity;
        int24 target= getTargetTick();

        mintAmount = _deposit(position, newLiquidity, target);

        // Calculate and mint a user's ERC20 liquidity tokens
        uint256 __supply = _totalSupply;
        if (__supply == 0) {
            mintAmount = newLiquidity;
        } else {
            mintAmount = uint256(newLiquidity).mul(_totalSupply).div(totalLiquidity);
        }

        _mint(recipient, uint256(mintAmount));

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
        
        // Burn sender tokens
        _burn(msg.sender, uint256(liquidityAmount));

        uint128 _liquidityBurned = liquidityAmount.mul(position.uniLiquidity).div(__supply);

        (amount0, amount1) = _withdraw(position, _liquidityBurned, recipient);
        emit Withdraw(msg.sender, recipient, liquidityAmount);
    }

    /**
     * @notice Public function to move liquidity to the correct threshold from the redemption price
     */
    function rebalance() external {
       require(block.timestamp.sub(lastRebalance) >= delay, "GebUniswapv3LiquidityManager/too-soon");

        int24 target= getTargetTick();

        _rebalance(position , target);
    }
}
