// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/test.sol";

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

contract SigUtils is Test {
    address private verifyingContract;
    string private name;
    string private version;

    constructor(address _address, string memory _name, string memory _version) {
        verifyingContract = _address;
        name = _name;
        version = _version;
    }

    function generateTypedDataHash(address owner, address recipient, uint256 amount, uint256 nonce, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = _domainSeparator();
        bytes32 structHash = _structHash(owner, recipient, amount, nonce, deadline);

        bytes32 digest = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
        return digest;
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(verifyingContract)
            )
        );

        return domainSeparator;
    }

    function _structHash(address owner, address recipient, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"),
                owner,
                recipient,
                amount,
                nonce,
                deadline
            )
        );

        return structHash;
    }

    // ─── V2 helpers (random bytes32 nonce + cancellation) ─────────────────────────

    function generateV2TypedDataHash(
        address sender,
        address recipient,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("MetaTransfer(address sender,address recipient,uint256 amount,bytes32 nonce,uint256 deadline)"),
                sender,
                recipient,
                amount,
                nonce,
                deadline
            )
        );

        return ECDSAUpgradeable.toTypedDataHash(_domainSeparator(), structHash);
    }

    function generateCancelTypedDataHash(address authorizer, bytes32 nonce) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(keccak256("CancelAuthorization(address authorizer,bytes32 nonce)"), authorizer, nonce));

        return ECDSAUpgradeable.toTypedDataHash(_domainSeparator(), structHash);
    }

    function sign(uint256 ownerPrivateKey, bytes32 digest) public pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = new bytes(65);

        // Copy r, s, and v into the signature
        assembly {
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore8(add(signature, 0x60), v)
        }

        return signature;
    }
}
