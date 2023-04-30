import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { marketplaceFixture } from "./utils/fixtures/marketplace";
import { calculateOrderHash, getItemETH, randomHex, toBN } from "./utils/encoding";
import { accountsFixture } from "./utils/fixtures/accounts";
import { erc721Fixture } from "./utils/fixtures/erc721";

const { keccak256, toUtf8Bytes, parseEther } = ethers.utils;

describe(`Getter tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("gets correct name", async () => {
        const { marketplace } = await loadFixture(marketplaceFixture);

        const name = await marketplace.name();
        expect(name).to.equal(MARKETPLACE_NAME);
    });

    it("gets correct version, domain separator", async () => {
        const { marketplace, domainData } = await loadFixture(marketplaceFixture);

        const name = await marketplace.name();
        const { version, domainSeparator } = await marketplace.information();

        expect(version).to.equal(MARKETPLACE_VERSION);

        const typehash = keccak256(
            toUtf8Bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        );
        const namehash = keccak256(toUtf8Bytes(name));
        const versionhash = keccak256(toUtf8Bytes(version));
        const { chainId } = domainData;
        const chainIdEncoded = chainId.toString(16).padStart(64, "0");
        const addressEncoded = marketplace.address.slice(2).padStart(64, "0");

        expect(domainSeparator).to.equal(
            keccak256(
                `0x${typehash.slice(2)}${namehash.slice(2)}${versionhash.slice(2)}${chainIdEncoded}${addressEncoded}`,
            ),
        );
    });

    it("gets correct order hash", async () => {
        const { marketplace } = await loadFixture(marketplaceFixture);
        const { seller, buyer, zone } = await loadFixture(accountsFixture);
        const { erc721, mintAndApproveAll721, getTestItem721 } = await loadFixture(erc721Fixture);

        const tokenId = await mintAndApproveAll721(seller, marketplace.address);
        const offer = [getTestItem721(tokenId)];
        const consideration = [
            getItemETH(parseEther("10"), parseEther("10"), seller.address),
            getItemETH(parseEther("1"), parseEther("1"), zone.address),
        ];

        const counter = await marketplace.getCounter(seller.address);
        const salt = randomHex();
        const startTime = 0;
        const endTime = toBN("0xff00000000000000000000000000");
        const orderParameters = {
            offerer: seller.address,
            seller,
            offer,
            consideration,
            salt,
            startTime,
            endTime,
        };
        const orderComponents = {
            ...orderParameters,
            counter,
        };

        const orderHash = await marketplace.getOrderHash(orderComponents);
        const derivedOrderHash = calculateOrderHash(orderComponents);
        expect(orderHash).to.equal(derivedOrderHash);
    });
});
