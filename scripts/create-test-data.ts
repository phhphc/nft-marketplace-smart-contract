import { ethers } from "hardhat";

async function main() {
    const [owner] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.deploy();
    await marketplace.deployed();
    console.log(`Marketplace deployed to ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("MyToken");
    const myToken = await MyToken.deploy();
    await myToken.deployed();
    console.log(`Mytoken deployed to ${myToken.address}`);

    const tokenIds = Array.from(Array(30).keys());
    const tokenUris = tokenIds.map(
        v => `https://gateway.pinata.cloud/ipfs/QmYTUyhsTWGkzGMDrgTJmDnzcuYEwejzPR6o7GVZ3LcmRv/${v}.json`,
    );
    for (let uri of tokenUris) {
        await myToken.safeMint(owner.address, uri);
    }

    const listingIds = Array.from(Array(25).keys());
    const listingPrices = listingIds.map(v => ethers.utils.parseUnits(String(v), "gwei"));
    const listingDatas = listingPrices.map(v => ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, v]));
    for (let id of listingIds) {
        await myToken["safeTransferFrom(address,address,uint256,bytes)"](
            owner.address,
            marketplace.address,
            tokenIds[id],
            listingDatas[id],
        );
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
