import { ethers } from "hardhat";
import { randomHex, randomBN, toBN, getItemETH } from "../test/utils/encoding";
import { getTestItem721, createOrder } from "./helpers/create-item";
import { address, accounts } from "hardhat";
import axios from "axios";

const { parseEther } = ethers.utils;
const { seller, zone, buyer } = accounts;

async function main() {
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.attach(address.marketplace);
    console.log(`Marketplace attached from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("Erc721Collection");
    const myToken = await MyToken.attach(address.erc721);
    console.log(`Erc721Collection attached from ${myToken.address}`);

    const isApprovedForAll = await myToken.isApprovedForAll(seller.address, marketplace.address);
    if (!isApprovedForAll) {
        await myToken.connect(seller).setApprovalForAll(marketplace.address, true);
    }

    // const nftId = ("0x0e8a6496903051988901c2cedbe07ad0");
    const nftId = randomBN();
    const uri = `https://gateway.pinata.cloud/ipfs/QmYTUyhsTWGkzGMDrgTJmDnzcuYEwejzPR6o7GVZ3LcmRv/${nftId
        .mod(20)
        .toString()}.json`;
    var tx = await myToken.mint(seller.address, nftId, uri);
    await tx.wait();
    console.log({ nftId });

    const offer = [getTestItem721(nftId, myToken.address)];
    const consideration = [getItemETH(parseEther("1"), parseEther("1"), buyer.address)];

    const { order, value, orderHash, orderComponents } = await createOrder(marketplace, seller, offer, consideration);

    // order.signature =
    //     "0x434eb9d7bfac174cf70c823455691b25720ba2dfca69389ecefde17d5e0db95aaccd9372f3f9293011cbc36555a49b2eb7c39b9498e4d378ecf394f65e2cb730";

    var data = {
        order_hash: orderHash,
        offerer: order.parameters.offerer,
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
        salt: order.parameters.salt,
        start_time: toBN(order.parameters.startTime)._hex,
        end_time: toBN(order.parameters.endTime)._hex,
        signature: order.signature,
    };
    await axios.post("http://165.232.160.106:9090/api/v0.1/order", data);
    // await axios.post("http://localhost:9090/api/v0.1/order", data);

    var orderString = JSON.stringify(order, null, 4);
    console.log(orderString);

    console.log({ orderHash });
    // console.log("sleep");
    // await new Promise(res => {
    //     setTimeout(() => res(0), 10000);
    // });
    // console.log("wakeup");

    // var tx = await marketplace.connect(seller).incrementCounter();
    // await tx.wait();
    // var tx = await marketplace.connect(seller).cancel([orderComponents]);
    // await tx.wait();
    // var tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
    // await tx.wait();

    console.log({ txBlockNumber: tx.blockNumber, txHash: tx.hash, orderHash });
    console.log(await marketplace.getOrderStatus(orderHash));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
