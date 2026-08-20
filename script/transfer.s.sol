// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {AKDD} from "../src/AKDD.sol";

contract Transfer is Script {
  AKDD akdd;

  constructor() {
    address addr = vm.envAddress("CONTRACT_ADDRESS");
    akdd = AKDD(addr);
  }

  function run() public {
    uint256 amount = vm.envUint("AMOUNT");

    address to = vm.envAddress("RECIPIENT");

    vm.startBroadcast();
    akdd.transfer(to, amount);
    vm.stopBroadcast();
  }

}
