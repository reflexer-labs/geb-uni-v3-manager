pragma solidity ^0.6.7;

contract PoolViewer {
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

    function mintViewer(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external {
        (bool success, bytes memory ret) =
            pool.delegatecall(abi.encodeWithSignature("mint(address,int24,int24,uint128,bytes)", recipient, tickLower, tickUpper, amount, data));
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

    function collectViewer(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external {
        (bool success, bytes memory ret) =
            pool.delegatecall(
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

    function burnViewer(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external {
        (bool success, bytes memory ret) = pool.delegatecall(abi.encodeWithSignature("burn(int24,int24,uint128)", tickLower, tickUpper, amount));
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
