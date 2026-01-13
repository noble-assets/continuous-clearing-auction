// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {MockERC20} from 'solmate/src/test/utils/mocks/MockERC20.sol';

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract AuctionNobleScript is Script {
    address constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0xaD354CfBAa4A8572DD6Df021514a3931A8329Ef5;
    address constant NOBLE_TOKEN = 0xe995e5A3A4BF15498246D7620CA39f7409397326;
    address constant NOBLE_WHALE = 0x8e18edE9d3cf753a6343fEFedD9ddbff654F7722;
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint128 constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 constant FLOOR_PRICE = 1e18;
    uint256 constant TICK_SPACING = 1e16;
    uint256 constant AUCTION_DURATION = 100;

    ContinuousClearingAuction public auction;
    IERC20 public currency;
    IERC20 public nobleToken;

    address owner;
    address tokensRecipient;
    address fundsRecipient;

    // Multiple bidders
    address[] bidders;
    uint256[] bidIds;
    uint64[] bidSubmitBlocks;
    uint256[] bidMaxPrices;
    uint128[] bidAmounts;

    function run() external {
        uint256 forkId = vm.createFork('https://eth-mainnet.public.blastapi.io');
        vm.selectFork(forkId);

        owner = makeAddr('owner');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        nobleToken = IERC20(NOBLE_TOKEN);
        currency = IERC20(USDC_ADDR);

        // Create multiple bidders
        for (uint256 i = 0; i < 5; i++) {
            bidders.push(makeAddr(string(abi.encodePacked('bidder', i))));
        }

        console.log('=== SETUP ===');

        // Transfer USDC to bidders
        for (uint256 i = 0; i < bidders.length; i++) {
            vm.prank(USDC_WHALE);
            IERC20(USDC_ADDR).transfer(bidders[i], 10_000_000e6);
        }

        uint64 startBlock = uint64(block.number + 1);
        uint64 endBlock = startBlock + uint64(AUCTION_DURATION);

        AuctionParameters memory params = AuctionParameters({
            currency: address(currency),
            floorPrice: FLOOR_PRICE,
            tickSpacing: TICK_SPACING,
            validationHook: address(0),
            fundsRecipient: fundsRecipient,
            tokensRecipient: tokensRecipient,
            startBlock: startBlock,
            endBlock: endBlock,
            claimBlock: endBlock,
            requiredCurrencyRaised: 1,
            auctionStepsData: abi.encodePacked(uint24(100e3), uint40(AUCTION_DURATION))
        });

        vm.prank(owner);
        auction = new ContinuousClearingAuction(NOBLE_TOKEN, TOTAL_SUPPLY, params);

        vm.prank(NOBLE_WHALE);
        nobleToken.transfer(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        console.log('Start block:', startBlock);
        console.log('End block:', endBlock);
        console.log('Total supply:', TOTAL_SUPPLY / 1e18);

        // Approve Permit2 for all bidders
        for (uint256 i = 0; i < bidders.length; i++) {
            vm.startPrank(bidders[i]);
            currency.approve(PERMIT2_ADDRESS, type(uint256).max);
            IPermit2(PERMIT2_ADDRESS).approve(address(currency), address(auction), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }

        // ============ BIDDING PHASE ============
        // Enter bids at block 1 (minimal delay) to maximize time in auction
        uint64 currentBlock = startBlock + 1;
        vm.roll(currentBlock);
        console.log('\n=== ENTERING BIDS EARLY (BLOCK 1) ===');
        console.log('Current block:', currentBlock);

        // Submit bids at different max prices
        // Total demand: 25M currency for 1M tokens
        console.log('\n=== BIDS WITH VARIED MAX PRICES ===');
        _submitBid(0, 30e18, 3_000_000e6, 'Bidder 0 - 3M currency, max price 30');
        _submitBid(1, 40e18, 5_000_000e6, 'Bidder 1 - 5M currency, max price 40');
        _submitBid(2, 50e18, 4_000_000e6, 'Bidder 2 - 4M currency, max price 50');
        _submitBid(3, 60e18, 7_000_000e6, 'Bidder 3 - 7M currency, max price 60');
        _submitBid(4, 70e18, 6_000_000e6, 'Bidder 4 - 6M currency, max price 70');

        console.log('\nTotal bid amount: 25,000,000 currency');
        console.log('Total supply: 1,000,000 tokens');

        // Checkpoint to process all bids together
        vm.roll(block.number + 1);
        auction.checkpoint();
        console.log('\nClearing price after all bids:', auction.clearingPrice());

        // Roll to end
        vm.roll(endBlock);
        console.log('\n=== AUCTION ENDED ===');

        // Final checkpoint
        auction.checkpoint();

        console.log('Is graduated:', auction.isGraduated());

        // ============ SWEEP OPERATIONS ============

        // Sweep currency
        console.log('\n=== SWEEPING CURRENCY ===');
        uint256 fundsBefore = currency.balanceOf(fundsRecipient);
        auction.sweepCurrency();
        uint256 currencyRaised = currency.balanceOf(fundsRecipient) - fundsBefore;
        console.log('Currency raised:', currencyRaised / 1e6);

        // Sweep unsold tokens
        console.log('\n=== SWEEPING UNSOLD TOKENS ===');
        uint256 tokensBefore = nobleToken.balanceOf(tokensRecipient);
        auction.sweepUnsoldTokens();
        uint256 unsoldTokens = nobleToken.balanceOf(tokensRecipient) - tokensBefore;
        console.log('Unsold tokens:', unsoldTokens / 1e18);

        // Burn sold tokens
        console.log('\n=== BURNING SOLD TOKENS ===');
        uint256 toBurn = nobleToken.balanceOf(address(auction));
        console.log('Tokens to burn:', toBurn / 1e18);
        auction.burnSoldTokens();
        console.log('Burn block:', auction.burnBlock());

        // ============ FINAL SUMMARY ============
        console.log('\n========================================');
        console.log('          FINAL SUMMARY');
        console.log('========================================');
        console.log('Total supply:        ', TOTAL_SUPPLY / 1e18);
        console.log('Total bid amount:    25_000_000');
        console.log('Max prices:          30, 40, 50, 60, 70');
        console.log('Tokens unsold:       ', unsoldTokens / 1e18);
        console.log('Tokens burned:       ', toBurn / 1e18);
        console.log('Currency raised:     ', currencyRaised / 1e6);
        console.log('Auction balance:     ', nobleToken.balanceOf(address(auction)));
        console.log('========================================');

        // Verify
        require(nobleToken.balanceOf(address(auction)) == 0, 'Auction should be empty');
        require(auction.burnBlock() != 0, 'Burn should have happened');
        require(currencyRaised > 0, 'Should have raised currency');

        console.log('\n=== SUCCESS ===');
    }

    function _submitBid(uint256 bidderIndex, uint256 maxPrice, uint128 amount, string memory description) internal {
        address bidder = bidders[bidderIndex];

        vm.prank(bidder);
        uint256 bidId = auction.submitBid(maxPrice, amount, bidder, FLOOR_PRICE, bytes(''));

        bidIds.push(bidId);
        bidSubmitBlocks.push(uint64(block.number));
        bidMaxPrices.push(maxPrice);
        bidAmounts.push(amount);

        console.log('');
        console.log(description);
        console.log('  Block:', block.number);
        console.log('  Amount:', amount / 1e6);
    }
}
