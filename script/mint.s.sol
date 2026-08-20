// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {EURK} from "../src/EURK.sol";


contract Mint is Script {
  EURK contractInstance;

  function setUp() public {
    address addr = vm.envAddress("CONTRACT_ADDRESS");
    contractInstance = EURK(addr);
  }

  function run() public {
    uint256 amount = vm.envUint("AMOUNT");

    vm.startBroadcast();
    contractInstance.mint(amount);
    vm.stopBroadcast();
  }
}


