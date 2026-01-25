// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionStepsBuilder} from '../../../test/utils/AuctionStepsBuilder.sol';
import {FixedPoint96} from '../../../src/libraries/FixedPoint96.sol';
import {Permit2} from '../../../lib/permit2/src/Permit2.sol';
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

    // Permit2 deployment salt (for deterministic address)
    bytes32 constant PERMIT2_SALT = bytes32(uint256(0x0000000000000000000000000000000000000000d3af2663da51c10215000000));
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Auction parameters
    // Price calculation: 1 USDC (1e6) buys 1M NOBLE (1e24)
    // Price = 1e6 / 1e24 = 1e-18 currency per token
    // In Q96 format: (1e6 * 2^96) / 1e24
    // Using: (1e6 << 96) / 1e24 for precision
    uint256 constant FLOOR_PRICE = (1e6 << FixedPoint96.RESOLUTION) / 1e24; // Q96: 1 USDC buys 1M NOBLE
    uint256 constant TICK_SPACING = FLOOR_PRICE;
    uint256 constant AUCTION_DURATION = 10; // blocks
    // uint24 constant STEP_PERCENTAGE = 1e3; // step size for price curve, in MPS

    function run() external {
        vm.startBroadcast();

        console.log('=== DEPLOYMENT CONFIG ===');
        console.log('Deployer:', msg.sender);
        console.log('Chain ID:', block.chainid);

        // 0. Deploy Permit2 if it doesn't exist (needed for ERC20 transfers)
        // Use vm.etch to deploy at canonical address since SafeTransferLib expects it there
        address permit2Address = PERMIT2_ADDRESS;
        if (permit2Address.code.length == 0) {
            console.log('\n=== DEPLOYING PERMIT2 AT CANONICAL ADDRESS ===');
            // Get Permit2 bytecode by deploying it first, then use vm.etch to place it at canonical address
            Permit2 tempPermit2 = new Permit2{salt: PERMIT2_SALT}();
            bytes memory permit2Bytecode = address(tempPermit2).code;
            vm.etch(permit2Address, permit2Bytecode);
            console.log('Permit2 deployed to canonical address:', permit2Address);
        } else {
            console.log('\n=== PERMIT2 ALREADY DEPLOYED ===');
            console.log('Permit2 address:', permit2Address);
        }

        // 1. Deploy tokens
        MockUSDC usdc = new MockUSDC();
        NobleToken noble = new NobleToken();

        console.log('\n=== TOKENS DEPLOYED ===');
        console.log('MockUSDC:', address(usdc));
        console.log('NobleToken:', address(noble));

        // 2. Setup auction parameters
        uint64 startBlock = uint64(block.number + 1); // start in 1 block
        uint64 endBlock = startBlock + uint64(AUCTION_DURATION);

        console.log('\n=== AUCTION PARAMETERS ===');
        console.log('Floor price (Q96):', FLOOR_PRICE);
        console.log('Tick spacing (Q96):', TICK_SPACING);
        console.log('Floor price ratio: 1 USDC buys 1M NOBLE');
        console.log('Tick spacing: 1% of floor price');

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
        console.log('Permit2:     ', permit2Address);
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
        console.log('');
        console.log('NOTE: If Permit2 is not at canonical address, set PERMIT2_ADDRESS env var when running make bid');
        console.log('      Example: PERMIT2_ADDRESS=', permit2Address, 'make bid');
    }
}