// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/test.sol";
import {console} from "forge-std/console.sol";

import {EURK} from "../src/EURK.sol";
import {Utils} from "./utils/Utils.sol";
import {SigUtils} from "./utils/SigUtils.sol";
import {ERC1967Proxy} from "./utils/ERC1967Proxy.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract EURKBaseSetup is Test {
    EURK internal contractInstance;
    Utils internal utils;

    address payable[] users;

    address payable admin;
    address internal akaunt;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(10);

        admin = users[0];
        akaunt = users[1];

        vm.prank(admin);
        EURK implementation = new EURK();

        vm.prank(admin);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(EURK.initialize.selector)
        );

        contractInstance = EURK(address(proxy));
    }
}

contract EURKSetupTest is EURKBaseSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function testDecimals() public {
        assertEq(contractInstance.decimals(), 2);
    }

    function testDefaultAdminRole() public {
        bytes32 role = contractInstance.DEFAULT_ADMIN_ROLE();
        assertTrue(contractInstance.hasRole(role, admin));
    }

    function testSymbolsAndName() public {
        assertEq(contractInstance.name(), "EURK");
        assertEq(contractInstance.symbol(), "EURK");
    }

    function testRevertsIfInitializeIsCalledAfterInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        contractInstance.initialize();
    }
}

contract EURKRolesTest is EURKBaseSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function testGrantsRoleIfCallerIsAdmin() public {
        bytes32 role = contractInstance.MINTERS();

        vm.prank(admin);
        contractInstance.grantRole(role, akaunt);
        assertTrue(contractInstance.hasRole(role, akaunt));
    }

    function testRevertsIfCallerIsNotAdmin() public {
        bytes32 role = contractInstance.MINTERS();
        bytes32 adminRole = contractInstance.DEFAULT_ADMIN_ROLE();

        bytes memory expectedRevertMessage = abi.encodePacked(
            "AccessControl: account ",
            StringsUpgradeable.toHexString(akaunt),
            " is missing role ",
            StringsUpgradeable.toHexString(uint256(adminRole), 32)
        );

        vm.expectRevert(expectedRevertMessage);
        vm.prank(akaunt);
        contractInstance.grantRole(role, akaunt);
    }

    function testRevertsIfRoleToRevokeIsAdminAndThereIsOnlyOneAdmin() public {
        bytes32 role = contractInstance.DEFAULT_ADMIN_ROLE();

        vm.expectRevert("contract cannot be left without an admin");
        vm.prank(admin);
        contractInstance.revokeRole(role, admin);
    }

    function testRevokeAdminRole() public {
        bytes32 role = contractInstance.DEFAULT_ADMIN_ROLE();
        address newAdmin = users[2];

        vm.prank(admin);
        contractInstance.grantRole(role, newAdmin);
        assertTrue(contractInstance.hasRole(role, newAdmin));

        vm.prank(admin);
        contractInstance.revokeRole(role, newAdmin);
        assertFalse(contractInstance.hasRole(role, newAdmin));
    }
}

contract EURKMintTest is EURKBaseSetup {
    function setUp() public virtual override {
        super.setUp();

        bytes32 minterRole = contractInstance.MINTERS();
        vm.prank(admin);
        contractInstance.grantRole(minterRole, akaunt);
    }

    function testMint() public {
        uint256 amount = 1000;

        vm.prank(akaunt);
        contractInstance.mint(amount);

        assertEq(contractInstance.balanceOf(address(akaunt)), amount);
    }

    function testRevertsIfCallerIsNotMinter() public {
        uint256 amount = 1000;

        vm.expectRevert("unauthorized");
        vm.prank(users[3]);
        contractInstance.mint(amount);
    }

    function testRevertsIfAmountIsZero() public {
        uint256 amount = 0;

        vm.expectRevert("amount cannot be 0");
        vm.prank(akaunt);
        contractInstance.mint(amount);
    }
}

contract EURKBurnTest is EURKBaseSetup {
    uint256 amount = 1000;

    function setUp() public virtual override {
        super.setUp();

        bytes32 burnerRole = contractInstance.BURNERS();
        vm.prank(admin);
        contractInstance.grantRole(burnerRole, akaunt);

        bytes32 minterRole = contractInstance.MINTERS();
        vm.prank(admin);
        contractInstance.grantRole(minterRole, akaunt);

        vm.prank(akaunt);
        contractInstance.mint(amount);
    }

    function testBurn() public {
        uint256 amountToBurn = 100;

        vm.prank(akaunt);
        contractInstance.burn(amountToBurn);

        assertEq(contractInstance.balanceOf(address(akaunt)), amount - amountToBurn);
        amount = amount - amountToBurn;
    }

    function testRevertsIfAmountIsGreaterThanBalance() public {
        uint256 amountToBurn = amount + 1;

        vm.expectRevert("ERC20: burn amount exceeds balance");
        vm.prank(akaunt);
        contractInstance.burn(amountToBurn);
    }

    function testRevertsIfCallerIsNotBurner() public {
        vm.expectRevert("unauthorized");
        vm.prank(users[3]);
        contractInstance.burn(amount);
    }

    function testRevertsIfAmountIsZero() public {
        vm.expectRevert("amount cannot be 0");
        vm.prank(akaunt);
        contractInstance.burn(0);
    }
}

contract EURKMetaTransferTest is EURKBaseSetup, EURK {
    string constant META = '{"userUid":"123-abc","transactionId":"123","currentState":"PENDING","transactionType":"BUY"}';

    SigUtils sigUtils;

    function setUp() public virtual override {
        super.setUp();

        sigUtils = new SigUtils(address(contractInstance), "EURK", "1");

        bytes32 minterRole = contractInstance.MINTERS();
        vm.prank(admin);
        contractInstance.grantRole(minterRole, akaunt);

        bytes32 transferrerRole = contractInstance.TRANSFERRERS();
        vm.prank(admin);
        contractInstance.grantRole(transferrerRole, akaunt);

        vm.prank(akaunt);
        contractInstance.mint(1000);
    }

    function testTransfersIfInvocatorIsSenderWithoutAValidSignatureOrDeadline() public {
        bytes memory signature = "sign";

        vm.prank(akaunt);
        contractInstance.metaTransfer(signature, akaunt, users[3], 100, 10000, META);

        assertEq(contractInstance.balanceOf(address(akaunt)), 900);
        assertEq(contractInstance.balanceOf(users[3]), 100);
    }

    function testTrasnfersIfInvocatorIsSenderWithValidSignatureAndDeadline() public {
        uint256 deadline = block.timestamp + 10000;
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        address receiver = users[3];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, owner, 100, 10000, META);

        bytes32 digest = sigUtils.generateTypedDataHash(owner, receiver, 100, contractInstance.nonces(owner), deadline);

        bytes memory signature = sigUtils.sign(ownerPrivateKey, digest);

        vm.prank(akaunt);
        vm.expectEmit();
        emit MetaTransferCalled(META);

        contractInstance.metaTransfer(
            signature, owner, receiver, 100, block.timestamp + 10000, META
        );

        assertEq(contractInstance.balanceOf(address(akaunt)), 900);
        assertEq(contractInstance.balanceOf(receiver), 100);
        assertEq(contractInstance.balanceOf(owner), 0);
    }

    function testRevertsIfSignatureDoesNotBelongToSender() public {
        uint256 deadline = block.timestamp + 10000;
        uint256 signerPrivateKey = 0xA11CE;
        address signer = vm.addr(signerPrivateKey);

        address sender = users[3];

        address receiver = users[4];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, sender, 100, 10000, META);

        bytes32 digest =
            sigUtils.generateTypedDataHash(signer, receiver, 100, contractInstance.nonces(sender), deadline);

        bytes memory signature = sigUtils.sign(signerPrivateKey, digest);

        vm.expectRevert("Permit: invalid signature");
        vm.prank(akaunt);

        contractInstance.metaTransfer(
            signature, sender, receiver, 100, block.timestamp + 10000, META
        );
    }

    function testRevertsIfSignatureIsReused() public {
        uint256 deadline = block.timestamp + 10000;
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        address receiver = users[3];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, owner, 100, 10000, META);

        bytes32 digest = sigUtils.generateTypedDataHash(owner, receiver, 50, contractInstance.nonces(owner), deadline);

        bytes memory signature = sigUtils.sign(ownerPrivateKey, digest);

        vm.prank(akaunt);
        contractInstance.metaTransfer(
            signature, owner, receiver, 50, block.timestamp + 10000, META
        );

        vm.expectRevert("Permit: invalid signature");
        vm.prank(akaunt);
        contractInstance.metaTransfer(
            signature, owner, receiver, 50, block.timestamp + 10000, META
        );
    }

    function testRevertsIfDestinationAddressDoesNotMatchDestinationOnTransaction() public {
        uint256 deadline = block.timestamp + 10000;
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        address receiver = users[3];
        address otherReceiver = users[4];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, owner, 100, 10000, META);

        bytes32 digest = sigUtils.generateTypedDataHash(owner, receiver, 100, contractInstance.nonces(owner), deadline);

        bytes memory signature = sigUtils.sign(ownerPrivateKey, digest);

        vm.expectRevert("Permit: invalid signature");
        vm.prank(akaunt);
        contractInstance.metaTransfer(
            signature, owner, otherReceiver, 100, block.timestamp + 10000, META
        );
    }

    function testRevertsIfDeadlinesDoNotMatch() public {
        uint256 deadline = block.timestamp + 100;
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        address receiver = users[3];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, owner, 100, 10000, META);

        bytes32 digest = sigUtils.generateTypedDataHash(owner, receiver, 100, contractInstance.nonces(owner), deadline);

        bytes memory signature = sigUtils.sign(ownerPrivateKey, digest);

        vm.expectRevert("Permit: invalid signature");
        vm.prank(akaunt);
        contractInstance.metaTransfer(
            signature, owner, receiver, 100, block.timestamp + 10000, META
        );
    }

    function testRevertsIfDeadlineIsExpired() public {
        uint256 deadline = 0;
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        address receiver = users[3];

        // Use metaTransfer to move tokens (direct transfer is disabled)
        vm.prank(akaunt);
        contractInstance.metaTransfer("sign", akaunt, owner, 100, 10000, META);

        bytes32 digest = sigUtils.generateTypedDataHash(owner, receiver, 100, contractInstance.nonces(owner), deadline);

        bytes memory signature = sigUtils.sign(ownerPrivateKey, digest);

        vm.expectRevert("Signature expired");
        vm.prank(akaunt);
        contractInstance.metaTransfer(signature, owner, receiver, 100, 0, META);
    }

    function testRevertsIfCallerIsNotTransferrer() public {
        address notTransferrer = users[3];
        bytes memory signature = "sign";

        vm.expectRevert("unauthorized");
        vm.prank(notTransferrer);
        contractInstance.metaTransfer(signature, notTransferrer, akaunt, 100, 10000, META);
    }

    function testRevertsIfAmountIsZero() public {
        bytes memory signature = "sign";

        vm.expectRevert("amount cannot be 0");
        vm.prank(akaunt);
        contractInstance.metaTransfer(signature, akaunt, akaunt, 0, 10000, META);
    }

    function testRevertsIfSourceIsZeroAddress() public {
        bytes memory signature = "sign";

        vm.expectRevert("address cannot be the zero address");
        vm.prank(akaunt);
        contractInstance.metaTransfer(signature, address(0), users[3], 100, 10000, META);
    }

    function testRevertsIfDestinationIsZeroAddress() public {
        bytes memory signature = "sign";

        vm.expectRevert("address cannot be the zero address");
        vm.prank(akaunt);
        contractInstance.metaTransfer(signature, akaunt, address(0), 100, 10000, META);
    }
}
