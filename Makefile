-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean:
	-@if [ -d "lib/forge-std" ]; then forge clean; else echo "Skipping clean - dependencies not installed"; fi

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; git submodule update --init --recursive && forge install OpenZeppelin/openzeppelin-contracts-upgradeable

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing

anvil-run :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/deploy/anvil/Deploy.s.sol:DeployNobleAuctionScript $(NETWORK_ARGS)

# Default Permit2 address for Anvil (update if redeployed)
PERMIT2_ADDRESS ?= 0x980C97D4d4221260C3473eE2FB84F025a711AB67

bid:
	@AUCTION_ADDRESS=0x9E545E3C0baAB3E08CdfD552C960A1050f373042 PERMIT2_ADDRESS=$(PERMIT2_ADDRESS) forge script script/deploy/anvil/Bid.s.sol:CCABidScript $(NETWORK_ARGS)