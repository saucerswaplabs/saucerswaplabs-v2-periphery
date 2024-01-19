// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import {IHederaTokenService} from '../interfaces/IHederaTokenService.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/libraries/SafeCast.sol';

library TransferHelper {
    address internal constant precompileAddress = address(0x167);

    event Transfer(address indexed from, address indexed to, uint256 value, address indexed token);
    event Approval(address indexed from, address indexed to, uint256 value, address indexed token);
    error RespCode(int32 respCode);

    /// @notice Transfers tokens from the targeted address to the given destination
    /// @param token The contract address of the token to be transferred
    /// @param sender The originating address from which the tokens will be transferred
    /// @param receiver The destination address of the transfer
    /// @param amount The amount to be transferred
    function safeTransferFrom(
        address token,
        address sender,
        address receiver,
        uint256 amount
    ) internal {

        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.transferToken.selector,
            token, sender, receiver, SafeCast.toInt64(amount)));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert RespCode(responseCode);
        }

        emit Transfer(sender, receiver, amount, token);
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @param token The contract address of the token which will be transferred
    /// @param receiver The recipient of the transfer
    /// @param amount The value of the transfer
    function safeTransfer(
        address token,
        address receiver,
        uint256 amount
    ) internal {
        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.transferToken.selector,
            token, address(this), receiver, SafeCast.toInt64(amount)));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert RespCode(responseCode);
        }

        emit Transfer(address(this), receiver, amount, token);
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @param token The contract address of the token to be approved
    /// @param spender The target of the approval
    /// @param amount The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.approve.selector,
            token, spender, SafeCast.toInt64(amount)));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert RespCode(responseCode);
        }

        emit Approval(address(this), spender, amount, token);
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}
