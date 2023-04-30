import { ethers } from "hardhat";
import {
    randomHex,
    randomBN,
    toBN,
    getItemETH,
    convertSignatureToEIP2098,
    calculateOrderHash,
} from "../../test/utils/encoding";
import { ConsiderationItem, OfferItem } from "../../test/utils/types";
import type { BigNumberish } from "ethers";
import { constants } from "ethers";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "../../test/constants/marketplace";
import { orderType as orderTypes } from "../../test/eip721-types/order";
import type { Contract, Wallet } from "ethers";
import { Marketplace } from "../../typechain-types";
import { keccak256, recoverAddress } from "ethers/lib/utils";
import axios from "axios";

export const getTestItem721 = (
    identifier: BigNumberish,
    token: string,
    startAmount: BigNumberish = 1,
    endAmount: BigNumberish = 1,
    recipient?: string,
) =>
    getOfferOrConsiderationItem(
        2, // ERC721
        token,
        identifier,
        startAmount,
        endAmount,
        recipient,
    );

const getOfferOrConsiderationItem = <RecipientType extends string | undefined = undefined>(
    itemType: number = 0,
    token: string,
    identifier: BigNumberish,
    startAmount: BigNumberish = 1,
    endAmount: BigNumberish = 1,
    recipient?: RecipientType,
): RecipientType extends string ? ConsiderationItem : OfferItem => {
    const offerItem: OfferItem = {
        itemType,
        token,
        identifier: toBN(identifier),
        startAmount: toBN(startAmount),
        endAmount: toBN(endAmount),
    };
    if (typeof recipient === "string") {
        return {
            ...offerItem,
            recipient: recipient as string,
        } as ConsiderationItem;
    }
    return offerItem as any;
};

export const createOrder = async (
    marketplace: Marketplace,
    offerer: Wallet | Contract,
    offer: OfferItem[],
    consideration: ConsiderationItem[],
    timeFlag?: "NOT_STARTED" | "EXPIRED" | null,
) => {
    const counter = await marketplace.getCounter(offerer.address);

    const salt = randomHex();
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

    const orderHash = await marketplace.getOrderHash(orderComponents);
    await calculateOrderHash(orderComponents);

    const { chainId } = await ethers.provider.getNetwork();
    const domainData = {
        name: MARKETPLACE_NAME,
        version: MARKETPLACE_VERSION,
        chainId,
        verifyingContract: marketplace.address,
    };

    const flatSig = await offerer._signTypedData(domainData, orderTypes, orderComponents);
    const { domainSeparator } = await marketplace.information();
    const digest = keccak256(`0x1901${domainSeparator.slice(2)}${orderHash.slice(2)}`);
    const recoveredAddress = recoverAddress(digest, flatSig);
    if (recoveredAddress !== offerer.address) {
        throw "wrong signature";
    }

    const order = {
        parameters: orderParameters,
        signature: convertSignatureToEIP2098(flatSig),
    };

    // How much ether (at most) needs to be supplied when fulfilling the order
    const value = offer
        .map(x => (x.itemType === 0 ? (x.endAmount.gt(x.startAmount) ? x.endAmount : x.startAmount) : toBN(0)))
        .reduce((a, b) => a.add(b), toBN(0))
        .add(
            consideration
                .map(x => (x.itemType === 0 ? (x.endAmount.gt(x.startAmount) ? x.endAmount : x.startAmount) : toBN(0)))
                .reduce((a, b) => a.add(b), toBN(0)),
        );

    return {
        order,
        value,
        orderComponents,
        orderHash,
        startTime,
        endTime,
    };
};
