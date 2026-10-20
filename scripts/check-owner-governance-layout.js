#!/usr/bin/env node
import fs from "node:fs";
import assert from "node:assert/strict";

const root = process.argv[2] ?? "forge-out";
const {storageLayout: layout} = JSON.parse(fs.readFileSync(`${root}/DegenerusOwnerGovernance.sol/DegenerusOwnerGovernance.json`));
assert.ok(layout?.types, "Build with storageLayout output before checking owner governance packing");
assert.equal(layout.types[layout.storage.find(field => field.label === "proposalCount").type].label, "uint32");
function check(mapping, bytes, expected) {
  const entry = layout.storage.find(field => field.label === mapping);
  const struct = layout.types[layout.types[entry.type].value];
  assert.equal(Number(struct.numberOfBytes), bytes, `${mapping}: struct size`);
  assert.deepEqual(struct.members.map(field => [field.label, Number(field.slot), field.offset, layout.types[field.type].label]), expected);
}
check("positions", 64, [
  ["amount", 0, 0, "uint128"], ["proposalId", 0, 16, "uint32"], ["assignedBlock", 0, 20, "uint40"], ["depositBlock", 0, 25, "uint40"],
  ["votingDelegate", 1, 0, "address"],
]);
check("_proposals", 128, [
  ["proposer", 0, 0, "address"], ["value", 0, 20, "uint96"],
  ["target", 1, 0, "address"], ["expiresAt", 1, 20, "uint40"], ["recentBlock", 1, 25, "uint40"], ["executed", 1, 30, "bool"],
  ["lockedWeight", 2, 0, "uint128"], ["recentWeight", 2, 16, "uint128"],
  ["dataHash", 3, 0, "bytes32"],
]);
console.log("Owner governance packing verified: Position 2 slots; Proposal 4 slots; all offsets/types pinned.");
