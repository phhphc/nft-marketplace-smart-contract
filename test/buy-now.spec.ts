import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { getItemETH } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";
import { marketplaceFixture } from "./utils/fixtures/marketplace";

const { parseEther } = ethers.utils;

describe(`Buy now (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    describe("A single ERC721 is to be transferred", async () => {
        describe("User fulfills a sell order for a single ERC721", async () => {
            it("ERC721 <=> ETH (standard)", async () => {
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
                    zone,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                );

                const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
                expect(tx).to.changeEtherBalances(
                    [marketplaceOwner, seller, zone, buyer],
                    [parseEther("1.0"), parseEther("10.0"), parseEther("1.0"), parseEther("-12.0")],
                );
                expect(tx)
                    .to.emit(marketplace, "OrderFulfilled")
                    .withArgs(orderHash, seller.address, zone.address, buyer.address, offer, consideration);

                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
        });
    });
});
