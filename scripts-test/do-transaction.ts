import { ethers } from "hardhat";
import { randomHex, randomBN, toBN, getItemETH, convertSignatureToEIP2098 } from "../test/utils/encoding";
import { ConsiderationItem, OfferItem } from "../test/utils/types";
import type { BigNumberish } from "ethers";
import { constants } from "ethers";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "../test/constants/marketplace";
import { orderType as orderTypes } from "../test/eip721-types/order";
import type { Contract, Wallet } from "ethers";
import { Marketplace } from "../typechain-types";
import { keccak256, recoverAddress } from "ethers/lib/utils";

const getTestItem721 = (
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

const createOrder = async (
    marketplace: Marketplace,
    offerer: Wallet | Contract,
    zone: string,
    offer: OfferItem[],
    consideration: ConsiderationItem[],
    orderType: number,
    timeFlag?: "NOT_STARTED" | "EXPIRED" | null,
    zoneHash = constants.HashZero,
) => {
    const counter = await marketplace.getCounter(offerer.address);

    const salt = randomHex();
    const startTime = timeFlag !== "NOT_STARTED" ? 0 : toBN("0xee00000000000000000000000000");
    const endTime = timeFlag !== "EXPIRED" ? toBN("0xff00000000000000000000000000") : 1;

    const orderParameters = {
        offerer: offerer.address,
        zone: zone,
        offer,
        consideration,
        totalOriginalConsiderationItems: consideration.length,
        orderType,
        zoneHash,
        salt,
        startTime,
        endTime,
    };

    var x = {
        parameters: {
            offerer: "0xA85c072a57bEfE1A907356673137B77ec9b5C985",
            zone: "0xA85c072a57bEfE1A907356673137B77ec9b5C985",
            offer: [
                {
                    itemType: 2,
                    token: "0xC9C7E04C41a01C9072C2d074e1258a1f56d0603a",
                    identifier: "0x13",
                    startAmount: "0x01",
                    endAmount: "0x01",
                },
            ],
            consideration: [
                {
                    itemType: 0,
                    token: "0x0000000000000000000000000000000000000000",
                    identifier: "0x00",
                    startAmount: "0x0de0b6b3a7640000",
                    endAmount: "0x0de0b6b3a7640000",
                    recipient: "0xA85c072a57bEfE1A907356673137B77ec9b5C985",
                },
            ],
            orderType: "0x00",
            startTime: "0x00",
            endTime: "0xff00000000000000000000000000",
            zoneHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
            salt: "0xc726f21637e102c3b38f6611f185567da877b11abce19ea28000000000000000",
            totalOriginalConsiderationItems: 1,
        },
        signature:
            "0xa82ae4d6346739b0b7e15489757aaa9be5276eeb0bb23f7c08a465f9e22d10f13da08ecce19d7612cd509778645f101ac16c760e5e73a96dd6018b1643c04c4c1b",
    };

    var counter2 = await marketplace.getCounter(x.parameters.offerer);
    const orderComponents2 = {
        ...x.parameters,
        counter: counter2,
    };
    var orderHash2 = await marketplace.getOrderHash(orderComponents2);

    var { domainSeparator: dsp } = await marketplace.information();
    var digest2 = keccak256(`0x1901${dsp.slice(2)}${orderHash2.slice(2)}`);
    const recoveredAddress2 = recoverAddress(digest2, x.signature);
    console.log(recoveredAddress2, x.parameters.offerer);
    if (recoveredAddress2 !== x.parameters.offerer) {
        throw "wrong signature 2";
    }

    const orderComponents = {
        ...orderParameters,
        counter,
    };

    const orderHash = await marketplace.getOrderHash(orderComponents);

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

async function main() {
    const [owner] = await ethers.getSigners();

    console.log(await owner.getBalance());

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.attach(process.env.MKP_ADDR as string);
    console.log(`Marketplace attached from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("MyToken");
    const myToken = await MyToken.attach(process.env.NFT_ADDR as string);
    console.log(`Mytoken attached from ${myToken.address}`);

    const { provider } = ethers;
    const { parseEther } = ethers.utils;

    const seller = new ethers.Wallet(randomHex(32), provider);
    const buyer = owner;
    const zone = new ethers.Wallet(randomHex(32), provider);

    for (const wallet of [seller]) {
        await owner.sendTransaction({
            to: wallet.address,
            value: parseEther("0.1"),
        });
    }

    await myToken.connect(seller).setApprovalForAll(marketplace.address, true);

    const nftId = randomBN();
    const uri = "url://" + nftId;
    await myToken.mint(seller.address, nftId, uri);

    const offer = [getTestItem721(nftId, myToken.address)];
    const consideration = [getItemETH(parseEther("1"), parseEther("1"), owner.address)];

    const { order, value } = await createOrder(
        marketplace,
        seller,
        zone.address,
        offer,
        consideration,
        0, // FULL_OPEN
    );

    console.log(JSON.stringify(order, null, 2));

    // const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
    // await tx.wait();

    // console.log(tx.blockNumber, tx.hash)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
