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

describe(`fulfillOrderBatch tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("A single order is to be fulfilled", async () => {
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

        await expect(marketplace.connect(buyer).fulfillOrderBatch([order]))
            .to.revertedWithCustomError(marketplace, "InsufficientNativeTokensSupplied")
            .withArgs();

        const tx = await marketplace.connect(buyer).fulfillOrderBatch([order], { value });
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

    it("Multiple order is to be fulfilled", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId1 = await mintAndApproveAll721(seller, marketplace.address);
        const offer1 = [getTestItem721(tokenId1)];
        const consideration1 = [
            getItemETH(parseEther("10"), parseEther("10"), seller.address),
            getItemETH(parseEther("5"), parseEther("5"), marketplaceOwner.address),
        ];
        const {
            order: order1,
            orderHash: orderHash1,
            value: value1,
        } = await createOrder(seller, offer1, consideration1, null, undefined, true);

        const tokenId2 = await mintAndApproveAll721(seller, marketplace.address);
        const offer2 = [getTestItem721(tokenId2)];
        const consideration2 = [
            getItemETH(parseEther("6"), parseEther("6"), seller.address),
            getItemETH(parseEther("1"), parseEther("1"), zone.address),
            getItemETH(parseEther("2"), parseEther("2"), marketplaceOwner.address),
        ];
        const {
            order: order2,
            orderHash: orderHash2,
            value: value2,
        } = await createOrder(seller, offer2, consideration2, null, undefined, true);

        await expect(marketplace.connect(buyer).fulfillOrderBatch([order1, order2]))
            .to.revertedWithCustomError(marketplace, "InsufficientNativeTokensSupplied")
            .withArgs();

        const tx = await marketplace.connect(buyer).fulfillOrderBatch([order1, order2], { value: value1.add(value2) });
        await tx.wait();
        await expect(tx)
            .to.emit(marketplace, "OrderFulfilled")
            .withArgs(orderHash1, seller.address, buyer.address, anyValue, anyValue);
        await expect(tx)
            .to.emit(marketplace, "OrderFulfilled")
            .withArgs(orderHash2, seller.address, buyer.address, anyValue, anyValue);
        expect(await erc721.ownerOf(tokenId1)).to.equal(buyer.address);
        expect(await erc721.ownerOf(tokenId2)).to.equal(buyer.address);
        await expect(tx).to.changeEtherBalances(
            [seller, zone, marketplaceOwner, buyer],
            [parseEther("16.0"), parseEther("1.0"), parseEther("7.0"), parseEther("-24.0")],
        );

        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash1);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(true);
        expect(isCancelled).to.equal(false);
        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash2);
        expect(isValidated).to.equal(true);
        expect(isFulFilled).to.equal(true);
        expect(isCancelled).to.equal(false);
    });

    it("Ignore expired order", async () => {
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
        const { order, orderHash, value } = await createOrder(seller, offer, consideration, "EXPIRED", undefined, true);

        const tx = await marketplace.connect(buyer).fulfillOrderBatch([order], { value });
        expect(tx).to.not.emit(marketplace, "OrderFulfilled");
    });

    it("Ignore not stated order", async () => {
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
        const { order, orderHash, value } = await createOrder(
            seller,
            offer,
            consideration,
            "NOT_STARTED",
            undefined,
            true,
        );

        console.log("hi");
        const tx = await marketplace.connect(buyer).fulfillOrderBatch([order], { value });
        expect(tx).to.not.emit(marketplace, "OrderFulfilled");
    });
});
