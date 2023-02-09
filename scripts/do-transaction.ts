import { ethers } from "hardhat";

async function main() {
    const [owner] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.attach(process.env.MKP_ADDR as string);
    console.log(`Marketplace attached from ${marketplace.address}`);

    const MyToken = await ethers.getContractFactory("MyToken");
    const myToken = await MyToken.attach(process.env.NFT_ADDR as string);
    console.log(`Mytoken attached from ${myToken.address}`);

    const tokenId = 1;

    // var res = await marketplace.buy(29, { value: "2000000000000000000" });
    // res.wait();
    // console.log(res.blockNumber);

    const listingPrice = ethers.utils.parseUnits("2", "ether");
    const listingData = ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, listingPrice]);
    var res = await myToken["safeTransferFrom(address,address,uint256,bytes)"](
        owner.address,
        marketplace.address,
        tokenId,
        listingData,
    );
    res.wait();
    console.log(res.blockNumber);

    // const tokenIds = Array.from(Array(20).keys()).slice(10);
    // const tokenUris = tokenIds.map(v => "https://test.com/" + v);
    // for (let uri of tokenUris) {
    // await myToken.safeMint(owner.address, uri);
    // }

    // const listingIds = Array.from(Array(15).keys()).slice(10);
    // const listingPrices = listingIds.map(v => ethers.utils.parseUnits(String(v), "gwei"));
    // const listingDatas = listingPrices.map(v => ethers.utils.defaultAbiCoder.encode(["int8", "uint256"], [0, v]));
    // for (let i=0;i<listingPrices.length;i++) {
    //     await myToken["safeTransferFrom(address,address,uint256,bytes)"](
    //         owner.address,
    //         marketplace.address,
    //         tokenIds[i],
    //         listingDatas[i],
    //     );
    // }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
