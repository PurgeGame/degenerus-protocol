import test from "node:test";
import assert from "node:assert/strict";
import {transactionIntrinsicGas, framesMatching, assertRequiredPasses, driveUntilRequest, driveUntilReadComplete} from "./lib/fork-probe-utils.js";

test("intrinsic gas excludes the supplied callback frame", () => {
  assert.equal(transactionIntrinsicGas("0x0001ff00"), 21040n);
  assert.equal(300000n + transactionIntrinsicGas("0x00") - transactionIntrinsicGas("0x00"), 300000n);
  assert.throws(() => transactionIntrinsicGas("0x0"));
});
test("mandatory WARN, SKIP and missing probes fail closed", () => {
  for (const status of ["WARN", "SKIP", "FAIL"]) assert.throws(() => assertRequiredPasses([{id:"AFK",status}], ["AFK"]));
  assert.throws(() => assertRequiredPasses([], ["AFK"]));
  assertRequiredPasses([{id:"AFK",status:"PASS"}], ["AFK"]);
});
test("selector drives preparation and maintenance before a request exists", async () => {
  let i = 0;
  const actions = [15,16,17];
  const result = await driveUntilRequest({action:async()=>actions[i],step:async()=>({id:++i===3?7:0}),requestFrom:r=>r.id||null});
  assert.deepEqual(result.actions, actions);
  assert.equal(result.request, 7);
});
test("unlock does not terminate unfinished AFK, box, bet, or certification work", async () => {
  let i = 0;
  const actions = [3,4,7,8,9,10,11,12,13,14];
  const result = await driveUntilReadComplete({complete:async()=>i===actions.length,action:async()=>actions[i],step:async()=>{++i;return{};},requestFrom:()=>null,fulfill:async()=>assert.fail()});
  assert.deepEqual(result, actions);
});
test("successor request during drain is fulfilled locally and still drained", async () => {
  let i=0, delivered=0;
  const result = await driveUntilReadComplete({complete:async()=>i===2,action:async()=>i===0?14:3,step:async()=>({id:++i===1?99:0}),requestFrom:r=>r.id||null,fulfill:async id=>{assert.equal(id,99);++delivered;}});
  assert.deepEqual(result,[14,3]);assert.equal(delivered,1);
});
test("waiting and no-progress bounds fail", async () => {
  await assert.rejects(driveUntilRequest({action:async()=>2,step:async()=>assert.fail(),requestFrom:()=>null}));
  await assert.rejects(driveUntilReadComplete({complete:async()=>false,action:async()=>9,step:async()=>({}),requestFrom:()=>null,fulfill:async()=>{},maximum:2}));
});
test("nested frame lookup requires actual transferSharesFrom child", () => {
  const frame={input:"pull",calls:[{input:"delegate",calls:[{input:"transferSharesFrom",gas:"0x123"}]}]};
  assert.equal(framesMatching(frame,x=>x.input==="transferSharesFrom").length,1);
  assert.equal(framesMatching(frame,x=>x.input==="absent").length,0);
});
