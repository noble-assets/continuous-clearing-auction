// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/// @title IWhitelistValidationHook
/// @notice Interface for validation hooks that support whitelist status queries
/// @dev Frontends can check for this interface to determine if they can query a user's whitelist status
interface IWhitelistValidationHook is IValidationHookIntrospection {
    /// @notice Returns whether an address is whitelisted
    /// @param addr The address to check
    /// @return True if the address is whitelisted
    function whitelisted(address addr) external view returns (bool);
}

/// @title IExpiringValidationHook
/// @notice Interface for validation hooks that have a time-limited validation period
/// @dev Frontends can check for this interface to determine if the hook has an expiration
interface IExpiringValidationHook is IValidationHookIntrospection {
    /// @notice The block number until which validation is enforced
    /// @return The block number after which validation is bypassed
    function expirationBlock() external view returns (uint256);
}

/// @title INobleValidationHook
/// @notice Full interface for the Noble validation hook with whitelist management and expiration
/// @dev Extends both IWhitelistValidationHook and IExpiringValidationHook with admin functions
interface INobleValidationHook is IWhitelistValidationHook, IExpiringValidationHook {
    /// @notice Returns whether an address has whitelister permissions
    /// @param addr The address to check
    /// @return True if the address can whitelist others
    function whitelisters(address addr) external view returns (bool);

    /// @notice Whitelist a single address
    /// @param addr The address to whitelist
    function whitelistAddress(address addr) external;

    /// @notice Whitelist multiple addresses in a single transaction
    /// @param addrs The addresses to whitelist
    function whitelistAddresses(address[] calldata addrs) external;

    /// @notice Grant whitelister permissions to an address
    /// @param addr The address to grant permissions to
    function addWhitelister(address addr) external;

    /// @notice Revoke whitelister permissions from an address
    /// @param addr The address to revoke permissions from
    function removeWhitelister(address addr) external;

    /// @notice Update the block number until which whitelist validation is enforced
    /// @param newBlock The new expiration block number
    function updateExpirationBlock(uint256 newBlock) external;
}

/// @title NobleValidationHook
/// @notice Validation hook that restricts auction participation to whitelisted addresses until a specified block
/// @dev After `expirationBlock`, the whitelist check is bypassed and anyone can participate.
///      This hook also enforces that bids can only be submitted by the owner themselves (no third-party submissions).
contract NobleValidationHook is INobleValidationHook, ValidationHookIntrospection, Ownable {
    /// @notice Mapping of addresses to their whitelist status
    mapping(address => bool) public whitelisted;

    /// @notice Mapping of addresses to their whitelister permissions
    mapping(address => bool) public whitelisters;

    /// @notice The block number until which whitelist validation is enforced
    uint256 public expirationBlock;

    /// @notice Emitted when an address is added to the whitelist
    /// @param addr The address that was whitelisted
    event AddressWhitelisted(address indexed addr);

    /// @notice Emitted when an address is granted whitelister permissions
    /// @param addr The address that was granted permissions
    event WhitelisterAdded(address indexed addr);

    /// @notice Emitted when an address has whitelister permissions revoked
    /// @param addr The address that had permissions revoked
    event WhitelisterRemoved(address indexed addr);

    /// @notice Emitted when the expiration block is updated
    /// @param newBlock The new expiration block number
    event ExpirationBlockUpdated(uint256 newBlock);

    /// @notice Thrown when a caller without whitelister permissions attempts to whitelist addresses
    error NotWhitelister();

    /// @notice Thrown when a non-whitelisted address attempts to participate in the auction
    error NotWhitelisted();

    /// @notice Thrown when the bid owner is not the same as the transaction sender
    error OwnerIsNotSender();

    /// @notice Restricts function access to addresses with whitelister permissions
    modifier onlyWhitelister() {
        if (!whitelisters[msg.sender]) revert NotWhitelister();
        _;
    }

    /// @notice Initializes the whitelist validation hook
    /// @param owner The address that will own the contract and can manage whitelisters
    /// @param initialWhitelister The first address granted whitelister permissions
    /// @param _expirationBlock The block number until which whitelist validation is enforced
    constructor(address owner, address initialWhitelister, uint256 _expirationBlock) Ownable(owner) {
        expirationBlock = _expirationBlock;
        whitelisters[initialWhitelister] = true;
    }

    /// @inheritdoc INobleValidationHook
    function addWhitelister(address addr) external onlyOwner {
        whitelisters[addr] = true;
        emit WhitelisterAdded(addr);
    }

    /// @inheritdoc INobleValidationHook
    function removeWhitelister(address addr) external onlyOwner {
        whitelisters[addr] = false;
        emit WhitelisterRemoved(addr);
    }

    /// @inheritdoc INobleValidationHook
    function whitelistAddress(address addr) external onlyWhitelister {
        whitelisted[addr] = true;
        emit AddressWhitelisted(addr);
    }

    /// @inheritdoc INobleValidationHook
    function whitelistAddresses(address[] calldata addrs) external onlyWhitelister {
        for (uint256 i = 0; i < addrs.length; i++) {
            whitelisted[addrs[i]] = true;
            emit AddressWhitelisted(addrs[i]);
        }
    }

    /// @inheritdoc INobleValidationHook
    function updateExpirationBlock(uint256 newBlock) external onlyOwner {
        expirationBlock = newBlock;
        emit ExpirationBlockUpdated(newBlock);
    }

    /// @notice Returns true if the contract supports the given interface
    /// @dev Reports support for IWhitelistValidationHook, IExpiringValidationHook, and INobleValidationHook
    /// @param _interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ValidationHookIntrospection, IERC165)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IWhitelistValidationHook).interfaceId
            || _interfaceId == type(IExpiringValidationHook).interfaceId
            || _interfaceId == type(INobleValidationHook).interfaceId;
    }

    /// @notice Validates that the sender is bidding for themselves and is whitelisted
    /// @dev Reverts if owner != sender (no third-party submissions allowed).
    ///      Whitelist check is only enforced until `expirationBlock`.
    /// @param owner The address that will own the bid and receive tokens
    /// @param sender The address submitting the bid transaction
    function validate(uint256, uint128, address owner, address sender, bytes calldata) external view {
        if (owner != sender) revert OwnerIsNotSender();

        if (block.number < expirationBlock) {
            if (!whitelisted[sender]) revert NotWhitelisted();
        }
    }
}
