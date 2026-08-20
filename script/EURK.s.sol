// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {EURK} from "../src/EURK.sol";
import {ERC1967Proxy} from "../test/utils/ERC1967Proxy.sol";

contract EURKDeployV1 is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy implementation
        EURK implementation = new EURK();

        // Deploy proxy pointing to implementation, calling initialize
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(EURK.initialize.selector)
        );

        console2.log("EURK implementation:", address(implementation));
        console2.log("EURK proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
