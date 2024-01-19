// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// For Hedera, contract mocking is currently not possible.  This contract mocks the values in IUniswapV3Pool.sol
/// that PoolTicksCounter.sol uses.  This essentially acts as a mock and allows us to unit test the logic in the
/// contracts
contract MockPool {

    int24 public tickSpacing;
    mapping(int16 => uint256) public tickBitmap;

    function setTickBitmap(int16 _index, uint256 _value) external {
        tickBitmap[_index] = _value;
    }

    function setTickSpacing(int24 _tickSpacing) external {
        tickSpacing = _tickSpacing;
    }
}
