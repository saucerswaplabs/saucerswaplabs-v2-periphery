// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './PeripheryPayments.sol';
import '../interfaces/IPeripheryPaymentsWithFee.sol';

import '../interfaces/external/IWHBAR.sol';
import '../libraries/TransferHelper.sol';

abstract contract PeripheryPaymentsWithFee is PeripheryPayments, IPeripheryPaymentsWithFee {
    /// @inheritdoc IPeripheryPaymentsWithFee
    function unwrapWHBARWithFee(
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    ) public payable override {
        require(feeBips > 0 && feeBips <= 100);

        uint256 balanceWHBAR = IERC20(whbar).balanceOf(address(this));
        require(balanceWHBAR >= amountMinimum, 'Insufficient WHBAR fee');

        if (balanceWHBAR > 0) {
            TransferHelper.safeApprove(whbar, WHBAR, balanceWHBAR);
            IWHBAR(WHBAR).withdraw(balanceWHBAR);
            uint256 feeAmount = (balanceWHBAR * feeBips) / 10_000;
            if (feeAmount > 0) TransferHelper.safeTransferETH(feeRecipient, feeAmount);
            TransferHelper.safeTransferETH(recipient, balanceWHBAR - feeAmount);
        }
    }

    /// @inheritdoc IPeripheryPaymentsWithFee
    function sweepTokenWithFee(
        address token,
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    ) public payable override {
        require(feeBips > 0 && feeBips <= 100);

        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, 'Insufficient token');

        if (balanceToken > 0) {
            uint256 feeAmount = (balanceToken * feeBips) / 10_000;
            if (feeAmount > 0) TransferHelper.safeTransfer(token, feeRecipient, feeAmount);
            TransferHelper.safeTransfer(token, recipient, balanceToken - feeAmount);
        }
    }
}
