// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import {IHederaTokenService} from '../interfaces/IHederaTokenService.sol';

/// @title NFTHelper
/// @notice Contains helper method for interacting with Hedera tokens that do not consistently return SUCCESS
library NFTHelper {
    error HederaFail(int respCode);

    address constant private precompileAddress = address(0x167);

    /// @notice Mints tokens to account
    /// @dev Calls mint on token contract, errors with HederaFail if mint fails
    /// @param token The token id to mint
    /// @param amount The amount of tokens to mint
    /// @param metadata The metadata of the NFT
    function safeMintTokens(
        address token, 
        int64 amount, 
        bytes[] memory metadata
    ) internal {
        
        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.mintToken.selector,
            token, amount, metadata));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert HederaFail(responseCode);
        }
    }

    /// @notice Burns tokens to account
    /// @dev Calls burn on token contract, errors with HederaFail if burn fails
    /// @param token The token id to burn
    /// @param amount The amount of tokens to burn
    /// @param serialNumbers The serial numbers to burn
    function safeBurnTokens(
        address token, 
        int64 amount, 
        int64[] memory serialNumbers
    ) internal {
        
        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.burnToken.selector,
            token, amount, serialNumbers));
        int32 responseCode = success ? abi.decode(result, (int32)) : int32(21); // 21 = unknown
        
        if (responseCode != 22) {
            revert HederaFail(responseCode);
        }
    }

    /// Transfers tokens where the calling account/contract is implicitly the first entry in the token transfer list,
    /// where the amount is the value needed to zero balance the transfers. Regular signing rules apply for sending
    /// (positive amount) or receiving (negative amount)
    /// @param token The token to transfer to/from
    /// @param sender The sender for the transaction
    /// @param receiver The receiver of the transaction
    /// @param serialNumber The serial number of the NFT to transfer.
    function safeTransferNFT(address token, address sender, address receiver, int64 serialNumber) internal
        returns (int responseCode)
    {
        (bool success, bytes memory result) = precompileAddress.call(
            abi.encodeWithSelector(IHederaTokenService.transferNFT.selector,
            token, sender, receiver, serialNumber));
        responseCode = success ? abi.decode(result, (int32)) : int32(21);

        if (responseCode != 22) {
            revert HederaFail(responseCode);
        }
    }
}