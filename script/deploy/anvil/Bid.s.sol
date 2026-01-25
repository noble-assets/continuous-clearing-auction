// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {ContinuousClearingAuction} from '../../../src/ContinuousClearingAuction.sol';
import {IAllowanceTransfer} from '../../../lib/permit2/src/interfaces/IAllowanceTransfer.sol';
import {console2} from "forge-std/console2.sol";
import {MockUSDC} from './Deploy.s.sol';

contract CCABidScript is Script {
    // Permit2 canonical address (on mainnet)
    address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ContinuousClearingAuction auction = ContinuousClearingAuction(vm.envAddress("AUCTION_ADDRESS"));

        address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // first anvil account
        MockUSDC currency = MockUSDC(auction.currency());
        uint256 balance = currency.balanceOf(owner);

        console2.log("Owner USDC balance:", balance / 1e6);

        // Find Permit2 address - try env var first, then canonical address
        address permit2Address;
        try vm.envAddress("PERMIT2_ADDRESS") returns (address envPermit2) {
            permit2Address = envPermit2;
            console2.log("Using Permit2 from PERMIT2_ADDRESS env var:", permit2Address);
        } catch {
            // Fallback to canonical address
            permit2Address = PERMIT2_CANONICAL;
            console2.log("PERMIT2_ADDRESS not set, trying canonical address:", permit2Address);
        }

        // Verify Permit2 exists at the chosen address
        if (permit2Address.code.length == 0) {
            revert(
                string.concat(
                    "Permit2 not found at address ",
                    vm.toString(permit2Address),
                    ". Please deploy Permit2 first using 'make deploy' and set PERMIT2_ADDRESS env var if it deployed to a different address."
                )
            );
        }

        console2.log("Using Permit2 at:", permit2Address);

        // Approve Permit2 to spend USDC
        currency.approve(permit2Address, type(uint256).max);

        // Approve auction via Permit2
        IAllowanceTransfer permit2 = IAllowanceTransfer(permit2Address);
        permit2.approve(address(currency), address(auction), type(uint160).max, type(uint48).max);

        uint256 maxPrice = auction.floorPrice() + auction.tickSpacing(); // Bid at the next possible price

        // Use USDC units (6 decimals) instead of ether (18 decimals)
        // 1 USDC = 1e6
        uint128 amount = 1e6; // 1 USDC

        console2.log("Submitting bid with amount:", amount / 1e6, "USDC");
        console2.log("Max price (Q96):", maxPrice);
        console2.log("Floor price (Q96):", auction.floorPrice());
        console2.log("Tick spacing (Q96):", auction.tickSpacing());

        uint256 bidId = auction.submitBid(maxPrice, amount, owner, bytes(""));

        console2.log("Bid submitted with ID:", bidId);

        vm.stopBroadcast();
    }
}