import { ethers } from "hardhat";
import { randomBN } from "../test/utils/encoding";

async function main() {
    const [owner] = await ethers.getSigners();

    const Erc721Collection = await ethers.getContractFactory("Erc721Collection");
    const erc721Collection = await Erc721Collection.deploy("MeoMeoMeo", "MMM", "https://abc.com");

    await erc721Collection.deployed();
    console.log(`MyToken deployed to ${erc721Collection.address}`);

    console.log(await erc721Collection.name());
    console.log(await erc721Collection.symbol());
    console.log(await erc721Collection.contractURI());

    const nftId = randomBN();
    const uri = "url://" + nftId;
    await erc721Collection.mint(owner.address, nftId, uri);

    console.log(nftId);
    console.log(await erc721Collection.ownerOf(nftId));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
