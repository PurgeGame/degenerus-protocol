# Phase 353 — v56.0 Design-Lock SPEC

**Phase:** 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode
**Milestone:** v56.0 — AfKing Everyday-Gas Minimization
**Baseline / frozen subject:** `453f8073` (`MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`)
**Status:** DRAFT (the XMODEL fold-in + the SPEC Lock are PENDING — Plan 02)
**Authored:** 2026-06-01
**Scope note:** PAPER-ONLY. ZERO `contracts/*.sol` mutation is permitted or expected in Phase 353. Every section below cites identifiers + line ranges + behavior only — NO contract code is authored or inlined. The implementation is owned by Phase 354 (IMPL); the empirical proofs by Phase 356 (TST); the close by Phase 357 (TERMINAL).

This SPEC is the **producer**: it design-locks AFF-01 / AFF-02 (OWNED here) and folds in every design feed the IMPL (354) / GAS (355) / TST (356) / TERMINAL (357) phases consume. Plan 02 (the XMODEL cross-model pass) pressure-tests this draft, folds its disposition table into the `## XMODEL-01` section, and then flips the `## SPEC Lock` placeholder.

---

## Anchor Attestation (vs 453f8073)

Every cited `file:line` below was grep/`sed`-re-attested against the working tree on 2026-06-01. Per the frozen-subject guard (next subsection), the working tree is byte-identical to `453f8073`, so each attested line **equals the frozen subject**. The table reconciles the ROADMAP/CONTEXT bare module names to their `contracts/modules/...` full paths and records every drift.

| # | Anchor (as cited upstream) | Reconciled path:line | Symbol confirmed | Drift note |
|---|----------------------------|----------------------|------------------|------------|
| A1 | afking per-buy cross-contract storm `GameAfkingModule.sol:760-831` | `contracts/modules/GameAfkingModule.sol:708-833` (debit `:709-710`; `quests.handlePurchase` `:760`; `affiliate.payAffiliate` `:806`+`:816`; per-buy `coinflip.creditFlip` `:831`) | Y | **DRIFT #1** — the storm spans `:708-833`; the cited `:760-831` is the inner span only. SPEC widens to `:708-833`. |
| A2 | lootbox stamp branch `:735-749` | `contracts/modules/GameAfkingModule.sol:735-833` (the `else` lootbox-stamp branch; comment header `:735-746`; stamp body to `:833`) | Y | OK — `:735` opens the branch; the stamp work extends to `:833`. |
| A3 | ticket-mode `purchaseWith` route `:713-731` | `contracts/modules/GameAfkingModule.sol:713-731` (`if (isTicket)` → `purchaseWith` delegatecall) | Y | EXACT. |
| A4 | affiliate daily-seeded roll `DegenerusAffiliate.sol:558` | `contracts/DegenerusAffiliate.sol:558-567` — `keccak256(AFFILIATE_ROLL_TAG, GameTimeLib.currentDayIndex(), sender, storedCode) % 20` | Y | EXACT (the `roll` decl is `:558`; the `keccak256` body runs `:559-567`). |
| A5 | buyer-never-wins `:579` | `contracts/DegenerusAffiliate.sol:579` — `if (winner != sender) { ... }` (when the buyer would win, the whole reward incl. quest credit is SKIPPED, not redirected) | Y | EXACT. |
| A6 | leaderboard writes `:510`/`:511`/`:521` | `contracts/DegenerusAffiliate.sol:510` (`earned[affiliateAddr] = newTotal`), `:511` (`_totalAffiliateScore[lvl] += scaledAmount`), `:521` (`_updateTopAffiliate(...)`) | Y | EXACT. |
| A7 | `_updateTopAffiliate:776` (read-once-compare) | `contracts/DegenerusAffiliate.sol:776-783` — 1 SLOAD (`affiliateTopByLevel[lvl]`) + conditional SSTORE only when `score > current.score` | Y | EXACT (D-08 confirmed). |
| A8 | taper `:504`/`:787` (`_applyLootboxTaper`) | call site `contracts/DegenerusAffiliate.sol:504-506`; impl `:787-795`; monotone-down (returns `amt * factor`, `factor ≤ BPS_DENOMINATOR`) | Y | EXACT (taper-only-reduces confirmed). |
| A9 | 1%-top consumer `DegenerusGameAdvanceModule.sol:700` (`_rewardTopAffiliate`) | `contracts/modules/DegenerusGameAdvanceModule.sol:700` — `function _rewardTopAffiliate(uint24 lvl)` (reads `affiliate.affiliateTop(lvl)`) | Y | EXACT (bare-name reconciled to `contracts/modules/`). |
| A10 | 5%-proportional consumer `DegenerusGameBingoModule.sol:217` (`claimAffiliateDgnrs`) | `contracts/modules/DegenerusGameBingoModule.sol:216` — `function claimAffiliateDgnrs(address player)` (reads cumulative `affiliateScore`/`totalAffiliateScore`, NOT the live ranking) | Y | **DRIFT #2** — it is `:216`, not `:217`. SPEC cites `:216`. |
| A11 | `DegenerusQuests.sol` `handlePurchase` `:763-898`; O1 at `:887`/`:890`/`:893` | `contracts/DegenerusQuests.sol:763-898`; burnie credit (KEEP) `:887`; **lootbox credit (DROP) `:890`** inside the `if (lootboxReward != 0)` at `:889`; `totalReturned = ethMintReward + lootboxReward` (KEEP) `:893` | Y | **DRIFT #4** — the O1-drop `creditFlip` is line `:890`, inside the `if` at `:889`. SPEC cites `:890` / guard `:889`. |
| A12 | `awardQuestStreakBonus:365` | `contracts/DegenerusQuests.sol:365-384` (`onlyGame`; adds streak days; clamps uint24) | Y | EXACT. |
| A13 | afking open path `_openAfkingBox`→`resolveAfkingBox` + `mintBurnie`/`_autoOpen`/`OPEN_BATCH` | `contracts/modules/GameAfkingModule.sol`: `_openAfkingBox` `:888-910`, `_afkingBoxReady` `:918-922`, `_autoOpen` `:938-966`, `mintBurnie` `:985-...`, `OPEN_BATCH` const `:191`; `resolveAfkingBox` `contracts/modules/DegenerusGameLootboxModule.sol:877-...` | Y | EXACT. |
| A14 | `Sub` 4-field stamp + `lastOpenedDay` in `DegenerusGameStorage.sol` | `contracts/storage/DegenerusGameStorage.sol:1867-1899` — config 56b (`dailyQuantity`8 + `validThroughLevel`32 + `reinvestPct`8 + `flags`8) + stamp 112b (`scorePlus1`16 + `amount`96) + markers 64b (`lastAutoBoughtDay`32 + `lastOpenedDay`32) = **232/256**; `mapping(address=>Sub) _subOf` `:1902` | Y | **DRIFT #5 (accumulator-layout premise)** — the slot is at **232/256 (24 spare)**, NOT the "176/256" CONTEXT/PLAN premise. See `## Accumulator Layout`. |
| A15 | EV-cap `lootboxEvBenefitUsedByLevel[player][level+1]` | `contracts/modules/DegenerusGameLootboxModule.sol` — `_applyEvMultiplierWithCap` `:459-495`; afking call `:902` with `currentLevel = level + 1` (`:894`) | Y | **DRIFT #6** — the EV-cap key is `[player][currentLevel]` where `currentLevel == level + 1` (`:894`/`:902`). SPEC records the key form. |
| A16 | STAGE placement in `DegenerusGameAdvanceModule.sol` | `contracts/modules/DegenerusGameAdvanceModule.sol`: `SUB_STAGE_BATCH` const `:149`; per-buy storm driver via `processSubscriberStage` (`contracts/modules/GameAfkingModule.sol:539`) | Y | EXACT (bare-name reconciled). |
| A17 | `MintModule:1243` century bonus (ROADMAP bare name) | `contracts/modules/DegenerusGameMintModule.sol:1243` — `if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0)` (ticket-mode only); body `:1243-1259` | Y | EXACT (bare-name reconciled). |
| A18 | MintModule O1 re-credit (`:1222-1232`, `:1366-1367`) | `contracts/modules/DegenerusGameMintModule.sol:1222` (`handlePurchase` call), `:1232` (`lootboxFlipCredit += questReward`), `:1366-1367` (batched `creditFlip(buyer, lootboxFlipCredit)`) | Y | EXACT (bare-name reconciled). |
| A19 | `handleLootBox` dead `:698-742` + interface `:107` | `contracts/DegenerusQuests.sol:698-741` (the fn; internal `creditFlip` `:739`); interface decl `contracts/interfaces/IDegenerusQuests.sol:107`; **NO production caller** (only comment refs `:746` / `IDegenerusQuests:126`; test refs in `test/`) | Y | **DRIFT #3** — the fn is `:698-741`, not `:698-742`. SPEC cites `:698-741`. |
| A20 | clean handlers — `handleMint` guard `:513`, `handleFlip` `:533`, `handleDecimator` credit `:629`, `handleAffiliate` `:644`, `handleDegenerette` credit `:954` | `contracts/DegenerusQuests.sol` — `handleMint` guard `:513` (`if (!paidWithEth && totalReward != 0)`); `handleFlip` `:533`; `handleDecimator` `:589` / credit `:629`; `handleAffiliate` `:644`; `handleDegenerette` `:913` / credit `:954` | Y | EXACT (D-04 confirmed — the O1 pattern is ISOLATED to `handlePurchase`'s lootbox leg). |
| A21 | external clean callers — `BurnieCoin:613`, `BurnieCoinflip:275`, `DegeneretteModule:467` | `contracts/BurnieCoin.sol:613` (`handleDecimator`, weight-boost dual-use); `contracts/BurnieCoinflip.sol:275` (`handleFlip`, credited once); `contracts/modules/DegenerusGameDegeneretteModule.sol:467` (`handleDegenerette`, return ignored) | Y | EXACT (D-04 confirmed). |

### Net Drift Recorded (the 5 reconciliations the SPEC carries forward)

1. **Storm range** — the per-buy cross-contract storm is `GameAfkingModule.sol:708-833`, NOT the ROADMAP's `:760-831` (the cited span is the inner storm; the debit at `:709-710` and the stamp tail at `:833` bracket it).
2. **`claimAffiliateDgnrs`** — `DegenerusGameBingoModule.sol:216`, NOT `:217` (one-line off-by-one).
3. **`handleLootBox` dead code** — `DegenerusQuests.sol:698-741`, NOT `:698-742`.
4. **O1-drop `creditFlip`** — line `:890`, inside the `if (lootboxReward != 0)` guard at `:889` (the burnie-credit KEEP is `:887`; the `totalReturned` KEEP is `:893`).
5. **EV-cap key** — `lootboxEvBenefitUsedByLevel[player][currentLevel]` where `currentLevel = level + 1` (`DegenerusGameLootboxModule.sol:894`/`:902`).

(A sixth reconciliation — the accumulator-layout "176/256 → 232/256" premise drift — is folded into A14 and fully resolved in `## Accumulator Layout`.)

All ROADMAP bare module names are reconciled to `contracts/modules/...` full paths in the table above (e.g. `MintModule:1243` → `contracts/modules/DegenerusGameMintModule.sol:1243`; `GameAfkingModule.sol:760` → `contracts/modules/GameAfkingModule.sol:760`).

### Frozen-Subject Guard

`git diff --quiet 453f8073 HEAD -- contracts/` returns **clean** (re-verified 2026-06-01 at execution start — exit 0, `FROZEN_GUARD_PASS`). HEAD is `453f8073` plus docs-only commits, and `453f8073` is an ancestor of HEAD. Therefore the working-tree `contracts/` is **byte-identical** to the frozen subject, and every `file:line` attested above was read directly from the working tree and **equals** the frozen subject `453f8073` — no `git show 453f8073:<path>` indirection was needed. No "by construction" anchor survives un-checked in this SPEC: each load-bearing line is grep/`sed`-attested in this table.
