// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {AKDD} from "../src/AKDD.sol";
import {ERC1967Proxy} from "../test/utils/ERC1967Proxy.sol";

contract AKDDDeployV1 is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy implementation
        AKDD implementation = new AKDD();

        // Deploy proxy pointing to implementation, calling initialize
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(AKDD.initialize.selector)
        );

        console2.log("AKDD implementation:", address(implementation));
        console2.log("AKDD proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
