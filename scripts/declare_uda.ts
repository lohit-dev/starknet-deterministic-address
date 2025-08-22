import { Account, RpcProvider } from "starknet";
import { getCompiledCode } from "./utils";
import * as dotenv from "dotenv";

dotenv.config();

const DEVNET_RPC: string = process.env.DEVNET_RPC || "";
const DEVNET_ACCOUNT_ADDRESS: string = process.env.DEVNET_ACCOUNT_ADDRESS || "";
const DEVNET_PRIVATE_KEY: string = process.env.DEVNET_PRIVATE_KEY || "";

async function main() {
  console.log("🚀 Starting Registry Contract Tests on Devnet");

  try {
    // Setup provider and account
    const provider = new RpcProvider({ nodeUrl: DEVNET_RPC });
    const account = new Account({
      address: DEVNET_ACCOUNT_ADDRESS,
      signer: DEVNET_PRIVATE_KEY,
      provider: provider,
      cairoVersion: "1",
    });

    console.log("✅ Connected to devnet");
    console.log(`Account: ${DEVNET_ACCOUNT_ADDRESS}`);

    // Load compiled code
    const { sierraCode, casmCode } = await getCompiledCode(
      "uda_registry_test_uda"
    );
    console.log("✅ Loaded Sierra contract");

    // Deploy contract using declareAndDeploy
    console.log("🚀 Declaring and deploying contract...");

    console.log(`The sierraCode: ${sierraCode}`);
    console.log(`The casmCode: ${casmCode}`);

    const deployRespose = await account.declare({
      casm: casmCode,
      contract: sierraCode,
    });

    // const deployResponse = await account.declareAndDeploy({
    //   contract: sierraCode,
    //   casm: casmCode,
    // });

    console.log(
      `✅ Contract deployed at Transaction hash: ${deployRespose.transaction_hash}`
    );
    console.log(
      `✅ Contract deployed at Class hash: ${deployRespose.class_hash}`
    );
  } catch (error) {
    console.error("❌ Error:", error);
    process.exit(1);
  }
}

main().catch(console.error);
