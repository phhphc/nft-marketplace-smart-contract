import { ethers } from "hardhat";

import type { Wallet } from "ethers";
import type { BigNumberish } from "ethers";
import { getOfferOrConsiderationItem, randomBN, toBN } from "../encoding";
import { expect } from "chai";

export const erc20Fixture = async () => {
    const Erc20 = await ethers.getContractFactory("ERC20Token");
    const erc20 = await Erc20.deploy();
    await erc20.deployed();

    const mintAndApproveERC20 = async (signer: Wallet, spender: string, tokenAmount: BigNumberish) => {
        const amount = toBN(tokenAmount);
        // Offerer mints ERC20
        await erc20.mint(signer.address, amount);

        // Offerer approves marketplace contract to tokens
        await expect(erc20.connect(signer).approve(spender, amount))
            .to.emit(erc20, "Approval")
            .withArgs(signer.address, spender, tokenAmount);
    };

    const getTestItem20 = (
        startAmount: BigNumberish = 50,
        endAmount: BigNumberish = 50,
        recipient?: string,
        token = erc20.address,
    ) => getOfferOrConsiderationItem(1, token, 0, startAmount, endAmount, recipient);

    return {
        erc20,
        mintAndApproveERC20,
        getTestItem20,
    };
};
