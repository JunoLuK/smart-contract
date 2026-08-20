// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {EURK} from "../src/EURK.sol";

contract GrantMinter is Script {
    EURK contractInstance;

    address minter;

    function setUp() public {
        address addr = vm.envAddress("CONTRACT_ADDRESS");
        minter = vm.envAddress("MINTER");
        contractInstance = EURK(addr);
    }

    function run() public {
        vm.startBroadcast();
        contractInstance.grantRole(keccak256("MINTERS"), minter);
        vm.stopBroadcast();
    }
}
