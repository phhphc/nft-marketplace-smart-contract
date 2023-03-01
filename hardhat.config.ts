import fs from "fs";
import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";

dotEnvConfig();

const GANACHE_PRIVATE_KEY = process.env.GANACHE_PRIVATE_KEY || "";

const DEVNET_URL = process.env.DEVNET_URL || "";
const DEVNET_PRIVATE_KEY = process.env.DEVNET_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
    solidity: "0.8.17",
    networks: {
        ganache: {
            url: "HTTP://127.0.0.1:7545",
            accounts: [GANACHE_PRIVATE_KEY],
        },
        devnet: {
            url: DEVNET_URL,
            accounts: [DEVNET_PRIVATE_KEY],
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
            .map(x => x.replace(/\.sol$/, ""))
            .concat("IERC721Metadata$"),
    },
};

export default config;
