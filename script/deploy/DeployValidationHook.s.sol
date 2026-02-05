// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {NobleValidationHook} from '../../src/periphery/validationHooks/NobleValidationHook.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

contract DeployValidationHookScript is Script {
    address constant WHITELISTER = 0x5d5b9Fc509b20BC8d2D845C8a5f746eEd31B55F8;
    address constant AUCTION = address(0xdead); // Placeholder
    address constant PREDICATE_REGISTRY = 0xe15a8Ca5BD8464283818088c1760d8f23B6a216E;
    string constant POLICY_ID = 'x-managed-policy-6abd348959bb04a99c93cf9158a450cb';
    uint256 constant EXPIRATION_BLOCK = 1_000_000;

    function run() external {
        vm.startBroadcast();

        NobleValidationHook nobleValidationHook = new NobleValidationHook(
            msg.sender, // owner
            WHITELISTER, // initialWhitelister
            EXPIRATION_BLOCK, // expirationBlock
            AUCTION, // auction
            PREDICATE_REGISTRY, // registry
            POLICY_ID // policyID
        );

        vm.stopBroadcast();

        console.log('NobleValidationHook deployed at:', address(nobleValidationHook));
    }
}
