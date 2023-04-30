// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {CounterManager} from "./CounterManager.sol";
import {OrderParameters, OfferItem, ConsiderationItem} from "./MarketplaceStruct.sol";
import "hardhat/console.sol";
import {toByte32} from "../utils/ByteUtil.sol";

contract GettersAndDerivers is CounterManager {
    function _deriveOrderHash(
        OrderParameters memory orderParameters,
        uint256 counter
    ) internal view returns (bytes32 orderHash) {
        bytes32 offerHash;
        {
            bytes memory offerData = new bytes(0);

            uint offerLength = orderParameters.offer.length;
            for (uint i = 0; i < offerLength; i++) {
                OfferItem memory item = orderParameters.offer[i];
                bytes memory itemData = bytes.concat(
                    _OFFER_ITEM_TYPEHASH,
                    bytes32(uint256(item.itemType)),
                    toByte32(item.token),
                    bytes32(item.identifier),
                    bytes32(item.startAmount),
                    bytes32(item.endAmount)
                );
                bytes32 itemHash = keccak256(itemData);

                offerData = bytes.concat(offerData, itemHash);
            }

            offerHash = keccak256(offerData);
        }

        bytes32 considerationHash;
        {
            bytes memory considerationData = new bytes(0);

            uint offerLength = orderParameters.consideration.length;
            for (uint i = 0; i < offerLength; i++) {
                ConsiderationItem memory item = orderParameters.consideration[i];
                bytes memory itemData = bytes.concat(
                    _CONSIDERATION_ITEM_TYPEHASH,
                    bytes32(uint256(item.itemType)),
                    toByte32(item.token),
                    bytes32(item.identifier),
                    bytes32(item.startAmount),
                    bytes32(item.endAmount),
                    toByte32(item.recipient)
                );
                bytes32 itemHash = keccak256(itemData);

                considerationData = bytes.concat(considerationData, itemHash);
            }

            considerationHash = keccak256(considerationData);
        }

        {
            bytes memory orderData = bytes.concat(
                _ORDER_TYPEHASH,
                toByte32(orderParameters.offerer),
                offerHash,
                considerationHash,
                bytes32(orderParameters.startTime),
                bytes32(orderParameters.endTime),
                bytes32(orderParameters.salt),
                bytes32(counter)
            );
            orderHash = keccak256(orderData);
        }
    }

    /**
     * @dev Internal view function to get the EIP-712 domain separator. If the
     *      chainId matches the chainId set on deployment, the cached domain
     *      separator will be returned; otherwise, it will be derived from
     *      scratch.
     *
     * @return The domain separator.
     */
    function _domainSeparator() internal view returns (bytes32) {
        return block.chainid == _CHAIN_ID ? _DOMAIN_SEPARATOR : _deriveDomainSeparator();
    }

    /**
     * @dev Internal view function to retrieve configuration information for
     *      this contract.
     *
     * @return version The contract version.
     * @return domainSeparator The domain separator for this contract.
     */
    function _information() internal view returns (string memory version, bytes32 domainSeparator) {
        // Derive the version.
        version = _version();

        // Derive the domain separator.
        domainSeparator = _domainSeparator();
    }

    /**
     * @dev Internal pure function to efficiently derive an digest to sign for
     *      an order in accordance with EIP-712.
     *
     * @param domainSeparator The domain separator.
     * @param orderHash       The order hash.
     *
     * @return value The hash.
     */
    function _deriveEIP712Digest(
        bytes32 domainSeparator,
        bytes32 orderHash
    ) internal pure returns (bytes32 value) {
        bytes memory data = bytes.concat(bytes2(0x1901), domainSeparator, orderHash);

        value = keccak256(data);
    }

    function _deriveSignature(
        bytes memory signature
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (signature.length == 64) {
            bytes32 yParityAndS;
            assembly {
                r := mload(add(signature, 32))
                yParityAndS := mload(add(signature, 64))
                // s = yParityAndS & ((1 << 255) - 1)
                s := and(
                    yParityAndS,
                    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                )
                // v = (yParityAndS >> 255)
                v := shr(255, yParityAndS)
                if lt(v, 0x1b) {
                    v := add(v, 0x1b)
                }
            }
        } else if (signature.length == 65) {
            assembly {
                r := mload(add(signature, 32))
                // second 32 bytes
                s := mload(add(signature, 64))
                // final byte (first byte of the next 32 bytes)
                v := byte(0, mload(add(signature, 96)))
            }
        }
    }
}
