// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.12;

import '../base/PeripheryImmutableState.sol';

contract PeripheryImmutableStateTest is PeripheryImmutableState {
    constructor(address _factory, address _WHBAR) PeripheryImmutableState(_factory, _WHBAR) {}
}
