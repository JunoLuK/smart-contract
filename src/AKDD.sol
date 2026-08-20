// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AKDD is Initializable, ERC20Upgradeable, EIP712Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /*
     represents the number of accounts with the DEFAULT_ADMIN_ROLE role attached
    */
    CountersUpgradeable.Counter private _adminCount;

    mapping(address => CountersUpgradeable.Counter) private _nonces;

    /*
      Role allowed to call mint
    */
    bytes32 public constant MINTERS = keccak256("MINTERS");

    /*
      Role allowed to call burn
    */
    bytes32 public constant BURNERS = keccak256("BURNERS");

    /*
      Role allowed to call metaTransfer
    */
    bytes32 public constant TRANSFERRERS = keccak256("TRANSFERRERS");

    /*
     event emitted on every metaTransfer with flexible metadata (e.g. JSON)
    */
    event MetaTransferCalled(string metadata);

    /*
     checks msg.sender has minter role
    */
    modifier onlyMinters() {
        require(hasRole(MINTERS, msg.sender), "unauthorized");
        _;
    }

    /*
     checks msg.sender has burner role
    */
    modifier onlyBurners() {
        require(hasRole(BURNERS, msg.sender), "unauthorized");
        _;
    }

    /*
     checks msg.sender has transferrer role
    */
    modifier onlyTransferrers() {
        require(hasRole(TRANSFERRERS, msg.sender), "unauthorized");
        _;
    }

    /*
     checks amount is non 0
    */
    modifier nonZeroAmount(uint256 amount) {
        require(amount > 0, "amount cannot be 0");
        _;
    }

    /*
     checks account is not address(0)
    */
    modifier nonZeroAccount(address account) {
        require(account != address(0), "address cannot be the zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        __ERC20_init("AKDD", "AKDD");
        __EIP712_init("AKDD", "1");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Required override for UUPS proxy pattern. Only admins can authorize upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ─── Transfer Restrictions ───────────────────────────────────────────────────
    // Direct ERC20 transfer/approve functions are disabled.
    // Tokens can only move via metaTransfer (controlled by TRANSFERRERS role).

    /**
     * @dev Disabled. Direct ERC20 transfers are not allowed. Use metaTransfer instead.
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("direct transfers disabled");
    }

    /**
     * @dev Disabled. Direct ERC20 transferFrom is not allowed. Use metaTransfer instead.
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("direct transfers disabled");
    }

    /**
     * @dev Disabled. Approvals are not allowed since direct transfers are disabled.
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("approvals disabled");
    }

    /**
     * @dev Disabled. increaseAllowance is not allowed since direct transfers are disabled.
     */
    function increaseAllowance(address, uint256) public pure override returns (bool) {
        revert("approvals disabled");
    }

    /**
     * @dev Disabled. decreaseAllowance is not allowed since direct transfers are disabled.
     */
    function decreaseAllowance(address, uint256) public pure override returns (bool) {
        revert("approvals disabled");
    }

    // ─── Roles ───────────────────────────────────────────────────────────────────

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual override {
        super._grantRole(role, account);

        if (role == DEFAULT_ADMIN_ROLE) {
            _adminCount.increment();
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     * if the role to revoke is DEFAULT_ADMIN_ROLE and there is only one account with that role it will revert
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            _adminCount.decrement();

            require(_adminCount.current() > 0, "contract cannot be left without an admin");
        }

        super._revokeRole(role, account);
    }

    // ─── Token Operations ────────────────────────────────────────────────────────

    /*
      mints tokens on the caller's account

      emits transfer(address(0), owner, amount)
    */
    function mint(uint256 amount) external onlyMinters nonZeroAmount(amount) returns (bool) {
        super._mint(msg.sender, amount);
        return true;
    }

    /*
      burns tokens from the caller's account

      emits transfer(owner, address(0), amount)
    */
    function burn(uint256 amount) external onlyBurners nonZeroAmount(amount) returns (bool) {
        super._burn(msg.sender, amount);
        return true;
    }

    /*
      Uses 2 decimal places for external systems to convert to FIAT with a higher precision.
    */
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    /**
     * @dev Returns "USDK" as the token name.
     */
    function name() public pure override returns (string memory) {
        return "USDK";
    }

    /**
     * @dev Returns "USDK" as the token symbol.
     */
    function symbol() public pure override returns (string memory) {
        return "USDK";
    }

    /*
    metaTransfer is the ONLY way to move tokens between accounts.
    Restricted to accounts with the TRANSFERRERS role.

    can be executed by a third party different than the owner of the sender account by providing a signature of some parameters
    from the transaction
    */
    function metaTransfer(
        bytes calldata signature,
        address sender,
        address recipient,
        uint256 amount,
        uint256 deadline,
        string calldata metadata
    ) public onlyTransferrers nonZeroAmount(amount) nonZeroAccount(sender) nonZeroAccount(recipient) returns (bool) {
        // if msg.sender is different from sender it checks the signature that sender must have signed
        if (msg.sender != sender) {
            address signer = _getSigningAddress(signature, sender, recipient, amount, deadline);

            require(signer == sender, "Permit: invalid signature");
        }
        super._transfer(sender, recipient, amount);

        emit MetaTransferCalled(metadata);

        return true;
    }

    /*
    retrieves the signing address of a signature provided from the metaTransfer function
    */
    function _getSigningAddress(
        bytes calldata signature,
        address sender,
        address recipient,
        uint256 amount,
        uint256 deadline
    ) internal returns (address signer) {
        require(block.timestamp < deadline, "Signature expired");

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Permit(address owner,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"),
                    sender,
                    recipient,
                    amount,
                    _useNonce(sender),
                    deadline
                )
            )
        );

        signer = ECDSAUpgradeable.recover(digest, signature);
        require(signer != address(0), "ECSDA: invalid signature");
    }

    /*
    returns the nonce value of an account in respect to this token
    */
    function nonces(address addr) public view virtual returns (uint256) {
        return _nonces[addr].current();
    }

    /*
    returns the nonce value of an account in respect to this token and increases the value by 1
    */
    function _useNonce(address addr) internal virtual returns (uint256 current) {
        CountersUpgradeable.Counter storage nonce = _nonces[addr];
        current = nonce.current();
        nonce.increment();
    }
}
