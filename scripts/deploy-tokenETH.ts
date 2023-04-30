import { ethers } from "hardhat";

async function main() {
    const TokenETH = await ethers.getContractFactory("TokenETH");
    const tokenEth = await TokenETH.deploy();

    await tokenEth.deployed();
    console.log(`TokenETH deployed to ${tokenEth.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
