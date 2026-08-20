// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/test.sol";

import {AKDD} from "../src/AKDD.sol";
import {ERC1967Proxy} from "./utils/ERC1967Proxy.sol";
import {Utils} from "./utils/Utils.sol";

contract AKDDTransferRestrictionsTest is Test {
    AKDD internal contractInstance;
    Utils internal utils;

    address payable[] users;
    address payable admin;
    address payable transferrer;
    address payable regularUser;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(5);
        admin = users[0];
        transferrer = users[1];
        regularUser = users[2];

        vm.prank(admin);
        AKDD implementation = new AKDD();

        vm.prank(admin);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(AKDD.initialize.selector)
        );

        contractInstance = AKDD(address(proxy));

        // Setup roles
        vm.startPrank(admin);
        contractInstance.grantRole(contractInstance.MINTERS(), transferrer);
        contractInstance.grantRole(contractInstance.TRANSFERRERS(), transferrer);
        vm.stopPrank();

        // Mint tokens to transferrer
        vm.prank(transferrer);
        contractInstance.mint(10000);
    }

    // ─── Direct transfer() is disabled ───────────────────────────────────────────

    function testDirectTransferReverts() public {
        vm.expectRevert("direct transfers disabled");
        vm.prank(transferrer);
        contractInstance.transfer(regularUser, 100);
    }

    function testDirectTransferRevertsForAnyUser() public {
        vm.expectRevert("direct transfers disabled");
        vm.prank(regularUser);
        contractInstance.transfer(transferrer, 100);
    }

    // ─── Direct transferFrom() is disabled ───────────────────────────────────────

    function testDirectTransferFromReverts() public {
        vm.expectRevert("direct transfers disabled");
        vm.prank(regularUser);
        contractInstance.transferFrom(transferrer, regularUser, 100);
    }

    function testDirectTransferFromRevertsEvenForAdmin() public {
        vm.expectRevert("direct transfers disabled");
        vm.prank(admin);
        contractInstance.transferFrom(transferrer, admin, 100);
    }

    // ─── approve() is disabled ───────────────────────────────────────────────────

    function testApproveReverts() public {
        vm.expectRevert("approvals disabled");
        vm.prank(transferrer);
        contractInstance.approve(regularUser, 100);
    }

    // ─── increaseAllowance() is disabled ─────────────────────────────────────────

    function testIncreaseAllowanceReverts() public {
        vm.expectRevert("approvals disabled");
        vm.prank(transferrer);
        contractInstance.increaseAllowance(regularUser, 100);
    }

    // ─── decreaseAllowance() is disabled ─────────────────────────────────────────

    function testDecreaseAllowanceReverts() public {
        vm.expectRevert("approvals disabled");
        vm.prank(transferrer);
        contractInstance.decreaseAllowance(regularUser, 100);
    }

    // ─── metaTransfer still works for TRANSFERRERS ───────────────────────────────

    function testMetaTransferWorksForTransferrer() public {
        vm.prank(transferrer);
        contractInstance.metaTransfer("sign", transferrer, regularUser, 100, 10000, '{"txId":"1"}');

        assertEq(contractInstance.balanceOf(regularUser), 100);
        assertEq(contractInstance.balanceOf(transferrer), 9900);
    }

    // ─── metaTransfer rejected for non-TRANSFERRERS ──────────────────────────────

    function testMetaTransferRevertsForNonTransferrer() public {
        vm.expectRevert("unauthorized");
        vm.prank(regularUser);
        contractInstance.metaTransfer("sign", regularUser, transferrer, 100, 10000, '{"txId":"1"}');
    }

    // ─── No way for a regular holder to move their own tokens ────────────────────

    function testRegularHolderCannotMoveOwnTokens() public {
        // First give regularUser some tokens via metaTransfer
        vm.prank(transferrer);
        contractInstance.metaTransfer("sign", transferrer, regularUser, 500, 10000, '{"txId":"1"}');

        assertEq(contractInstance.balanceOf(regularUser), 500);

        // regularUser cannot transfer their tokens directly
        vm.expectRevert("direct transfers disabled");
        vm.prank(regularUser);
        contractInstance.transfer(users[3], 100);

        // regularUser cannot approve anyone
        vm.expectRevert("approvals disabled");
        vm.prank(regularUser);
        contractInstance.approve(users[3], 100);

        // regularUser cannot use transferFrom
        vm.expectRevert("direct transfers disabled");
        vm.prank(regularUser);
        contractInstance.transferFrom(regularUser, users[3], 100);

        // Balance unchanged
        assertEq(contractInstance.balanceOf(regularUser), 500);
    }

    // ─── Mint and burn still work for authorized roles ───────────────────────────

    function testMintStillWorks() public {
        vm.prank(transferrer);
        contractInstance.mint(1000);
        assertEq(contractInstance.balanceOf(transferrer), 11000);
    }

    function testBurnStillWorks() public {
        vm.startPrank(admin);
        contractInstance.grantRole(contractInstance.BURNERS(), transferrer);
        vm.stopPrank();

        vm.prank(transferrer);
        contractInstance.burn(500);
        assertEq(contractInstance.balanceOf(transferrer), 9500);
    }
}
