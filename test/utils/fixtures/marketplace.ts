import { expect } from "chai";
import { constants } from "ethers";
import { keccak256, recoverAddress } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { ConsiderationItem, OfferItem, OrderComponents } from "../types";
import { calculateOrderHash, convertSignatureToEIP2098, randomHex, toBN } from "../encoding";

import type { Contract, Wallet } from "ethers";
import { orderType } from "../../eip721-types/order";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "../../constants/marketplace";

export const marketplaceFixture = async () => {
    const { chainId } = await ethers.provider.getNetwork();
    const [, marketplaceOwner] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.connect(marketplaceOwner).deploy();

    // Required for EIP712 signing
    const domainData = {
        name: MARKETPLACE_NAME,
        version: MARKETPLACE_VERSION,
        chainId,
        verifyingContract: marketplace.address,
    };

    const getAndVerifyOrderHash = async (orderComponents: OrderComponents) => {
        const orderHash = await marketplace.getOrderHash(orderComponents);
        const derivedOrderHash = calculateOrderHash(orderComponents);
        expect(orderHash).to.equal(derivedOrderHash);
        return orderHash;
    };

    const signOrder = async (orderComponents: OrderComponents, signer: Wallet | Contract) => {
        const signature = await signer._signTypedData(domainData, orderType, orderComponents);

        const orderHash = await getAndVerifyOrderHash(orderComponents);
        const { domainSeparator } = await marketplace.information();
        const digest = keccak256(`0x1901${domainSeparator.slice(2)}${orderHash.slice(2)}`);
        const recoveredAddress = recoverAddress(digest, signature);
        expect(recoveredAddress).to.equal(signer.address);
        return signature;
    };

    const createOrder = async (
        offerer: Wallet | Contract,
        offer: OfferItem[],
        consideration: ConsiderationItem[],
        timeFlag?: "NOT_STARTED" | "EXPIRED" | null,
        signer?: Wallet,
        extraCheap = false,
    ) => {
        const counter = await marketplace.getCounter(offerer.address);

        const salt = !extraCheap ? randomHex() : constants.HashZero;
        const startTime = timeFlag !== "NOT_STARTED" ? 0 : toBN("0xee00000000000000000000000000");
        const endTime = timeFlag !== "EXPIRED" ? toBN("0xff00000000000000000000000000") : 1;

        const orderParameters = {
            offerer: offerer.address,
            offer,
            consideration,
            salt,
            startTime,
            endTime,
        };

        const orderComponents = {
            ...orderParameters,
            counter,
        };

        const orderHash = await getAndVerifyOrderHash(orderComponents);

        const { isValidated, isCancelled } = await marketplace.getOrderStatus(orderHash);

        expect(isCancelled).to.equal(false);

        const orderStatus = {
            isValidated,
            isCancelled,
        };

        const flatSig = await signOrder(orderComponents, signer ?? offerer);

        const order = {
            parameters: orderParameters,
            signature: !extraCheap ? flatSig : convertSignatureToEIP2098(flatSig),
        };

        // How much ether (at most) needs to be supplied when fulfilling the order
        const value = offer
            .map(x => (x.itemType === 0 ? (x.endAmount.gt(x.startAmount) ? x.endAmount : x.startAmount) : toBN(0)))
            .reduce((a, b) => a.add(b), toBN(0))
            .add(
                consideration
                    .map(x =>
                        x.itemType === 0 ? (x.endAmount.gt(x.startAmount) ? x.endAmount : x.startAmount) : toBN(0),
                    )
                    .reduce((a, b) => a.add(b), toBN(0)),
            );

        return {
            order,
            orderHash,
            value,
            orderStatus,
            orderComponents,
            startTime,
            endTime,
        };
    };

    return {
        marketplace,
        marketplaceOwner,
        domainData,
        getAndVerifyOrderHash,
        signOrder,
        createOrder,
    };
};
