// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {EURK} from "../../src/EURK.sol";

/**
 * @dev V2 mock of EURK for upgrade testing.
 * Adds a simple `version()` function to verify the upgrade succeeded.
 */
contract EURKV2 is EURK {
    function version() public pure returns (string memory) {
        return "v2";
    }
}
