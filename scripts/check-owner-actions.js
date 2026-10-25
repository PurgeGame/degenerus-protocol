#!/usr/bin/env node
// Typed selector/ABI and source-gate coverage for the immutable owner surface.
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { Interface } from "ethers";

const root = process.argv[2] ?? "forge-out";
const targets = {
  VAULT: "DegenerusVault", ADMIN: "DegenerusAdmin", GAME: "DegenerusGame",
  WWXRP: "WWXRP", CRAPS: "CrapsBattle", GNRUS: "GNRUS", ICONS_32: "Icons32Data",
  DEITY_PASS: "DegenerusDeityPass", RECORD_BOUNTY: "DegenerusRecordBounty",
  AFKING_SUB_TOKEN: "AFKingSubscriptionToken",
};
const source = fs.readFileSync("contracts/libraries/OwnerActions.sol", "utf8");
const branches = [...source.matchAll(/if \(target == ContractAddresses\.(\w+)\) \{([\s\S]*?)\n        \}/g)];
assert.deepEqual(branches.map(([, target]) => target).sort(), Object.keys(targets).sort());
let count = 0;
for (const [, target, body] of branches) {
  const name = targets[target];
  const {abi} = JSON.parse(fs.readFileSync(path.join(root, `${name}.sol`, `${name}.json`)));
  const iface = new Interface(abi);
  const methods = new Set();
  const selectors = new Set();
  for (const [, type, method] of body.matchAll(/(\w+)\.(\w+)\.selector/g)) {
    // GameFacade is the profile-independent external surface of the Game; JackpotBattle holds the Craps owner calls.
    assert.ok(type === name || (target === "GAME" && type === "GameFacade") || (target === "CRAPS" && type === "JackpotBattle"),
      `${target}: selector from wrong ABI`);
    const f = iface.getFunction(method);
    assert.ok(f && !["view", "pure"].includes(f.stateMutability), `${target}: missing mutable method ${method}`);
    assert.ok(!selectors.has(f.selector), `${target}: duplicate/colliding selector ${method}`);
    selectors.add(f.selector); methods.add(method); ++count;
  }
  for (const f of iface.fragments.filter(f => f.type === "function" && !methods.has(f.name))) {
    assert.ok(!selectors.has(f.selector), `${target}: excluded selector collision ${f.name}`);
  }
  // Discover direct public gates. Delegated facades are checked against their module source below.
  for (const file of [name, ...(target === "GAME" ? ["modules/GameFacade", "modules/DegenerusGameAdvanceModule", "modules/DegenerusGameMintModule"] : []),
    ...(target === "CRAPS" ? ["JackpotBattle"] : [])]) {
    const text = fs.readFileSync(`contracts/${file}.sol`, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
    for (const m of text.matchAll(/function\s+(\w+)\s*\([^)]*\)[^{;]*\{/g)) {
      if (!/\b(public|external)\b/.test(m[0]) || /\b(view|pure)\b/.test(m[0])) continue;
      let depth = 1, end = m.index + m[0].length;
      for (; depth && end < text.length; ++end) { if (text[end] === "{") ++depth; if (text[end] === "}") --depth; }
      const fn = text.slice(m.index, end);
      if (/\b(onlyOwner|onlyVaultOwner|_requireVaultOwner|_authorizeWrite|_compAllowance|_isVaultOwner)\b|\.isVaultOwner\(/.test(fn)) {
        assert.ok(methods.has(m[1]), `${target}: owner gate not executable: ${file}.${m[1]}`);
      }
    }
  }
}
for (const forbidden of ["burnEth", "burnCoin", "approve", "transfer", "transferFrom", "vote"]) {
  assert.ok(!source.includes(`.${forbidden}.selector`), `Forbidden owner selector: ${forbidden}`);
}
console.log(`${count} owner selectors checked across ${branches.length} pinned targets; discovered owner gates covered.`);
