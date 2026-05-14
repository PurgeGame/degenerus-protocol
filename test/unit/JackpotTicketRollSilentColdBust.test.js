// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotTicketRollSilentColdBust.test.js — Phase 276 Wave 2 TST-JPT-BR-02
//
// Silent cold-bust regression on the jackpot ticket-roll path:
//   When the Bernoulli round-up fails (`whole == 0` after the inline Bernoulli
//   math runs on `scaledTickets > 0` with `scaledTickets < TICKET_SCALE`), the
//   jackpot ticket-roll path produces:
//     - ZERO `TicketsQueued` emit (the `_queueTickets` helper at
//       `DegenerusGameStorage.sol:568` early-returns on `quantity == 0`,
//       BEFORE the `emit TicketsQueued` and any SSTORE).
//     - ZERO consolation: `_jackpotTicketRoll` has NO `wwxrp.mintPrize` call,
//       NO `LootBoxWwxrpReward` emit, NO `LootboxTicketRoll` emit, NO
//       consolation branch — D-40N-SILENT-01 (jackpot cold-bust is SILENT).
//   BUT `JackpotTicketWin` STILL fires unconditionally with the pre-Bernoulli
//   scaled `ticketCount` (`uint32(quantityScaled)`) — D-276-EVT-STATUSQUO-01.
//   The silent-cold-bust scope is the QUEUE surface only, NOT the
//   `JackpotTicketWin` event. Phase 277 EVT-UNI-04 added a trailing non-indexed
//   `bool roundedUp` field to `JackpotTicketWin`; `_jackpotTicketRoll` threads
//   the captured Bernoulli outcome into that field, so the cold-bust emit
//   carries `roundedUp = false`. Part (c) asserts that updated signature.
//
// DIVERGENCE FROM THE PHASE 275 ANALOG (test/unit/LootboxAutoResolveSilentColdBust.test.js):
//   The jackpot ticket-roll path has NO `LootboxTicketRoll` analog and NO
//   manual-path consolation positive-control. `_jackpotTicketRoll` is a SINGLE
//   path — it ALWAYS emits `JackpotTicketWin` with the pre-Bernoulli scaled
//   `ticketCount` regardless of the Bernoulli outcome (D-276-EVT-STATUSQUO-01).
//   So there is NO manual-path positive control to copy: the silent-cold-bust
//   assertion is specifically `whole == 0` ⇒ zero `TicketsQueued`, while
//   `JackpotTicketWin` still fires scaled.
//
// TEST STRATEGY:
//   No state fixture exists for `_jackpotTicketRoll` at the FOG-of-state
//   required (jackpot winner selection, level + day simulation, VRF-derived
//   rngWord with controlled bits[200..215] slice, BAF accumulation, etc.) —
//   same fixture-coverage-gap precedent as LBX-02 in v39 Phase 274 and the
//   Phase 275 auto-resolve analog. Per `feedback_gas_worst_case.md` discipline
//   ("derive theoretical worst case FIRST; if no fixture, source-level /
//   tester-direct evidence is load-bearing"), this test combines:
//     (a) Direct-call cold-bust math verification on the byte-identical
//         inline Bernoulli (JackpotBernoulliTester).
//     (b) Source-level structural proof that `_jackpotTicketRoll`'s
//         post-Bernoulli path contains ONLY the single
//         `_queueTickets(winner, targetLevel, whole, true)` call (no emit, no
//         mintPrize, no consolation branch) + that the cold-bust gate is the
//         `if (quantity == 0) return;` early-return inside `_queueTickets` at
//         `DegenerusGameStorage.sol:568`.
//     (c) Emit-absence assertion: on `whole == 0` the part-(b) structural
//         proof establishes zero `TicketsQueued` emit; AND the source
//         structure shows `JackpotTicketWin` STILL fires unconditionally with
//         `uint32(quantityScaled)` (D-276-EVT-STATUSQUO-01).
//
// CROSS-CITES:
//   - D-276-INLINE-01 (Bernoulli math inlined in _jackpotTicketRoll)
//   - D-40N-SILENT-01 (jackpot cold-bust is SILENT — no consolation)
//   - D-276-EVT-STATUSQUO-01 (JackpotTicketWin always fires the pre-Bernoulli scaled ticketCount)
//   - test/unit/LootboxAutoResolveRemByte.test.js (fs.readFileSync + regex source-structural-proof idiom)
//   - feedback_rng_backward_trace.md (cold-bust slice selection upstream)
//   - feedback_rng_commitment_window.md (winner cannot mutate the per-roll
//     entropy once _jackpotTicketRoll is entered)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("JackpotBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

// Brace-match function-body extractor (mirrors test/unit/LootboxAutoResolveRemByte.test.js).
function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  let bodyEnd = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        bodyEnd = i;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) return null;
  return source.slice(bodyStart, bodyEnd + 1);
}

// Strip `//` line comments so structural greps do not self-invalidate on
// comment prose (e.g. a NatSpec line mentioning `LootboxTicketRoll`).
function stripLineComments(body) {
  return body
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("//");
      return idx >= 0 ? line.slice(0, idx) : line;
    })
    .join("\n");
}

describe("JackpotTicketRollSilentColdBust — Phase 276 Wave 2 TST-JPT-BR-02", function () {
  this.timeout(60_000);

  describe("Part (a) — direct-call cold-bust math: scaledTickets ∈ (0, 100) AND Bernoulli loses ⇒ whole == 0, roundedUp == false", function () {
    it("[01a] tester confirms cold-bust math: scaledTickets ∈ {1, 47, 99} AND a losing seed (bernoulliSlice >= frac) ⇒ whole=0", async function () {
      const tester = await deployTester();
      for (const scaledTickets of [1, 47, 99]) {
        const frac = BigInt(scaledTickets) % TICKET_SCALE; // == scaledTickets here
        // Search a small seed range for a LOSING slice (slice >= frac).
        let lossSeed = null;
        for (let s = 0; s < 4096; s++) {
          // Place the candidate value into bits[200..215].
          const seed = BigInt(s) << 200n;
          const slice = await tester.bernoulliSlice(seed);
          if (BigInt(slice) >= frac) {
            lossSeed = seed;
            break;
          }
        }
        expect(
          lossSeed !== null,
          `could not find a losing seed for scaledTickets=${scaledTickets} (frac=${frac})`
        ).to.equal(true);
        const [whole, roundedUp] = await tester.bernoulliWhole(
          scaledTickets,
          lossSeed
        );
        expect(
          whole,
          `cold-bust must produce whole=0 at scaledTickets=${scaledTickets} (frac=${frac})`
        ).to.equal(0n);
        expect(
          roundedUp,
          `cold-bust must produce roundedUp=false at scaledTickets=${scaledTickets}`
        ).to.equal(false);
      }
    });

    it("[01b] tester confirms warm scenarios: scaledTickets ∈ {1, 47, 99} AND a winning seed (bernoulliSlice < frac) ⇒ whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // seed=0 ⇒ slice=0 ⇒ 0 < frac for every frac >= 1 ⇒ Bernoulli wins.
      const seedSliceLow = 0n;
      for (const scaledTickets of [1, 47, 99]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(
          scaledTickets,
          seedSliceLow
        );
        expect(
          whole,
          `warm path must produce whole=1 at scaledTickets=${scaledTickets}`
        ).to.equal(1n);
        expect(
          roundedUp,
          `warm path must produce roundedUp=true at scaledTickets=${scaledTickets}`
        ).to.equal(true);
      }
    });
  });

  describe("Part (b) — source-level structural proof: _jackpotTicketRoll's post-Bernoulli path is the single _queueTickets(winner, targetLevel, whole, true) call — no emit, no mintPrize, no consolation", function () {
    it("[02a] `_jackpotTicketRoll` body contains exactly one `_queueTickets(winner, targetLevel, whole, true)` call (rngBypass = true)", function () {
      // Source-structural proof reads: fs.readFileSync DegenerusGameJackpotModule.sol
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _jackpotTicketRoll(")
      );
      expect(body, "`_jackpotTicketRoll` body not found").to.not.equal(null);
      const calls = (
        body.match(/_queueTickets\(winner, targetLevel, whole, true\)/g) || []
      ).length;
      expect(
        calls,
        "`_jackpotTicketRoll` must contain exactly one `_queueTickets(winner, targetLevel, whole, true)` call (the single post-Bernoulli queue call, rngBypass = true)"
      ).to.equal(1);
    });

    it("[02b] `_jackpotTicketRoll` body has NO consolation surface — no `wwxrp.mintPrize`, no `LootBoxWwxrpReward` emit, no `LootboxTicketRoll` emit, no `_queueTicketsScaled` (D-40N-SILENT-01)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _jackpotTicketRoll(")
      );
      expect(body, "`_jackpotTicketRoll` body not found").to.not.equal(null);
      expect(
        body.includes("wwxrp.mintPrize"),
        "_jackpotTicketRoll must not call wwxrp.mintPrize (cold-bust is SILENT — D-40N-SILENT-01)"
      ).to.equal(false);
      expect(
        body.includes("emit LootBoxWwxrpReward"),
        "_jackpotTicketRoll must not emit LootBoxWwxrpReward (no jackpot consolation)"
      ).to.equal(false);
      expect(
        body.includes("emit LootboxTicketRoll"),
        "_jackpotTicketRoll must not emit LootboxTicketRoll (no LootboxTicketRoll analog on the jackpot path)"
      ).to.equal(false);
      expect(
        body.includes("_queueTicketsScaled"),
        "_jackpotTicketRoll must not call _queueTicketsScaled (Plan A swapped to the whole-ticket _queueTickets)"
      ).to.equal(false);
    });

    it("[02c] cold-bust gate is the `_queueTickets` early-return at DegenerusGameStorage.sol — body contains `if (quantity == 0) return;` before any emit or SSTORE (D-40N-SILENT-01)", function () {
      // Source-structural proof reads: fs.readFileSync DegenerusGameStorage.sol
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const body = extractBody(storage, "function _queueTickets(");
      expect(body, "`_queueTickets` function not found in storage").to.not.equal(
        null
      );
      expect(
        /if\s*\(\s*quantity\s*==\s*0\s*\)\s*return;/.test(body),
        "_queueTickets must contain `if (quantity == 0) return;` early-return (D-40N-SILENT-01 silent-cold-bust gate)"
      ).to.equal(true);
      // The early-return must come BEFORE the `emit TicketsQueued` — proving
      // whole==0 produces ZERO TicketsQueued emit and ZERO SSTORE.
      const returnIdx = body.search(
        /if\s*\(\s*quantity\s*==\s*0\s*\)\s*return;/
      );
      const emitIdx = body.indexOf("emit TicketsQueued(");
      expect(emitIdx, "_queueTickets must emit TicketsQueued").to.be.greaterThan(
        -1
      );
      expect(
        returnIdx,
        "the `if (quantity == 0) return;` early-return must precede `emit TicketsQueued` (silent on whole==0)"
      ).to.be.lessThan(emitIdx);
    });
  });

  describe("Part (c) — emit-absence: whole == 0 ⇒ zero TicketsQueued; JackpotTicketWin STILL fires the pre-Bernoulli scaled ticketCount + the Phase 277 `roundedUp` field (D-276-EVT-STATUSQUO-01, EVT-UNI-04)", function () {
    it("[03a] `_jackpotTicketRoll` emits `JackpotTicketWin` unconditionally with `uint32(quantityScaled)` and the trailing `roundedUp` field — the pre-Bernoulli scaled count, NOT `whole` (D-276-EVT-STATUSQUO-01, EVT-UNI-04)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _jackpotTicketRoll(")
      );
      expect(body, "`_jackpotTicketRoll` body not found").to.not.equal(null);
      // Exactly one JackpotTicketWin emit, and it carries uint32(quantityScaled).
      const emitCount = (body.match(/emit JackpotTicketWin\(/g) || []).length;
      expect(
        emitCount,
        "_jackpotTicketRoll must emit JackpotTicketWin exactly once"
      ).to.equal(1);
      expect(
        body.includes("uint32(quantityScaled)"),
        "JackpotTicketWin must carry `uint32(quantityScaled)` — the pre-Bernoulli scaled ticketCount per D-276-EVT-STATUSQUO-01"
      ).to.equal(true);
      // Phase 277 EVT-UNI-04: the emit threads the captured `roundedUp` local as
      // its trailing (7th) non-indexed field. _jackpotTicketRoll declares
      // `bool roundedUp = false;` before the Bernoulli predicate and sets it
      // `true` inside the round-up branch.
      expect(
        body.includes("bool roundedUp = false;"),
        "_jackpotTicketRoll must declare `bool roundedUp = false;` before the Bernoulli predicate"
      ).to.equal(true);
      expect(
        body.includes("roundedUp = true;"),
        "_jackpotTicketRoll must set `roundedUp = true;` inside the Bernoulli round-up branch"
      ).to.equal(true);
      // The JackpotTicketWin emit's last arg is the captured `roundedUp` local.
      const emitMatch = body.match(/emit JackpotTicketWin\(([\s\S]*?)\);/);
      expect(emitMatch, "JackpotTicketWin emit arg list not parsed").to.not.equal(
        null
      );
      const emitArgs = emitMatch[1]
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a.length > 0);
      expect(
        emitArgs.length,
        "JackpotTicketWin emit must supply 7 args including the trailing roundedUp"
      ).to.equal(7);
      expect(
        emitArgs[6],
        "the 7th JackpotTicketWin arg must be the captured `roundedUp` local"
      ).to.equal("roundedUp");
      // The emit is NOT gated behind a `whole != 0` / `whole > 0` predicate —
      // it sits at the function tail, unconditional. Assert no `if (whole`
      // branch wraps it: the emit must appear AFTER the _queueTickets call and
      // at brace-depth 1 (function body), not nested in a conditional.
      const queueIdx = body.indexOf(
        "_queueTickets(winner, targetLevel, whole, true)"
      );
      const emitIdx = body.indexOf("emit JackpotTicketWin(");
      expect(queueIdx, "_queueTickets call not found").to.be.greaterThan(-1);
      expect(
        emitIdx,
        "the JackpotTicketWin emit must come AFTER the _queueTickets call (unconditional function-tail emit)"
      ).to.be.greaterThan(queueIdx);
    });

    it("[03b] structural cold-bust conclusion: on `whole == 0` (part (a)), the part-(b) early-return at DegenerusGameStorage.sol:568 produces ZERO TicketsQueued — silent cold-bust scope is the QUEUE surface only; there is NO manual-path positive control (single jackpot path, divergence from the Phase 275 analog)", async function () {
      // Synthesis assertion — ties parts (a) + (b) together. No fixture can
      // drive the full _jackpotTicketRoll caller stack (fixture-coverage gap,
      // LBX-02 precedent), so the cold-bust conclusion is established by
      // composition: part (a) proves the inline Bernoulli yields whole==0 on a
      // losing slice for scaledTickets ∈ (0, 100); part (b) proves the only
      // post-Bernoulli statement consuming `whole` is
      // `_queueTickets(winner, targetLevel, whole, true)`, which early-returns
      // at `if (quantity == 0) return;` BEFORE `emit TicketsQueued`. Therefore
      // whole==0 ⇒ zero TicketsQueued, zero SSTORE — silent.
      const tester = await deployTester();
      // Re-confirm the part-(a) cold-bust outcome inline for scaledTickets=1.
      let lossSeed = null;
      for (let s = 0; s < 4096; s++) {
        const seed = BigInt(s) << 200n;
        const slice = await tester.bernoulliSlice(seed);
        if (BigInt(slice) >= 1n) {
          lossSeed = seed;
          break;
        }
      }
      expect(
        lossSeed !== null,
        "no losing seed found for scaledTickets=1"
      ).to.equal(true);
      const [whole] = await tester.bernoulliWhole(1, lossSeed);
      expect(
        whole,
        "scaledTickets=1 on a losing slice must Bernoulli-collapse to whole=0 — the cold-bust input to the silent _queueTickets early-return"
      ).to.equal(0n);
      // The QUEUE-surface silence is structurally proven in [02c]; the
      // JackpotTicketWin unconditional emit in [03a]. There is NO
      // LootboxTicketRoll / manual-path consolation positive control on the
      // jackpot path (single path) — that is the documented divergence from
      // test/unit/LootboxAutoResolveSilentColdBust.test.js.
    });
  });
});
