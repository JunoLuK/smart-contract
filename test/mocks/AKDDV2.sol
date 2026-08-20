// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AKDD} from "../../src/AKDD.sol";

/**
 * @dev V2 mock of AKDD for upgrade testing.
 * Adds a simple `version()` function to verify the upgrade succeeded.
 */
contract AKDDV2 is AKDD {
    function version() public pure returns (string memory) {
        return "v2";
    }
}
