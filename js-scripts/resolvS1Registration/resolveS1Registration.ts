import { hashMessage } from "ethers";
import Safe from "@safe-global/protocol-kit";
import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import fs from "fs";
import path from "path";
import { distro } from "./rumpelPoints";
import {
  SIGN_MESSAGE_LIB,
  SIGN_MESSAGE_LIB_INTERFACE,
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
  START_REGISTER_MESSAGE,
  END_REGISTER_MESSAGE,
} from "./resolveS1Constants";

const printExpectedSignedHash = async (
  message: string,
  signer: string,
  safeAddress: string
) => {
  const provider = process.env.MAINNET_RPC_URL;
  if (!provider) {
    throw new Error("ERROR: no provider url");
  }

  const protocolKit = await Safe.init({
    provider,
    signer,
    safeAddress,
  });

  const safeMessageHash = await protocolKit.getSafeMessageHash(message);
  console.log(`expected safeMessageHash: ${safeMessageHash}`);
};

const addressesWithResolv = Object.entries(distro)
  .filter(
    ([, balances]) => balances["Resolv S1"] && balances["Resolv S1"] !== "0"
  )
  .map(([address]) => address);

console.log(
  JSON.stringify(addressesWithResolv, null, 2),
  addressesWithResolv.length
);

const transactions: any[] = [];

for (const address of addressesWithResolv) {
  const balances = distro[address];
  for (const pointId in balances) {
    if (pointId !== "Resolv S1") continue;
    if (balances[pointId] !== "0") {
      const readableMessage = `${START_REGISTER_MESSAGE}${address}${END_REGISTER_MESSAGE}`;
      const messageHash = hashMessage(readableMessage);

      const signMessageData = SIGN_MESSAGE_LIB_INTERFACE.encodeFunctionData(
        "signMessage",
        [messageHash]
      );
      const executeTransactionData = RUMPEL_MODULE_INTERFACE.encodeFunctionData(
        "exec",
        [
          [
            {
              safe: address,
              to: SIGN_MESSAGE_LIB,
              data: signMessageData,
              operation: 1, // Delegatecall
            },
          ],
        ]
      );

      transactions.push({
        to: RUMPEL_MODULE,
        value: "0",
        data: executeTransactionData,
      });

      console.log(address, pointId, balances[pointId]);
      console.log(`wallet: ${address}`);
      console.log(`messageHash: ${messageHash}`);
      await printExpectedSignedHash(messageHash, address, address);
      console.log(`sign message data: ${signMessageData}`);
      console.log();
    }
  }
}

const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, transactions);

// Create safe-batches in working directory if it doesn't exist
const safeBatchesFolder = path.join(
  process.cwd(),
  "/js-scripts/resolvS1Registration/safe-batches"
);
if (!fs.existsSync(safeBatchesFolder)) {
  fs.mkdirSync(safeBatchesFolder);
}

// Write the result to a file in the safe-batches folder
const outputPath = path.join(safeBatchesFolder, `resolvS1Registration.json`);
fs.writeFileSync(outputPath, JSON.stringify(batchJson, null, 2));
