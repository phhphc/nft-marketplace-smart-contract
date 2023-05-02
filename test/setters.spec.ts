import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { marketplaceFixture } from "./utils/fixtures/marketplace";

import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { calculateOrderHash, getItemETH, randomHex, toBN } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";

const { keccak256, toUtf8Bytes, parseEther } = ethers.utils;

describe(`Setters tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("correctly verify order and update status", async () => {
        const { marketplace, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId1 = await mintAndApproveAll721(seller, marketplace.address);
        const offer1 = [getTestItem721(tokenId1)];
        const consideration1 = [
            getItemETH(parseEther("10"), parseEther("10"), seller.address),
            getItemETH(parseEther("1"), parseEther("1"), zone.address),
        ];
        const { order: order1, orderHash: orderHash1 } = await createOrder(
            seller,
            offer1,
            consideration1,
            null,
            undefined,
            false,
        );

        const tokenId2 = await mintAndApproveAll721(seller, marketplace.address);
        const offer2 = [getTestItem721(tokenId2)];
        const consideration2 = [
            getItemETH(parseEther("10"), parseEther("10"), seller.address),
            getItemETH(parseEther("1"), parseEther("1"), zone.address),
        ];

        const { order: order2, orderHash: orderHash2 } = await createOrder(
            seller,
            offer2,
            consideration2,
            null,
            undefined,
            true,
        );

        const tx = await marketplace.validate([order1, order2]);
        await expect(tx).to.emit(marketplace, "OrderValidated").withArgs(orderHash1, anyValue);
        await expect(tx).to.emit(marketplace, "OrderValidated").withArgs(orderHash2, anyValue);

        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash1);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(false);
        expect(isCancelled).to.equal(false);

        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash2);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(false);
        expect(isCancelled).to.equal(false);
    });
});
