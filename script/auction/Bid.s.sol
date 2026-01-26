// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function allowance(address user, address token, address spender) external view returns (uint160, uint48, uint48);
}

contract BidScript is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        address auctionAddr = vm.envAddress('AUCTION');
        uint128 amount = uint128(vm.envUint('AMOUNT'));

        ContinuousClearingAuction auction = ContinuousClearingAuction(auctionAddr);
        address currency = auction.currency();

        // Use a very high max price for market order behavior
        uint256 tickSpacing = auction.tickSpacing();
        uint256 floorPrice = auction.floorPrice();
        uint256 rawMaxPrice = vm.envOr('MAX_PRICE', uint256(0));

        uint256 maxPrice;
        if (rawMaxPrice == 0) {
            // Default: 1 billion ticks above floor
            maxPrice = floorPrice + (tickSpacing * 1_000_000_000);
        } else {
            // Align provided price to tick boundary
            maxPrice = floorPrice + ((rawMaxPrice - floorPrice) / tickSpacing) * tickSpacing;
        }

        vm.startBroadcast();

        // Approve Permit2 if needed
        IERC20 token = IERC20(currency);
        if (token.allowance(msg.sender, PERMIT2) < amount) {
            console.log('Approving Permit2...');
            token.approve(PERMIT2, type(uint256).max);
        }

        // Approve auction via Permit2 if needed
        (uint160 permitAllowance,,) = IPermit2(PERMIT2).allowance(msg.sender, currency, auctionAddr);
        if (permitAllowance < amount) {
            console.log('Approving auction via Permit2...');
            IPermit2(PERMIT2).approve(currency, auctionAddr, type(uint160).max, type(uint48).max);
        }

        // Submit bid
        uint256 bidId = auction.submitBid(maxPrice, amount, msg.sender, auction.floorPrice(), bytes(''));

        vm.stopBroadcast();

        console.log('Bid placed successfully!');
        console.log('Bid ID:', bidId);
        console.log('Amount:', amount);
        console.log('Max Price:', maxPrice);
    }
}
