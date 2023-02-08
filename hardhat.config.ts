import fs from "fs";
import { config as dotEnvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";

dotEnvConfig();

const GANACHE_PRIVATE_KEY = process.env.GANACHE_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
    solidity: "0.8.9",
    networks: {
        ganache: {
            url: "HTTP://127.0.0.1:7545",
            accounts: [GANACHE_PRIVATE_KEY],
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
