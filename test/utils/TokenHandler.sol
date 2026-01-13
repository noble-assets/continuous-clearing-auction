// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

contract ERC20MockAuction is ERC20Mock {
    constructor() ERC20Mock() {}

    function burn() public {
        uint256 balance = balanceOf(msg.sender);
        _burn(msg.sender, balance);
    }
}

/// @notice Handler contract for setting up tokens
abstract contract TokenHandler {
    ERC20MockAuction public token;
    ERC20MockAuction public erc20Currency;
    address public constant ETH_SENTINEL = address(0);

    function setUpTokens() public {
        token = new ERC20MockAuction();
        erc20Currency = new ERC20MockAuction();
    }
}
