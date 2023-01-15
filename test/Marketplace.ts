import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Marketplace", function () {
    async function deployMarketplaceFixture() {
        const [owner, otherAccount] = await ethers.getSigners();

        const Marketplace = await ethers.getContractFactory("Marketplace");
        const marketplace = await Marketplace.deploy();

        return { marketplace, owner, otherAccount };
    }

    async function deployErc721WithTokensFixture() {
        const { owner } = await loadFixture(deployMarketplaceFixture);

        const MyToken = await ethers.getContractFactory("MyToken");
        const myToken = await MyToken.deploy();
        await myToken.deployed();

        const tokenIds = Array.from(Array(5).keys());
        const tokenUris = tokenIds.map(v => "https://123.com/" + v);
        Promise.all(tokenUris.map(uri => myToken.safeMint(owner.address, uri)));

        return { myToken, tokenIds, tokenUris };
    }

    describe("Trader", function () {
        async function deployMarketplaceWithListingFixture() {
            const listingId = 0;

            const { marketplace, owner, otherAccount } = await loadFixture(deployMarketplaceFixture);
            const { myToken, tokenIds } = await loadFixture(deployErc721WithTokensFixture);

            const listingPrice = ethers.utils.parseUnits("1", "gwei");
            const listingData = ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, listingPrice]);

            await myToken["safeTransferFrom(address,address,uint256,bytes)"](
                owner.address,
                marketplace.address,
                tokenIds[0],
                listingData,
            );

            return {
                marketplace,
                listingId,
                myToken,
                tokenId: tokenIds[0],
                listingPrice,
                owner,
                otherAccount,
            };
        }

        describe("Listing", function () {
            const listingPrice = ethers.utils.parseEther("1");
            const listingData = ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, listingPrice]);
            const listingId = 0;

            it("should emit listing event", async function () {
                const { marketplace, owner } = await loadFixture(deployMarketplaceFixture);
                const { myToken, tokenIds } = await loadFixture(deployErc721WithTokensFixture);

                await expect(
                    myToken["safeTransferFrom(address,address,uint256,bytes)"](
                        owner.address,
                        marketplace.address,
                        tokenIds[0],
                        listingData,
                    ),
                )
                    .to.emit(marketplace, "NewListing")
                    .withArgs(listingId, myToken.address, tokenIds[0], owner.address, listingPrice);
            });

            it("should add correct token to listing", async function () {
                const { marketplace, owner } = await loadFixture(deployMarketplaceFixture);
                const { myToken, tokenIds } = await loadFixture(deployErc721WithTokensFixture);

                await myToken["safeTransferFrom(address,address,uint256,bytes)"](
                    owner.address,
                    marketplace.address,
                    tokenIds[0],
                    listingData,
                );
                const listingItem = await marketplace.getListing(listingId);
                expect(listingItem["collection"]).to.be.equal(myToken.address);
                expect(listingItem["tokenId"]).to.be.equal(tokenIds[0]);
                expect(listingItem["seller"]).to.be.equal(owner.address);
                expect(listingItem["price"]).to.be.equal(listingPrice);
            });
        });

        describe("Cancel Listing", function () {
            it("should emit listing canceled event", async function () {
                const { marketplace, myToken, tokenId, listingId, owner, listingPrice } = await loadFixture(
                    deployMarketplaceWithListingFixture,
                );

                await expect(marketplace.cancelListing(listingId))
                    .to.emit(marketplace, "ListingCanceled")
                    .withArgs(listingId, myToken.address, tokenId, owner.address, listingPrice);
            });

            it("should revert on non-owner sender", async function () {
                const { marketplace, myToken, tokenId, otherAccount, listingId } = await loadFixture(
                    deployMarketplaceWithListingFixture,
                );

                await expect(marketplace.connect(otherAccount).cancelListing(listingId)).to.be.revertedWith(
                    "You aren't the seller",
                );
            });

            it("should return token to owner", async function () {
                const { marketplace, myToken, tokenId, otherAccount, owner, listingId } = await loadFixture(
                    deployMarketplaceWithListingFixture,
                );

                await marketplace.cancelListing(listingId);
                expect(await myToken.ownerOf(tokenId)).to.equal(owner.address);
            });

            it("should remove token from listing", async function () {
                const { marketplace, myToken, tokenId, otherAccount, owner, listingId } = await loadFixture(
                    deployMarketplaceWithListingFixture,
                );

                await marketplace.cancelListing(listingId);
                await expect(marketplace.getListing(listingId)).to.be.revertedWith("Listing doesn't exists");
            });

            it("should revert if listing is invalid", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await expect(marketplace.cancelListing(listingId + 1)).to.be.revertedWith("Listing doesn't exists");
            });
        });

        describe("Buy", function () {
            it("should emit sale event", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await expect(marketplace.connect(otherAccount).buy(listingId, { value: listingPrice }))
                    .to.emit(marketplace, "ListingSale")
                    .withArgs(listingId, myToken.address, tokenId, owner.address, otherAccount.address, listingPrice);
            });

            it("should transfer token to buyer", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await marketplace.connect(otherAccount).buy(listingId, { value: listingPrice });
                expect(await myToken.ownerOf(tokenId)).to.equal(otherAccount.address);
            });

            it("should transfer ether to token owner", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await expect(
                    marketplace.connect(otherAccount).buy(listingId, { value: listingPrice }),
                ).to.changeEtherBalances([otherAccount, owner], [-listingPrice, listingPrice]);
            });

            it("should revert on incorrect token value", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await expect(
                    marketplace.connect(otherAccount).buy(listingId, { value: listingPrice.add(1) }),
                ).to.be.revertedWith("You didn't provide the correct price");

                await expect(
                    marketplace.connect(otherAccount).buy(listingId, { value: listingPrice.sub(1) }),
                ).to.be.revertedWith("You didn't provide the correct price");
            });

            it("should revert if token is not listing", async function () {
                const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await expect(
                    marketplace.connect(otherAccount).buy(listingId + 1, { value: listingPrice }),
                ).to.be.revertedWith("Listing doesn't exists");
            });

            it("should remove token from listing", async function () {
                const { marketplace, myToken, tokenId, otherAccount, owner, listingId, listingPrice } =
                    await loadFixture(deployMarketplaceWithListingFixture);

                await marketplace.connect(otherAccount).buy(listingId, { value: listingPrice });
                await expect(marketplace.getListing(listingId)).to.be.revertedWith("Listing doesn't exists");
            });
        });
    });
});
