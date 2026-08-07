// Register the parent name on L1 Sepolia without touching the ENS web app.
//
// sepolia.app.ens.domains is a SPA that follows the connected wallet and tends
// to bounce back to mainnet mid-flow. This does the same commit/reveal directly
// against the controller, so the only thing that matters is which key signs.
//
// The controller on Sepolia takes a STRUCT, not positional args:
//   register((string,address,uint256,bytes32,address,bytes[],uint8,bytes32))
// Field order was confirmed against the live contract via makeCommitment before
// this script was written. reverseRecord is a coin-type bitmap on this version
// (0 = do not touch the signer's own reverse record, which is what we want:
// the probe sets its own, the deployer EOA should be left alone).
//
// Required env: SEPOLIA_RPC_URL (or RPC_URL), DEPLOYER_PRIVATE_KEY
// Optional env: ENS_PARENT_NAME (default "degenerus.eth"), ENS_DURATION_YEARS (1)
//
// Usage: npx hardhat run scripts/ens-sepolia-register.js --network sepolia

import hre from "hardhat";

const SEPOLIA_CHAIN_ID = 11155111n;
const CONTROLLER = "0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968";
const PUBLIC_RESOLVER = "0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5";
const SECONDS_PER_YEAR = 31557600n;

const CONTROLLER_ABI = [
  "function available(string) view returns (bool)",
  "function rentPrice(string,uint256) view returns (uint256 base, uint256 premium)",
  "function minCommitmentAge() view returns (uint256)",
  "function maxCommitmentAge() view returns (uint256)",
  "function makeCommitment((string label,address owner,uint256 duration,bytes32 secret,address resolver,bytes[] data,uint8 reverseRecord,bytes32 referrer)) view returns (bytes32)",
  "function commit(bytes32) external",
  "function register((string label,address owner,uint256 duration,bytes32 secret,address resolver,bytes[] data,uint8 reverseRecord,bytes32 referrer)) external payable",
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const { ethers } = hre;

  const net = await ethers.provider.getNetwork();
  if (net.chainId !== SEPOLIA_CHAIN_ID) {
    throw new Error(`Wrong network: chainId ${net.chainId}, expected Sepolia (11155111).`);
  }

  const parentName = process.env.ENS_PARENT_NAME || "degenerus.eth";
  if (!parentName.endsWith(".eth") || parentName.split(".").length !== 2) {
    throw new Error(`ENS_PARENT_NAME must be a second-level .eth name, got "${parentName}".`);
  }
  const label = parentName.slice(0, -".eth".length);
  const years = BigInt(process.env.ENS_DURATION_YEARS || "1");
  const duration = SECONDS_PER_YEAR * years;

  const [signer] = await ethers.getSigners();
  const controller = new ethers.Contract(CONTROLLER, CONTROLLER_ABI, signer);

  console.log(`Network:  sepolia`);
  console.log(`Signer:   ${signer.address}`);
  console.log(`Name:     ${parentName}`);
  console.log(`Duration: ${years} year(s)\n`);

  if (!(await controller.available(label))) {
    const registry = new ethers.Contract(
      "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
      ["function owner(bytes32) view returns (address)"],
      ethers.provider
    );
    const owner = await registry.owner(ethers.namehash(parentName));
    throw new Error(
      `${parentName} is not available on Sepolia (registry owner ${owner}). ` +
        `If that is the NameWrapper, you may already own it — run ens-sepolia-proof.js.`
    );
  }

  const [base, premium] = await controller.rentPrice(label, duration);
  const price = base + premium;
  const balance = await ethers.provider.getBalance(signer.address);
  console.log(`Rent:     ${ethers.formatEther(price)} ETH`);
  console.log(`Balance:  ${ethers.formatEther(balance)} ETH`);
  if (balance <= price) {
    throw new Error(`Insufficient Sepolia ETH. Need more than ${ethers.formatEther(price)} plus gas.`);
  }

  // The same secret must be used for both halves, so it only ever lives in this
  // process. A crash between commit and register means waiting out
  // maxCommitmentAge and starting over, which costs only the commit gas.
  const secret = ethers.hexlify(ethers.randomBytes(32));
  const registration = {
    label,
    owner: signer.address,
    duration,
    secret,
    resolver: PUBLIC_RESOLVER,
    data: [],
    reverseRecord: 0,
    referrer: ethers.ZeroHash,
  };

  const commitment = await controller.makeCommitment(registration);
  console.log(`\nCommitment: ${commitment}`);
  const commitTx = await controller.commit(commitment);
  console.log(`  commit tx ${commitTx.hash}`);
  await commitTx.wait();

  const minAge = await controller.minCommitmentAge();
  const waitMs = Number(minAge) * 1000 + 15_000; // pad past the boundary
  console.log(`  waiting ${Math.round(waitMs / 1000)}s for minCommitmentAge (${minAge}s)…`);
  await sleep(waitMs);

  // Overpay slightly; the controller refunds the difference. Guards against the
  // premium moving between the quote and the reveal.
  const value = (price * 110n) / 100n;
  const registerTx = await controller.register(registration, { value });
  console.log(`  register tx ${registerTx.hash}`);
  const receipt = await registerTx.wait();
  console.log(`  confirmed in block ${receipt.blockNumber}`);

  const registry = new ethers.Contract(
    "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
    ["function owner(bytes32) view returns (address)"],
    ethers.provider
  );
  const owner = await registry.owner(ethers.namehash(parentName));
  console.log(`\n${parentName} registry owner: ${owner}`);
  console.log(
    owner.toLowerCase() === "0x0635513f179d50a207757e05759cbd106d7dfce8"
      ? `  (wrapped — expected; ens-sepolia-proof.js handles the NameWrapper path)`
      : `  (unwrapped)`
  );
  console.log(`\nNext: npx hardhat run scripts/ens-sepolia-proof.js --network sepolia`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
