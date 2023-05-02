import { ethers } from "hardhat";
import { randomHex, randomBN, toBN, getItemETH } from "../test/utils/encoding";
import { getTestItem721, createOrder } from "./helpers/create-item";
import { address, accounts } from "hardhat";
import axios from "axios";

const { parseEther, keccak256, recoverAddress } = ethers.utils;
const { seller, zone, buyer } = accounts;

async function main() {
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.attach(address.marketplace);
    console.log(`Marketplace attached from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("Erc721Collection");
    const myToken = await MyToken.attach(address.erc721);
    console.log(`Erc721Collection attached from ${myToken.address}`);

    const x = {
        data: {
            pageSize: 99999,
            pageNum: 0,
            content: [
                {
                    consideration: [
                        {
                            endAmount: "1000000000000",
                            identifier: "0",
                            itemType: 0,
                            recipient: "0xbBF3aB1Ce5b412aA10FfD604e3290B0B49cFBb1E",
                            startAmount: "1000000000000",
                            token: "0x0000000000000000000000000000000000000000",
                        },
                    ],
                    endTime: "5172014448931175958106549077934080",
                    offer: [
                        {
                            endAmount: "1",
                            identifier: "260061503377924468503595715501951997186",
                            itemType: 2,
                            startAmount: "1",
                            token: "0x52DFcF0556b905bC1D620593b7EF1d11bC5C737c",
                        },
                    ],
                    offerer: "0xbBF3aB1Ce5b412aA10FfD604e3290B0B49cFBb1E",
                    orderHash: "0x4a488665a995b22ea9f69ec1e802dc5c65553bc4f5fb39605ddab8256857c929",
                    salt: "0x7c7bc7c038ebfb054c85f1c634514d6e76ca217f3bddbe9b094892d67e439398",
                    signature:
                        "0xb724cc897a94fe8c599bc6678e544c49d1a6a73f75fc54fd7d017c087863d63a4a1581a278bf10a410e67ad17a9520a78dbcd882e395c834def5c4309f5bd4f81c",
                    startTime: "0",
                    status: {
                        isCancelled: false,
                        isFulfilled: false,
                        isInvalid: false,
                    },
                },
            ],
        },
        is_success: true,
    };
    type RespData = typeof x;
    // type OrderData = (typeof x)["data"]["content"][0];

    // const orderHash = "0x22e8c872253c6ff0816b2e1b1d2f233d1f4bcfdfb46a8deb7fdc10117bf4d03a";
    const orderHash = "0x57503666e7ffd1b814a92bb74b29ecc302cfe8ac6b80722d8e4e0204e1418af3";
    // const orderHash = "0x145225f2331f65127d8cd30309046422e0b891961ab973a2df5b004ee80b5643"
    const BeAddr = "http://165.232.160.106:9090";
    const apiData = await axios.get(`${BeAddr}/api/v0.1/order`, {
        params: { orderHash },
    });
    const respData = apiData.data as RespData;
    const orderData = respData.data.content[0];

    const offererAddress = orderData.offerer;
    const signature = orderData.signature;
    // const signature = "0x434eb9d7bfac174cf70c823455691b25720ba2dfca69389ecefde17d5e0db95aaccd9372f3f9293011cbc36555a49b2eb7c39b9498e4d378ecf394f65e2cb730";

    const counter = await marketplace.getCounter(offererAddress);
    const orderParameters = {
        offerer: offererAddress,
        zone: zone,
        offer: orderData.offer.map(v => ({
            itemType: v.itemType,
            token: v.token,
            identifier: v.identifier,
            startAmount: v.startAmount,
            endAmount: v.endAmount,
        })),
        consideration: orderData.consideration.map(v => ({
            itemType: v.itemType,
            token: v.token,
            identifier: v.identifier,
            startAmount: v.startAmount,
            endAmount: v.endAmount,
            recipient: v.recipient,
        })),
        totalOriginalConsiderationItems: orderData.consideration.length,
        salt: orderData.salt,
        startTime: orderData.startTime,
        endTime: orderData.endTime,
    };
    const orderComponents = {
        ...orderParameters,
        counter,
    };
    console.log(JSON.stringify(orderComponents, null, 4));

    const orderHash2 = await marketplace.getOrderHash(orderComponents);
    console.log(orderHash2, orderHash);
    if (orderHash2.toLowerCase().localeCompare(orderHash.toLowerCase())) {
        throw "wrong order hash";
    }

    const { domainSeparator } = await marketplace.information();
    const digest = keccak256(`0x1901${domainSeparator.slice(2)}${orderHash.slice(2)}`);
    const recoveredAddress = recoverAddress(digest, signature);
    console.log(recoveredAddress, offererAddress);
    if (recoveredAddress !== offererAddress) {
        throw "wrong signature";
    }

    console.log("order_hash", orderHash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
