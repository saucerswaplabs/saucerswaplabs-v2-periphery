// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.12;

import '@saucerswaplabs/saucerswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/libraries/HbarConversion.sol';

import './PeripheryImmutableState.sol';
import '../interfaces/IPoolInitializer.sol';

/// @title Creates and initializes V3 Pools
abstract contract PoolInitializer is IPoolInitializer, PeripheryImmutableState {
    /// @inheritdoc IPoolInitializer
    /// @dev we recommend calling this function using a multicall with refundETH
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        require(token0 < token1);
        
        pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            uint256 poolCreateFee = IUniswapV3Factory(factory).poolCreateFee();
            uint256 poolCreateFeeInTinybars;
            if(poolCreateFee > 0) {
                poolCreateFeeInTinybars = HbarConversion.tinycentsToTinybars(poolCreateFee);
                
                // Slop for conversion rounding
                poolCreateFeeInTinybars += 1;
                require(address(this).balance >= poolCreateFeeInTinybars, 'PCF');
            }
            pool = IUniswapV3Factory(factory).createPool{value: poolCreateFeeInTinybars}(token0, token1, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
