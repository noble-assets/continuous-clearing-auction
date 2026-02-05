# Remember to set your .env file with all necessary variables
set dotenv-load

####################################
# Blockchain commands
####################################

anvil:
    anvil --fork-url $SEPOLIA_RPC_URL --block-time 5

mine blocks:
    cast rpc anvil_mine {{blocks}}

####################################
# Contract commands
####################################

test-auction:
    forge script script/test/AuctionNoble.s.sol --tc AuctionNobleScript -vvv

test-deployment:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL -vvv

deploy:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

deploy-and-verify:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast -vvv

# Market order
bid auction amount:
    AUCTION={{auction}} AMOUNT={{amount}} forge script script/auction/Bid.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

# Limit order
bid-max-price auction amount max-price:
    AUCTION={{auction}} AMOUNT={{amount}} MAX_PRICE={{max-price}} forge script script/auction/Bid.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

deploy-hook:
    forge script script/deploy/DeployValidationHook.s.sol --tc DeployValidationHookScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

deploy-and-verify-hook:
    forge script script/deploy/DeployValidationHook.s.sol --tc DeployValidationHookScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast -vvv
