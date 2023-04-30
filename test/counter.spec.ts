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

describe(`counter tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("correctly increase counter", async () => {
        const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);

        expect(await marketplace.getCounter(seller.address)).to.equal(0);
        expect(await marketplace.getCounter(buyer.address)).to.equal(0);

        let latestBlockHash = (await ethers.provider.getBlock("latest")).hash;
        let newCounter = toBN(latestBlockHash).shr(0x80);

        var tx = await marketplace.connect(seller).incrementCounter();
        await tx.wait();
        await expect(tx).to.emit(marketplace, "CounterIncremented").withArgs(newCounter, seller.address);
        expect(await marketplace.getCounter(seller.address)).to.equal(newCounter);

        latestBlockHash = (await ethers.provider.getBlock("latest")).hash;
        newCounter = toBN(latestBlockHash).shr(0x80).add(newCounter);

        var tx = await marketplace.connect(seller).incrementCounter();
        await tx.wait();
        await expect(tx).to.emit(marketplace, "CounterIncremented").withArgs(newCounter, seller.address);
        expect(await marketplace.getCounter(seller.address)).to.equal(newCounter);
    });

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
        var tx = await marketplace.connect(seller).incrementCounter();
        await tx.wait();

        await expect(marketplace.validate([order1, order2]))
            .to.revertedWithCustomError(marketplace, "InvalidSigner")
            .withArgs();
    });
});
