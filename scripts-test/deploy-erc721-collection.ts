import { ethers } from "hardhat";

async function main() {
    const Erc721Collection = await ethers.getContractFactory("Erc721Collection");
    const erc721Collection = await Erc721Collection.deploy(
        "Penguins",
        "PGS",
        "https://mocki.io/v1/b33d46c6-dea0-4005-b020-d6046c01aaa4",
    );

    await erc721Collection.deployed();
    console.log(`Erc721Collection deployed to ${erc721Collection.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
