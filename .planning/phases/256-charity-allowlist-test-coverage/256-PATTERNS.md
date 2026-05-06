# Phase 256: Charity Allowlist Test Coverage — Pattern Map

**Mapped:** 2026-05-06
**Files analyzed:** 4 (2 NEW, 2 MODIFIED)
**Analogs found:** 4 / 4

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `test/governance/CharityAllowlist.test.js` (NEW) | hardhat unit-test | request-response (impersonated game caller + EOA voter calls + custom-error reverts) | `test/unit/DegenerusCharity.test.js` | exact (same contract, same harness shape) |
| `test/helpers/charityFixture.js` (NEW) | helper module (factor) | utility (impersonate / fund / deploy wrapper) | `test/unit/DegenerusCharity.test.js` lines 26-116 (in-file helpers being extracted) + `test/helpers/deployFixture.js` (wrapped, not replaced) | exact (verbatim extraction) |
| `test/unit/DegenerusCharity.test.js` (MODIFIED) | hardhat unit-test (prune) | request-response | self (in-place prune) | self |
| `test/integration/CharityGameHooks.test.js` (MODIFIED) | hardhat integration-test (extend) | event-driven (real game flow drives `pickCharity` via `advanceGame` → VRF cycle) | self (extend existing `pickCharity fires at level transition` describe) | self |

## Pattern Assignments

### `test/governance/CharityAllowlist.test.js` (NEW)

**Analog:** `test/unit/DegenerusCharity.test.js` (the Governance describes are being deleted FROM this file and re-implemented in the new v33.0 shape in the new file).

**Imports pattern** — copy from `test/unit/DegenerusCharity.test.js:1-10`, adjust paths and add the new helper module:

```js
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  eth,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";
import {
  deployGNRUSFixture,
  impersonate,
  stopImpersonating,
  giveSDGNRS,
  setCharityAs,
  runLevelTransitionViaGame,
  POOL_REWARD,
} from "../helpers/charityFixture.js";
```

**Module-level constants pattern** — drop the v32 stale set, keep only what's still in scope, and add the v33 reason-code mirrors per CONTEXT `<specifics>`:

```js
const INITIAL_SUPPLY = hre.ethers.parseEther("1000000000000"); // 1T
const DISTRIBUTION_BPS = 200n;
const BPS_DENOM = 10_000n;
const LOCKED_SLOTS = 3;
const MAX_ACTIVE_SLOTS = 20;

// vote() reject reasons (mirror contracts/GNRUS.sol)
const REJECT_EMPTY_SLOT = 0;
const REJECT_ALREADY_VOTED = 1;
const REJECT_ZERO_WEIGHT = 2;

// pickCharity() reject reasons
const REJECT_LEVEL_NOT_ACTIVE = 0;
const REJECT_LEVEL_ALREADY_RESOLVED = 1;
```

**Top-level describe + per-section describe shape** — copy from `test/unit/DegenerusCharity.test.js:140-144`:

```js
describe("GNRUS Charity Allowlist (v33.0)", function () {
  describe("setCharity -- instant-apply branch", function () {
    it("...", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      // ...
    });
  });
});
```

**Custom-error revert pattern (no args)** — copy from `test/unit/DegenerusCharity.test.js:217-220`:

```js
await expect(
  charity.connect(voter1).burn(eth("0.5"))
).to.be.revertedWithCustomError(charity, "InsufficientBurn");
```

For Phase 256 use the v33 errors verbatim: `InvalidSlot`, `SlotAlreadyEmpty`, `SlotLocked`, `CapExceeded`, `Unauthorized`.

**Custom-error revert pattern WITH `withArgs(reasonCode)`** — pattern is established at `test/unit/GovernanceGating.test.js:329-331` and `test/unit/BurnieCoin.test.js:126`. For Phase 256 reason-code asserts (per D-256-VOTE-REJECT-01 / D-256-PICKCHARITY-REJECT-01):

```js
await expect(charity.connect(voter1).vote(slot))
  .to.be.revertedWithCustomError(charity, "VoteRejected")
  .withArgs(REJECT_ZERO_WEIGHT);

await expect(charity.connect(gameSigner).pickCharity(level + 5))
  .to.be.revertedWithCustomError(charity, "PickCharityRejected")
  .withArgs(REJECT_LEVEL_NOT_ACTIVE);
```

**Game-impersonation for unit-side `pickCharity` driver** — copy from `test/unit/DegenerusCharity.test.js:131-134` (the existing `runGovernanceCycle` tail) and the `pickCharity` describes at L628-635, L644-647, L662-665:

```js
const gameSigner = await impersonate(gameAddress);
const tx = await charity.connect(gameSigner).pickCharity(level);
await stopImpersonating(gameAddress);
```

For Phase 256 prefer the `runLevelTransitionViaGame(charity, gameAddress, level)` helper from `charityFixture.js` (D-256-HELPER-01) which encapsulates this 3-line dance.

**Event extraction pattern** — copy from `test/unit/DegenerusCharity.test.js:629-635`:

```js
const tx = await charity.connect(gameSigner).pickCharity(level);
const ev = await getEvent(tx, charity, "LevelResolved");
expect(ev.args.slot).to.equal(bestSlot);
expect(ev.args.recipient).to.equal(currentSlateRecipient);
expect(ev.args.gnrusDistributed).to.equal(expectedDist);
```

For multi-event captures (e.g., `CharityFlushed` per applied edit during a `pickCharity` flush — D-255-FLUSH-EVENT-01), use `getEvents` from `test/unit/DegenerusCharity.test.js:775-779`:

```js
const flushed = await getEvents(tx, charity, "CharityFlushed");
expect(flushed.length).to.equal(numAppliedEdits);
```

**Vault-owner gating pattern** — copy the implicit "deployer is vault owner" assumption from `test/unit/DegenerusCharity.test.js:622-624`, L743-744. For Phase 256 `setCharity` tests:

```js
// Positive: deployer (vault owner) succeeds
await charity.connect(deployer).setCharity(slot, recipient1.address);

// Negative: any non-vault-owner reverts Unauthorized
await expect(
  charity.connect(voter1).setCharity(slot, recipient1.address)
).to.be.revertedWithCustomError(charity, "Unauthorized");
```

**Conservation-style balance-delta pattern** — copy from `test/unit/DegenerusCharity.test.js:625-635` and `test/unit/DegenerusCharity.test.js:983` for the post-tx balance check:

```js
const unallocatedBefore = await charity.balanceOf(charityAddress);
const expectedDist = (unallocatedBefore * DISTRIBUTION_BPS) / BPS_DENOM;
// ... pickCharity call ...
expect(await charity.balanceOf(recipient1.address)).to.equal(expectedDist);
expect(await charity.balanceOf(charityAddress)).to.equal(unallocatedBefore - expectedDist);
```

**Gas measurement assertion (D-256-GAS-01 single regression guardrail)** — copy from `test/gas/AdvanceGameGas.test.js:1265` (the `expect(r.gasUsed).to.be.lt(16_000_000n)` shape). For Phase 256 the ceiling is the PLAN.md-derived value:

```js
const tx = await charity.connect(gameSigner).pickCharity(level);
const receipt = await tx.wait();
expect(receipt.gasUsed).to.be.lt(CEILING); // CEILING = PLAN.md theoretical worst case * 1.1
```

If the gas test is colocated in the governance file, no `recordGas` summary table is needed — that's an `AdvanceGameGas`-specific decoration. A single it-block with a single assertion suffices.

---

### `test/helpers/charityFixture.js` (NEW)

**Analog:** `test/unit/DegenerusCharity.test.js:26-116` (helpers being extracted verbatim) + `test/helpers/deployFixture.js` (wrapped, not replaced).

**Imports pattern** — mirror `test/helpers/deployFixture.js:1-12`:

```js
import hre from "hardhat";
import { deployFullProtocol } from "./deployFixture.js";
import { eth } from "./testUtils.js";

export const POOL_REWARD = 3;
```

**`impersonate` helper — copy verbatim from `test/unit/DegenerusCharity.test.js:26-36`:**

```js
export async function impersonate(address) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x56BC75E2D63100000", // 100 ETH
  ]);
  return hre.ethers.getSigner(address);
}
```

**`stopImpersonating` — copy verbatim from `test/unit/DegenerusCharity.test.js:38-43`:**

```js
export async function stopImpersonating(address) {
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [address],
  });
}
```

**`giveSDGNRS` — copy verbatim from `test/unit/DegenerusCharity.test.js:48-52`:**

```js
export async function giveSDGNRS(sdgnrs, gameAddress, recipient, amount) {
  const gameSigner = await impersonate(gameAddress);
  await sdgnrs.connect(gameSigner).transferFromPool(POOL_REWARD, recipient, amount);
  await stopImpersonating(gameAddress);
}
```

**`deployGNRUSFixture` — adapted from `test/unit/DegenerusCharity.test.js:57-116`. STRIP the v32 0.5%-threshold reasoning; tune voter amounts to v33 vote-weight scenarios per CONTEXT `<specifics>`.**

Existing v32 shape (lines 77-89 — what to drop):

```js
// Give voter1 and voter2 enough sDGNRS to be above 0.5% threshold.
// votingSupply starts at 0 (all tokens in pools/DGNRS/vault).
// ... [9 lines of v32 reasoning prose] ...
const voterAmount = eth("100");
const voter3Amount = eth("1"); // 1 / 201 = ~0.497% → below 0.5% threshold

await giveSDGNRS(sdgnrs, gameAddress, voter1.address, voterAmount);
await giveSDGNRS(sdgnrs, gameAddress, voter2.address, voterAmount);
await giveSDGNRS(sdgnrs, gameAddress, voter3.address, voter3Amount);
```

v33 replacement shape — voter weights tuned for tie-break, multi-slot, zero-weight test cases (per D-256-TIEBREAK-01 + D-256-MULTI-VOTE-01 + D-256-VOTE-REJECT-01):

```js
// v33: vote weight = sdgnrs balance / 1e18, no threshold, no bonus.
// voter1, voter2, voter3 sized for tie-break (equal weights) and
// multi-slot vote independence tests.
const voterAmount = eth("100");      // 100 sDGNRS → weight = 100
const voter3Amount = eth("200");     // 200 sDGNRS → weight = 200 (tie-break breaker)
const subUnitAmount = eth("0.5");    // < 1e18 → weight = 0 → REJECT_ZERO_WEIGHT

await giveSDGNRS(sdgnrs, gameAddress, voter1.address, voterAmount);
await giveSDGNRS(sdgnrs, gameAddress, voter2.address, voterAmount);
await giveSDGNRS(sdgnrs, gameAddress, voter3.address, voter3Amount);
// subUnitVoter funded only when explicitly needed by an it-block (kept off the default fixture
// to avoid polluting tie-break tests with extra voting weight).
```

**Returned shape — copy from `test/unit/DegenerusCharity.test.js:95-115`:**

```js
return {
  charity, charityAddress, sdgnrs, game, vault, mockSteth,
  deployer, voter1, voter2, voter3,
  recipient1, recipient2, recipient3, others,
  gameAddress, sdgnrsAddress, vaultAddress, stethAddress,
};
```

**`setCharityAs` (optional convenience per D-256-HELPER-01):**

```js
export async function setCharityAs(charity, signer, slot, recipient) {
  return charity.connect(signer).setCharity(slot, recipient);
}
```

**`runLevelTransitionViaGame` — encapsulates the impersonate-game / pickCharity / stopImpersonate dance (copy from `test/unit/DegenerusCharity.test.js:131-134`):**

```js
export async function runLevelTransitionViaGame(charity, gameAddress, level) {
  const gameSigner = await impersonate(gameAddress);
  const tx = await charity.connect(gameSigner).pickCharity(level);
  await stopImpersonating(gameAddress);
  return tx;
}
```

**Critical:** Per `feedback_no_dead_guards.md`, only export what's actually consumed by the new governance file or the trimmed unit file. If `setCharityAs` ends up unused, drop it. Planner verifies the consumer set in PLAN.md before sealing the helper export surface.

---

### `test/unit/DegenerusCharity.test.js` (MODIFIED — prune)

**Analog:** self.

**Module-level constants delete pattern (D-256-CONST-CLEANUP-01)** — delete lines 16-18:

```js
// DELETE — Phase 254 deleted propose() / vault-owner bonus
const PROPOSE_THRESHOLD_BPS = 50n;
const VAULT_VOTE_BPS = 500n;
const MAX_CREATOR_PROPOSALS = 5;
```

Per `feedback_no_history_in_comments.md`: the deleted lines leave NO trace — no "removed for v33.0" annotation, no commented-out version. Just gone.

**In-file helper migration pattern** — once `charityFixture.js` exports `impersonate` / `stopImpersonating` / `giveSDGNRS` / `deployGNRUSFixture` / `POOL_REWARD`, REPLACE lines 20-116 of `test/unit/DegenerusCharity.test.js` with a single import block:

```js
import {
  deployGNRUSFixture,
  impersonate,
  stopImpersonating,
  giveSDGNRS,
  POOL_REWARD,
} from "../helpers/charityFixture.js";

// Local helper that's NOT extracted (uses v33 setCharity + pickCharity instead of v32 propose/vote)
async function distributeGNRUS(charity, deployer, recipientAddr, gameAddress) {
  // v33 shape: setCharity (instant-apply on empty slot) + impersonate game + pickCharity
  // OR: just delete distributeGNRUS too if no remaining describe needs the GNRUS-distributed
  // setup (Burn Redemption tests do — they need balanceOf(recipient1) > 0).
  // ...
}
```

**Token Metadata `proposalCount` deletion** — delete lines 175-178 (the `it("proposalCount starts at 0")` block) entirely. No replacement (per CONTEXT `## Reuse / Drop Existing v32 Test Constants`).

**Governance describe deletion (D-256-LAYOUT-01)** — delete lines 376-802 (the three `Governance -- Propose`, `Governance -- Vote`, `Governance -- pickCharity` describes) entirely. The `// =========================================================================` separators and section numbering comments go too — `feedback_no_history_in_comments.md` forbids any "removed" trace.

**`distributeGNRUS` rewrite (lines 121-135)** — the existing helper uses v32 `propose` + `vote` + `pickCharity`. Rewrite to v33 shape OR replace call sites with direct v33 calls. Suggested v33 helper shape:

```js
async function distributeGNRUS(charity, deployer, recipientAddr, gameAddress) {
  // v33: deployer (vault owner) sets charity directly into an empty slot
  const slot = 5; // any non-locked slot (LOCKED_SLOTS = 3)
  await charity.connect(deployer).setCharity(slot, recipientAddr);
  // No vote needed — single-active-slot wins by default in v33
  const gameSigner = await impersonate(gameAddress);
  await charity.connect(gameSigner).pickCharity(await charity.currentLevel());
  await stopImpersonating(gameAddress);
}
```

The Burn Redemption / burnAtGameOver / Edge Cases describes call `distributeGNRUS` — verify their assertions still hold after the rewrite (recipient1 still receives `2% of unallocated`, slot 5 is the active winning slot, etc.).

**`distributeGNRUS` callsite signature migration** — the existing call sites pass `(charity, deployer, voter1, recipient1.address, gameAddress)` (5 args, lines 232/244/253/269/275/297/303/319/329/335/352/355/873/970/973/974). v33 doesn't need `voter1` — drop it from the helper signature and update all callsites to `(charity, deployer, recipient1.address, gameAddress)`.

**Edge Cases describe (lines 917-991)** — the multi-level tests at lines 918-967 reference `propose` / `proposalCount` / `creatorProposalCount` (all deleted in v33). Delete the three v32-shape it-blocks (`multiple levels: proposals from previous levels are not accessible for voting`, `community proposer can propose in new level after resolve`, `vault owner proposal count resets per level`). Keep `totalSupply is conserved` (lines 969-983) — it uses `distributeGNRUS` and `balanceOf` only.

---

### `test/integration/CharityGameHooks.test.js` (MODIFIED — extend)

**Analog:** self (extend existing describes).

**Existing `pickCharity fires at level transition` describe extension pattern (D-256-CONSERVATION-01)** — copy the harness shape from `test/integration/CharityGameHooks.test.js:115-147`. Add a new it-block in the same describe that adds the v33.0-shape conservation assertions:

```js
it("conservation: 2% distribution preserves totalSupplies and soulbound enforcement", async function () {
  const fixture = await loadFixture(deployFullProtocol);
  const { game, deployer, mockVRF, alice, bob, carol, dan, eve, others, deployedAddrs, sdgnrs, dgnrs } = fixture;
  const charity = await getCharity(deployedAddrs);
  const charityAddr = await charity.getAddress();

  // SETUP: vault owner (deployer) populates an active slot so pickCharity has a winner
  const slot = 5; // non-locked
  await charity.connect(deployer).setCharity(slot, dan.address);

  // PRE-TRANSITION SNAPSHOT
  const gnrusUnallocBefore = await charity.balanceOf(charityAddr);
  const gnrusTotalBefore = await charity.totalSupply();
  const sdgnrsTotalBefore = await sdgnrs.totalSupply();
  const sdgnrsVotingBefore = await sdgnrs.votingSupply();
  const dgnrsTotalBefore = await dgnrs.totalSupply();

  // DRIVE: real game flow → charityResolve.pickCharity(lvl - 1) at DegenerusGameAdvanceModule:1634
  const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 5)];
  await fillPrizePoolForLevelTransition(game, buyers);
  await advanceToNextDay();
  await driveVRFCycle(game, deployer, mockVRF);
  await advanceToNextDay();
  await driveVRFCycle(game, deployer, mockVRF);

  // POST-TRANSITION ASSERTIONS
  const expectedDist = (gnrusUnallocBefore * 200n) / 10_000n;
  expect(await charity.balanceOf(dan.address)).to.equal(expectedDist);
  expect(await charity.balanceOf(charityAddr)).to.equal(gnrusUnallocBefore - expectedDist);
  expect(await charity.totalSupply()).to.equal(gnrusTotalBefore); // unchanged
  expect(await sdgnrs.totalSupply()).to.equal(sdgnrsTotalBefore);
  expect(await sdgnrs.votingSupply()).to.equal(sdgnrsVotingBefore);
  expect(await dgnrs.totalSupply()).to.equal(dgnrsTotalBefore);

  // Soulbound smoke (still intact post-transition)
  await expect(
    charity.connect(dan).transfer(eve.address, eth("1"))
  ).to.be.revertedWithCustomError(charity, "TransferDisabled");
});
```

**Existing `LevelResolved` event capture pattern** — copy from `test/integration/CharityGameHooks.test.js:170-178` (the events-collected-during-drain pattern):

```js
let levelResolvedEvent = null;
for (let i = 0; i < 200; i++) {
  if (!(await game.rngLocked())) break;
  const tx = await game.connect(deployer).advanceGame();
  const events = await getEvents(tx, charity, "LevelResolved");
  if (events.length > 0) {
    levelResolvedEvent = events[0];
  }
}
expect(levelResolvedEvent).to.not.be.null;
expect(levelResolvedEvent.args.slot).to.equal(slot);
expect(levelResolvedEvent.args.recipient).to.equal(dan.address);
```

**Stale describe rewrite (D-256-CONSERVATION-01)** — `test/integration/CharityGameHooks.test.js:149-185` is the `LevelSkipped(0) when no proposals exist for level 0` it-block. Rewrite the describe wording + comments to v33.0 slate-empty shape:

Existing v32 shape (lines 149, 174-175):
```js
it("emits LevelSkipped(0) when no proposals exist for level 0", async function () {
  // ...
  expect(events[0].args.level).to.equal(0);
});
```

v33 replacement:
```js
it("emits LevelSkipped(0) when no active slots in slate", async function () {
  // No setCharity() calls before transition → currentActiveBitmap == 0 → skip-path A
  // ...
  expect(events[0].args.level).to.equal(0);
});
```

Per `feedback_no_history_in_comments.md`: change the wording, do NOT leave a `// was: "no proposals exist for level 0"` annotation.

**Reused integration helpers (preserve as-is):**
- `getCharity(deployedAddrs)` — `test/integration/CharityGameHooks.test.js:38-41`
- `fillPrizePoolForLevelTransition(game, signers)` — `test/integration/CharityGameHooks.test.js:51-71`
- `driveVRFCycle(game, deployer, mockVRF)` — `test/integration/CharityGameHooks.test.js:79-92`
- `triggerGameOver(game, deployer, mockVRF)` — `test/integration/CharityGameHooks.test.js:101-109`

---

## Shared Patterns

### Fixture loading
**Source:** `test/unit/DegenerusCharity.test.js:138` + `test/integration/CharityGameHooks.test.js:117`
**Apply to:** Every test file in scope
```js
const fixture = await loadFixture(deployGNRUSFixture); // unit
const fixture = await loadFixture(deployFullProtocol); // integration
```

### Custom-error reverts
**Source:** `test/unit/DegenerusCharity.test.js:217-220` (no args), `test/unit/GovernanceGating.test.js:329-331` (with `withArgs`)
**Apply to:** All sad-path tests in `CharityAllowlist.test.js`
```js
// No args (e.g., InvalidSlot, SlotLocked, CapExceeded, Unauthorized)
.to.be.revertedWithCustomError(charity, "ErrorName");

// With args (VoteRejected(uint8), PickCharityRejected(uint8))
.to.be.revertedWithCustomError(charity, "VoteRejected").withArgs(REJECT_ZERO_WEIGHT);
```

### Game impersonation for direct charity hook calls
**Source:** `test/unit/DegenerusCharity.test.js:131-134`, replicated in `test/unit/FeedGovernance.test.js:46-64`, `test/unit/GovernanceGating.test.js:312-316`
**Apply to:** All unit-side `pickCharity` driving (NOT integration — integration uses real `advanceGame` flow per D-256-CONSERVATION-01)
```js
const gameSigner = await impersonate(gameAddress);
await charity.connect(gameSigner).pickCharity(level);
await stopImpersonating(gameAddress);
```

### Event extraction (single + multi)
**Source:** `test/helpers/testUtils.js:44-63` + usage at `test/unit/DegenerusCharity.test.js:629, 775`
**Apply to:** All event-bearing tests
```js
const ev = await getEvent(tx, charity, "LevelResolved");        // throws if not found
const events = await getEvents(tx, charity, "CharityFlushed");  // returns [] if none
```

### `restoreAddresses()` after-hook
**Source:** `test/integration/CharityGameHooks.test.js:27-29` + `test/access/AccessControl.test.js:33-35`
**Apply to:** Top-level `describe` of `test/governance/CharityAllowlist.test.js` (top-level — required because `deployFullProtocol` patches `ContractAddresses.sol`). Existing `test/unit/DegenerusCharity.test.js` does NOT call `restoreAddresses` — verify whether the unit suite relies on `restoreAddresses` from another file's `after` hook. If yes, the new governance file should add the same `after(() => restoreAddresses())` for safety.

```js
import { restoreAddresses } from "../helpers/deployFixture.js";

describe("GNRUS Charity Allowlist (v33.0)", function () {
  after(() => restoreAddresses());
  // ...
});
```

### Conservation balance-delta assertions
**Source:** `test/unit/DegenerusCharity.test.js:625-635` + `test/unit/DegenerusCharity.test.js:969-983`
**Apply to:** TST-05 conservation tests in `test/integration/CharityGameHooks.test.js`
```js
const balBefore = await token.balanceOf(addr);
// ... action ...
expect(await token.balanceOf(addr)).to.equal(balBefore + expectedDelta);
expect(await token.totalSupply()).to.equal(supplyBefore); // unchanged
```

### Gas measurement (single-assertion regression guardrail)
**Source:** `test/gas/AdvanceGameGas.test.js:1265, 1275, 1351, 1361`
**Apply to:** D-256-GAS-01 single it-block (location: planner picks `test/governance/CharityAllowlist.test.js` describe vs. new `test/gas/CharityGas.test.js` per `<deferred>` Claude's discretion)
```js
const tx = await charity.connect(gameSigner).pickCharity(level);
const receipt = await tx.wait();
expect(receipt.gasUsed).to.be.lt(CEILING); // CEILING from PLAN.md
```

NOTE: The `recordGas` summary table + `after(() => console.log(...))` in `test/gas/AdvanceGameGas.test.js:47-86` is OPTIONAL — appropriate only if the gas test lands in a dedicated `test/gas/CharityGas.test.js` file with multiple measurements. For a single-assertion guardrail in the governance file, drop the summary table entirely.

### Soulbound smoke check
**Source:** `test/unit/DegenerusCharity.test.js:191-208`
**Apply to:** TST-05 conservation it-block in `test/integration/CharityGameHooks.test.js` (post-transition smoke)
```js
await expect(
  charity.connect(holder).transfer(other.address, eth("1"))
).to.be.revertedWithCustomError(charity, "TransferDisabled");
```

---

## No Analog Found

None — every Phase 256 file has a strong analog in the existing test suite. The v33.0 shape is a v32→v33 surgical replacement, not a greenfield architecture.

| File | Status |
|------|--------|
| `test/governance/CharityAllowlist.test.js` (NEW) | Strong analog: `test/unit/DegenerusCharity.test.js` Governance describes (being deleted from there) — same patterns rewritten to v33 surface. |
| `test/helpers/charityFixture.js` (NEW) | Verbatim extraction from `test/unit/DegenerusCharity.test.js:26-116`. |
| `test/unit/DegenerusCharity.test.js` (MODIFIED) | Self. |
| `test/integration/CharityGameHooks.test.js` (MODIFIED) | Self — extend existing describes. |

---

## Metadata

**Analog search scope:** `test/unit/`, `test/integration/`, `test/gas/`, `test/access/`, `test/helpers/`
**Files scanned:** 8 (DegenerusCharity, CharityGameHooks, deployFixture, testUtils, AdvanceGameGas, GovernanceGating, FeedGovernance, AccessControl)
**Pattern extraction date:** 2026-05-06
**RESEARCH.md:** intentionally not produced (`--skip-research` per `feedback_skip_research_test_phases.md`); patterns derived directly from existing test surface.
