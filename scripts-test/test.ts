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

async function main() {
    const [owner] = await ethers.getSigners();

    console.log(await owner.getBalance());

    // const Marketplace = await ethers.getContractFactory("Marketplace");
    // const marketplace = await Marketplace.attach(process.env.MKP_ADDR as string);
    // console.log(`Marketplace attached from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("MyToken");
    const myToken = await MyToken.attach(process.env.NFT_ADDR as string);
    console.log(`Mytoken attached from ${myToken.address}`);

    const { provider } = ethers;
    const { parseEther } = ethers.utils;

    console.log(await myToken.name());
    console.log(await myToken.tokenURI("1"));

    // console.log(await marketplace.getOrderStatus("0x4bd6aee0eff47bba01d4a793d325489aa3de45570d1e00895772760ae0ad1daf"))

    // const tx = await provider.getTransaction("0xdd9375b3e4b6b417cf70dcdee8b7d9c517e6e9727dc3376470251037b70958a7")
    // console.log(tx)
    // console.log(await marketplace.getOrderStatus("0xdd9375b3e4b6b417cf70dcdee8b7d9c517e6e9727dc3376470251037b70958a7"))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
