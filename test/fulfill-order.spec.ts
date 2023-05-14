import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { marketplaceFixture } from "./utils/fixtures/marketplace";
import { calculateOrderHash, getItemETH, randomHex, toBN } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";

const { keccak256, toUtf8Bytes, parseEther } = ethers.utils;

describe(`fulfillOrder tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("A single token is to be transferred", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId = await mintAndApproveAll721(seller, marketplace.address);
        const offer = [getTestItem721(tokenId)];
        const consideration = [
            getItemETH(parseEther("10"), parseEther("10"), seller.address),
            getItemETH(parseEther("1"), parseEther("1"), zone.address),
            getItemETH(parseEther("1"), parseEther("1"), marketplaceOwner.address),
        ];
        const { order, orderHash, value } = await createOrder(seller, offer, consideration, null, undefined, true);

        await expect(marketplace.connect(buyer).fulfillOrder(order))
            .to.revertedWithCustomError(marketplace, "InsufficientNativeTokensSupplied")
            .withArgs();

        const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
        await tx.wait();
        await expect(tx)
            .to.emit(marketplace, "OrderFulfilled")
            .withArgs(orderHash, seller.address, buyer.address, anyValue, anyValue);
        expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
        await expect(tx).to.changeEtherBalances(
            [seller, zone, marketplaceOwner, buyer],
            [parseEther("10.0"), parseEther("1.0"), parseEther("1.0"), parseEther("-12.0")],
        );

        const { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(true);
        expect(isCancelled).to.equal(false);
    });

    it("A multiple token is to be transferred", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId1 = await mintAndApproveAll721(seller, marketplace.address);
        const tokenId2 = await mintAndApproveAll721(seller, marketplace.address);
        const tokenId3 = await mintAndApproveAll721(seller, marketplace.address);
        const offer = [getTestItem721(tokenId1), getTestItem721(tokenId2), getTestItem721(tokenId3)];
        const consideration = [getItemETH(parseEther("18"), parseEther("18"), seller.address)];
        const { order, orderHash, value } = await createOrder(seller, offer, consideration, null, undefined, true);

        await expect(marketplace.connect(buyer).fulfillOrder(order))
            .to.revertedWithCustomError(marketplace, "InsufficientNativeTokensSupplied")
            .withArgs();

        const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
        await tx.wait();
        await expect(tx)
            .to.emit(marketplace, "OrderFulfilled")
            .withArgs(orderHash, seller.address, buyer.address, anyValue, anyValue);
        expect(await erc721.ownerOf(tokenId1)).to.equal(buyer.address);
        expect(await erc721.ownerOf(tokenId2)).to.equal(buyer.address);
        expect(await erc721.ownerOf(tokenId3)).to.equal(buyer.address);
        await expect(tx).to.changeEtherBalances([seller, buyer], [parseEther("18.0"), parseEther("-18.0")]);

        const { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(true);
        expect(isCancelled).to.equal(false);

        await expect(marketplace.connect(buyer).fulfillOrder(order, { value }))
            .to.revertedWithCustomError(marketplace, "OrderAlreadyFilled")
            .withArgs(orderHash);
    });

    it("Reverse on expired order", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId = await mintAndApproveAll721(seller, marketplace.address);
        const offer = [getTestItem721(tokenId)];
        const consideration = [getItemETH(parseEther("10"), parseEther("10"), seller.address)];
        const { order, orderHash, value } = await createOrder(seller, offer, consideration, "EXPIRED", undefined, true);

        await expect(marketplace.connect(buyer).fulfillOrder(order, { value }))
            .to.be.revertedWithCustomError(marketplace, "InvalidTime")
            .withArgs(order.parameters.startTime, order.parameters.endTime);
    });

    it("Reverse on not stated order", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId = await mintAndApproveAll721(seller, marketplace.address);
        const offer = [getTestItem721(tokenId)];
        const consideration = [getItemETH(parseEther("10"), parseEther("10"), seller.address)];
        const { order, orderHash, value } = await createOrder(
            seller,
            offer,
            consideration,
            "NOT_STARTED",
            undefined,
            true,
        );

        await expect(marketplace.connect(buyer).fulfillOrder(order, { value }))
            .to.be.revertedWithCustomError(marketplace, "InvalidTime")
            .withArgs(order.parameters.startTime, order.parameters.endTime);
    });
});
