// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {Attestation} from '@predicate/interfaces/IPredicateRegistry.sol';
import {PredicateClient} from '@predicate/mixins/PredicateClient.sol';

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

    /// @notice Update the auction contract address that this hook validates for
    /// @param newAuction The new auction contract address
    function updateAuction(address newAuction) external;
}

/// @title NobleValidationHook
/// @notice Validation hook that restricts auction participation to whitelisted addresses until a specified block
/// @dev After `expirationBlock`, the whitelist check is bypassed and anyone can participate.
///      This hook also enforces that bids can only be submitted by the owner themselves (no third-party submissions).
contract NobleValidationHook is INobleValidationHook, ValidationHookIntrospection, PredicateClient, Ownable {
    /// @notice The auction contract this hook validates bids for
    address public auction;

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

    /// @notice Emitted when the auction contract address is updated
    /// @param newAuction The new auction contract address
    event AuctionUpdated(address newAuction);

    /// @notice Emitted when an attestation is successfully validated
    /// @param sender The address that submitted the bid
    /// @param uuid The unique identifier of the attestation
    event AttestationValidated(address indexed sender, string uuid);

    /// @notice Thrown when a caller without whitelister permissions attempts to whitelist addresses
    error NotWhitelister();

    /// @notice Thrown when a non-whitelisted address attempts to participate in the auction
    error NotWhitelisted();

    /// @notice Thrown when the bid owner is not the same as the transaction sender
    error OwnerIsNotSender();

    /// @notice Error thrown when validate is called by an address other than the auction
    error OnlyAuction();

    /// @notice Error thrown when an invalid attestation is provided
    error InvalidAttestation();

    /// @notice Restricts function access to addresses with whitelister permissions
    modifier onlyWhitelister() {
        if (!whitelisters[msg.sender]) revert NotWhitelister();
        _;
    }

    /// @notice Initializes the whitelist validation hook
    /// @param owner The address that will own the contract and can manage whitelisters
    /// @param initialWhitelister The first address granted whitelister permissions
    /// @param _expirationBlock The block number until which whitelist validation is enforced
    /// @param _auction The address of the auction contract this hook will validate for
    /// @param _registry The Predicate registry contract address
    /// @param _policyID The policy ID for attestation verification
    constructor(
        address owner,
        address initialWhitelister,
        uint256 _expirationBlock,
        address _auction,
        address _registry,
        string memory _policyID
    ) Ownable(owner) {
        expirationBlock = _expirationBlock;
        whitelisters[initialWhitelister] = true;
        auction = _auction;
        _initPredicateClient(_registry, _policyID);
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

    /// @inheritdoc INobleValidationHook
    function updateAuction(address newAuction) external onlyOwner {
        auction = newAuction;
    }

    /// @notice Validates that the sender is bidding for themselves, is whitelisted (if applicable), and has a valid attestation
    /// @dev Reverts if:
    ///      - Caller is not the auction contract
    ///      - Owner != sender (no third-party submissions allowed)
    ///      - Sender is not whitelisted and block.number < expirationBlock
    ///      - Attestation verification fails via _authorizeTransaction
    /// @param owner The address that will own the bid and receive tokens
    /// @param sender The address submitting the bid transaction
    /// @param hookData ABI-encoded Attestation struct containing compliance proof
    function validate(uint256, uint128, address owner, address sender, bytes calldata hookData) external {
        if (msg.sender != auction) {
            revert OnlyAuction();
        }
        if (owner != sender) revert OwnerIsNotSender();
        if (block.number < expirationBlock) {
            if (!whitelisted[sender]) revert NotWhitelisted();
        }

        Attestation memory attestation = abi.decode(hookData, (Attestation));

        // Encode the validate call signature and arguments for attestation verification
        // Placeholder values used for maxPrice and amount as they're not relevant for compliance checks
        bytes memory encodedSigAndArgs =
            abi.encodeWithSelector(IValidationHook.validate.selector, uint256(0), uint128(0), owner, sender, hookData);

        bool success = _authorizeTransaction(attestation, encodedSigAndArgs, sender, 0);
        if (!success) {
            revert InvalidAttestation();
        }

        emit AttestationValidated(sender, attestation.uuid);
    }

    /// @notice Updates the policy ID for this hook
    /// @dev Can only be called by the contract Owner
    /// @param _policyID The new policy ID
    function setPolicyID(string memory _policyID) external override onlyOwner {
        _setPolicyID(_policyID);
    }

    /// @notice Updates the Predicate registry address
    /// @dev Can only be called by the contract Owner
    /// @param _registry The new registry address
    function setRegistry(address _registry) external override onlyOwner {
        _setRegistry(_registry);
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
}
