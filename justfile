# Remember to set your .env file with all necessary variables
set dotenv-load

test-auction:
    forge script script/test/AuctionNoble.s.sol --tc AuctionNobleScript -vvv

test-deployment:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL -vvv

deploy:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

deploy-and-verify:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify --broadcast -vvv

bid auction amount:
    AUCTION={{auction}} AMOUNT={{amount}} forge script script/auction/Bid.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

bid-max-price auction amount max-price:
    AUCTION={{auction}} AMOUNT={{amount}} MAX_PRICE={{max-price}} forge script script/auction/Bid.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv
