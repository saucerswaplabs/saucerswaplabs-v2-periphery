// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.12;

import '../interfaces/IPeripheryImmutableState.sol';
import '../interfaces/external/IWHBAR.sol';
import '../libraries/AssociateHelper.sol';

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override factory;
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override WHBAR; // the contract
    address public immutable override whbar; // the token

    constructor(address _factory, address _WHBAR) {
        factory = _factory;
        WHBAR = _WHBAR;
        whbar = IWHBAR(_WHBAR).token();
        
        AssociateHelper.safeAssociateToken(address(this), whbar);
    }
}
