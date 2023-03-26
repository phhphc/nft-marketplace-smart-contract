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
import { string } from "hardhat/internal/core/params/argumentTypes";

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
    console.log({ domainData });
    console.log(JSON.stringify(orderTypes, null, 4));
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

    const x = {
        data: {
            consideration: [
                {
                    end_amount: "1000000000000000000",
                    identifier: "0",
                    item_type: 0,
                    recipient: "0x71bE63f3384f5fb98995898A86B02Fb2426c5788",
                    start_amount: "1000000000000000000",
                    token: "0x0000000000000000000000000000000000000000",
                },
            ],
            end_time: "5172014448931175958106549077934080",
            offer: [
                {
                    end_amount: "1",
                    identifier: "12582568993202215531773345202466753417",
                    item_type: 2,
                    start_amount: "1",
                    token: "0x162459Bb429a63D2e31Fe2d1cdb5b058f2D31AdF",
                },
            ],
            offerer: "0x71bE63f3384f5fb98995898A86B02Fb2426c5788",
            order_hash: "0x4bd6aee0eff47bba01d4a793d325489aa3de45570d1e00895772760ae0ad1daf",
            order_type: 0,
            salt: "0x963171d12c2cb800000000000000000000000000000000000000000000000000",
            signature:
                "0x0a159972e2f49c955696a80c94b4ba5279b61ee109be405f7a471bc56cf6136699204ab03e3c20aa38b6fc341cb9277df74a8acb6711db911d8a2689bb3e21aa",
            start_time: "0",
            zone: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            zone_hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
        },
        is_success: true,
    };
    type OrderData = typeof x;

    const orderHash = "0x4dbe2af29bc588fa4ccc5ae293aefe5eec86c2c3f2d919a4f8a443a56a085308";
    // const orderHash = "0x145225f2331f65127d8cd30309046422e0b891961ab973a2df5b004ee80b5643"
    const BeAddr = "http://165.232.160.106:9090";
    const apiData = await axios.get(`${BeAddr}/api/v0.1/order?order_hash=${orderHash}`);
    const orderData = apiData.data as OrderData;

    const offererAddress = orderData.data.offerer;
    const flatSig = orderData.data.signature;
    const zone = orderData.data.zone;

    const counter = await marketplace.getCounter(offererAddress);
    const orderParameters = {
        offerer: offererAddress,
        zone: zone,
        offer: orderData.data.offer.map(v => ({
            itemType: v.item_type,
            token: v.token,
            identifier: v.identifier,
            startAmount: v.start_amount,
            endAmount: v.end_amount,
        })),
        consideration: orderData.data.consideration.map(v => ({
            itemType: v.item_type,
            token: v.token,
            identifier: v.identifier,
            startAmount: v.start_amount,
            endAmount: v.end_amount,
            recipient: v.recipient,
        })),
        totalOriginalConsiderationItems: orderData.data.consideration.length,
        orderType: orderData.data.order_type,
        zoneHash: orderData.data.zone_hash,
        salt: orderData.data.salt,
        startTime: orderData.data.start_time,
        endTime: orderData.data.end_time,
    };
    const orderComponents = {
        ...orderParameters,
        counter,
    };
    console.log(JSON.stringify(orderComponents, null, 4));

    const orderHash2 = await marketplace.getOrderHash(orderComponents);
    console.log(orderHash2, orderHash);
    if (orderHash2 === orderHash2) {
        throw "wrong order hash";
    }

    const { domainSeparator } = await marketplace.information();
    const digest = keccak256(`0x1901${domainSeparator.slice(2)}${orderHash.slice(2)}`);
    const recoveredAddress = recoverAddress(digest, flatSig);
    console.log(recoveredAddress, offererAddress);
    if (recoveredAddress !== offererAddress) {
        throw "wrong signature";
    }

    // const seller = new ethers.Wallet(process.env.SELLER_PRIVATE_KEY as string, provider);
    const buyer = new ethers.Wallet(process.env.BUYER_PRIVATE_KEY as string, provider);
    // const zone = new ethers.Wallet(process.env.ZONE_PRIVATE_KEY as string, provider);

    // console.log(await myToken.ownerOf("22596384042339072632483211526420607445"));
    // console.log(await marketplace.getOrderStatus("0x10be3b95af8238e12b7feae365746aef6992b226eeecb145bf7170146344a4a5"))
    // return

    // await myToken.connect(seller).setApprovalForAll(marketplace.address, true);

    // const nftId = randomBN();
    // const uri = "url://" + nftId;
    // await myToken.mint(seller.address, nftId, uri);

    // const offer = [getTestItem721(nftId, myToken.address)];
    // const consideration = [getItemETH(parseEther("1"), parseEther("1"), owner.address)];

    // const { order, value, orderHash, orderComponents } = await createOrder(
    //     marketplace,
    //     seller,
    //     zone.address,
    //     offer,
    //     consideration,
    //     0, // FULL_OPEN
    // );

    // var data =
    // {
    //     "order_hash": orderHash,
    //     "offerer": order.parameters.offerer,
    //     "zone": order.parameters.zone,
    //     "offer": order.parameters.offer.map(o => ({
    //         "item_type": o.itemType,
    //         "token": o.token,
    //         "identifier": o.identifier._hex,
    //         "start_amount": o.startAmount._hex,
    //         "end_amount": o.endAmount._hex
    //     })),
    //     "consideration": order.parameters.consideration.map(c => ({
    //         "item_type": c.itemType,
    //         "token": c.token,
    //         "identifier": c.identifier._hex,
    //         "start_amount": c.startAmount._hex,
    //         "end_amount": c.endAmount._hex,
    //         "recipient": c.recipient
    //     })),
    //     "order_type": order.parameters.orderType,
    //     "zone_hash": order.parameters.zoneHash,
    //     "salt": order.parameters.salt,
    //     "start_time": toBN(order.parameters.startTime)._hex,
    //     "end_time": toBN(order.parameters.endTime)._hex,
    //     "signature": order.signature
    // };
    // await axios.post("http://165.232.160.106:9090/api/v0.1/order", data)
    // // await axios.post("http://localhost:9099/api/v0.1/order", data)

    // var dd = JSON.stringify(order, null, 4);
    // console.log(dd);

    // console.log(await myToken.name());

    // const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
    // await tx.wait();

    // console.log(tx)
    // console.log(tx.blockNumber, tx.hash);
    console.log("order_hash", orderHash);

    // console.log(await marketplace.getOrderStatus(orderHash))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
