// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {EURK} from "../src/EURK.sol";

contract GrantTransferrer is Script {
    EURK contractInstance;

    address transferrer;

    function setUp() public {
        address addr = vm.envAddress("CONTRACT_ADDRESS");
        transferrer = vm.envAddress("TRANSFERRER");
        contractInstance = EURK(addr);
    }

    function run() public {
        vm.startBroadcast();
        contractInstance.grantRole(keccak256("TRANSFERRERS"), transferrer);
        vm.stopBroadcast();
    }
}
