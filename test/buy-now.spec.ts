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
                    [parseEther("1.0"), parseEther("1.0"), parseEther("1.0"), parseEther("-12.0")],
                );

                expect(tx)
                    .to.emit(marketplace, "OrderFulfilled")
                    .withArgs(orderHash, seller.address, zone.address, buyer.address, offer, consideration);

                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
            it("ERC721 <=> ETH (standard with tip)", async () => {
                const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
                const { seller, buyer, zone } = await loadFixture(accountsFixture);
                const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

                const tokenId = await mintAndApproveAll721(seller, marketplace.address);

                const offer = [getTestItem721(tokenId)];

                const consideration = [
                    getItemETH(parseEther("10"), parseEther("10"), seller.address),
                    getItemETH(parseEther("1"), parseEther("1"), zone.address),
                ];

                const { order, orderHash, value } = await createOrder(
                    seller,
                    zone,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                );

                // Add a tip
                order.parameters.consideration.push(
                    getItemETH(parseEther("1"), parseEther("1"), marketplaceOwner.address),
                );

                const tx = await marketplace.connect(buyer).fulfillOrder(order, { value: value.add(parseEther("1")) });

                const fulfillment = await tx.wait();
                const event = fulfillment.events && fulfillment.events[1];
                expect(event?.event).to.equal("OrderFulfilled");

                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
            it("ERC721 <=> ETH (standard with restricted order)", async () => {
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
                    2, // FULL_RESTRICTED
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
            it("ERC721 <=> ETH (standard, minimal and listed off-chain)", async () => {
                const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
                const { seller, buyer, zone } = await loadFixture(accountsFixture);
                const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

                // Seller mints nft
                const tokenId = await mintAndApproveAll721(seller, marketplace.address);

                const offer = [getTestItem721(tokenId)];

                const consideration = [getItemETH(toBN(1), toBN(1), seller.address)];

                const { order, orderHash, value } = await createOrder(
                    seller,
                    ethers.constants.AddressZero,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                    null,
                    seller,
                    ethers.constants.HashZero,
                    ethers.constants.HashZero,
                    true, // extraCheap
                );

                const tx = await marketplace.connect(buyer).fulfillOrder(order, { value });
                const fulfillment = await tx.wait();
                const event = fulfillment.events && fulfillment.events[1];
                expect(event?.event).to.equal("OrderFulfilled");

                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
            it("ERC721 <=> ETH (standard, minimal and verified on-chain)", async () => {
                const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
                const { seller, buyer, zone } = await loadFixture(accountsFixture);
                const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

                // Seller mints nft
                const tokenId = await mintAndApproveAll721(seller, marketplace.address);

                const offer = [getTestItem721(tokenId)];

                const consideration = [getItemETH(toBN(1), toBN(1), seller.address)];

                const { order, orderHash, value } = await createOrder(
                    seller,
                    zone,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                    null,
                    seller,
                    ethers.constants.HashZero,
                    ethers.constants.HashZero,
                    true, // extraCheap
                );

                // Validate the order from any account. E.g seller
                const validTx = await marketplace.connect(seller).validate([order]);

                const receipt = await validTx.wait();
                const validEvent = receipt.events && receipt.events[0];
                expect(validEvent?.event).to.equal("OrderValidated");

                // Fulfillment
                const fulfillTx = await marketplace.connect(buyer).fulfillOrder(order, { value });

                const fulfillment = await fulfillTx.wait();
                const fulfillEvent = fulfillment.events && fulfillment.events[1];
                expect(fulfillEvent?.event).to.equal("OrderFulfilled");

                expect(await erc721.ownerOf(tokenId)).to.equal(buyer.address);
            });
            it("ERC721 <=> ERC20 (standard)", async () => {
                const { marketplace, marketplaceOwner, createOrder } = await loadFixture(marketplaceFixture);
                const { seller, buyer, zone } = await loadFixture(accountsFixture);
                const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);
                const { erc20, mintAndApproveERC20, getTestItem20 } = await loadFixture(erc20Fixture);
                const tokenId = await mintAndApproveAll721(seller, marketplace.address);

                // Buyer mints ERC20
                const tokenAmount = minRandom(100);
                await mintAndApproveERC20(buyer, marketplace.address, tokenAmount);

                const offer = [getTestItem721(tokenId)];

                const consideration = [
                    getTestItem20(tokenAmount.sub(100), tokenAmount.sub(100), seller.address),
                    getTestItem20(50, 50, zone.address),
                    getTestItem20(50, 50, marketplaceOwner.address),
                ];

                const { order, orderHash } = await createOrder(
                    seller,
                    zone,
                    offer,
                    consideration,
                    0, // FULL_OPEN
                );

                const tx = marketplace.connect(buyer).fulfillOrder(order);

                expect(await erc721.ownerOf(tokenId)).to.equal(seller.address);
            });
        });
    });
});
