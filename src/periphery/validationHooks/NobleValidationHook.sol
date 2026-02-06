// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IBaseERC1155ValidationHook} from './BaseERC1155ValidationHook.sol';
import {IGatedERC1155ValidationHook} from './GatedERC1155ValidationHook.sol';
import {ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC1155} from '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {IPredicateClient} from '@predicate/interfaces/IPredicateClient.sol';
import {Attestation} from '@predicate/interfaces/IPredicateRegistry.sol';
import {PredicateClient} from '@predicate/mixins/PredicateClient.sol';

/// @title INobleValidationHook
/// @notice Full interface for the Noble validation hook with whitelist management and expiration
/// @dev Extends IGatedERC1155ValidationHook with admin functions for whitelister management and auction configuration
interface INobleValidationHook is IGatedERC1155ValidationHook {
    /// @notice Returns whether an address has whitelister permissions
    /// @param addr The address to check
    /// @return True if the address can whitelist others
    function whitelisters(address addr) external view returns (bool);

    /// @notice The auction contract this hook validates bids for
    /// @return The auction contract address
    function auction() external view returns (address);

    /// @notice Whitelist a single address by minting them a soulbound ERC1155 token
    /// @param addr The address to whitelist
    function whitelistAddress(address addr) external;

    /// @notice Whitelist multiple addresses in a single transaction by minting each a soulbound ERC1155 token
    /// @param addrs The addresses to whitelist
    function whitelistAddresses(address[] calldata addrs) external;

    /// @notice Grant whitelister permissions to an address
    /// @param addr The address to grant permissions to
    function addWhitelister(address addr) external;

    /// @notice Revoke whitelister permissions from an address
    /// @param addr The address to revoke permissions from
    function removeWhitelister(address addr) external;

    /// @notice Update the auction contract address that this hook validates for
    /// @param newAuction The new auction contract address
    function updateAuction(address newAuction) external;

    /// @notice Update the block number until which whitelist validation is enforced
    /// @param newBlock The new expiration block number
    function updateExpirationBlock(uint256 newBlock) external;
}

/// @title NobleValidationHook
/// @notice Soulbound ERC1155 validation hook that restricts auction participation to whitelisted addresses until a specified block
/// @dev The contract itself is the ERC1155 token — whitelisting mints a soulbound token, and validation checks the balance.
///      After `expirationBlock`, the token balance check is bypassed and anyone can participate.
///      This hook also enforces that bids can only be submitted by the owner themselves (no third-party submissions).
contract NobleValidationHook is INobleValidationHook, ValidationHookIntrospection, ERC1155, PredicateClient, Ownable {
    /// @notice The block number until which whitelist validation is enforced
    /// @inheritdoc IGatedERC1155ValidationHook
    uint256 public expirationBlock;

    /// @notice The ERC1155 token ID used for whitelist credentials
    /// @inheritdoc IBaseERC1155ValidationHook
    uint256 public constant tokenId = 0;

    /// @notice The auction contract this hook validates bids for
    address public auction;

    /// @notice Mapping of addresses to their whitelister permissions
    mapping(address => bool) public whitelisters;

    /// @notice Emitted when an address is granted whitelister permissions
    /// @param addr The address that was granted permissions
    event WhitelisterAdded(address indexed addr);

    /// @notice Emitted when an address has whitelister permissions revoked
    /// @param addr The address that had permissions revoked
    event WhitelisterRemoved(address indexed addr);

    /// @notice Emitted when the auction contract address is updated
    /// @param newAuction The new auction contract address
    event AuctionUpdated(address newAuction);

    /// @notice Emitted when an attestation is successfully validated
    /// @param sender The address that submitted the bid
    /// @param uuid The unique identifier of the attestation
    event AttestationValidated(address indexed sender, string uuid);

    /// @notice Emitted when the expiration block is updated
    /// @param newBlock The new expiration block number
    event ExpirationBlockUpdated(uint256 newBlock);

    /// @notice Thrown when a caller without whitelister permissions attempts to whitelist addresses
    error NotWhitelister();

    /// @notice Thrown when an address without a whitelist token attempts to participate in the auction
    error NotWhitelisted();

    /// @notice Thrown when the bid owner is not the same as the transaction sender
    error OwnerIsNotSender();

    /// @notice Thrown when validate is called by an address other than the auction
    error OnlyAuction();

    /// @notice Thrown when an invalid attestation is provided
    error InvalidAttestation();

    /// @notice Thrown when a transfer is attempted — whitelist tokens are soulbound (non-transferable)
    error SoulboundToken();

    /// @notice Restricts function access to addresses with whitelister permissions
    modifier onlyWhitelister() {
        if (!whitelisters[msg.sender]) revert NotWhitelister();
        _;
    }

    /// @notice Initializes the Noble validation hook
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
    ) ERC1155('') Ownable(owner) {
        expirationBlock = _expirationBlock;
        whitelisters[initialWhitelister] = true;
        auction = _auction;
        _initPredicateClient(_registry, _policyID);
    }

    // ─── IBaseERC1155ValidationHook ──────────────────────────────────

    /// @notice Returns the ERC1155 token contract used for whitelist checks
    /// @dev Returns `address(this)` since this contract is itself the ERC1155 token
    /// @return The ERC1155 interface pointing to this contract
    /// @inheritdoc IBaseERC1155ValidationHook
    function erc1155() external view returns (IERC1155) {
        return IERC1155(address(this));
    }

    // ─── Soulbound ───────────────────────────────────────────────────

    /// @notice Prevents all transfers — only minting (from == address(0)) is allowed
    /// @dev Overrides ERC1155._update to enforce soulbound behavior
    /// @param from The sender address (must be address(0) for minting)
    /// @param to The recipient address
    /// @param ids The token IDs being transferred
    /// @param values The amounts being transferred
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        if (from != address(0)) revert SoulboundToken();
        super._update(from, to, ids, values);
    }

    // ─── Whitelister Management ──────────────────────────────────────

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

    // ─── Whitelisting ────────────────────────────────────────────────

    /// @notice Whitelists a single address by minting them a soulbound ERC1155 token
    /// @inheritdoc INobleValidationHook
    function whitelistAddress(address addr) external onlyWhitelister {
        _mint(addr, tokenId, 1, '');
    }

    /// @notice Whitelists multiple addresses by minting each a soulbound ERC1155 token
    /// @inheritdoc INobleValidationHook
    function whitelistAddresses(address[] calldata addrs) external onlyWhitelister {
        for (uint256 i = 0; i < addrs.length; i++) {
            _mint(addrs[i], tokenId, 1, '');
        }
    }

    // ─── Validation ──────────────────────────────────────────────────

    /// @notice Validates that the sender is bidding for themselves, holds a whitelist token (if applicable), and has a valid attestation
    /// @dev Reverts if:
    ///      - Caller is not the auction contract
    ///      - Owner != sender (no third-party submissions allowed)
    ///      - Sender does not hold a whitelist token and block.number < expirationBlock
    ///      - Attestation verification fails via _authorizeTransaction
    /// @param owner The address that will own the bid and receive tokens
    /// @param sender The address submitting the bid transaction
    /// @param hookData ABI-encoded Attestation struct containing compliance proof
    function validate(uint256, uint128, address owner, address sender, bytes calldata hookData) external {
        if (msg.sender != auction) revert OnlyAuction();
        if (owner != sender) revert OwnerIsNotSender();

        if (block.number < expirationBlock) {
            if (balanceOf(sender, tokenId) == 0) revert NotWhitelisted();
        }

        Attestation memory attestation = abi.decode(hookData, (Attestation));

        // Encode the validate call signature and arguments for attestation verification
        // Placeholder values used for maxPrice and amount as they're not relevant for compliance checks
        bytes memory encodedSigAndArgs =
            abi.encodeWithSelector(IValidationHook.validate.selector, uint256(0), uint128(0), owner, sender, hookData);

        bool success = _authorizeTransaction(attestation, encodedSigAndArgs, sender, 0);
        if (!success) revert InvalidAttestation();

        emit AttestationValidated(sender, attestation.uuid);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @inheritdoc INobleValidationHook
    function updateAuction(address newAuction) external onlyOwner {
        auction = newAuction;
        emit AuctionUpdated(newAuction);
    }

    /// @notice Updates the policy ID for this hook
    /// @dev Can only be called by the contract owner
    /// @param _policyID The new policy ID
    function setPolicyID(string memory _policyID) external override onlyOwner {
        _setPolicyID(_policyID);
    }

    /// @notice Updates the Predicate registry address
    /// @dev Can only be called by the contract owner
    /// @param _registry The new registry address
    function setRegistry(address _registry) external override onlyOwner {
        _setRegistry(_registry);
    }

    /// @notice Update the block number until which whitelist validation is enforced
    /// @dev Can only be called by the contract owner
    /// @param newBlock The new expiration block number
    /// @inheritdoc INobleValidationHook
    function updateExpirationBlock(uint256 newBlock) external onlyOwner {
        expirationBlock = newBlock;
        emit ExpirationBlockUpdated(newBlock);
    }

    // ─── Introspection ──────────────────────────────────────────────

    /// @notice Returns true if the contract supports the given interface
    /// @dev Reports support for IBaseERC1155ValidationHook, IGatedERC1155ValidationHook, INobleValidationHook, IPredicateClient, and inherited interfaces
    /// @param _interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ValidationHookIntrospection, ERC1155, IERC165)
        returns (bool)
    {
        return ValidationHookIntrospection.supportsInterface(_interfaceId) || ERC1155.supportsInterface(_interfaceId)
            || _interfaceId == type(IBaseERC1155ValidationHook).interfaceId
            || _interfaceId == type(IGatedERC1155ValidationHook).interfaceId
            || _interfaceId == type(INobleValidationHook).interfaceId
            || _interfaceId == type(IPredicateClient).interfaceId;
    }
}
