import { Account, Contract, RpcProvider, shortString } from "starknet";
import { getCompiledCode } from "./utils";
import * as dotenv from "dotenv";

dotenv.config();

const DEVNET_RPC: string = process.env.DEVNET_RPC || "";
const DEVNET_ACCOUNT_ADDRESS: string = process.env.DEVNET_ACCOUNT_ADDRESS || "";
const DEVNET_PRIVATE_KEY: string = process.env.DEVNET_PRIVATE_KEY || "";

async function main() {
  console.log("🧪 Testing Address Prediction vs Actual Deployment");

  try {
    const provider = new RpcProvider({ nodeUrl: DEVNET_RPC });
    const account = new Account({
      address: DEVNET_ACCOUNT_ADDRESS,
      signer: DEVNET_PRIVATE_KEY,
      provider: provider,
      cairoVersion: "1",
    });

    console.log("✅ Connected to testnet");

    // Test parameters
    const testName = shortString.encodeShortString("STARKNET_CONTRACT_ADDRESS");
    const ownerAddress = DEVNET_ACCOUNT_ADDRESS;
    const classHash =
      "0x02d4c8cc6b4915da816a96cf63a53c148848ffc2a83401266881a2008c231585";

    console.log(`\n📋 Test Parameters:`);
    console.log(`Name (felt252): ${testName}`);
    console.log(`Owner: ${ownerAddress}`);
    console.log(`Class Hash: ${classHash}`);

    // Deploy registry
    console.log(`\n📦 Deploying registry...`);
    const { sierraCode: registryCode, casmCode: registryCasm } =
      await getCompiledCode("uda_registry_test_registry");

    const registryDeploy = await account.declareAndDeploy({
      contract: registryCode,
      casm: registryCasm,
    });

    await provider.waitForTransaction(registryDeploy.deploy.transaction_hash);
    console.log(
      `✅ Registry deployed at: ${registryDeploy.deploy.contract_address}`
    );

    const registry = new Contract({
      abi: registryCode.abi,
      address: registryDeploy.deploy.contract_address,
      providerOrAccount: account,
    });

    // Step 1: Predict the address
    console.log(`\n🔮 Step 1: Predicting deployment address...`);
    const predictedAddress = await registry.get_address(
      testName,
      ownerAddress,
      classHash
    );
    console.log(`📍 Predicted address: ${predictedAddress}`);
    console.log(
      `📍 Predicted address (hex): 0x${BigInt(predictedAddress).toString(16)}`
    );

    // Step 2: Actually deploy and get the real address
    console.log(`\n🚀 Step 2: Actually deploying...`);
    const deployResult = await registry.create_address(
      testName,
      ownerAddress,
      classHash
    );
    console.log(`📤 Deploy transaction hash: ${deployResult.transaction_hash}`);

    await provider.waitForTransaction(deployResult.transaction_hash);
    console.log("✅ Deployment confirmed");

    // Step 3: Extract the actual deployed address from the event
    console.log(`\n🔍 Step 3: Extracting actual deployed address...`);
    const txReceipt = await provider.getTransactionReceipt(
      deployResult.transaction_hash
    );

    let actualDeployedAddress;
    // @ts-ignore - events property exists on successful receipts
    if (txReceipt.events && txReceipt.events.length > 0) {
      // Look for our UdaDeployed event (first event should be ours)
      // @ts-ignore
      const ourEvent = txReceipt.events[0];
      if (ourEvent.data && ourEvent.data.length > 0) {
        // The deployed_address should be the first (and only) data field
        actualDeployedAddress = ourEvent.data[0];
        console.log(
          `📍 Found our event with data: ${JSON.stringify(ourEvent.data)}`
        );
      } else {
        console.log(`❌ Our event has no data: ${JSON.stringify(ourEvent)}`);
      }
    }

    console.log(`📍 Actual deployed address: ${actualDeployedAddress}`);

    // Step 4: Compare prediction vs reality
    console.log(`\n🔍 Step 4: Comparing Prediction vs Reality`);
    console.log(`Predicted:  ${predictedAddress}`);
    console.log(`Actual:      ${actualDeployedAddress}`);

    if (predictedAddress.toString() === actualDeployedAddress.toString()) {
      console.log("🎉 SUCCESS: Address prediction is correct!");
      console.log("✅ Your get_address function works perfectly!");
      console.log(
        "✅ You can now predict addresses before deployment for 'initiate on behalf' scenarios"
      );
    } else {
      console.log("❌ FAILURE: Address prediction is wrong!");
      console.log("❌ The get_address function needs to be fixed");

      // Show the difference
      const predictedHex = BigInt(predictedAddress).toString(16);
      const actualHex = BigInt(actualDeployedAddress).toString(16);
      console.log(`\n📊 Hex Comparison:`);
      console.log(`Predicted: 0x${predictedHex}`);
      console.log(`Actual:    0x${actualHex}`);
    }
  } catch (error) {
    console.error("❌ Error:", error);
    process.exit(1);
  }
}

main().catch(console.error);
