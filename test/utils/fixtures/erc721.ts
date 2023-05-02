import { ethers } from "hardhat";

import type { Wallet, Contract } from "ethers";
import type { BigNumberish } from "ethers";
import { getOfferOrConsiderationItem, randomBN, toBN } from "../encoding";

export const erc721Fixture = async () => {
    const Erc721 = await ethers.getContractFactory("Erc721Collection");
    const erc721 = await Erc721.deploy("Mytoken", "MTK", "https://url.com");
    await erc721.deployed();

    const mint721 = async (owner: Wallet | Contract, id?: BigNumberish) => {
        const nftId = id ? toBN(id) : randomBN();

        const uri = "url://" + nftId;
        await erc721.mint(owner.address, nftId, uri);
        return nftId;
    };

    const mint721s = async (owner: Wallet | Contract, count: number) => {
        const arr = [];
        for (let i = 0; i < count; i++) arr.push(await mint721(owner));
        return arr;
    };

    const mintAndApproveAll721 = async (owner: Wallet, spender: string, id?: BigNumberish) => {
        await erc721.connect(owner).setApprovalForAll(spender, true);
        return mint721(owner, id);
    };

    const getTestItem721 = (
        identifier: BigNumberish,
        startAmount: BigNumberish = 1,
        endAmount: BigNumberish = 1,
        recipient?: string,
        token = erc721.address,
    ) =>
        getOfferOrConsiderationItem(
            2, // ERC721
            token,
            identifier,
            startAmount,
            endAmount,
            recipient,
        );

    return {
        erc721,
        mint721,
        mint721s,
        mintAndApproveAll721,
        getTestItem721,
    };
};
