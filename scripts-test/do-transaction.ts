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
import axios from "axios";

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

    const seller = new ethers.Wallet(process.env.SELLER_PRIVATE_KEY as string, provider);
    const buyer = new ethers.Wallet(process.env.BUYER_PRIVATE_KEY as string, provider);
    const zone = new ethers.Wallet(process.env.ZONE_PRIVATE_KEY as string, provider);

    // console.log(await myToken.ownerOf("22596384042339072632483211526420607445"));
    // console.log(await marketplace.getOrderStatus("0x10be3b95af8238e12b7feae365746aef6992b226eeecb145bf7170146344a4a5"))
    // return

    await myToken.connect(seller).setApprovalForAll(marketplace.address, true);

    const nftId = randomBN();
    const uri = "url://" + nftId;
    // await myToken.mint(seller.address, nftId, uri);
    await myToken.mint("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", nftId, uri);

    console.log(nftId);

    return;

    const offer = [getTestItem721(nftId, myToken.address)];
    const consideration = [getItemETH(parseEther("1"), parseEther("1"), owner.address)];

    const { order, value, orderHash, orderComponents } = await createOrder(
        marketplace,
        seller,
        zone.address,
        offer,
        consideration,
        0, // FULL_OPEN
    );

    var data = {
        order_hash: orderHash,
        offerer: order.parameters.offerer,
        zone: order.parameters.zone,
        offer: order.parameters.offer.map(o => ({
            item_type: o.itemType,
            token: o.token,
            identifier: o.identifier._hex,
            start_amount: o.startAmount._hex,
            end_amount: o.endAmount._hex,
        })),
        consideration: order.parameters.consideration.map(c => ({
            item_type: c.itemType,
            token: c.token,
            identifier: c.identifier._hex,
            start_amount: c.startAmount._hex,
            end_amount: c.endAmount._hex,
            recipient: c.recipient,
        })),
        order_type: order.parameters.orderType,
        zone_hash: order.parameters.zoneHash,
        salt: order.parameters.salt,
        start_time: toBN(order.parameters.startTime)._hex,
        end_time: toBN(order.parameters.endTime)._hex,
        signature: order.signature,
    };
    await axios.post("http://165.232.160.106:9090/api/v0.1/order", data);
    // await axios.post("http://localhost:9099/api/v0.1/order", data)

    var dd = JSON.stringify(order, null, 4);
    console.log(dd);

    // console.log(await myToken.name());

    const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
    await tx.wait();

    // console.log(tx)
    // console.log(tx.blockNumber, tx.hash, orderHash);
    console.log("order_hash", orderHash);

    console.log(await marketplace.getOrderStatus(orderHash));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
