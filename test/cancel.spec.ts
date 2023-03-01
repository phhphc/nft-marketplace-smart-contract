import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { getItemETH } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";
import { marketplaceFixture } from "./utils/fixtures/marketplace";

const { parseEther } = ethers.utils;

describe(`Cancel (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    describe("A single order is to be canceled", async () => {
        it("owner cancel single order", async () => {
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
                zone,
                offer,
                consideration,
                0, // FULL_OPEN
            );

            expect(await marketplace.connect(seller).cancel([orderComponents]))
                .to.emit(marketplace, "OrderCancelled")
                .withArgs(orderHash, seller.address, zone.address);

            expect(await marketplace.getOrderStatus(orderHash)).to.deep.equal([false, true]);

            await expect(marketplace.connect(buyer).fulfillOrder(order, { value }))
                .to.revertedWithCustomError(marketplace, "OrderIsCancelled")
                .withArgs(orderHash);
        });
    });
});
