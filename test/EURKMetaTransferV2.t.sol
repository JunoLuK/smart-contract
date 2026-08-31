// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/test.sol";

import {EURK} from "../src/EURK.sol";
import {Utils} from "./utils/Utils.sol";
import {SigUtils} from "./utils/SigUtils.sol";
import {ERC1967Proxy} from "./utils/ERC1967Proxy.sol";

contract EURKMetaTransferV2Test is Test, EURK {
    string constant META = '{"txId":"v2"}';

    EURK internal contractInstance;
    Utils internal utils;
    SigUtils internal sigUtils;

    address payable[] users;
    address payable admin;
    address payable transferrer;

    uint256 internal ownerPrivateKey = 0xA11CE;
    address internal owner;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(5);
        admin = users[0];
        transferrer = users[1];
        owner = vm.addr(ownerPrivateKey);

        vm.prank(admin);
        EURK implementation = new EURK();

        vm.prank(admin);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(EURK.initialize.selector)
        );

        contractInstance = EURK(address(proxy));
        sigUtils = new SigUtils(address(contractInstance), "EURK", "1");

        vm.startPrank(admin);
        contractInstance.grantRole(contractInstance.MINTERS(), transferrer);
        contractInstance.grantRole(contractInstance.TRANSFERRERS(), transferrer);
        vm.stopPrank();

        // Fund the owner via a V1 metaTransfer from the transferrer.
        vm.prank(transferrer);
        contractInstance.mint(10000);
        vm.prank(transferrer);
        contractInstance.metaTransfer("sign", transferrer, owner, 1000, block.timestamp + 10000, META);
    }

    function _signV2(address recipient, uint256 amount, bytes32 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = sigUtils.generateV2TypedDataHash(owner, recipient, amount, nonce, deadline);
        return sigUtils.sign(ownerPrivateKey, digest);
    }

    // ─── Happy path ──────────────────────────────────────────────────────────────

    function testMetaTransferV2Works() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("random-1");
        uint256 deadline = block.timestamp + 10000;

        bytes memory sig = _signV2(receiver, 100, nonce, deadline);

        vm.prank(transferrer);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationUsed(owner, nonce);
        contractInstance.metaTransferV2(sig, owner, receiver, 100, nonce, deadline, META);

        assertEq(contractInstance.balanceOf(receiver), 100);
        assertEq(contractInstance.balanceOf(owner), 900);
        assertTrue(contractInstance.authorizationState(owner, nonce));
    }

    // ─── No ordering constraint: out-of-order + gaps allowed (Finding 1) ─────────

    function testMetaTransferV2OutOfOrderAndGapsAllowed() public {
        address receiver = users[3];
        uint256 deadline = block.timestamp + 10000;

        bytes32 nA = keccak256("A");
        bytes32 nB = keccak256("B");
        bytes32 nC = keccak256("C");

        bytes memory sigA = _signV2(receiver, 10, nA, deadline);
        bytes memory sigB = _signV2(receiver, 20, nB, deadline);
        bytes memory sigC = _signV2(receiver, 30, nC, deadline);

        // Redeem C, then A, skipping B entirely — impossible under sequential nonces.
        vm.startPrank(transferrer);
        contractInstance.metaTransferV2(sigC, owner, receiver, 30, nC, deadline, META);
        contractInstance.metaTransferV2(sigA, owner, receiver, 10, nA, deadline, META);
        vm.stopPrank();

        assertEq(contractInstance.balanceOf(receiver), 40);
        assertTrue(contractInstance.authorizationState(owner, nA));
        assertTrue(contractInstance.authorizationState(owner, nC));
        // B never used and is still redeemable.
        assertFalse(contractInstance.authorizationState(owner, nB));

        vm.prank(transferrer);
        contractInstance.metaTransferV2(sigB, owner, receiver, 20, nB, deadline, META);
        assertEq(contractInstance.balanceOf(receiver), 60);
    }

    // ─── Replay protection ───────────────────────────────────────────────────────

    function testMetaTransferV2ReplayReverts() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("replay");
        uint256 deadline = block.timestamp + 10000;
        bytes memory sig = _signV2(receiver, 50, nonce, deadline);

        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 50, nonce, deadline, META);

        vm.expectRevert("authorization used or canceled");
        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 50, nonce, deadline, META);
    }

    function testMetaTransferV2ExpiredReverts() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("expired");
        bytes memory sig = _signV2(receiver, 50, nonce, 0);

        vm.expectRevert("Signature expired");
        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 50, nonce, 0, META);
    }

    function testMetaTransferV2WrongSignerReverts() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("wrong-signer");
        uint256 deadline = block.timestamp + 10000;

        bytes32 digest = sigUtils.generateV2TypedDataHash(owner, receiver, 50, nonce, deadline);
        bytes memory sig = sigUtils.sign(0xB0B, digest); // signed by someone else

        vm.expectRevert("Permit: invalid signature");
        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 50, nonce, deadline, META);
    }

    function testMetaTransferV2NonTransferrerReverts() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("role");
        uint256 deadline = block.timestamp + 10000;
        bytes memory sig = _signV2(receiver, 50, nonce, deadline);

        vm.expectRevert("unauthorized");
        vm.prank(users[4]);
        contractInstance.metaTransferV2(sig, owner, receiver, 50, nonce, deadline, META);
    }

    // ─── Direct cancellation (Finding 2, variant a) ──────────────────────────────

    function testDirectCancellationBlocksRedemption() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("cancel-direct");
        uint256 deadline = block.timestamp + 10000;
        bytes memory sig = _signV2(receiver, 100, nonce, deadline);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationCanceled(owner, nonce);
        contractInstance.cancelAuthorization(nonce);

        assertTrue(contractInstance.authorizationState(owner, nonce));

        vm.expectRevert("authorization used or canceled");
        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 100, nonce, deadline, META);
    }

    function testDirectCancellationTwiceReverts() public {
        bytes32 nonce = keccak256("cancel-twice");
        vm.prank(owner);
        contractInstance.cancelAuthorization(nonce);

        vm.expectRevert("authorization used or canceled");
        vm.prank(owner);
        contractInstance.cancelAuthorization(nonce);
    }

    // ─── Gasless cancellation (Finding 2, variant b, ERC-3009 style) ─────────────

    function testGaslessCancellationBlocksRedemption() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("cancel-gasless");
        uint256 deadline = block.timestamp + 10000;
        bytes memory transferSig = _signV2(receiver, 100, nonce, deadline);

        // owner signs a cancellation off-chain, transferrer submits it
        bytes32 cancelDigest = sigUtils.generateCancelTypedDataHash(owner, nonce);
        bytes memory cancelSig = sigUtils.sign(ownerPrivateKey, cancelDigest);

        vm.prank(transferrer);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationCanceled(owner, nonce);
        contractInstance.cancelAuthorization(owner, nonce, cancelSig);

        assertTrue(contractInstance.authorizationState(owner, nonce));

        vm.expectRevert("authorization used or canceled");
        vm.prank(transferrer);
        contractInstance.metaTransferV2(transferSig, owner, receiver, 100, nonce, deadline, META);
    }

    function testGaslessCancellationWrongSignerReverts() public {
        bytes32 nonce = keccak256("cancel-badsig");
        bytes32 cancelDigest = sigUtils.generateCancelTypedDataHash(owner, nonce);
        bytes memory badSig = sigUtils.sign(0xB0B, cancelDigest);

        vm.expectRevert("Permit: invalid signature");
        vm.prank(transferrer);
        contractInstance.cancelAuthorization(owner, nonce, badSig);
    }

    function testGaslessCancellationNonTransferrerReverts() public {
        bytes32 nonce = keccak256("cancel-role");
        bytes32 cancelDigest = sigUtils.generateCancelTypedDataHash(owner, nonce);
        bytes memory cancelSig = sigUtils.sign(ownerPrivateKey, cancelDigest);

        vm.expectRevert("unauthorized");
        vm.prank(users[4]);
        contractInstance.cancelAuthorization(owner, nonce, cancelSig);
    }

    function testCannotCancelAlreadyUsedAuthorization() public {
        address receiver = users[3];
        bytes32 nonce = keccak256("used-then-cancel");
        uint256 deadline = block.timestamp + 10000;
        bytes memory sig = _signV2(receiver, 100, nonce, deadline);

        vm.prank(transferrer);
        contractInstance.metaTransferV2(sig, owner, receiver, 100, nonce, deadline, META);

        vm.expectRevert("authorization used or canceled");
        vm.prank(owner);
        contractInstance.cancelAuthorization(nonce);
    }
}
