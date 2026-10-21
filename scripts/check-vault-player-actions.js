#!/usr/bin/env node
// Check the fixed allowlist against compiled ABIs. Newly added player methods must be
// routed or explicitly classified here; stale/mistyped allowed signatures fail as well.
// Run after the focused Foundry build: node scripts/check-vault-player-actions.js [forge-out]
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { Interface } from "ethers";

const root = process.argv[2] ?? "forge-out";
const contracts = {
  GAME: "DegenerusGame", COINFLIP: "Coinflip", COIN: "FLIP", CRAPS: "CrapsBattle",
  PARIMUTUEL: "DegenerusParimutuel", WWXRP: "WWXRP", SDGNRS: "sDGNRS", DGNRS: "DGNRS",
  AFFILIATE: "DegenerusAffiliate", JACKPOTS: "DegenerusJackpots",
  AFKING_SUB_TOKEN: "AFKingSubscriptionToken", GNRUS: "GNRUS",
  LINK_TOKEN: "MockLinkToken", // Test ERC677 ABI; production target is the pinned LINK token.
};
// These are not missing player controls. Explicit owner controls are called by the
// DGVE owner directly; token sweeps and Vault-only mints retain their existing wrappers.
const excluded = {
  GAME: [
    // Internal settlement, registration/cache maintenance, bootstrap and privileged hooks.
    "adminStakeEthForStEth", "adminSwapEthForStEth", "consumeCoinflipBoon", "consumeDecimatorBoon",
    "creditMiddayRng", "creditRedemptionDirect", "drainAffiliateBases", "emitDailyWinningTraits",
    "floorAfkingStreakBase", "initProtocolDeity", "minerAction", "payRecordSdgnrs",
    "playerActivityScoreCached", "playerActivityScoreCachedById", "pullAfkingSteth",
    "rawFulfillRandomWords", "recordAfkingSecondary", "recordDecBurn", "registerWallet",
    "registerWalletIdentity", "resolveRedemptionLootbox", "retryRng", "runBafJackpot",
    "runDecimatorJackpot", "runTerminalJackpotWork", "setCrapsRngPending",
    "updateVrfCoordinatorAndSub", "wireVrf",
    "spendDegenesis", // Dedicated Vault restricted-budget control.
    "borrow", "repay", // The Vault never takes loans.
    // Direct DGVE-owner controls.
    "raiseSmurfBaseAllowance", "setLootboxRngThreshold", "setMiddayMaxBasefee", "setThanosLevel",
  ],
  COINFLIP: [
    "armBafDraw", "armDiceRunRecord", "armRecord", "claimCoinflipsFromFlip",
    "consumeCoinflipsForBurn", "consumeFlipBacking", "creditFlip", "creditFlipBatch",
    "creditFlipPair", "creditSdgnrsBacking", "fundRecordPool", "processCoinflipGap",
    "processCoinflipPayouts", "redeemableFlipBacking", "sweepAccountCoinflips", "withdrawRedeemedFlip",
  ],
  COIN: [
    "approve", "transfer", "transferFrom", "vaultMintTo", // DGVF backing must use share redemption.
    "autoDecimatorBurn", "burnCoin", "burnCoinForCraps", "burnForCoinflip", "creditCrapsComps",
    "mintForGame", "tombstoneAtGameOver",
  ],
  CRAPS: [
    "vaultComp", "donate", // Dedicated Vault batch/delegate-budget controls.
    "creditPasses", "deliverPasses", "resolveRngSlot", "runCrapsMaintenance", "runDailyBattleWork",
    "setBattleCreator", // DGVE owner calls this directly, including to authorize the Vault.
  ],
  PARIMUTUEL: ["recordGrowth", "runGrowthWork"],
  WWXRP: [
    "approve", "transfer", "transferFrom", "vaultMintTo", // Existing sweepToken / wwxrpMint.
    "burnForAccount", "burnForGame", "consumeBoon", "creditPrize", "mintPrize", "resolveIncinerator",
    "setGameMintScale", "setTrustedMinter", // Direct DGVE-owner controls.
  ],
  SDGNRS: [
    "burnAtGameOver", "burnForLiquidation", "closeRedemptionBatch", "depositSteth",
    "recycleCentury", "resolveTerminalRedemptions", "runRedemptionWork",
    "transferFromPool", "wrapperTransferTo",
    "gameAdvance", // Anyone can trigger this externally; bounty belongs to sDGNRS, not the caller.
  ],
  DGNRS: ["unwrapTo", "approve", "transfer", "transferFrom", "burnForSdgnrs"],
  AFFILIATE: ["payAffiliate", "payAffiliateCombined", "referSmurf"],
  JACKPOTS: ["beginBaf", "finalizeBaf", "markBafSkipped", "recordBafFlip"],
  AFKING_SUB_TOKEN: [
    "consumeSeat", "mintSeatFor", "setRenderer", "vaultMintSeats",
    "transferFrom", "safeTransferFrom", // The Vault moves seats with sweepNft.
  ],
  GNRUS: [
    "burnAtGameOver", "onFinalSweep", "pickCharity",
    "setCharity", "sweepResidualToVault", "vaultRedeemFor", // Direct DGVE-owner controls.
  ],
  LINK_TOKEN: ["approve", "transfer", "transferFrom", "mint"],
};
const source = fs.readFileSync("contracts/libraries/VaultPlayerActions.sol", "utf8");
const branches = [...source.matchAll(/if \(target == ContractAddresses\.(\w+)\) \{([\s\S]*?)\n        \}/g)];
assert.deepEqual(branches.map(([, target]) => target).sort(), Object.keys(contracts).sort());
const selectorInterfaces = new Map();
function selectorSignature(name, method) {
  if (!selectorInterfaces.has(name)) {
    const artifact = JSON.parse(fs.readFileSync(path.join(root, name.startsWith("IVault") ? "IVaultPlayerActions.sol" : name === "ILinkTokenLike" ? "DegenerusAdmin.sol" : `${name}.sol`, `${name}.json`), "utf8"));
    selectorInterfaces.set(name, new Interface(artifact.abi));
  }
  return selectorInterfaces.get(name).getFunction(method).format("sighash");
}
let count = 0;
for (const [, target, body] of branches) {
  const name = contracts[target];
  assert.ok(name, `Unclassified target ${target}`);
  const artifact = JSON.parse(fs.readFileSync(path.join(root, `${name}.sol`, `${name}.json`), "utf8"));
  const iface = new Interface(artifact.abi);
  const mutable = iface.fragments.filter(f => f.type === "function" && !["pure", "view"].includes(f.stateMutability));
  const signatures = new Set(mutable.map(f => f.format("sighash")));
  const allowed = new Set([...body.matchAll(/(\w+)\.(\w+)\.selector/g)].map(([, name, method]) => selectorSignature(name, method)));
  for (const signature of allowed) assert.ok(signatures.has(signature), `${target}: invalid allowed ABI ${signature}`);
  for (const f of mutable) {
    const signature = f.format("sighash");
    assert.ok(allowed.has(signature) || excluded[target].includes(f.name), `${target}: unreviewed player surface ${signature}`);
    if (!allowed.has(signature)) {
      assert.ok(![...allowed].some(s => iface.getFunction(s).selector === f.selector), `${target}: excluded selector collision ${signature}`);
    }
  }
  for (const name of excluded[target]) assert.ok(mutable.some(f => f.name === name), `${target}: stale exclusion ${name}`);
  count += allowed.size;
}
const vault = JSON.parse(fs.readFileSync(path.join(root, "DegenerusVault.sol", "DegenerusVault.json"), "utf8"));
const vaultIface = new Interface(vault.abi);
const removedWrappers = [
  "gameDepositAfkingFunding", "recoverAfkingFunding", "gameAdvance", "gamePurchase",
  "gamePurchaseTicketsFlip", "gameClaimWinnings", "gameSweepAccounts", "gameDegeneretteBet",
  "gameSetOperatorApproval", "crapsSetPreferredBoard", "crapsEnterBattle", "crapsAmendSlip",
  "coinDepositCoinflip", "coinClaimCoinflips", "coinDecimatorBurn", "coinSetAutoRebuy",
  "coinSetAutoRebuyTakeProfit", "afkingSeatTransfer", "afkingSeatRestyle", "sdgnrsBurn",
  "dgnrsBurnWrapped", "sdgnrsClaimRedemption",
];
for (const name of removedWrappers) assert.equal(vaultIface.getFunction(name), null, `Duplicate wrapper returned: ${name}`);
for (const name of ["playerAction", "spendDegenesis", "dgnrsUnwrapTo", "crapsComp", "crapsCompDonate", "wwxrpMint", "afkingSeatMint", "burnCoin", "burnEth"]) {
  assert.ok(vaultIface.getFunction(name), `Missing Vault control: ${name}`);
}
const runtime = (vault.deployedBytecode.object.replace(/^0x/, "").length) / 2;
assert.ok(runtime <= 24_576, `Vault runtime exceeds EIP-170: ${runtime}`);
console.log(`${count} player signatures checked across ${branches.length} targets; all other mutable methods classified.`);
console.log(`Vault runtime: ${runtime} / 24576 bytes.`);
