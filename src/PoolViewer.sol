pragma solidity ^0.6.7;

library PoolViewer {
    // --- Mint  ---
    /**
     * @notice Helper function to simulate(non state-mutating) a mint action on a uniswap v3 pool
     * @param pool The address of the target pool
     * @param recipient The address that will receive and pay for tokens
     * @param tickLower The lower bound of the range to deposit the liquidity to
     * @param tickUpper The upper bound of the range to deposit the liquidity to
     * @param amount The uamount of liquidity to mint
     * @param data The data for the callback function
     * @return success Indicating if the underlaying mint would succeed
     * @return amount0 The amount of token0 sent and 0 if success is false
     * @return amount1 The amount of token1 sent and 0 if success is false
     */
    function mint(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    )
        external
        returns (
            bool success,
            uint256 amount0,
            uint256 amount1
        )
    {
        (, bytes memory ret) =
            address(this).delegatecall(
                abi.encodeWithSignature("mintViewer(address,address,int24,int24,uint128,bytes)", pool, recipient, tickLower, tickUpper, amount, data)
            );
        uint256 result;
        (result, amount0, amount1) = abi.decode(ret, (uint256, uint256, uint256));
        success = result == 1 ? true : false;
    }

    /**
     * @notice DO NOT CALL Helper function to simulate(non state-mutating) a mint action on a uniswap v3 pool
     * @notice This function always revert, passing the desired returns values as revert reason
     */
    function mintViewer(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external {
        (bool success, bytes memory ret) =
            pool.call(abi.encodeWithSignature("mint(address,int24,int24,uint128,bytes)", recipient, tickLower, tickUpper, amount, data));
        uint256 succ;
        (uint256 amount0, uint256 amount1) = (0, 0);
        if (success) {
            succ = 1;
            (amount0, amount1) = abi.decode(ret, (uint256, uint256));
        } else {
            succ = 0;
        }
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, succ)
            mstore(add(ptr, 32), amount0)
            mstore(add(ptr, 64), amount1)
            revert(ptr, 96)
        }
    }

    // --- Collect  ---
    /**
     * @notice Helper function to simulate(non state-mutating) an action on a uniswap v3 pool
     * @param pool The address of the target pool
     * @param recipient The address that will receive and pay for tokens
     * @param tickLower The lower bound of the range to deposit the liquidity to
     * @param tickUpper The upper bound of the range to deposit the liquidity to
     * @param amount0Requested The amount of token0 requested
     * @param amount1Requested The amount of token1 requested
     * @return success Indicating if the underlaying function would succeed
     * @return amount0 The amount of token0 received
     * @return amount1 The amount of token1 received
     */
    function collect(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    )
        external
        returns (
            bool success,
            uint128 amount0,
            uint128 amount1
        )
    {
        (, bytes memory ret) =
            address(this).delegatecall(
                abi.encodeWithSignature(
                    "collectViewer(address,address,int24,int24,uint128,uint128)",
                    pool,
                    recipient,
                    tickLower,
                    tickUpper,
                    amount0Requested,
                    amount1Requested
                )
            );
        uint256 result;
        (result, amount0, amount1) = abi.decode(ret, (uint256, uint128, uint128));

        success = result == 1 ? true : false;
    }

    /**
     * @notice DO NOT CALL Helper function to simulate(non state-mutating) an action on a uniswap v3 pool
     * @notice This function always revert, passing the desired returns values as revert reason
     */
    function collectViewer(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external {
        (bool success, bytes memory ret) =
            pool.call(
                abi.encodeWithSignature("collect(address,int24,int24,uint128,uint128)", recipient, tickLower, tickUpper, amount0Requested, amount1Requested)
            );
        uint256 succ;
        (uint128 amount0, uint128 amount1) = (0, 0);
        if (success) {
            succ = 1;
            (amount0, amount1) = abi.decode(ret, (uint128, uint128));
        } else {
            succ = 0;
        }
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, succ)
            mstore(add(ptr, 32), amount0)
            mstore(add(ptr, 64), amount1)
            revert(ptr, 96)
        }
    }

    // --- Burn ---
    /**
     * @notice Helper function to simulate(non state-mutating) an action on a uniswap v3 pool
     * @param pool The address of the target pool
     * @param tickLower The lower bound of the uni v3 position
     * @param tickUpper The lower bound of the uni v3 position
     * @param amount The amount of liquidity to burn
     * @return success Indicating if the underlaying function would succeed
     * @return amount0 The amount of token0 received
     * @return amount1 The amount of token1 received
     */
    function burn(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    )
        external
        returns (
            bool success,
            uint256 amount0,
            uint256 amount1
        )
    {
        (, bytes memory ret) =
            address(this).delegatecall(abi.encodeWithSignature("burnViewer(address,int24,int24,uint128)", pool, tickLower, tickUpper, amount));
        uint256 result;
        (result, amount0, amount1) = abi.decode(ret, (uint256, uint256, uint256));

        success = result == 1 ? true : false;
    }

    /**
     * @notice DO NOT CALL Helper function to simulate(non state-mutating) action on a uniswap v3 pool
     * @notice This function always revert, passing the desired returns values as revert reason
     */
    function burnViewer(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external {
        (bool success, bytes memory ret) = pool.call(abi.encodeWithSignature("burn(int24,int24,uint128)", tickLower, tickUpper, amount));
        uint256 succ;
        (uint256 amount0, uint256 amount1) = (0, 0);
        if (success) {
            succ = 1;
            (amount0, amount1) = abi.decode(ret, (uint128, uint128));
        } else {
            succ = 0;
        }
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, succ)
            mstore(add(ptr, 32), amount0)
            mstore(add(ptr, 64), amount1)
            revert(ptr, 96)
        }
    }
}
