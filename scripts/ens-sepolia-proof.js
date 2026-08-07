// End-to-end ENS proof on L1 Sepolia — deploy a probe, wire both directions,
// and confirm the name renders the way MetaMask will render it.
//
// WHY SEPOLIA AND NOT THE BASE SEPOLIA TESTNET:
//   1. MetaMask's @metamask/ens-controller enables ENS only for the chain ids in
//      DEFAULT_ENS_NETWORK_MAP: 1, 3, 4, 5, 17000, 11155111. Base Sepolia
//      (84532) is absent, so MetaMask never attempts a lookup there at all.
//   2. Base Sepolia's Basenames stack is broken for reverse records anyway: the
//      registry grants 80002105.reverse to 0xa0A8401E…dCd7 while the resolver
//      only accepts setName from 0x876eF94c…841f, so the registrar's write
//      reverts inside the resolver. Base mainnet has both set to 0x79EA9601…,
//      which is why it works there and not on their testnet.
//
// This script touches nothing in the protocol deploy. It proves the mechanism
// the 15 production constructors rely on, using the same call, on a chain where
// the result is actually visible.
//
// Prerequisite (one manual step): own the parent name on Sepolia. Register it
// at https://app.ens.domains with the wallet set to Sepolia. degenerus.eth was
// confirmed available there. The commit/reveal flow is far less error-prone in
// the ENS app than scripted.
//
// Required env:
//   SEPOLIA_RPC_URL (or RPC_URL), DEPLOYER_PRIVATE_KEY
// Optional env:
//   ENS_PARENT_NAME       default "degenerus.eth"
//   ENS_LABEL             default "game"
//   ENS_PUBLIC_RESOLVER   default: parent's resolver, else registrar default
//
// Usage: npx hardhat run scripts/ens-sepolia-proof.js --network sepolia

import hre from "hardhat";
import { forwardConfirmedName } from "./lib/ensForwardConfirmed.js";

const SEPOLIA_CHAIN_ID = 11155111n;
const REGISTRY = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";
const REVERSE_REGISTRAR = "0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6";
// app.ens.domains wraps names by default, so a name registered through the UI
// reports the NameWrapper as its registry owner and subnodes must be created
// through the wrapper instead of the registry. Verified on Sepolia: test.eth,
// alice.eth and ens.eth all show this owner.
const NAME_WRAPPER = "0x0635513f179D50A207757E05759CbD106d7dFcE8";
const ADDR_INTERFACE_ID = "0x3b3b57de";

const REGISTRY_ABI = [
  "function owner(bytes32) view returns (address)",
  "function resolver(bytes32) view returns (address)",
  "function setSubnodeRecord(bytes32,bytes32,address,address,uint64) external",
];
const NAME_WRAPPER_ABI = [
  "function ownerOf(uint256) view returns (address)",
  "function getData(uint256) view returns (address owner, uint32 fuses, uint64 expiry)",
  "function setSubnodeRecord(bytes32,string,address,address,uint64,uint32,uint64) external returns (bytes32)",
];
const RESOLVER_ABI = [
  "function setAddr(bytes32,address) external",
  "function addr(bytes32) view returns (address)",
  "function supportsInterface(bytes4) view returns (bool)",
];

async function main() {
  const { ethers } = hre;

  const net = await ethers.provider.getNetwork();
  if (net.chainId !== SEPOLIA_CHAIN_ID) {
    throw new Error(
      `Wrong network: chainId ${net.chainId}. This proof only means anything on ` +
        `L1 Sepolia (11155111) — see the header for why Base Sepolia cannot work.`
    );
  }

  const parentName = process.env.ENS_PARENT_NAME || "degenerus.eth";
  const label = process.env.ENS_LABEL || "game";
  const fullName = `${label}.${parentName}`;

  const [signer] = await ethers.getSigners();
  const registry = new ethers.Contract(REGISTRY, REGISTRY_ABI, signer);
  const parentNode = ethers.namehash(parentName);

  const parentOwner = await registry.owner(parentNode);
  if (parentOwner === ethers.ZeroAddress) {
    throw new Error(
      `${parentName} is unregistered on Sepolia. Register it at ` +
        `https://app.ens.domains with your wallet switched to Sepolia, then rerun.`
    );
  }

  // Wrapped and unwrapped names create subnodes through different contracts.
  const wrapped = parentOwner.toLowerCase() === NAME_WRAPPER.toLowerCase();
  const nameWrapper = new ethers.Contract(NAME_WRAPPER, NAME_WRAPPER_ABI, signer);
  let parentExpiry = 0n;

  if (wrapped) {
    const wrapperOwner = await nameWrapper.ownerOf(BigInt(parentNode));
    if (wrapperOwner.toLowerCase() !== signer.address.toLowerCase()) {
      throw new Error(
        `${parentName} is wrapped, and signer ${signer.address} is not its ` +
          `NameWrapper owner (${wrapperOwner}). Register or transfer it to the ` +
          `deployer wallet, then rerun.`
      );
    }
    ({ expiry: parentExpiry } = await nameWrapper.getData(BigInt(parentNode)));
  } else if (parentOwner.toLowerCase() !== signer.address.toLowerCase()) {
    throw new Error(
      `Signer ${signer.address} does not control ${parentName} on Sepolia ` +
        `(registry owner is ${parentOwner}). Subdomains require the registry owner.`
    );
  }

  // Forward records need a resolver exposing addr(). Prefer an explicit
  // override, then the parent's own resolver, then the registrar's default.
  let resolverAddr = process.env.ENS_PUBLIC_RESOLVER;
  if (!resolverAddr) {
    resolverAddr = await registry.resolver(parentNode);
  }
  if (!resolverAddr || resolverAddr === ethers.ZeroAddress) {
    const rr = new ethers.Contract(
      REVERSE_REGISTRAR,
      ["function defaultResolver() view returns (address)"],
      signer
    );
    resolverAddr = await rr.defaultResolver();
  }
  const resolver = new ethers.Contract(resolverAddr, RESOLVER_ABI, signer);
  const supportsAddr = await resolver.supportsInterface(ADDR_INTERFACE_ID).catch(() => false);
  if (!supportsAddr) {
    throw new Error(
      `Resolver ${resolverAddr} does not implement addr(bytes32) — forward ` +
        `records would be unreadable. Set ENS_PUBLIC_RESOLVER to a PublicResolver.`
    );
  }

  console.log(`Network:   sepolia (${net.chainId})`);
  console.log(`Signer:    ${signer.address}`);
  console.log(`Parent:    ${parentName} (${wrapped ? "wrapped" : "unwrapped"})`);
  console.log(`Resolver:  ${resolverAddr}`);
  console.log(`Claiming:  ${fullName}\n`);

  // 1. Deploy the probe. Its constructor makes the same raw setName call the
  //    15 production contracts make, but records whether it succeeded.
  const Probe = await ethers.getContractFactory("EnsReverseProbe");
  const probe = await Probe.deploy(REVERSE_REGISTRAR, fullName);
  await probe.waitForDeployment();
  const probeAddr = await probe.getAddress();
  const deployTx = probe.deploymentTransaction();
  const receipt = await deployTx.wait();
  console.log(`Deployed probe at ${probeAddr}`);
  console.log(`  deploy gas used: ${receipt.gasUsed}`);

  // 2. This is the assertion production cannot make about itself.
  const ensOk = await probe.ensOk();
  if (!ensOk) {
    throw new Error(
      `setName REVERTED inside the constructor. The reverse record does not ` +
        `exist. In production this failure is silent (the result is discarded ` +
        `with \`ok;\`) and unrecoverable, since the call is constructor-only ` +
        `with no setter. Check ENS_REVERSE_REGISTRAR.`
    );
  }
  console.log(`  reverse record written: yes\n`);

  // 3. Forward record. Without this the reverse name displays nowhere, because
  //    every consumer forward-verifies before trusting a reverse claim.
  const labelHash = ethers.keccak256(ethers.toUtf8Bytes(label));
  const node = ethers.namehash(fullName);

  const existing = await resolver.addr(node).catch(() => ethers.ZeroAddress);
  if (existing.toLowerCase() === probeAddr.toLowerCase()) {
    console.log(`Forward record already points at the probe.`);
  } else {
    if (wrapped) {
      // Wrapper takes the label as a string, plus fuses and expiry. Inheriting
      // the parent's expiry keeps the subname alive as long as the parent;
      // fuses stay 0 so nothing is burned irreversibly on a throwaway probe.
      const t1 = await nameWrapper.setSubnodeRecord(
        parentNode, label, signer.address, resolverAddr, 0, 0, parentExpiry
      );
      await t1.wait();
    } else {
      const t1 = await registry.setSubnodeRecord(
        parentNode, labelHash, signer.address, resolverAddr, 0
      );
      await t1.wait();
    }
    const t2 = await resolver.setAddr(node, probeAddr);
    await t2.wait();
    console.log(`Forward record set: ${fullName} -> ${probeAddr}`);
  }

  // 4. Round trip, the same rule MetaMask applies.
  const { name, reason } = await forwardConfirmedName(ethers.provider, REGISTRY, probeAddr);
  if (name !== fullName) {
    throw new Error(`Round trip failed: ${reason}`);
  }

  console.log(`\nForward-confirmed: ${probeAddr} -> ${name}`);
  console.log(`\nTo see it in MetaMask (switch the network to Sepolia first):`);
  console.log(`  Forward — paste ${fullName} into the send field. It resolves to`);
  console.log(`  ${probeAddr}. This is deterministic: it is the same registry read`);
  console.log(`  performed above.`);
  console.log(`  Reverse — MetaMask surfaces reverse-resolved names through its petnames`);
  console.log(`  feature in confirmation screens and the activity log. That path depends on`);
  console.log(`  MetaMask's UI version, so treat the forward check as the proof and the`);
  console.log(`  reverse display as the thing you are eyeballing.`);
  console.log(`\nEither way the on-chain state is now exactly what a mainnet deploy produces,`);
  console.log(`via the same constructor call all 15 protocol contracts make.`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
