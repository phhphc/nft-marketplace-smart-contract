import fs from "fs";
import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig, extendEnvironment } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import type { Wallet } from "ethers";
import "@solidstate/hardhat-bytecode-exporter";

dotEnvConfig();

const SEPOLIA_URL = process.env.SEPOLIA_URL || "";
const SEPOLIA_PRIVATE_KEY = process.env.SEPOLIA_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
    solidity: "0.8.17",
    networks: {
        sepolia: {
            url: SEPOLIA_URL,
            accounts: [SEPOLIA_PRIVATE_KEY],
        },
    },
    abiExporter: {
        path: "./abi",
        format: "json",
        flat: true,
        clear: true,
        only: fs
            .readdirSync("contracts")
            .filter(x => x.match(/^.+\.sol$/))
            .map(x => x.replace(/\.sol$/, "")),
    },
    bytecodeExporter: {
        path: "./bytecode",
        runOnCompile: true,
        clear: true,
        flat: true,
        only: fs
            .readdirSync("contracts")
            .filter(x => x.match(/^.+\.sol$/))
            .map(x => x.replace(/\.sol$/, "")),
    },
};

declare module "hardhat/types/runtime" {
    interface HardhatRuntimeEnvironment {
        accounts: {
            seller: Wallet;
            buyer: Wallet;
            zone: Wallet;
        };
        address: {
            marketplace: string;
            erc721: string;
            erc20: string;
        };
    }
}

extendEnvironment(async hre => {
    const { ethers } = hre;

    switch (hre.hardhatArguments.network) {
        case undefined:
        case "sepolia":
            {
                const SELLER_PRIVATE_KEY = process.env.SEPOLIA_SELLER_PRIVATE_KEY || "";
                const BUYER_PRIVATE_KEY = process.env.SEPOLIA_BUYER_PRIVATE_KEY || "";
                const ZONE_PRIVATE_KEY = process.env.SEPOLIA_ZONE_PRIVATE_KEY || "";
                hre.accounts = {
                    seller: new ethers.Wallet(SELLER_PRIVATE_KEY, ethers.provider),
                    buyer: new ethers.Wallet(BUYER_PRIVATE_KEY, ethers.provider),
                    zone: new ethers.Wallet(ZONE_PRIVATE_KEY, ethers.provider),
                };

                const MKP_ADDR = process.env.SEPOLIA_MKP_ADDR || "";
                const ERC721_ADDR = process.env.SEPOLIA_ERC721_ADDR || "";
                const ERC20_ADDR = process.env.SEPOLIA_ERC20_ADDR || "";
                hre.address = {
                    marketplace: MKP_ADDR,
                    erc721: ERC721_ADDR,
                    erc20: ERC20_ADDR,
                };
            }
            break;
        default:
            {
                const [, , , , , , , , , , seller, buyer, zone] = await ethers.getSigners();
                hre.accounts = {
                    seller: seller as unknown as Wallet,
                    buyer: buyer as unknown as Wallet,
                    zone: zone as unknown as Wallet,
                };

                const MKP_ADDR = process.env.DEFAULT_MKP_ADDR || "";
                const ERC721_ADDR = process.env.DEFAULT_ERC721_ADDR || "";
                const ERC20_ADDR = process.env.DEFAULT_ERC20_ADDR || "";
                hre.address = {
                    marketplace: MKP_ADDR,
                    erc721: ERC721_ADDR,
                    erc20: ERC20_ADDR,
                };
            }
            break;
    }
});

export default config;
