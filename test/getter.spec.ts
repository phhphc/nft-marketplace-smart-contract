import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MARKETPLACE_NAME, MARKETPLACE_VERSION } from "./constants/marketplace";
import { marketplaceFixture } from "./utils/fixtures/marketplace";

const { keccak256, toUtf8Bytes } = ethers.utils;

describe(`Getter tests (${MARKETPLACE_NAME} v${MARKETPLACE_VERSION})`, function () {
    it("gets correct name", async () => {
        const { marketplace } = await loadFixture(marketplaceFixture);

        const name = await marketplace.name();
        expect(name).to.equal(MARKETPLACE_NAME);
    });

    it("gets correct version, domain separator and conduit controller", async () => {
        const { marketplace, domainData } = await loadFixture(marketplaceFixture);

        const name = await marketplace.name();
        const { version, domainSeparator } = await marketplace.information();

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
});
