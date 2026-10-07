// SPDX-License-Identifier: AGPL-3.0-only
// Whole-entry appends preserve fractional credit; scaled purchases accumulate it.

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);

// Brace-match function-body extractor.
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

describe("Whole and scaled entry remainder storage", function () {
  this.timeout(30_000);

  describe("`_queueEntries` body proof: writes ONLY whole tickets — rem byte carried unchanged from existing slot value (LBX-AR-06)", function () {
    it("[01a] `_queueEntries` body in `entry-owed codec` write packs `(packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem)` where `rem = uint8(packed)` from the PRE-existing slot value (no fractional accumulation)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const body = extractBody(storage, "function _queueEntries(");
      expect(body, "`_queueEntries` body not found").to.not.equal(null);

      // The write site MUST pack `rem` from the existing slot, never from a
      // newly-computed fractional value. The pattern is:
      //   entry-owed codec[wk][buyer] =
      //       (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem);
      // The wallet-ID bits above bit 48 ride along untouched.
      expect(
        /_setEntryOwed\(wk,\s*id,\s*\(packed\s*&\s*OWNER_IDX_MASK\)\s*\|\s*\(uint80\(owed\)\s*<<\s*8\)\s*\|\s*uint80\(rem\)/.test(body),
        "_queueEntries must pack `(packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem)` with rem carried from existing slot"
      ).to.equal(true);

      // No fractional/remainder arithmetic appears in the body — specifically,
      // no `% QTY_SCALE` modulo, no `frac` variable, no `newRem` variable.
      expect(body.includes("% QTY_SCALE"), "_queueEntries must not compute fractional remainder").to.equal(false);
      expect(/\bfrac\b/.test(body), "_queueEntries must not have a `frac` local").to.equal(false);
      expect(/\bnewRem\b/.test(body), "_queueEntries must not have a `newRem` local").to.equal(false);


      // Emission: EntriesQueued (whole-helper), not EntriesQueuedScaled.
      expect(body.includes("emit EntriesQueued("), "_queueEntries must emit EntriesQueued").to.equal(true);
      expect(body.includes("emit EntriesQueuedScaled("), "_queueEntries must NOT emit EntriesQueuedScaled").to.equal(false);
    });

    it("[01b] positive control: `_queueEntriesScaled` body DOES write a non-zero rem byte when frac != 0", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const body = extractBody(storage, "function _queueEntriesScaledCore(");
      expect(body, "`_queueEntriesScaled` body not found").to.not.equal(null);

      // The scaled helper computes `uint8 frac = uint8(uint256(quantityScaled) % QTY_SCALE)`
      // and folds it into `newRem` before packing into `entry-owed codec`.
      expect(body.includes("% QTY_SCALE"), "_queueEntriesScaled must compute frac via % QTY_SCALE").to.equal(true);
      expect(/\bfrac\b/.test(body), "_queueEntriesScaled must have a `frac` local").to.equal(true);
      expect(/\bnewRem\b/.test(body), "_queueEntriesScaled must have a `newRem` local").to.equal(true);
      // Emission contract: EntriesQueuedScaled (scaled helper).
      expect(body.includes("emit EntriesQueuedScaled("), "_queueEntriesScaled must emit EntriesQueuedScaled").to.equal(true);
    });
  });


});
