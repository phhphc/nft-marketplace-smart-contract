import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { marketplaceFixture } from "./utils/fixtures/marketplace";
import { calculateOrderHash, getItemETH, randomHex, toBN } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";

const { keccak256, toUtf8Bytes, parseEther } = ethers.utils;

describe(`cancel orders tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("A single order to be cancel", async () => {
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
        const { order, orderHash, value, orderComponents } = await createOrder(
            seller,
            offer,
            consideration,
            null,
            undefined,
            true,
        );

        await expect(marketplace.connect(buyer).cancel([orderComponents]))
            .to.revertedWithCustomError(marketplace, "CannotCancelOrder")
            .withArgs();

        const tx = await marketplace.connect(seller).cancel([orderComponents]);
        await tx.wait();
        await expect(tx).to.emit(marketplace, "OrderCancelled").withArgs(orderHash, seller.address);

        const { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash);
        expect(isValidated).to.equal(false);
        expect(isFulFilled).to.equal(false);
        expect(isCancelled).to.equal(true);

        await expect(marketplace.connect(buyer).fulfillOrder(order, { value }))
            .to.revertedWithCustomError(marketplace, "OrderIsCancelled")
            .withArgs(orderHash);
    });
    it("Multiple order to be cancel", async () => {
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
        const {
            order: order1,
            orderHash: orderHash1,
            orderComponents: orderComponents1,
        } = await createOrder(seller, offer, consideration, null, undefined, true);

        const {
            order: order2,
            orderHash: orderHash2,
            orderComponents: orderComponents2,
        } = await createOrder(seller, offer, consideration, null, undefined, false);

        await expect(marketplace.connect(buyer).cancel([orderComponents1, orderComponents2]))
            .to.revertedWithCustomError(marketplace, "CannotCancelOrder")
            .withArgs();

        const tx = await marketplace.connect(seller).cancel([orderComponents1, orderComponents2]);
        await tx.wait();
        await expect(tx).to.emit(marketplace, "OrderCancelled").withArgs(orderHash1, seller.address);
        await expect(tx).to.emit(marketplace, "OrderCancelled").withArgs(orderHash2, seller.address);

        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash1);
        expect(isValidated).to.equal(false);
        expect(isFulFilled).to.equal(false);
        expect(isCancelled).to.equal(true);

        var { isCancelled, isFulFilled, isValidated } = await marketplace.getOrderStatus(orderHash2);
        expect(isValidated).to.equal(false);
        expect(isFulFilled).to.equal(false);
        expect(isCancelled).to.equal(true);
    });
});
