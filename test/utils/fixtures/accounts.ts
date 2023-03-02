import { ethers } from "hardhat";
import { randomHex } from "../encoding";

const { parseEther } = ethers.utils;

export const accountsFixture = async () => {
    const { provider } = ethers;
    const [miner] = await ethers.getSigners();

    // Setup basic buyer/seller wallets with ETH
    const seller = new ethers.Wallet(randomHex(32), provider);
    const buyer = new ethers.Wallet(randomHex(32), provider);
    const zone = new ethers.Wallet(randomHex(32), provider);

    for (const wallet of [seller, buyer, zone]) {
        await miner.sendTransaction({
            to: wallet.address,
            value: parseEther("100.0"),
        });
    }

    return { miner, seller, buyer, zone };
};
