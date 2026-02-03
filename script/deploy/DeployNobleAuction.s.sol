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

/// @notice Mock Noble token with burn function
contract Noble is ERC20 {
    constructor() ERC20('Noble', 'NOBLE') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn() public {
        uint256 balance = balanceOf(msg.sender);
        _burn(msg.sender, balance);
    }
}

interface INoble {
    function burn() external;
}

interface INobleBurner {
    function doBurn() external;
}

contract NobleBurner is INobleBurner {
    INoble public immutable NOBLE;

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

    address public immutable NOBLE;
    INobleBurner public immutable BURNER;
    bool public mintedToAuction;

    constructor(address _owner, address _noble) ERC20('AuctionNoble', 'aNOBLE') Ownable(_owner) {
        NOBLE = _noble;
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

contract DeployNobleAuctionScript is Script {
    // Token amounts
    uint128 constant AUCTION_SUPPLY = 1_000_000e18;
    uint256 constant DEPLOYER_NOBLE = 10_000_000e18;
    uint256 constant DEPLOYER_USDC = 100_000_000e6;

    // Auction parameters
    uint256 constant TICK_SPACING = (uint256(10000) << 96) / 1e18;
    uint256 constant FLOOR_PRICE = TICK_SPACING * 5; // 0.05 $
    uint256 constant AUCTION_DURATION = 10_000;
    uint256 constant CLAIM_START = AUCTION_DURATION + 100;
    uint24 constant STEP_PERCENTAGE = 1e3;

    function run() external {
        vm.startBroadcast();

        console.log('Tick Spacing:', TICK_SPACING);

        console.log('=== DEPLOYMENT CONFIG ===');
        console.log('Deployer:', msg.sender);
        console.log('Chain ID:', block.chainid);

        // 1. Deploy mock tokens
        MockUSDC usdc = new MockUSDC();
        Noble noble = new Noble();

        console.log('\n=== TOKENS DEPLOYED ===');
        console.log('MockUSDC:', address(usdc));
        console.log('Noble:', address(noble));

        // 2. Deploy wrapper
        AuctionNoble auctionNoble = new AuctionNoble(msg.sender, address(noble));

        console.log('\n=== WRAPPER DEPLOYED ===');
        console.log('AuctionNoble:', address(auctionNoble));

        // 3. Setup auction parameters
        uint64 startBlock = uint64(block.number + 10);
        uint64 endBlock = startBlock + uint64(AUCTION_DURATION);
        uint64 claimBlock = endBlock + uint64(CLAIM_START);

        AuctionParameters memory params = AuctionParameters({
            currency: address(usdc),
            floorPrice: FLOOR_PRICE,
            tickSpacing: TICK_SPACING,
            validationHook: address(0),
            fundsRecipient: msg.sender,
            tokensRecipient: address(auctionNoble), // Unsold tokens go back to wrapper
            startBlock: startBlock,
            endBlock: endBlock,
            claimBlock: claimBlock,
            requiredCurrencyRaised: 1,
            auctionStepsData: abi.encodePacked(uint24(STEP_PERCENTAGE), uint40(AUCTION_DURATION))
        });

        // 4. Deploy auction with wrapper as token
        ContinuousClearingAuction auction = new ContinuousClearingAuction(address(auctionNoble), AUCTION_SUPPLY, params);

        console.log('\n=== AUCTION DEPLOYED ===');
        console.log('Auction:', address(auction));
        console.log('Start block:', startBlock);
        console.log('End block:', endBlock);
        console.log('Claim block:', claimBlock);
        // 5. Mint tokens
        usdc.mint(msg.sender, DEPLOYER_USDC);
        noble.mint(msg.sender, DEPLOYER_NOBLE);
        noble.mint(address(auctionNoble), AUCTION_SUPPLY); // Fund wrapper with underlying

        // 6. Mint wrapped tokens to auction
        auctionNoble.mintToAuction(address(auction));

        // 7. Notify auction
        auction.onTokensReceived();

        vm.stopBroadcast();

        // Summary
        console.log('\n=== FINAL SUMMARY ===');
        console.log('MockUSDC:     ', address(usdc));
        console.log('Noble:        ', address(noble));
        console.log('AuctionNoble: ', address(auctionNoble));
        console.log('Auction:      ', address(auction));
        console.log('');
        console.log('Deployer mUSDC balance:', usdc.balanceOf(msg.sender) / 1e6);
        console.log('Deployer NOBLE balance:', noble.balanceOf(msg.sender) / 1e18);
        console.log('Auction aNOBLE balance:', auctionNoble.balanceOf(address(auction)) / 1e18);
        console.log('Wrapper NOBLE backing: ', noble.balanceOf(address(auctionNoble)) / 1e18);
        console.log('');
        console.log('Auction starts at block:', startBlock);
        console.log('Auction ends at block:  ', endBlock);
        console.log('Current block:          ', block.number);
    }
}
