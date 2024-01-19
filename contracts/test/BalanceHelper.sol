// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.12;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

contract BalanceHelper {
    function getNFTBalance(address token, address account) external view returns (uint) {
        return IERC721(token).balanceOf(account);
    }

    function getTokenBalance(address token, address account) external view returns (uint) {
        return IERC20(token).balanceOf(account);
    }
}
