import { expect } from "chai";
import { randomBytes as nodeRandomBytes } from "crypto";
import { BigNumber, constants, utils } from "ethers";
import { getAddress, keccak256, toUtf8Bytes } from "ethers/lib/utils";

import type {
    BasicOrderParameters,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    Order,
    OrderComponents,
} from "./types";
import type { BigNumberish, ContractTransaction } from "ethers";

const randomBytes = (n: number) => nodeRandomBytes(n).toString("hex");

export const randomHex = (bytes = 32) => `0x${randomBytes(bytes)}`;

export const random128 = () => toBN(randomHex(16));

const hexRegex = /[A-Fa-fx]/g;

export const toHex = (n: BigNumberish, numBytes: number = 0) => {
    const asHexString = BigNumber.isBigNumber(n)
        ? n.toHexString().slice(2)
        : typeof n === "string"
        ? hexRegex.test(n)
            ? n.replace(/0x/, "")
            : Number(n).toString(16)
        : Number(n).toString(16);
    return `0x${asHexString.padStart(numBytes * 2, "0")}`;
};

export const baseFee = async (tx: ContractTransaction) => {
    const data = tx.data;
    const { gasUsed } = await tx.wait();
    const bytes = toHex(data)
        .slice(2)
        .match(/.{1,2}/g) as string[];
    const numZero = bytes.filter(b => b === "00").length;
    return gasUsed.toNumber() - (21000 + (numZero * 4 + (bytes.length - numZero) * 16));
};

export const randomBN = (bytes: number = 16) => toBN(randomHex(bytes));

export const toBN = (n: BigNumberish) => BigNumber.from(toHex(n));

export const toAddress = (n: BigNumberish) => getAddress(toHex(n, 20));

export const toKey = (n: BigNumberish) => toHex(n, 32);

export const convertSignatureToEIP2098 = (signature: string) => {
    if (signature.length === 130) {
        return signature;
    }

    expect(signature.length, "signature must be 64 or 65 bytes").to.eq(132);

    return utils.splitSignature(signature).compact;
};

// export const getBasicOrderParameters = (
//   basicOrderRouteType: number,
//   order: Order,
//   fulfillerConduitKey: string | boolean = false,
//   tips: { amount: BigNumber; recipient: string }[] = []
// ): BasicOrderParameters => ({
//   offerer: order.parameters.offerer,
//   zone: order.parameters.zone,
//   basicOrderType: order.parameters.orderType + 4 * basicOrderRouteType,
//   offerToken: order.parameters.offer[0].token,
//   offerIdentifier: order.parameters.offer[0].identifierOrCriteria,
//   offerAmount: order.parameters.offer[0].endAmount,
//   considerationToken: order.parameters.consideration[0].token,
//   considerationIdentifier:
//     order.parameters.consideration[0].identifierOrCriteria,
//   considerationAmount: order.parameters.consideration[0].endAmount,
//   startTime: order.parameters.startTime,
//   endTime: order.parameters.endTime,
//   zoneHash: order.parameters.zoneHash,
//   salt: order.parameters.salt,
//   totalOriginalAdditionalRecipients: BigNumber.from(
//     order.parameters.consideration.length - 1
//   ),
//   signature: order.signature,
//   offererConduitKey: order.parameters.conduitKey,
//   fulfillerConduitKey: toKey(
//     typeof fulfillerConduitKey === "string" ? fulfillerConduitKey : 0
//   ),
//   additionalRecipients: [
//     ...order.parameters.consideration
//       .slice(1)
//       .map(({ endAmount, recipient }) => ({ amount: endAmount, recipient })),
//     ...tips,
//   ],
// });

export const getOfferOrConsiderationItem = <RecipientType extends string | undefined = undefined>(
    itemType: number = 0,
    token: string = constants.AddressZero,
    identifierOrCriteria: BigNumberish = 0,
    startAmount: BigNumberish = 1,
    endAmount: BigNumberish = 1,
    recipient?: RecipientType,
): RecipientType extends string ? ConsiderationItem : OfferItem => {
    const offerItem: OfferItem = {
        itemType,
        token,
        identifier: toBN(identifierOrCriteria),
        startAmount: toBN(startAmount),
        endAmount: toBN(endAmount),
    };
    if (typeof recipient === "string") {
        return {
            ...offerItem,
            recipient: recipient as string,
        } as ConsiderationItem;
    }
    return offerItem as any;
};

export const buildOrderStatus = (...arr: Array<BigNumber | number | boolean>) => {
    const values = arr.map(v => (typeof v === "number" ? toBN(v) : v));
    return ["isValidated", "isCancelled", "totalFilled", "totalSize"].reduce(
        (obj, key, i) => ({
            ...obj,
            [key]: values[i],
            [i]: values[i],
        }),
        {},
    );
};

export const getItemETH = (startAmount: BigNumberish = 1, endAmount: BigNumberish = 1, recipient?: string) =>
    getOfferOrConsiderationItem(0, constants.AddressZero, 0, toBN(startAmount), toBN(endAmount), recipient);

export const getItem721 = (
    token: string,
    identifierOrCriteria: BigNumberish,
    startAmount: number = 1,
    endAmount: number = 1,
    recipient?: string,
) => getOfferOrConsiderationItem(2, token, identifierOrCriteria, startAmount, endAmount, recipient);

export const toFulfillmentComponents = (arr: number[][]): FulfillmentComponent[] =>
    arr.map(([orderIndex, itemIndex]) => ({ orderIndex, itemIndex }));

export const toFulfillment = (offerArr: number[][], considerationsArr: number[][]): Fulfillment => ({
    offerComponents: toFulfillmentComponents(offerArr),
    considerationComponents: toFulfillmentComponents(considerationsArr),
});

export const buildResolver = (
    orderIndex: number,
    side: 0 | 1,
    index: number,
    identifier: BigNumber,
    criteriaProof: string[],
): CriteriaResolver => ({
    orderIndex,
    side,
    index,
    identifier,
    criteriaProof,
});

export const calculateOrderHash = (orderComponents: OrderComponents) => {
    const offerItemTypeString =
        "OfferItem(uint8 itemType,address token,uint256 identifier,uint256 startAmount,uint256 endAmount)";
    const considerationItemTypeString =
        "ConsiderationItem(uint8 itemType,address token,uint256 identifier,uint256 startAmount,uint256 endAmount,address recipient)";
    const orderComponentsPartialTypeString =
        "OrderComponents(address offerer,OfferItem[] offer,ConsiderationItem[] consideration,uint256 startTime,uint256 endTime,uint256 salt,uint256 counter)";
    const orderTypeString = `${orderComponentsPartialTypeString}${considerationItemTypeString}${offerItemTypeString}`;

    const offerItemTypeHash = keccak256(toUtf8Bytes(offerItemTypeString));
    const considerationItemTypeHash = keccak256(toUtf8Bytes(considerationItemTypeString));
    const orderTypeHash = keccak256(toUtf8Bytes(orderTypeString));

    const offerHash = keccak256(
        "0x" +
            orderComponents.offer
                .map(offerItem => {
                    return keccak256(
                        "0x" +
                            [
                                offerItemTypeHash.slice(2),
                                offerItem.itemType.toString().padStart(64, "0"),
                                offerItem.token.slice(2).padStart(64, "0"),
                                toBN(offerItem.identifier).toHexString().slice(2).padStart(64, "0"),
                                toBN(offerItem.startAmount).toHexString().slice(2).padStart(64, "0"),
                                toBN(offerItem.endAmount).toHexString().slice(2).padStart(64, "0"),
                            ].join(""),
                    ).slice(2);
                })
                .join(""),
    );

    const considerationHash = keccak256(
        "0x" +
            orderComponents.consideration
                .map(considerationItem => {
                    return keccak256(
                        "0x" +
                            [
                                considerationItemTypeHash.slice(2),
                                considerationItem.itemType.toString().padStart(64, "0"),
                                considerationItem.token.slice(2).padStart(64, "0"),
                                toBN(considerationItem.identifier).toHexString().slice(2).padStart(64, "0"),
                                toBN(considerationItem.startAmount).toHexString().slice(2).padStart(64, "0"),
                                toBN(considerationItem.endAmount).toHexString().slice(2).padStart(64, "0"),
                                considerationItem.recipient.slice(2).padStart(64, "0"),
                            ].join(""),
                    ).slice(2);
                })
                .join(""),
    );

    const derivedOrderHash = keccak256(
        "0x" +
            [
                orderTypeHash.slice(2),
                orderComponents.offerer.slice(2).padStart(64, "0"),
                offerHash.slice(2),
                considerationHash.slice(2),
                toBN(orderComponents.startTime).toHexString().slice(2).padStart(64, "0"),
                toBN(orderComponents.endTime).toHexString().slice(2).padStart(64, "0"),
                orderComponents.salt.slice(2).padStart(64, "0"),
                toBN(orderComponents.counter).toHexString().slice(2).padStart(64, "0"),
            ].join(""),
    );

    return derivedOrderHash;
};

// export const getBasicOrderExecutions = (
//   order: Order,
//   fulfiller: string,
//   fulfillerConduitKey: string
// ) => {
//   const { offerer, conduitKey, offer, consideration } = order.parameters;
//   const offerItem = offer[0];
//   const considerationItem = consideration[0];
//   const executions = [
//     {
//       item: {
//         ...offerItem,
//         amount: offerItem.endAmount,
//         recipient: fulfiller,
//       },
//       offerer,
//       conduitKey,
//     },
//     {
//       item: {
//         ...considerationItem,
//         amount: considerationItem.endAmount,
//       },
//       offerer: fulfiller,
//       conduitKey: fulfillerConduitKey,
//     },
//   ];
//   if (consideration.length > 1) {
//     for (const additionalRecipient of consideration.slice(1)) {
//       const execution = {
//         item: {
//           ...additionalRecipient,
//           amount: additionalRecipient.endAmount,
//         },
//         offerer: fulfiller,
//         conduitKey: fulfillerConduitKey,
//       };
//       if (additionalRecipient.itemType === offerItem.itemType) {
//         execution.offerer = offerer;
//         execution.conduitKey = conduitKey;
//         executions[0].item.amount = executions[0].item.amount.sub(
//           execution.item.amount
//         );
//       }
//       executions.push(execution);
//     }
//   }
//   return executions;
// };

export const defaultBuyNowMirrorFulfillment = [
    [[[0, 0]], [[1, 0]]],
    [[[1, 0]], [[0, 0]]],
    [[[1, 0]], [[0, 1]]],
    [[[1, 0]], [[0, 2]]],
].map(([offerArr, considerationArr]) => toFulfillment(offerArr, considerationArr));

export const defaultAcceptOfferMirrorFulfillment = [
    [[[1, 0]], [[0, 0]]],
    [[[0, 0]], [[1, 0]]],
    [[[0, 0]], [[0, 1]]],
    [[[0, 0]], [[0, 2]]],
].map(([offerArr, considerationArr]) => toFulfillment(offerArr, considerationArr));
