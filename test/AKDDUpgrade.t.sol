// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/test.sol";

import {AKDD} from "../src/AKDD.sol";
import {AKDDV2} from "./mocks/AKDDV2.sol";
import {ERC1967Proxy} from "./utils/ERC1967Proxy.sol";
import {Utils} from "./utils/Utils.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract AKDDUpgradeTest is Test {
    AKDD internal implementation;
    AKDD internal proxy;
    Utils internal utils;

    address payable[] users;
    address payable admin;
    address payable nonAdmin;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(5);
        admin = users[0];
        nonAdmin = users[1];

        // Deploy implementation
        vm.prank(admin);
        implementation = new AKDD();

        // Deploy proxy
        vm.prank(admin);
        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(AKDD.initialize.selector)
        );

        proxy = AKDD(address(proxyContract));
    }

    function testProxyInitialization() public {
        assertEq(proxy.name(), "USDK");
        assertEq(proxy.symbol(), "USDK");
        assertEq(proxy.decimals(), 2);
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testImplementationCannotBeInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize();
    }

    function testUpgradeToV2() public {
        // Deploy V2 implementation
        vm.prank(admin);
        AKDDV2 v2Implementation = new AKDDV2();

        // Upgrade proxy to V2
        vm.prank(admin);
        proxy.upgradeTo(address(v2Implementation));

        // Verify upgrade worked
        AKDDV2 proxyV2 = AKDDV2(address(proxy));
        assertEq(proxyV2.version(), "v2");
    }

    function testStoragePersistsAfterUpgrade() public {
        // Setup: grant minter role and mint tokens
        bytes32 minterRole = proxy.MINTERS();
        vm.prank(admin);
        proxy.grantRole(minterRole, nonAdmin);

        vm.prank(nonAdmin);
        proxy.mint(500);

        assertEq(proxy.balanceOf(nonAdmin), 500);

        // Deploy V2 and upgrade
        vm.prank(admin);
        AKDDV2 v2Implementation = new AKDDV2();

        vm.prank(admin);
        proxy.upgradeTo(address(v2Implementation));

        // Verify storage persisted
        AKDDV2 proxyV2 = AKDDV2(address(proxy));
        assertEq(proxyV2.balanceOf(nonAdmin), 500);
        assertEq(proxyV2.name(), "USDK");
        assertEq(proxyV2.symbol(), "USDK");
        assertEq(proxyV2.decimals(), 2);
        assertTrue(proxyV2.hasRole(proxyV2.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(proxyV2.hasRole(minterRole, nonAdmin));
    }

    function testNonAdminCannotUpgrade() public {
        vm.prank(admin);
        AKDDV2 v2Implementation = new AKDDV2();

        bytes32 adminRole = proxy.DEFAULT_ADMIN_ROLE();
        bytes memory expectedRevertMessage = abi.encodePacked(
            "AccessControl: account ",
            StringsUpgradeable.toHexString(nonAdmin),
            " is missing role ",
            StringsUpgradeable.toHexString(uint256(adminRole), 32)
        );

        vm.expectRevert(expectedRevertMessage);
        vm.prank(nonAdmin);
        proxy.upgradeTo(address(v2Implementation));
    }

    function testUpgradeToAndCall() public {
        // Deploy V2 implementation
        vm.prank(admin);
        AKDDV2 v2Implementation = new AKDDV2();

        // Upgrade with a call to version()
        vm.prank(admin);
        proxy.upgradeToAndCall(
            address(v2Implementation),
            abi.encodeWithSelector(AKDDV2.version.selector)
        );

        AKDDV2 proxyV2 = AKDDV2(address(proxy));
        assertEq(proxyV2.version(), "v2");
    }

    function testCannotUpgradeToNonUUPSContract() public {
        address fakeImpl = address(0xdead);

        vm.prank(admin);
        vm.expectRevert();
        proxy.upgradeTo(fakeImpl);
    }

    function testRolesPreservedAfterUpgrade() public {
        // Grant various roles
        bytes32 minterRole = proxy.MINTERS();
        bytes32 burnerRole = proxy.BURNERS();
        bytes32 transferrerRole = proxy.TRANSFERRERS();

        vm.startPrank(admin);
        proxy.grantRole(minterRole, nonAdmin);
        proxy.grantRole(burnerRole, nonAdmin);
        proxy.grantRole(transferrerRole, nonAdmin);
        vm.stopPrank();

        // Upgrade
        vm.prank(admin);
        AKDDV2 v2Implementation = new AKDDV2();

        vm.prank(admin);
        proxy.upgradeTo(address(v2Implementation));

        // Verify roles persist
        AKDDV2 proxyV2 = AKDDV2(address(proxy));
        assertTrue(proxyV2.hasRole(minterRole, nonAdmin));
        assertTrue(proxyV2.hasRole(burnerRole, nonAdmin));
        assertTrue(proxyV2.hasRole(transferrerRole, nonAdmin));
        assertTrue(proxyV2.hasRole(proxyV2.DEFAULT_ADMIN_ROLE(), admin));
    }
}
