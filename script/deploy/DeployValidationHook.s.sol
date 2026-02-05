// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {NobleValidationHook} from '../../src/periphery/validationHooks/NobleValidationHook.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

contract DeployValidationHookScript is Script {
    address constant WHITELISTER = 0x5d5b9Fc509b20BC8d2D845C8a5f746eEd31B55F8;

    function run() external {
        vm.startBroadcast();

        NobleValidationHook nobleValidationHook = new NobleValidationHook(msg.sender, WHITELISTER, 1_000_000);

        vm.stopBroadcast();

        console.log('NobleValidationHook deployed at:', address(nobleValidationHook));
    }
}
