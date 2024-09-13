// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {AssociatedLinkedListSet, AssociatedLinkedListSetLib} from "@alchemy/light-account/lib/modular-account/src/libraries/AssociatedLinkedListSetLib.sol";

import {ExecutionManifest, ManifestExecutionFunction} from "@erc-6900/reference-implementation/interfaces/IExecutionModule.sol";
import {ExecutionManifest, IExecutionModule} from "@erc-6900/reference-implementation/interfaces/IExecutionModule.sol";
import {IModule} from "@erc-6900/reference-implementation/interfaces/IModule.sol";

import {BaseModule} from "../BaseModule.sol";
import {IMultisigPlugin} from "./IMultisigPlugin.sol";

/// @title Multisig Plugin
/// @author Wa;etX
/// @notice This plugin adds a k of n threshold ownership scheme to a ERC6900 smart contract account
/// @notice Multisig verification impl is derived from [Safe](https://github.com/safe-global/safe-smart-account)
///
/// It supports [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) signature
/// validation for both validating the signature on user operations and in
/// exposing its own `isValidSignature` method. This only works when the owner of
/// modular account also support ERC-1271.
///
/// ERC-4337's bundler validation rules limit the types of contracts that can be
/// used as owners to validate user operation signatures. For example, the
/// contract's `isValidSignature` function may not use any forbidden opcodes
/// such as `TIMESTAMP` or `NUMBER`, and the contract may not be an ERC-1967
/// proxy as it accesses a constant implementation slot not associated with
/// the account, violating storage access rules. This also means that the
/// owner of a modular account may not be another modular account if you want to
/// send user operations through a bundler.

contract MultisigModule is IExecutionModule, BaseModule, IERC1271 {
    using ECDSA for bytes32;
    using SafeCast for uint256;

    string internal constant _NAME = "Multisig Plugin";
    string internal constant _VERSION = "1.0.0";
    string internal constant _AUTHOR = "WalletX";

    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
        );
    bytes32 private constant _HASHED_NAME = keccak256(bytes(_NAME));
    bytes32 private constant _HASHED_VERSION = keccak256(bytes(_VERSION));
    bytes32 private immutable _SALT = bytes32(bytes20(address(this)));

    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant _1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _1271_MAGIC_VALUE_FAILURE = 0xffffffff;

    bytes32 private constant _MULTISIG_PLUGIN_TYPEHASH =
        keccak256("WalletXMultisigMessage(bytes message)");

    AssociatedLinkedListSet internal _owners;
    mapping(address => OwnershipMetadata) internal _ownerMetadata;
    address public immutable ENTRYPOINT;

    /// @notice Metadata of the ownership of an account.
    /// @param numOwners number of owners on the account
    /// @param threshold number of signatures required to perform an action
    struct OwnershipMetadata {
        uint128 numOwners;
        uint128 threshold;
    }

    constructor(address entryPoint) {
        ENTRYPOINT = entryPoint;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc IMultisigPlugin
    /// @dev If an owner is present in both ownersToAdd and ownersToRemove, it will be added as owner.
    /// The owner array cannot have 0 or duplicated addresses.
    function updateOwnership(
        address[] memory ownersToAdd,
        address[] memory ownersToRemove,
        uint128 newThreshold
    ) public isInitialized(msg.sender) {
        // update owners array
        uint256 toRemoveLen = ownersToRemove.length;
        for (uint256 i = 0; i < toRemoveLen; ++i) {
            if (
                !_owners.tryRemove(
                    msg.sender,
                    CastLib.toSetValue(ownersToRemove[i])
                )
            ) {
                revert OwnerDoesNotExist(ownersToRemove[i]);
            }
        }

        _addOwnersOrRevert(msg.sender, ownersToAdd);

        OwnershipMetadata storage metadata = _ownerMetadata[msg.sender];
        uint256 numOwners = metadata.numOwners;

        uint256 toAddLen = ownersToAdd.length;
        if (toAddLen != toRemoveLen) {
            numOwners = numOwners - toRemoveLen + toAddLen;
            if (numOwners == 0) {
                revert EmptyOwnersNotAllowed();
            }
            metadata.numOwners = numOwners.toUint128();
        }

        // If newThreshold is zero, don't update and keep the previous threshold value
        if (newThreshold != 0) {
            metadata.threshold = newThreshold;
        }
        if (metadata.threshold > numOwners) {
            revert InvalidThreshold();
        }

        emit OwnerUpdated(
            msg.sender,
            ownersToAdd,
            ownersToRemove,
            newThreshold
        );
    }
}
