// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;
pragma abicoder v2;

import '../SwapRouter.sol';

contract MockTimeSwapRouter is SwapRouter {
    uint256 time;

    constructor(address _factory, address _WHBAR) SwapRouter(_factory, _WHBAR) {}

    function _blockTimestamp() internal view override returns (uint256) {
        return time;
    }

    function setTime(uint256 _time) external {
        time = _time;
    }
}
