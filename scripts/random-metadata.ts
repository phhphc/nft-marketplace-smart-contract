import { faker } from "@faker-js/faker";
import fs from "fs";
import path from "path";

const imageUrls = [
    "https://i.seadn.io/gcs/files/28ab56a502d504c5f765de3f94928dec.png",
    "https://i.seadn.io/gcs/files/d904865bae36459379693e3d60b9a469.png",
    "https://i.seadn.io/gcs/files/8ad02f09253833f041359e8913aba827.png",
    "https://i.seadn.io/gcs/files/c7382a28e88d4be4098bf7f7a303cee7.png",
    "https://i.seadn.io/gcs/files/7c59fad0ff1ee9b7ac508da3221d12c9.png",
    "https://i.seadn.io/gcs/files/638bc61aaad97ab7e44258d4a9cc34e8.png",
    "https://i.seadn.io/gcs/files/ba7c42b08c764dcd99900d39a1669120.png",
    "https://i.seadn.io/gcs/files/98c78812fda433ae05deef92ec288dd8.png",
    "https://i.seadn.io/gcs/files/0cf9d1d2fedfdb36ad794f6426e9ddc8.png",
    "https://i.seadn.io/gcs/files/adb7c11276b7d59966baab404b2c8928.png",
    "https://i.seadn.io/gcs/files/d62b8f5b9c63086b7a62b7da46f4997f.png",
    "https://i.seadn.io/gcs/files/11d907b983b622c7f47be67de10531ed.png",
    "https://i.seadn.io/gcs/files/643c7ee86fa243be57285e9346952e8e.png",
    "https://i.seadn.io/gcs/files/cd26421db0233b5a224ebe12ec40b6b6.png",
    "https://i.seadn.io/gcs/files/787ee67725d1b01ae5e8c84d93b6904a.png",
    "https://i.seadn.io/gcs/files/0f560083ab1af40a3ac7280aa350c07a.png",
    "https://i.seadn.io/gcs/files/e8377a9aae14052640516fc36becbe37.png",
    "https://i.seadn.io/gcs/files/72d3f31e42c6dc81329dcb44bc52a9f9.png",
    "https://i.seadn.io/gcs/files/2ed01e7b4e8751c1c1715262ffb4cd33.png",
    "https://i.seadn.io/gcs/files/ebf940b515174c821b17b011749bf437.png",
    "https://i.seadn.io/gcs/files/ad8940314e534e78e3a693c1afc3b22b.png",
    "https://i.seadn.io/gcs/files/3896c516989f18ef63010d84c139e2f1.png",
];

function createRandomErc721Token(): any {
    const nameLength = faker.datatype.number({
        min: 1,
        max: 4,
    });
    const descLength = faker.datatype.number({
        min: 1,
        max: 4,
    });
    return {
        name: faker.lorem.words(nameLength),
        description: faker.lorem.paragraph(descLength),
        image: faker.helpers.arrayElement(imageUrls),
    };
}

faker.seed(1);
const assetDir = path.join(__dirname, "assets");
if (!fs.existsSync(assetDir)) {
    fs.mkdirSync(assetDir);
}
for (let i = 0; i < 100; i++) {
    const jsonStr = JSON.stringify(createRandomErc721Token(), null, 2);
    fs.writeFile(path.join(assetDir, `${i}.json`), jsonStr, err => {
        if (err != null) {
            console.error(err);
        }
    });
}
