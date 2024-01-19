// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import {IHederaTokenService} from '../interfaces/IHederaTokenService.sol';

/// @title AssociateHelper
/// @notice Contains helper method for interacting with Hedera tokens that do not consistently return SUCCESS
library AssociateHelper {
    error AssociateFail(int respCode);

    /// @notice Associates token to account
    /// @dev Calls associate on token contract, errors with AssociateFail if association fails
    /// @param account The target of the association
    /// @param token The solidity address of the token to associate to target
    function safeAssociateToken(
        address account,
        address token
    ) internal {
        address precompileAddress = address(0x167);

        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector,
            account, token));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert AssociateFail(responseCode);
        }
    }
}