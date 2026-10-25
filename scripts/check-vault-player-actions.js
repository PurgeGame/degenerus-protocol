#!/usr/bin/env node
// Check the fixed allowlist against compiled ABIs. Newly added player methods must be
// routed or explicitly classified here; stale/mistyped allowed signatures fail as well.
// Run after the focused Foundry build: node scripts/check-vault-player-actions.js [forge-out]
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { Interface } from "ethers";

const root = process.argv[2] ?? "forge-out";
// Mangled selector suffixes do not change the role of an excluded internal hook.
// Allowed actions below still require exact signatures and collision checks.
const canonical = name => name.replace(/_g\d+$/, "");
const contracts = {
  GAME: "DegenerusGame", COINFLIP: "Coinflip", COIN: "FLIP", CRAPS: "CrapsBattle",
  PARIMUTUEL: "DegenerusParimutuel", WWXRP: "WWXRP", SDGNRS: "sDGNRS", DGNRS: "DGNRS",
  AFFILIATE: "DegenerusAffiliate", JACKPOTS: "DegenerusJackpots",
  AFKING_SUB_TOKEN: "AFKingSubscriptionToken", GNRUS: "GNRUS",
  ADMIN: "DegenerusAdmin",
};
// These are not missing player controls. Explicit owner controls are called by the
// DGVE owner directly; token sweeps and Vault-only mints retain their existing wrappers.
const excluded = {
  GAME: [
    // Internal settlement, registration/cache maintenance, bootstrap and privileged hooks.
    "adminStakeEthForStEth", "adminSwapEthForStEth", "consumeCoinflipBoon", "consumeDecimatorBoon",
    "creditMiddayRng", "creditRedemptionDirect", "drainAffiliateBases", "emitDailyWinningTraits",
    "floorAfkingStreakBase", "initProtocolDeity", "minerAction", "payRecordSdgnrs",
    "playerActivityScoreCached", "playerActivityScoreCachedById_g975", "pullAfkingSteth",
    "rawFulfillRandomWords", "recordAfkingSecondary_g3316", "recordDecBurn", "registerWallet_g9539",
    "registerWalletIdentity", "resolveRedemptionLootbox", "retryRng", "runBafJackpot",
    "runDecimatorJackpot", "runTerminalJackpotWork", "setCrapsRngPending",
    "updateVrfCoordinatorAndSub", "initVrf",
    "spendDegenesis", // Dedicated Vault restricted-budget control.
    "borrow", "clearDebtNow", // The Vault never takes loans.
    // Direct DGVE-owner controls.
    "raiseSmurfBaseAllowance", "setLootboxRngThreshold", "setMiddayMaxBasefee", "setThanosLevel",
  ],
  COINFLIP: [
    "armBafDraw", "armDiceRunRecord", "armRecord", "claimCoinflipsFromFlip",
    "consumeCoinflipsForBurn", "consumeFlipBacking", "creditFlip", "creditFlipBatch",
    "creditFlipPair", "creditSdgnrsBacking", "fundRecordPool", "onDailyRequest",
    "processCoinflipPayouts", "redeemableFlipBacking", "sweepAccountCoinflips", "withdrawRedeemedFlip",
  ],
  COIN: [
    "approve", "transfer", "transferFrom", "vaultMintTo", // DGVF backing must use share redemption.
    "autoDecimatorBurn", "burnCoin", "burnCoinForCraps_g292454", "burnForCoinflip", "creditCrapsComps_g37225",
    "mintForGame_g152734", "tombstoneAtGameOver",
  ],
  CRAPS: [
    // Consolidated JackpotBattle settlement: Game-only or table self-call-only.
    "admitCustom", "appendJackpotBattle", "finalizeBattle", "lockJackpotBattle", "payBattlePot",
    "prepareJackpotBattle", "registerRngSlot", "runCrapsMaintenance", "runCrapsReadWork",
    "runDailyBattleWork", "settleHighRollerReserve",
    "vaultComp", "donate", // Dedicated Vault batch/delegate-budget controls.
    "creditPasses", "deliverPasses", "resolveRngSlot_g1079",
    "setBattleCreator", // DGVE owner calls this directly, including to authorize the Vault.
  ],
  // Affiliate and Quests hooks: Game, token or Parimutuel authorized. A standalone Affiliate
  // exposes the first set; the Coinflip shell of the profile that hosts it adds both.
  AFFILIATE: ["payAffiliate", "payAffiliateCombined", "referSmurf"],
  QUESTS_SHELL: [
    "awardQuestStreakBonus", "awardQuestStreakShield", "beginAfking", "finalizeAfking",
    "handleAffiliate", "handleDecimator", "handleDegenerette", "handleFlip", "handleFoilPurchase",
    "handlePurchase", "recordCrapsAction", "recordGrowthBet", "rollDailyQuest", "rollLevelQuest",
  ],
  PARIMUTUEL: ["recordGrowth", "runGrowthWork"],
  WWXRP: [
    "approve", "transfer", "transferFrom", "vaultMintTo", // Existing sweepToken / wwxrpMint.
    "burnForAccount", "burnForGame", "consumeBoon", "creditPrize", "mintPrize", "resolveIncinerator",
    "setGameMintScale", "setTrustedMinter", // Direct DGVE-owner controls.
  ],
  SDGNRS: [
    "burnAtGameOver", "burnForLiquidation", "closeRedemptionBatch_g165517", "depositSteth",
    "recycleCentury", "resolveTerminalRedemptions", "runRedemptionWork",
    "transferFromPool_g106128", "wrapperTransferTo",
    "gameAdvance", // Anyone can trigger this externally; bounty belongs to sDGNRS, not the caller.
  ],
  DGNRS: ["unwrapTo", "approve", "transfer", "transferFrom", "burnForSdgnrs"],
  JACKPOTS: ["beginBafOn", "finalizeBaf", "markBafSkippedAt", "recordBafFlip"],
  AFKING_SUB_TOKEN: [
    "consumeSeat", "mintSeatFor", "setRenderer", "vaultMintSeats",
    "transferFrom", "safeTransferFrom", // The Vault moves seats with sweepNft.
  ],
  GNRUS: [
    "burnAtGameOver", "onFinalSweep", "pickCharity",
    "setCharity", "sweepResidualToVault", "vaultRedeemFor", // Direct DGVE-owner controls.
  ],
  ADMIN: ["propose", "vote", "retryGameRng", "retrySubCancel", "shutdownVrf", "swapGameEthForStEth"],
};
const source = fs.readFileSync("contracts/libraries/VaultPlayerActions.sol", "utf8");
const branches = [...source.matchAll(/if \(target == ContractAddresses\.(\w+)\) \{([\s\S]*?)\n        \}/g)];
assert.deepEqual(branches.map(([, target]) => target).sort(), Object.keys(contracts).sort());
const selectorInterfaces = new Map();
function selectorSignature(name, method) {
  if (!selectorInterfaces.has(name)) {
    const artifact = JSON.parse(fs.readFileSync(path.join(root, name.startsWith("IVault") ? "IVaultPlayerActions.sol" : `${name}.sol`, `${name}.json`), "utf8"));
    selectorInterfaces.set(name, new Interface(artifact.abi));
  }
  return selectorInterfaces.get(name).getFunction(method).format("sighash");
}
const abiOf = name => new Interface(JSON.parse(fs.readFileSync(path.join(root, `${name}.sol`, `${name}.json`), "utf8")).abi);
const allowedOf = body => new Set([...body.matchAll(/(\w+)\.(\w+)\.selector/g)].map(([, name, method]) => selectorSignature(name, method)));
const mutableOf = iface => iface.fragments.filter(f => f.type === "function" && !["pure", "view"].includes(f.stateMutability));
// One profile hosts Affiliate (and Quests) inside Coinflip; the other deploys them standalone.
const sharedShell = mutableOf(abiOf(contracts.COINFLIP)).some(f => f.name === "createAffiliateCode");
const bodies = Object.fromEntries(branches.map(([, target, body]) => [target, body]));
let count = 0;
for (const [, target, body] of branches) {
  const name = sharedShell && target === "AFFILIATE" ? contracts.COINFLIP : contracts[target];
  assert.ok(name, `Unclassified target ${target}`);
  const iface = abiOf(name);
  const mutable = mutableOf(iface);
  const signatures = new Set(mutable.map(f => f.format("sighash")));
  const own = allowedOf(body);
  for (const signature of own) assert.ok(signatures.has(signature), `${target}: invalid allowed ABI ${signature}`);
  count += own.size;
  // The shared shell answers at one address: its allowlist and exclusions are the union.
  if (sharedShell && target === "AFFILIATE") continue;
  const merged = sharedShell && target === "COINFLIP";
  const allowed = merged ? new Set([...own, ...allowedOf(bodies.AFFILIATE)]) : own;
  const exclusions = merged ? [...excluded.COINFLIP, ...excluded.AFFILIATE, ...excluded.QUESTS_SHELL] : excluded[target];
  for (const f of mutable) {
    const signature = f.format("sighash");
    assert.ok(allowed.has(signature) || exclusions.some(name => canonical(name) === canonical(f.name)), `${target}: unreviewed player surface ${signature}`);
    if (!allowed.has(signature)) {
      assert.ok(![...allowed].some(s => iface.getFunction(s).selector === f.selector), `${target}: excluded selector collision ${signature}`);
    }
  }
  for (const name of exclusions) assert.ok(mutable.some(f => canonical(f.name) === canonical(name)), `${target}: stale exclusion ${name}`);
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
