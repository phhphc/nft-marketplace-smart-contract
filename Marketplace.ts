import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { OrderStruct } from "./typechain-types/contracts/Marketplace";
import { signOrder } from "./test/utils/helper";
import { Wallet } from "ethers";
import { randomBytes } from "crypto";
import { calculateOrderHash, getItemETH } from "./test/utils/encoding";
import { BigNumber } from "ethers";
import { Domain, OrderComponents } from "./test/utils/types";

const { parseEther, keccak256, toUtf8Bytes, recoverAddress } = ethers.utils;

describe("Marketplace", function () {
    async function deployMarketplaceFixture() {
        const { provider } = ethers;
        // const seller = new ethers.Wallet(randomBytes(32).toString('hex'), provider);
        // const zone = new ethers.Wallet(randomBytes(32).toString('hex'), provider);
        const seller = new ethers.Wallet(
            "0x0123456789012345678901234567890123456789012345678901234567891232",
            provider,
        );
        const zone = new ethers.Wallet("0x0123456789012345678901234567890123456789012345678901234567891233", provider);
        const buyer = new ethers.Wallet("0x0123456789012345678901234567890123456789012345678901234567891234", provider);

        const [owner, otherAccount] = await ethers.getSigners();

        await owner.sendTransaction({
            to: buyer.address,
            value: ethers.utils.parseEther("20.0"),
        });
        await owner.sendTransaction({
            to: seller.address,
            value: ethers.utils.parseEther("20.0"),
        });

        const Marketplace = await ethers.getContractFactory("Marketplace");
        const marketplace = await Marketplace.deploy();

        const { chainId } = await provider.getNetwork();
        const domain: Domain = {
            name: await marketplace.name(),
            chainId: chainId,
            version: "1.2",
            verifyingContract: marketplace.address,
        };

        return { marketplace, owner, otherAccount, seller, buyer, zone, provider, domain };
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
        // async function deployMarketplaceWithListingFixture() {
        //     const listingId = 0;

        //     const { marketplace, owner, otherAccount } = await loadFixture(deployMarketplaceFixture);
        //     const { myToken, tokenIds } = await loadFixture(deployErc721WithTokensFixture);

        //     const listingPrice = ethers.utils.parseUnits("1", "gwei");
        //     const listingData = ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, listingPrice]);

        //     await myToken["safeTransferFrom(address,address,uint256,bytes)"](
        //         owner.address,
        //         marketplace.address,
        //         tokenIds[0],
        //         listingData,
        //     );

        //     return {
        //         marketplace,
        //         listingId,
        //         myToken,
        //         tokenId: tokenIds[0],
        //         listingPrice,
        //         owner,
        //         otherAccount,
        //     };
        // }
        describe("Helper", function () {
            it("gets correct name", async () => {
                const { marketplace, seller, owner, zone, provider } = await loadFixture(deployMarketplaceFixture);

                const name = await marketplace.name();
                expect(name).to.equal("Marketplace");
            });

            it("gets correct version, domain separator and conduit controller", async () => {
                const { marketplace, seller, owner, zone, provider } = await loadFixture(deployMarketplaceFixture);

                const name = await marketplace.name();
                const { version, domainSeparator, conduitController: controller } = await marketplace.information();

                const typehash = keccak256(
                    toUtf8Bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                );
                const namehash = keccak256(toUtf8Bytes(name));
                const versionhash = keccak256(toUtf8Bytes(version));
                const { chainId } = await provider.getNetwork();
                const chainIdEncoded = chainId.toString(16).padStart(64, "0");
                const addressEncoded = marketplace.address.slice(2).padStart(64, "0");

                expect(domainSeparator).to.equal(
                    keccak256(
                        `0x${typehash.slice(2)}${namehash.slice(2)}${versionhash.slice(
                            2,
                        )}${chainIdEncoded}${addressEncoded}`,
                    ),
                );
            });

            it("gets correct order hash", async () => {
                const { marketplace, seller, owner, zone, provider } = await loadFixture(deployMarketplaceFixture);

                const counter = await marketplace.getCounter(seller.address);
                const offer = [
                    {
                        itemType: 2,
                        token: "0x8f788633F394A6FA19f1E8c09782921e427c3396",
                        identifier: BigNumber.from("0xe2ed90ee2cc04af3e64f712c91105b80"),
                        startAmount: BigNumber.from("0x01"),
                        endAmount: BigNumber.from("0x01"),
                    },
                ];
                const consideration = [
                    getItemETH(parseEther("10"), parseEther("10"), seller.address),
                    getItemETH(parseEther("1"), parseEther("1"), owner.address),
                ];
                const HashZero = "0x0000000000000000000000000000000000000000000000000000000000000000";
                const orderParameters = {
                    offerer: seller.address,
                    zone: zone.address,
                    offer,
                    consideration,
                    totalOriginalConsiderationItems: consideration.length,
                    orderType: 0,
                    zoneHash: HashZero,
                    salt: "0x7db511bb1e2c5b7a09f6df9f757507bd3d79b1e3d515ee8799e20bbd762dfbc9",
                    startTime: 0,
                    endTime: "0xff00000000000000000000000000",
                };

                const orderComponents = {
                    ...orderParameters,
                    counter,
                };

                const orderHash = await marketplace.getOrderHash(orderComponents);
                const derivedOrderHash = calculateOrderHash(orderComponents);
                expect(orderHash).to.equal(derivedOrderHash);
            });

            it("correctly recover signer address", async () => {
                const { marketplace, seller, owner, zone, domain } = await loadFixture(deployMarketplaceFixture);

                const counter = await marketplace.getCounter(seller.address);
                const offer = [
                    {
                        itemType: 2,
                        token: "0x8f788633F394A6FA19f1E8c09782921e427c3396",
                        identifier: BigNumber.from("0xe2ed90ee2cc04af3e64f712c91105b80"),
                        startAmount: BigNumber.from("0x01"),
                        endAmount: BigNumber.from("0x01"),
                    },
                ];
                const consideration = [
                    getItemETH(parseEther("10"), parseEther("10"), seller.address),
                    getItemETH(parseEther("1"), parseEther("1"), owner.address),
                ];
                const HashZero = "0x0000000000000000000000000000000000000000000000000000000000000000";
                const orderParameters = {
                    offerer: seller.address,
                    zone: zone.address,
                    offer,
                    consideration,
                    totalOriginalConsiderationItems: consideration.length,
                    orderType: 0,
                    zoneHash: HashZero,
                    salt: "0x7db511bb1e2c5b7a09f6df9f757507bd3d79b1e3d515ee8799e20bbd762dfbc9",
                    startTime: 0,
                    endTime: "0xff00000000000000000000000000",
                };

                const orderComponents = {
                    ...orderParameters,
                    counter,
                };

                const { domainSeparator } = await marketplace.information();
                console.log("doamin:", domainSeparator);

                const orderHash = await marketplace.getOrderHash(orderComponents);
                const digest = keccak256(`0x1901${domainSeparator.slice(2)}${orderHash.slice(2)}`);

                const flatSig = await signOrder(orderComponents, seller, domain);
                const recoveredAddress = recoverAddress(digest, flatSig);

                expect(recoveredAddress).to.equal(seller.address);
            });
        });

        describe("Test", function () {
            it("should work", async function () {
                const { marketplace, seller, buyer, owner, zone, domain } = await loadFixture(deployMarketplaceFixture);
                const { myToken, tokenIds } = await loadFixture(deployErc721WithTokensFixture);

                const counter = await marketplace.getCounter(seller.address);

                await myToken.transferFrom(owner.address, seller.address, tokenIds[0]);
                await myToken.connect(seller).setApprovalForAll(marketplace.address, true);

                // const offer = [
                //     {
                //         "itemType": 2,
                //         "token": "0x8f788633F394A6FA19f1E8c09782921e427c3396",
                //         "identifier": "0xe2ed90ee2cc04af3e64f712c91105b80",
                //         "startAmount": "0x01",
                //         "endAmount": "0x01"
                //     }
                // ];
                const offer = [
                    {
                        itemType: 2,
                        token: myToken.address,
                        identifier: BigNumber.from(tokenIds[0]),
                        startAmount: BigNumber.from("0x01"),
                        endAmount: BigNumber.from("0x01"),
                    },
                ];

                const consideration = [
                    getItemETH(parseEther("10"), parseEther("10"), seller.address),
                    getItemETH(parseEther("1"), parseEther("1"), owner.address),
                ];

                console.log(consideration);

                const HashZero = "0x0000000000000000000000000000000000000000000000000000000000000000";

                const orderParameters = {
                    offerer: seller.address,
                    zone: zone.address,
                    offer,
                    consideration,
                    totalOriginalConsiderationItems: consideration.length,
                    orderType: 0,
                    zoneHash: HashZero,
                    salt: "0x7db511bb1e2c5b7a09f6df9f757507bd3d79b1e3d515ee8799e20bbd762dfbc9",
                    startTime: 0,
                    endTime: "0xff00000000000000000000000000",
                };

                const orderComponents = {
                    ...orderParameters,
                    counter,
                };

                const flatSig = await signOrder(orderComponents, seller, domain);
                const order = {
                    parameters: orderParameters,
                    signature: flatSig,
                };

                console.log(flatSig);

                expect(
                    await marketplace.connect(buyer).fulfillOrder(order, { value: parseEther("11.0") }),
                ).to.changeEtherBalances(
                    [owner, seller, buyer],
                    [parseEther("1.0"), parseEther("10.0"), parseEther("-11.0")],
                );

                expect(await myToken.ownerOf(tokenIds[0])).to.equal(buyer.address);
            });
        });
        //     it("should emit listing canceled event", async function () {
        //         const { marketplace, myToken, tokenId, listingId, owner, listingPrice } = await loadFixture(
        //             deployMarketplaceWithListingFixture,
        //         );

        //         await expect(marketplace.cancelListing(listingId))
        //             .to.emit(marketplace, "ListingCanceled")
        //             .withArgs(listingId, myToken.address, tokenId, owner.address, listingPrice);
        //     });

        //     it("should revert on non-owner sender", async function () {
        //         const { marketplace, myToken, tokenId, otherAccount, listingId } = await loadFixture(
        //             deployMarketplaceWithListingFixture,
        //         );

        //         await expect(marketplace.connect(otherAccount).cancelListing(listingId)).to.be.revertedWith(
        //             "You aren't the seller",
        //         );
        //     });

        //     it("should return token to owner", async function () {
        //         const { marketplace, myToken, tokenId, otherAccount, owner, listingId } = await loadFixture(
        //             deployMarketplaceWithListingFixture,
        //         );

        //         await marketplace.cancelListing(listingId);
        //         expect(await myToken.ownerOf(tokenId)).to.equal(owner.address);
        //     });

        //     it("should remove token from listing", async function () {
        //         const { marketplace, myToken, tokenId, otherAccount, owner, listingId } = await loadFixture(
        //             deployMarketplaceWithListingFixture,
        //         );

        //         await marketplace.cancelListing(listingId);
        //         await expect(marketplace.getListing(listingId)).to.be.revertedWith("Listing doesn't exists");
        //     });

        //     it("should revert if listing is invalid", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await expect(marketplace.cancelListing(listingId + 1)).to.be.revertedWith("Listing doesn't exists");
        //     });
        // });

        // describe("Buy", function () {
        //     it("should emit sale event", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await expect(marketplace.connect(otherAccount).buy(listingId, { value: listingPrice }))
        //             .to.emit(marketplace, "ListingSale")
        //             .withArgs(listingId, myToken.address, tokenId, owner.address, otherAccount.address, listingPrice);
        //     });

        //     it("should transfer token to buyer", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await marketplace.connect(otherAccount).buy(listingId, { value: listingPrice });
        //         expect(await myToken.ownerOf(tokenId)).to.equal(otherAccount.address);
        //     });

        //     it("should transfer ether to token owner", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await expect(
        //             marketplace.connect(otherAccount).buy(listingId, { value: listingPrice }),
        //         ).to.changeEtherBalances([otherAccount, owner], [-listingPrice, listingPrice]);
        //     });

        //     it("should revert on incorrect token value", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await expect(
        //             marketplace.connect(otherAccount).buy(listingId, { value: listingPrice.add(1) }),
        //         ).to.be.revertedWith("You didn't provide the correct price");

        //         await expect(
        //             marketplace.connect(otherAccount).buy(listingId, { value: listingPrice.sub(1) }),
        //         ).to.be.revertedWith("You didn't provide the correct price");
        //     });

        //     it("should revert if token is not listing", async function () {
        //         const { marketplace, myToken, tokenId, listingPrice, otherAccount, owner, listingId } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await expect(
        //             marketplace.connect(otherAccount).buy(listingId + 1, { value: listingPrice }),
        //         ).to.be.revertedWith("Listing doesn't exists");
        //     });

        //     it("should remove token from listing", async function () {
        //         const { marketplace, myToken, tokenId, otherAccount, owner, listingId, listingPrice } =
        //             await loadFixture(deployMarketplaceWithListingFixture);

        //         await marketplace.connect(otherAccount).buy(listingId, { value: listingPrice });
        //         await expect(marketplace.getListing(listingId)).to.be.revertedWith("Listing doesn't exists");
        //     });
        // });
    });
});
