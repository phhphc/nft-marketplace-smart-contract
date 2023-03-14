import { ethers } from "hardhat";

async function main() {
    const [owner] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.attach("0x630d7Edbb8BfB00FAC9e5b8B7bcCeed3AFa60569");
    console.log(`Marketplace deployed from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("MyToken");
    const myToken = await MyToken.attach("0x6FD78c06f77E05924E5Cf11a78E76fB39371E014");
    console.log(`Mytoken deployed from ${myToken.address}`);

    const tokenIds = Array.from(Array(20).keys()).slice(10);
    const tokenUris = tokenIds.map(v => "https://test.com/" + v);
    for (let uri of tokenUris) {
        await myToken.safeMint(owner.address, uri);
    }

    const listingIds = Array.from(Array(15).keys()).slice(10);
    const listingPrices = listingIds.map(v => ethers.utils.parseUnits(String(v), "gwei"));
    const listingDatas = listingPrices.map(v => ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, v]));
    for (let i = 0; i < listingPrices.length; i++) {
        await myToken["safeTransferFrom(address,address,uint256,bytes)"](
            owner.address,
            marketplace.address,
            tokenIds[i],
            listingDatas[i],
        );
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
