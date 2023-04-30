// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {toByte32} from "../utils/ByteUtil.sol";
import "hardhat/console.sol";

contract MarketplaceBase {
    // Precompute hashes, original chainId, and domain separator on deployment.
    bytes32 internal immutable _NAME_HASH;
    bytes32 internal immutable _VERSION_HASH;
    bytes32 internal immutable _EIP_712_DOMAIN_TYPEHASH;
    bytes32 internal immutable _OFFER_ITEM_TYPEHASH;
    bytes32 internal immutable _CONSIDERATION_ITEM_TYPEHASH;
    bytes32 internal immutable _ORDER_TYPEHASH;
    uint256 internal immutable _CHAIN_ID;
    bytes32 internal immutable _DOMAIN_SEPARATOR;

    constructor() {
        // Derive name and version hashes alongside required EIP-712 typehashes.
        (
            _NAME_HASH,
            _VERSION_HASH,
            _EIP_712_DOMAIN_TYPEHASH,
            _OFFER_ITEM_TYPEHASH,
            _CONSIDERATION_ITEM_TYPEHASH,
            _ORDER_TYPEHASH
        ) = _deriveTypehashes();

        // Store the current chainId and derive the current domain separator.
        _CHAIN_ID = block.chainid;
        _DOMAIN_SEPARATOR = _deriveDomainSeparator();
    }

    /**
     * @dev Internal view function to derive the EIP-712 domain separator.
     *
     * @return domainSeparator The derived domain separator.
     */
    function _deriveDomainSeparator() internal view returns (bytes32 domainSeparator) {
        bytes memory localBytes = bytes.concat(
            _EIP_712_DOMAIN_TYPEHASH,
            _NAME_HASH,
            _VERSION_HASH,
            bytes32(_CHAIN_ID),
            toByte32(address(this))
        );

        domainSeparator = keccak256(localBytes);
    }

    /**
     * @dev Internal pure function to retrieve the default name of this
     *      contract and return.
     *
     * @return The name of this contract.
     */
    function _name() internal pure virtual returns (string memory) {
        return "Marketplace";
    }

    /**
     * @dev Internal pure function to retrieve the version of this
     *      contract and return.
     *
     * @return The version of this contract.
     */
    function _version() internal pure returns (string memory) {
        return "1.0";
    }

    /**
     * @dev Internal pure function to derive required EIP-712 typehashes and
     *      other hashes during contract creation.
     *
     * @return nameHash                  The hash of the name of the contract.
     * @return versionHash               The hash of the version string of the
     *                                   contract.
     * @return eip712DomainTypehash      The primary EIP-712 domain typehash.
     * @return offerItemTypehash         The EIP-712 typehash for OfferItem
     *                                   types.
     * @return considerationItemTypehash The EIP-712 typehash for
     *                                   ConsiderationItem types.
     * @return orderTypehash             The EIP-712 typehash for Order types.
     */
    function _deriveTypehashes()
        internal
        pure
        returns (
            bytes32 nameHash,
            bytes32 versionHash,
            bytes32 eip712DomainTypehash,
            bytes32 offerItemTypehash,
            bytes32 considerationItemTypehash,
            bytes32 orderTypehash
        )
    {
        // Derive hash of the name of the contract.
        nameHash = keccak256(bytes(_name()));

        // Derive hash of the version string of the contract.
        versionHash = keccak256(bytes(_version()));

        // Construct the OfferItem type string.
        bytes memory offerItemTypeString = bytes(
            "OfferItem("
            "uint8 itemType,"
            "address token,"
            "uint256 identifier,"
            "uint256 startAmount,"
            "uint256 endAmount"
            ")"
        );

        // Construct the ConsiderationItem type string.
        bytes memory considerationItemTypeString = bytes(
            "ConsiderationItem("
            "uint8 itemType,"
            "address token,"
            "uint256 identifier,"
            "uint256 startAmount,"
            "uint256 endAmount,"
            "address recipient"
            ")"
        );

        // Construct the OrderComponents type string, not including the above.
        bytes memory orderComponentsPartialTypeString = bytes(
            "OrderComponents("
            "address offerer,"
            "OfferItem[] offer,"
            "ConsiderationItem[] consideration,"
            "uint256 startTime,"
            "uint256 endTime,"
            "uint256 salt,"
            "uint256 counter"
            ")"
        );

        // Construct the primary EIP-712 domain type string.
        eip712DomainTypehash = keccak256(
            bytes(
                "EIP712Domain("
                "string name,"
                "string version,"
                "uint256 chainId,"
                "address verifyingContract"
                ")"
            )
        );

        // Derive the OfferItem type hash using the corresponding type string.
        offerItemTypehash = keccak256(offerItemTypeString);

        // Derive ConsiderationItem type hash using corresponding type string.
        considerationItemTypehash = keccak256(considerationItemTypeString);

        bytes memory orderTypeString = bytes.concat(
            orderComponentsPartialTypeString,
            considerationItemTypeString,
            offerItemTypeString
        );

        // Derive OrderItem type hash via combination of relevant type strings.
        orderTypehash = keccak256(orderTypeString);
    }
}
