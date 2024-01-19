// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;
pragma abicoder v2;

import '../NonfungiblePositionManager.sol';

contract MockTimeNonfungiblePositionManager is NonfungiblePositionManager {
    uint256 time;

    constructor(
        address _factory,
        address _WHBAR
    ) NonfungiblePositionManager(_factory, _WHBAR) {} // token descriptor was third param

    function _blockTimestamp() internal view override returns (uint256) {
        return time;
    }

    function setTime(uint256 _time) external {
        time = _time;
    }
}
