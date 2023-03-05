import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { getItemETH, toBN } from "./utils/encoding";
import { minRandom } from "./utils/helper";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";
import { erc20Fixture } from "./utils/fixtures/erc20";
import { marketplaceFixture } from "./utils/fixtures/marketplace";

const { parseEther } = ethers.utils;

describe(`Accept offer (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    describe("A single ERC721 is to be transferred", async () => {
        describe("User accepts a buy offer on a single ERC721", async () => {
            // Note: ETH is not a possible case
            it("ERC721 <=> ERC20 (standard)", async () => {
                const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
                const { seller, buyer, zone } = await loadFixture(accountsFixture);
                const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);
                const { erc20, mintAndApproveERC20, getTestItem20 } = await loadFixture(erc20Fixture);

                // Buyer mints nft and approves marketplace contract to transfer NFT
                const tokenId = await mintAndApproveAll721(buyer, marketplace.address);

                // Seller mints ERC20
                const tokenAmount = minRandom(100);
                await mintAndApproveERC20(seller, marketplace.address, tokenAmount);

                // Buyer approves marketplace contract to transfer ERC20 tokens too
                await expect(erc20.connect(buyer).approve(marketplace.address, tokenAmount))
                    .to.emit(erc20, "Approval")
                    .withArgs(buyer.address, marketplace.address, tokenAmount);

                const offer = [getTestItem20(tokenAmount.sub(100), tokenAmount.sub(100))];

                const consideration = [
                    getTestItem721(tokenId, 1, 1, seller.address),
                    getTestItem20(50, 50, zone.address),
                    getTestItem20(50, 50, marketplaceOwner.address),
                ];

                const { order, orderHash, value } = await createOrder(
                    seller,
                    zone,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                );

                const tx = marketplace.connect(buyer).fulfillOrder(order, { value });

                // expect(await erc721.ownerOf(tokenId)).to.equal(seller.address);
                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
        });
    });
});
