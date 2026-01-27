// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface INoble {
    function burn() external;
}

interface INobleBurner {
    function doBurn() external;
}

contract NobleBurner is INobleBurner {
    INoble immutable NOBLE;

    constructor(address _noble) {
        NOBLE = INoble(_noble);
    }

    function doBurn() external {
        NOBLE.burn();
    }
}

contract AuctionNoble is ERC20, Ownable {
    using SafeERC20 for IERC20;

    error NothingToMint();
    error AlreadyMintedToAuction();
    error NothingToRecover();

    event Burned(address indexed from, uint256 amount);

    address immutable NOBLE = 0xe995e5A3A4BF15498246D7620CA39f7409397326;

    INobleBurner immutable BURNER;

    bool public mintedToAuction;

    constructor(address _owner) ERC20('AuctionNoble', 'NOBLE') Ownable(_owner) {
        BURNER = new NobleBurner(NOBLE);
    }

    function mintToAuction(address auction) external onlyOwner {
        uint256 balance = IERC20(NOBLE).balanceOf(address(this));
        if (balance == 0) revert NothingToMint();
        if (mintedToAuction) revert AlreadyMintedToAuction();
        mintedToAuction = true;
        _mint(auction, balance);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0) || to == address(this)) {
            super._update(from, to, amount);
            return;
        }
        _burn(from, amount);
        IERC20(NOBLE).safeTransfer(address(BURNER), amount);
        BURNER.doBurn();

        emit Burned(from, amount);
    }

    function recoverUnsold() external onlyOwner {
        uint256 held = balanceOf(address(this));
        if (held == 0) revert NothingToRecover();
        _burn(address(this), held);
        IERC20(NOBLE).safeTransfer(owner(), held);
    }
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
    AuctionNoble public auctionNoble;
    IERC20 public currency;
    IERC20 public nobleToken;

    address owner;
    address fundsRecipient;

    address[] bidders;
    uint256[] bidIds;

    function run() external {
        string memory rpcUrl = vm.envString('RPC_URL');
        vm.createSelectFork(rpcUrl);

        owner = makeAddr('owner');
        fundsRecipient = makeAddr('fundsRecipient');
        nobleToken = IERC20(NOBLE_TOKEN);
        currency = IERC20(USDC_ADDR);

        for (uint256 i = 0; i < 3; i++) {
            bidders.push(makeAddr(string(abi.encodePacked('bidder', i))));
        }

        console.log('=== SETUP ===');

        for (uint256 i = 0; i < bidders.length; i++) {
            vm.prank(USDC_WHALE);
            currency.transfer(bidders[i], 5_000_000e6);
        }

        // Deploy contract
        vm.startPrank(owner);
        auctionNoble = new AuctionNoble(owner);
        vm.stopPrank();

        console.log('AuctionNoble:', address(auctionNoble));

        // Fund wrapper with underlying NOBLE
        vm.prank(NOBLE_WHALE);
        nobleToken.transfer(address(auctionNoble), TOTAL_SUPPLY);

        uint64 startBlock = uint64(block.number + 1);
        uint64 endBlock = startBlock + uint64(AUCTION_DURATION);

        AuctionParameters memory params = AuctionParameters({
            currency: address(currency),
            floorPrice: FLOOR_PRICE,
            tickSpacing: TICK_SPACING,
            validationHook: address(0),
            fundsRecipient: fundsRecipient,
            tokensRecipient: address(auctionNoble),
            startBlock: startBlock,
            endBlock: endBlock,
            claimBlock: endBlock,
            requiredCurrencyRaised: 1,
            auctionStepsData: abi.encodePacked(uint24(100e3), uint40(AUCTION_DURATION))
        });

        vm.prank(owner);
        auction = new ContinuousClearingAuction(address(auctionNoble), TOTAL_SUPPLY, params);
        console.log('Auction:', address(auction));

        // Mint wrapped tokens to auction
        vm.prank(owner);
        auctionNoble.mintToAuction(address(auction));
        console.log('Minted to auction:', auctionNoble.balanceOf(address(auction)) / 1e18);

        auction.onTokensReceived();

        // Approve Permit2
        for (uint256 i = 0; i < bidders.length; i++) {
            vm.startPrank(bidders[i]);
            currency.approve(PERMIT2_ADDRESS, type(uint256).max);
            IPermit2(PERMIT2_ADDRESS).approve(address(currency), address(auction), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }

        // ============ BIDDING ============
        vm.roll(startBlock + 1);
        console.log('\n=== BIDDING ===');

        _submitBid(0, 30e18, 2_000_000e6, 'Bidder 0 - 2M @ 30');
        _submitBid(1, 40e18, 2_000_000e6, 'Bidder 1 - 2M @ 40');
        _submitBid(2, 50e18, 1_000_000e6, 'Bidder 2 - 1M @ 50');

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(endBlock);
        console.log('\n=== AUCTION ENDED ===');
        auction.checkpoint();

        console.log('Clearing price:', auction.clearingPrice());
        console.log('Graduated:', auction.isGraduated());

        // ============ SWEEPS ============
        auction.sweepCurrency();
        uint256 currencyRaised = currency.balanceOf(fundsRecipient);
        console.log('Currency raised:', currencyRaised / 1e6);

        auction.sweepUnsoldTokens();
        uint256 unsoldTokens = auctionNoble.balanceOf(address(auctionNoble));
        console.log('Unsold returned to wrapper:', unsoldTokens / 1e18);

        // ============ TEST CLAIM BURNS ============
        console.log('\n=== TEST CLAIM ===');

        auction.exitBid(bidIds[0]);

        address bidder0 = bidders[0];
        uint256 nobleBefore = nobleToken.balanceOf(bidder0);
        uint256 wrapperBefore = auctionNoble.balanceOf(bidder0);

        auction.claimTokens(bidIds[0]);

        uint256 nobleAfter = nobleToken.balanceOf(bidder0);
        uint256 wrapperAfter = auctionNoble.balanceOf(bidder0);

        console.log('Bidder NOBLE delta:', nobleAfter - nobleBefore);
        console.log('Bidder wrapper delta:', wrapperAfter - wrapperBefore);

        require(nobleAfter == nobleBefore, 'Should not receive NOBLE');
        require(wrapperAfter == wrapperBefore, 'Should not receive wrapper');
        console.log('VERIFIED: Claim burned tokens, user got nothing');

        // ============ TEST RECOVER ============
        console.log('\n=== TEST RECOVER ===');

        uint256 ownerBefore = nobleToken.balanceOf(owner);
        uint256 toRecover = auctionNoble.balanceOf(address(auctionNoble));

        vm.prank(owner);
        auctionNoble.recoverUnsold();

        uint256 recovered = nobleToken.balanceOf(owner) - ownerBefore;
        console.log('Recovered:', recovered / 1e18);

        require(recovered == toRecover, 'Should recover all unsold');
        console.log('VERIFIED: Owner recovered unsold NOBLE');

        console.log('\n=== ALL TESTS PASSED ===');
    }

    function _submitBid(uint256 idx, uint256 maxPrice, uint128 amount, string memory desc) internal {
        vm.prank(bidders[idx]);
        uint256 bidId = auction.submitBid(maxPrice, amount, bidders[idx], FLOOR_PRICE, bytes(''));
        bidIds.push(bidId);
        console.log(desc, '- Bid ID:', bidId);
    }
}
