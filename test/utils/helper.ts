import { Contract, Wallet } from "ethers";
import { calculateOrderHash } from "./encoding";
import { Domain, OrderComponents } from "./types";
import { expect } from "chai";
import { getAddress, keccak256, toUtf8Bytes, recoverAddress } from "ethers/lib/utils";
import { ethers } from "hardhat";

// export const getAndVerifyOrderHash = async (orderComponents: OrderComponents) => {
//     const orderHash = await marketplaceContract.getOrderHash(orderComponents);
//     const derivedOrderHash = calculateOrderHash(orderComponents);
//     expect(orderHash).to.equal(derivedOrderHash);
//     return orderHash;
// };
const { provider } = ethers;

// Returns signature
export const signOrder = async (orderComponents: OrderComponents, signer: Wallet | Contract, domain: Domain) => {
    // The named list of all type definitions
    const orderType = {
        OrderComponents: [
            { name: "offerer", type: "address" },
            { name: "zone", type: "address" },
            { name: "offer", type: "OfferItem[]" },
            { name: "consideration", type: "ConsiderationItem[]" },
            { name: "orderType", type: "uint8" },
            { name: "startTime", type: "uint256" },
            { name: "endTime", type: "uint256" },
            { name: "zoneHash", type: "bytes32" },
            { name: "salt", type: "uint256" },
            // { name: "conduitKey", type: "bytes32" },
            { name: "counter", type: "uint256" },
        ],
        OfferItem: [
            { name: "itemType", type: "uint8" },
            { name: "token", type: "address" },
            { name: "identifier", type: "uint256" },
            { name: "startAmount", type: "uint256" },
            { name: "endAmount", type: "uint256" },
        ],
        ConsiderationItem: [
            { name: "itemType", type: "uint8" },
            { name: "token", type: "address" },
            { name: "identifier", type: "uint256" },
            { name: "startAmount", type: "uint256" },
            { name: "endAmount", type: "uint256" },
            { name: "recipient", type: "address" },
        ],
    };

    const signature = await signer._signTypedData(domain, orderType, orderComponents);

    return signature;
};
