// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionStepsBuilder} from '../../../test/utils/AuctionStepsBuilder.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC20Burnable} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/// @notice Mock USDC with 6 decimals
contract MockUSDC is ERC20 {
    constructor() ERC20('Mock USDC', 'mUSDC') {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NobleToken is ERC20 {
    constructor() ERC20('Noble', 'NOBLE') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn() public {
        uint256 balance = balanceOf(msg.sender);
        _burn(msg.sender, balance);
    }
}

contract DeployNobleAuctionScript is Script {
    using AuctionStepsBuilder for bytes;

    // Token amounts
    uint128 constant AUCTION_SUPPLY = 100_000_000e18; // 100M NOBLE for auction
    uint256 constant DEPLOYER_NOBLE = 10_000_000e18; // 10M NOBLE for deployer
    uint256 constant DEPLOYER_USDC = 1_000_000e6; // 1M mUSDC for deployer

    // Auction parameters
    uint256 constant FLOOR_PRICE = 1e18; // currency:token, 1 usdc to buy 1M noble, represented as Q96
    uint256 constant TICK_SPACING = 1e16; // 1% of the floor price
    uint256 constant AUCTION_DURATION = 10; // blocks
    // uint24 constant STEP_PERCENTAGE = 1e3; // step size for price curve, in MPS

    function run() external {
        vm.startBroadcast();

        console.log('=== DEPLOYMENT CONFIG ===');
        console.log('Deployer:', msg.sender);
        console.log('Chain ID:', block.chainid);

        // 1. Deploy tokens
        MockUSDC usdc = new MockUSDC();
        NobleToken noble = new NobleToken();

        console.log('\n=== TOKENS DEPLOYED ===');
        console.log('MockUSDC:', address(usdc));
        console.log('NobleToken:', address(noble));

        // 2. Setup auction parameters
        uint64 startBlock = uint64(block.number + 1); // start in 1 block
        uint64 endBlock = startBlock + uint64(AUCTION_DURATION);

        AuctionParameters memory params = AuctionParameters({
            currency: address(usdc),
            tokensRecipient: msg.sender,
            fundsRecipient: msg.sender,
            startBlock: startBlock,
            endBlock: endBlock,
            claimBlock: endBlock + 1,
            tickSpacing: TICK_SPACING,
            validationHook: address(0), // opt-out
            floorPrice: FLOOR_PRICE,
            requiredCurrencyRaised: 0,
            // auctionStepsData: AuctionStepsBuilder.init().addStep(10_000, 5).addStep(50_000, 4).addStep(750_000, 1)
            auctionStepsData: AuctionStepsBuilder.splitEvenlyAmongSteps(uint40(AUCTION_DURATION))
        });

        // 3. Deploy auction
        ContinuousClearingAuction auction = new ContinuousClearingAuction(address(noble), AUCTION_SUPPLY, params);

        console.log('\n=== AUCTION DEPLOYED ===');
        console.log('Auction:', address(auction));
        console.log('Start block:', startBlock);
        console.log('End block:', endBlock);

        // 4. Mint tokens
        usdc.mint(msg.sender, DEPLOYER_USDC);
        noble.mint(msg.sender, DEPLOYER_NOBLE);
        noble.mint(address(auction), AUCTION_SUPPLY);

        // 5. Notify auction of received tokens
        auction.onTokensReceived();

        vm.stopBroadcast();

        // Summary
        console.log('\n=== FINAL SUMMARY ===');
        console.log('MockUSDC:    ', address(usdc));
        console.log('NobleToken:  ', address(noble));
        console.log('Auction:     ', address(auction));
        console.log('');
				console.log('Deployer:', msg.sender);
        console.log('Deployer mUSDC balance:', usdc.balanceOf(msg.sender) / 1e6);
        console.log('Deployer NOBLE balance:', noble.balanceOf(msg.sender) / 1e18);
        console.log('Auction NOBLE balance: ', noble.balanceOf(address(auction)) / 1e18);
        console.log('');
        console.log('Auction starts at block:', startBlock);
        console.log('Auction ends at block:  ', endBlock);
        console.log('Current block:          ', block.number);
    }
}