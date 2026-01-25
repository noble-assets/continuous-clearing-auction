// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {ContinuousClearingAuction} from '../../../src/ContinuousClearingAuction.sol';
import {console2} from "forge-std/console2.sol";
import {MockUSDC} from './Deploy.s.sol';

contract CCABidScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ContinuousClearingAuction auction = ContinuousClearingAuction(vm.envAddress("AUCTION_ADDRESS"));

				address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // first anvil account
				MockUSDC currency = MockUSDC(auction.currency());
				uint256 balance = currency.balanceOf(owner);

				uint256 clearingPrice = auction.clearingPrice();
        uint256 maxPrice = auction.floorPrice() + auction.tickSpacing(); // Bid at the next possible price
        uint128 amount = 1 ether;

        uint256 bidId = auction.submitBid(maxPrice, amount, owner, bytes(""));

        console2.log("Bid submitted with ID:", bidId);

        vm.stopBroadcast();
    }
}