test-auction:
    forge script script/test/AuctionNoble.s.sol --tc AuctionNobleScript -vvv

test-deployment rpc:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url {{rpc}} -vvv

deploy rpc key:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url {{rpc}} --private-key {{key}} --broadcast -vvv

deploy-and-verify rpc key:
    forge script script/deploy/DeployNobleAuction.s.sol --tc DeployNobleAuctionScript --rpc-url {{rpc}} --private-key {{key}} --verify --broadcast -vvv
