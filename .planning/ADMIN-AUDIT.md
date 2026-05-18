# ADMIN-AUDIT — Phase 300 Admin Path Enumeration Audit (v43.0)

**Generated:** 2026-05-18
**Milestone:** v43.0 Total rngLock Determinism Audit (AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`)
**Audit baseline:** v42.0 closure HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`
**Posture:** Single AGENT-COMMITTED canonical ADMA deliverable for ADMA-01..04; zero `contracts/` and zero `test/` mutations across the phase; per-admin-function FIX recommendations are AGENT-COMMITTED documentation handing forward to v44.0 FIX-MILESTONE via `D-43N-V44-ADMA-NN` anchors.

This artifact enumerates every admin-gated external / public function in `contracts/`, cross-references each against the Phase 298 RNGLOCK-CATALOG §15 per-slot writer table, and emits per-admin-function recommendation entries for admin functions that reach a participating slot at any non-EXEMPT callsite. Per `D-43N-AUDIT-ONLY-01`, no design-acceptance classifications appear — every admin-function-reaches-participating-slot edge gets a tactic recommendation + v44.0 handoff anchor.

---

## §0 — Executive Summary

**Admin function count (§1):** 37 admin-gated external entry points across 8 contracts (`DegenerusVault`, `DegenerusGame`, `DegenerusAdmin`, `DegenerusDeityPass`, `Icons32Data`, `DegenerusGameAdvanceModule`, `DegenerusStonk`, `GNRUS`).

**Breakdown by role-gate type:**

| Role-gate type | Count | Notes |
|---|---|---|
| `onlyVaultOwner` modifier (DegenerusVault) | 23 | All bareword `\bonlyVaultOwner\b` external usages; modifier defined at `DegenerusVault.sol:431` (`_isVaultOwner` check at `:432`) |
| `onlyOwner` modifier (DegenerusDeityPass via `isVaultOwner`) | 2 | Modifier defined at `DegenerusDeityPass.sol:80` (`vault.isVaultOwner` check at `:81`) |
| `onlyOwner` modifier (DegenerusAdmin via `isVaultOwner`) | 1 | Modifier defined at `DegenerusAdmin.sol:436` (`vault.isVaultOwner` check at `:437`) |
| Hand-rolled `msg.sender != ContractAddresses.ADMIN` | 3 | `DegenerusGame.sol:1809`; `DegenerusGameAdvanceModule.sol:503`, `:1682` |
| Hand-rolled `msg.sender != ContractAddresses.CREATOR` | 3 | `Icons32Data.sol:154, :172, :197` |
| Hand-rolled `!vault.isVaultOwner(msg.sender)` (inline at function body) | 5 | `DegenerusGame.sol:480, :1827`; `DegenerusStonk.sol:188, :203`; `GNRUS.sol:380` |
| **Total** | **37** | Matches expected §1 row floor per D-300-ENUM-SCOPE-01 |

**Participating-slot-writer subset (§2 VIOLATION count):** 16 admin functions write a participating slot per RNGLOCK-CATALOG §14/§15 at a non-EXEMPT callsite. 21 admin functions are pure-admin-state-only (no participating-slot write) — they are enumerated in §2 with verdict `N/A` for completeness per ADMA-02 but produce no §3 recommendation entry.

**Recommendation entries (§3):** 21 R-NN entries, one per §2 VIOLATION row (no collapse per `D-300-ADMA-LAYOUT-01` — each admin function reaching a participating slot gets its own §3 entry so v44.0 plan-phase can consume per-admin-function anchors).

**Breakdown of §3 entries by admin-class:**

| Admin-class | Count | Functions (R-NN) |
|---|---|---|
| governance | 6 | R-01 wireVrf, R-02 updateVrfCoordinatorAndSub, R-03 adminSwapEthForStEth, R-04 adminStakeEthForStEth, R-05 swapGameEthForStEth, R-06 setCharity (GNRUS) |
| parameter-update | 0 | (setLootboxRngThreshold writes a non-participating threshold slot; not classified here as a participating-slot writer) |
| charity-allowlist | 0 | (charity-allowlist routing handled under R-06 governance — sole charity-allowlist mutator is `GNRUS.setCharity`) |
| decimator-config | 0 | (no decimator-config admin function in v43.0 surface) |
| presale-config | 0 | (no presale-config admin function in v43.0 surface) |
| general | 15 | R-07 gamePurchase, R-08 gamePurchaseTicketsBurnie, R-09 gamePurchaseBurnieLootbox, R-10 gameOpenLootBox, R-11 gamePurchaseDeityPassFromBoon, R-12 gameDegeneretteBet, R-13 gameSetAutoRebuy, R-14 gameSetAutoRebuyTakeProfit, R-15 gameSetAfKingMode, R-16 coinDepositCoinflip, R-17 coinDecimatorBurn, R-18 gameClaimWinnings, R-19 gameClaimWhalePass, R-20 jackpotsClaimDecimator, R-21 sdgnrsBurn |
| **Total** | **21** | (plus R-22 sdgnrsClaimRedemption under general; total **22** when sDGNRS pair split) |

**v44.0 handoff anchors (§4):** 22 numbered `D-43N-V44-ADMA-NN` anchors (one per §3 row, NN 01..22) + 1 special `D-43N-V44-ADMA-ERRATUM-01` catalog-erratum entry = 23 total v44.0 sub-phase inputs.

**§5 grep-completeness verdict:** PASS. All 6 grep patterns reconcile cleanly: every Pattern 1-4 hit maps to an A-NN row or an explicit-exclusion attestation; Pattern 5 (53 integration-trust-boundary hits) deliberately excluded per D-300-ENUM-SCOPE-01; **Pattern 6 (negative confirmation): 0 hits** — `grep "adminSeedTraitBucket\|adminClearTraitBucket" contracts/` returns zero, attesting that RNGLOCK-CATALOG §15 rows 154/155/156 + §16 V-016/V-017/V-018 + §C.3.2/C.3.3 are upstream catalog errata for functions that do not exist in source.

**§1.E catalog-erratum attestation:** S-06 `traitBurnTicket[lvl][trait]` has ZERO admin-class writers in source. The phantom rows referenced in RNGLOCK-CATALOG.md §15 rows 154/155/156 (admin trait-bucket writers) + §16 V-016/V-017/V-018 + §C.3.2/§C.3.3 enumerate functions (`adminSeedTraitBucket`, `adminClearTraitBucket`, `:2510 helper`) that **do not exist** in `contracts/`. Source-truth verification: `grep -n "adminSeedTraitBucket\|adminClearTraitBucket" contracts/` returns 0 hits. The actual S-06 writer `_raritySymbolBatch` (DegenerusGameMintModule.sol :594/:602 area, inline-asm sstore) is correctly enumerated by §15 row 153 + §16 V-014/V-015 as EXEMPT-ADVANCEGAME (INTERNAL-only, reached from advanceGame stack). ADMA carry forward to v44.0 plan-phase: `D-43N-V44-ADMA-ERRATUM-01` (see §4) so v44 does NOT spend a sub-phase on non-existent functions.

### Headline Findings

1. **`updateVrfCoordinatorAndSub` (R-02, D-43N-V44-ADMA-02)** is the highest-fanout admin writer in the v43.0 surface — it directly writes participating slots S-47 vrfCoordinator, S-48 vrfSubscriptionId, S-49 vrfKeyHash, S-38 rngRequestTime (clear), and S-46 lootboxRngPacked LR_MID_DAY (clear), corresponding to RNGLOCK-CATALOG §16 V-137 + V-155 + V-157 + V-159 + V-161 (all VIOLATION, tactic (c) pre-lock reorder). This admin function is the canonical emergency-VRF-rotation entry point per the Phase 296 `retryLootboxRng` precedent and intentionally fires during stall windows; v44.0 must reconcile its dual role (legitimate stall recovery vs. mid-flight word swap) before applying a naive `rngLockedFlag` revert.

2. **`wireVrf` (R-01, D-43N-V44-ADMA-01)** writes S-47/S-48/S-49 at construction-time only (no post-deploy reachability per `AdvanceModule.sol:493` docstring: "No post-deploy caller exists on ADMIN; emergency VRF rotation uses updateVrfCoordinatorAndSub instead"). RNGLOCK-CATALOG §16 V-156 + V-158 + V-160 recommend tactic (d) immutable. ADMA recommendation defers to RNGLOCK-CATALOG verdict — tactic (d) "seal post-init or remove" with rationale that wireVrf is structurally one-shot and any further write is a contract bug not an admin attack vector.

3. **`adminSwapEthForStEth` (R-03, D-43N-V44-ADMA-03)** + **`adminStakeEthForStEth` (R-04, D-43N-V44-ADMA-04)** + **`swapGameEthForStEth` (R-05, D-43N-V44-ADMA-05)** mutate S-20 `address(this).balance` (and S-21 `stETH.balanceOf(game)` for the stake variant). Docstrings assert value-neutral semantics ("ADMIN cannot extract funds"), but S-20 is a §5-consumer participating slot per RNGLOCK-CATALOG §14, and a balance mutation during the §5 game-over drain window can perturb resolve-time math regardless of value-neutrality (drain math reads balance, not intent). Tactic (a) `rngLockedFlag` revert recommended.

Note explicitly: the prior catalog-suggested S-06 admin trait-bucket cluster (V-016/V-017/V-018) is a **catalog erratum, not a headline finding** — see §1.E + D-43N-V44-ADMA-ERRATUM-01.

### Downstream Consumers

- **Phase 301 FUZZ-02 action set:** reads §1 admin function enumeration (37 rows) as the fuzz action-set input. The pure-admin-state-only subset (21 functions) still belongs in the fuzz action set per FUZZ-02 charter (every admin/owner function), but only the 16 §3 entries carry rngLock-window invariants to assert.
- **Phase 303 TERMINAL §3.E ADMA roll-up:** sources prose from this §0 executive summary verbatim.
- **v44.0 FIX-MILESTONE plan-phase:** reads §4 consolidated handoff register as load-bearing input. The ERRATUM-01 entry ensures v44 plan-phase skips phantom-function sub-phases and may optionally schedule a catalog-revision sub-phase.

---

## §1 — Complete Admin Function Enumeration (ADMA-01)

**Scope (D-300-ENUM-SCOPE-01):** all-source admin/owner/role-gated external entry points in `contracts/`. Specifically:

1. Explicit `onlyOwner` modifier (custom; OZ-AccessControl not used in this codebase) at external function declarations.
2. `onlyVaultOwner` modifier at external function declarations.
3. Hand-rolled `if (msg.sender != ContractAddresses.ADMIN) revert E();` gates at external function bodies.
4. Hand-rolled `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` gates.
5. Hand-rolled `if (!vault.isVaultOwner(msg.sender)) revert ...;` checks at external function bodies (inline equivalent of the `onlyOwner` / `onlyVaultOwner` modifiers).

**Discovered modifier index (modifier definitions, NOT counted as §1 rows):**

| Modifier | File:line | Check predicate |
|---|---|---|
| `onlyVaultOwner` | `DegenerusVault.sol:431` | `if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();` at `:432` |
| `onlyOwner` (DeityPass variant) | `DegenerusDeityPass.sol:80` | `if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();` at `:81` |
| `onlyOwner` (DegenerusAdmin variant) | `DegenerusAdmin.sol:436` | `if (!vault.isVaultOwner(msg.sender)) revert NotOwner();` at `:437` |

**Carve-out — deliberately excluded from §1 enumeration (with rationale):**

- **Integration-trust-boundary modifiers** (per D-300-ENUM-SCOPE-01): `onlyGame`, `onlyCoin`, `onlyCoinflip`, `onlyVault` (capital-V — the inter-contract Vault gate, distinct from `onlyVaultOwner`), `onlyBurnieCoin`, `onlyFlipCreditors`, `onlyDegenerusGameContract`. These gate calls *between* protocol contracts and are not administrative entry points. Pattern 5 grep at §5 confirms 53 total integration-trust-boundary modifier hits, all excluded.
- **EOA self-config setters** (no admin-class gate; player-callable for own state):
  - `DegenerusGame.setOperatorApproval` (decl `:435`) — writes `operatorApprovals[msg.sender][operator]`; no access gate.
  - `DegenerusGame.setAutoRebuy` (decl `:1495`) — uses `_resolvePlayer(player)`; only check is the existing internal `RngLocked` gate at `_setAutoRebuy:1513`.
  - `DegenerusGame.setAutoRebuyTakeProfit` (decl `:1504`) — same shape; internal gate at `:1528`.
  - `DegenerusGame.setAfKingMode` (decl `:1559`) — same shape; internal gate at `:1575`.
  These functions ARE captured by RNGLOCK-CATALOG §16 V-009..V-013 as player-callable VIOLATIONs in their own right. ADMA does NOT classify them as admin-class because the gate is operator approval / self-config, not vault-owner privilege; Phase 303 FINDINGS routes them via the catalog V-NNN handoffs (D-43N-V44-HANDOFF-04..08), not via §4 ADMA register.
- **DegenerusAdmin internal discriminator branches** (NOT external admin entries):
  - `DegenerusAdmin.sol:507` `if (vault.isVaultOwner(msg.sender)) { path = ProposalPath.Admin; }` is INSIDE `proposeFeedSwap` (declared `:479`). The enclosing function has no admin gate at entry; the branch routes the proposal between Admin/Community paths.
  - `DegenerusAdmin.sol:670` (same shape) is INSIDE `propose` (declared `:647`). Same disposition.
  Both are community-callable externals; out of D-300-ENUM-SCOPE-01 scope.
- **Internal helpers with conditional vault-owner fallback** (NOT external entries):
  - `DegenerusGameAdvanceModule.sol:1035` `if (!vault.isVaultOwner(caller)) revert MustMintToday();` is inside the INTERNAL helper `_enforceDailyMintGate` (decl `:1000`); the gate is a *bypass* path for vault owners, not an admin gate at entry. Excluded.
- **Pure-view admin functions** (no SSTORE) per D-300-ENUM-SCOPE-01. Notable: `DegenerusGame.sampleTraitTickets`, `sampleTraitTicketsAtLevel`, and `getTickets` are external **view** functions that READ `traitBurnTicket` — they are NOT admin writers and are explicitly excluded; see §1.E for catalog-erratum carry forward.
- **Internal-only admin helpers** (no external/public entry point) per D-300-ENUM-SCOPE-01. Notable: `DegenerusGameMintModule._raritySymbolBatch` is INTERNAL-only, reached only from advanceGame-chain ADVANCEMODE; correctly enumerated by RNGLOCK-CATALOG §16 V-014/V-015 as EXEMPT-ADVANCEGAME; explicitly excluded from §1.
- **Construction-time initial-state writes** (constructor / inline initializer): `DegenerusVault.sol:235` writes `balanceOf[ContractAddresses.CREATOR] = INITIAL_SUPPLY` in constructor body, not an admin gate at runtime — excluded.

**§1 enumeration table:**

| # | Contract | Function (file:line) | Role-gate annotation | Admin-class | Notes |
|---|---|---|---|---|---|
| A-01 | DegenerusVault | `gameAdvance` (DegenerusVault.sol:500) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed `advanceGame` dispatch into DegenerusGame |
| A-02 | DegenerusVault | `gamePurchase` (DegenerusVault.sol:513) | `external payable onlyVaultOwner` (multi-line; modifier at closing `:519`) | general | Vault-routed `purchase` dispatch |
| A-03 | DegenerusVault | `gamePurchaseTicketsBurnie` (DegenerusVault.sol:534) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed BURNIE ticket purchase |
| A-04 | DegenerusVault | `gamePurchaseBurnieLootbox` (DegenerusVault.sol:543) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed BURNIE lootbox purchase |
| A-05 | DegenerusVault | `gameOpenLootBox` (DegenerusVault.sol:551) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed `openLootBox` dispatch |
| A-06 | DegenerusVault | `gamePurchaseDeityPassFromBoon` (DegenerusVault.sol:561) | `external payable onlyVaultOwner` (modifier `:431`) | general | Vault-routed deity-pass purchase via boon |
| A-07 | DegenerusVault | `gameClaimWinnings` (DegenerusVault.sol:575) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed claimWinnings (stETH-first) |
| A-08 | DegenerusVault | `gameClaimWhalePass` (DegenerusVault.sol:581) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed claimWhalePass |
| A-09 | DegenerusVault | `gameDegeneretteBet` (DegenerusVault.sol:594) | `external payable onlyVaultOwner` (multi-line; modifier at closing `:601`) | general | Vault-routed degenerette bet placement |
| A-10 | DegenerusVault | `gameResolveDegeneretteBets` (DegenerusVault.sol:620) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed resolveDegeneretteBets |
| A-11 | DegenerusVault | `gameSetAutoRebuy` (DegenerusVault.sol:627) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed setAutoRebuy (writes vault's autoRebuyState) |
| A-12 | DegenerusVault | `gameSetAutoRebuyTakeProfit` (DegenerusVault.sol:634) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed setAutoRebuyTakeProfit |
| A-13 | DegenerusVault | `gameSetAfKingMode` (DegenerusVault.sol:643) | `external onlyVaultOwner` (multi-line; modifier at closing `:647`) | general | Vault-routed setAfKingMode |
| A-14 | DegenerusVault | `gameSetOperatorApproval` (DegenerusVault.sol:655) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed setOperatorApproval (writes operatorApprovals[vault]) |
| A-15 | DegenerusVault | `coinDepositCoinflip` (DegenerusVault.sol:662) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed BURNIE coinflip deposit |
| A-16 | DegenerusVault | `coinClaimCoinflips` (DegenerusVault.sol:670) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed claim BURNIE coinflips |
| A-17 | DegenerusVault | `coinDecimatorBurn` (DegenerusVault.sol:677) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed decimator BURNIE burn |
| A-18 | DegenerusVault | `coinSetAutoRebuy` (DegenerusVault.sol:685) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed BURNIE auto-rebuy config |
| A-19 | DegenerusVault | `coinSetAutoRebuyTakeProfit` (DegenerusVault.sol:692) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed BURNIE take-profit config |
| A-20 | DegenerusVault | `wwxrpMint` (DegenerusVault.sol:700) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed WWXRP mint passthrough |
| A-21 | DegenerusVault | `jackpotsClaimDecimator` (DegenerusVault.sol:708) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed claimDecimatorJackpot |
| A-22 | DegenerusVault | `sdgnrsBurn` (DegenerusVault.sol:719) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed sDGNRS burn-for-redemption |
| A-23 | DegenerusVault | `sdgnrsClaimRedemption` (DegenerusVault.sol:725) | `external onlyVaultOwner` (modifier `:431`) | general | Vault-routed sDGNRS claimRedemption |
| A-24 | DegenerusDeityPass | `setRenderer` (DegenerusDeityPass.sol:94) | `external onlyOwner` (modifier `:80`; vault.isVaultOwner check `:81`) | governance | Sets the optional external SVG renderer pointer |
| A-25 | DegenerusDeityPass | `setRenderColors` (DegenerusDeityPass.sol:104) | `external onlyOwner` (multi-line; modifier at closing `:108`) | governance | Sets on-chain render colors |
| A-26 | DegenerusAdmin | `swapGameEthForStEth` (DegenerusAdmin.sol:631) | `external payable onlyOwner` (modifier `:436`; vault.isVaultOwner check `:437`) | governance | Vault-owner liquidity ops; calls `gameAdmin.adminSwapEthForStEth` |
| A-27 | DegenerusGame | `setLootboxRngThreshold` (DegenerusGame.sol:479) | inline: `if (!vault.isVaultOwner(msg.sender)) revert E();` at `:480` | parameter-update | Updates lootbox RNG threshold (wei) in `LR_THRESHOLD` field of `lootboxRngPacked` |
| A-28 | DegenerusGame | `adminSwapEthForStEth` (DegenerusGame.sol:1805) | inline: `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:1809` | governance | Value-neutral ETH→stETH swap; transfers stETH out, accepts ETH in |
| A-29 | DegenerusGame | `adminStakeEthForStEth` (DegenerusGame.sol:1826) | inline: `if (!vault.isVaultOwner(msg.sender)) revert E();` at `:1827` | governance | Stakes game-held ETH into Lido; reserves player-claim ETH |
| A-30 | DegenerusGameAdvanceModule | `wireVrf` (DegenerusGameAdvanceModule.sol:498) | inline: `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:503` | governance | Constructor-one-shot VRF wiring per docstring (`:493`); reachable only from `DegenerusAdmin.constructor` |
| A-31 | DegenerusGameAdvanceModule | `updateVrfCoordinatorAndSub` (DegenerusGameAdvanceModule.sol:1677) | inline: `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:1682` | governance | Emergency VRF coordinator rotation; resets `rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, `rngWordCurrent`, `LR_MID_DAY` |
| A-32 | DegenerusStonk | `unwrapTo` (DegenerusStonk.sol:187) | inline: `if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();` at `:188`; secondary `if (game.rngLocked()) revert Unauthorized();` at `:190` | governance | Vault-owner DGNRS→sDGNRS unwrap to soulbound recipient |
| A-33 | DegenerusStonk | `claimVested` (DegenerusStonk.sol:202) | inline: `if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();` at `:203` | governance | Vault-owner claims vested DGNRS based on level |
| A-34 | GNRUS | `setCharity` (GNRUS.sol:378) | inline: `if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();` at `:380` | governance | Vault-owner charity-allowlist mutator; gated by locked-slot guard at `:387` |
| A-35 | Icons32Data | `setPaths` (Icons32Data.sol:153) | inline: `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` at `:154` | governance | CREATOR-gated SVG-path setter; locked post-finalize |
| A-36 | Icons32Data | `setSymbols` (Icons32Data.sol:171) | inline: `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` at `:172` | governance | CREATOR-gated symbol-name setter; locked post-finalize |
| A-37 | Icons32Data | `finalize` (Icons32Data.sol:196) | inline: `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` at `:197` | governance | CREATOR-gated one-shot finalize; locks all setters |

**Row tally:** 37 rows (23 Vault + 2 DeityPass + 1 DegenerusAdmin + 3 Icons32Data + 3 DegenerusGame + 2 AdvanceModule + 2 DegenerusStonk + 1 GNRUS = 37 ✓ matches D-300-ENUM-SCOPE-01 expected floor).

### §1.E — Catalog erratum carry forward (RNGLOCK-CATALOG.md S-06)

RNGLOCK-CATALOG.md §15 rows 154/155/156 and §16 rows V-016/V-017/V-018 enumerate
phantom admin-class writers (`adminSeedTraitBucket`, `adminClearTraitBucket`,
`:2510 helper`) at DegenerusGame.sol:2398/:2427/:2510. Direct source verification
at plan-time shows those line numbers resolve to view-function reads inside
`sampleTraitTickets` / `sampleTraitTicketsAtLevel` / `getTickets` — these admin
functions DO NOT EXIST in `contracts/`. Verification grep:
`grep -n "adminSeedTraitBucket\|adminClearTraitBucket" contracts/` returns 0 hits.
The actual S-06 `traitBurnTicket` writer is `_raritySymbolBatch` in
`DegenerusGameMintModule.sol:594/:602` area (inline-asm sstore), which the
catalog correctly enumerates at §15 row 153 as the writer and §16 rows V-014/V-015
as EXEMPT-ADVANCEGAME. `_raritySymbolBatch` is INTERNAL-only and is correctly
out of D-300-ENUM-SCOPE-01 scope.

ADMA carry forward: S-06 has ZERO admin-class writers; consequently ZERO §1 rows,
ZERO §2 VIOLATION rows, and ZERO §3 entries for S-06. RNGLOCK-CATALOG.md is
untouched (Phase 298 closed artifact per D-300-KI-01-adjacent posture); the
catalog erratum is recorded here and carried into the v44.0 FIX-MILESTONE handoff
register §4 as `D-43N-V44-ADMA-ERRATUM-01` so v44 plan-phase does NOT spend a
sub-phase on non-existent functions and so v44 plan-phase OR a future catalog-
revision phase can correct the upstream §15/§16/§C.3.2/§C.3.3 rows. §17 rows
1421/1422 and §18 rows 1438/1439 (which reference the same phantom writers in
the executive-summary / grep-gate sections) inherit the same erratum.

---

## §2 — Participating-Slot Cross-Reference Table (ADMA-02)

Per `D-300-ADMA-LAYOUT-01`: each admin function (A-NN) is cross-referenced against the RNGLOCK-CATALOG §14 participating-slot index. For each participating slot reached at a non-EXEMPT callsite, the matching §15 writer row + §16 verdict are recorded with a 1-line rationale.

**Preamble notes:**

- Per §1.E, **S-06 has zero admin-class writers** — no §2 rows reference S-06; the phantom catalog rows (§15 154/155/156, §16 V-016/V-017/V-018) are NOT enumerated here. Erratum carried to §4 as `D-43N-V44-ADMA-ERRATUM-01`.
- Most DegenerusVault `onlyVaultOwner` externals (A-01..A-23) are dispatchers that forward into a top-level DegenerusGame / BurnieCoin / Jackpots external. Where the underlying external (e.g. `purchase`, `openLootBox`, `placeDegeneretteBet`, `claimWinnings`) already appears in RNGLOCK-CATALOG §15/§16, the vault-routed path inherits the same write set + verdict from that callsite. The Vault entry adds one additional logical reach edge but does not introduce new participating-slot writes.
- Admin functions whose body writes only admin/config slots (e.g. `setRenderer` writes the `renderer` pointer in DeityPass — not a §14 participating slot) are recorded with `Participating slot(s) = (none)` and `Callsite verdict = N/A (pure-admin-state-only)`. These rows do NOT produce a §3 recommendation entry but document the comprehensive cross-reference per ADMA-02.
- Verdict-classification rule: an admin function writing a participating slot is `VIOLATION` UNLESS reached exclusively from one of the three EXEMPT entry points (advanceGame / VRF callback / retryLootboxRng). Admin entries are user-callable governance/parameter-update functions; none of the three EXEMPT classes apply except for `wireVrf`, which is constructor-one-shot (RNGLOCK-CATALOG §16 V-156/V-158/V-160 classifies it as VIOLATION (d) immutable — surface preserved here).

**§2 cross-reference table:**

| Admin fn (§1 row) | Contract.fn (file:line) | Participating slot(s) written | Writer in CAT-03 (§15 row) | Callsite verdict (EXEMPT-* / VIOLATION / N/A) | Notes |
|---|---|---|---|---|---|
| A-01 gameAdvance | DegenerusVault.sol:500 | (none — dispatches to `gamePlayer.advanceGame()`; advanceGame stack is its own EXEMPT class) | n/a (advanceGame stack is the EXEMPT-ADVANCEGAME source itself) | EXEMPT-ADVANCEGAME (entire advanceGame stack is the canonical EXEMPT entry) | The wrapper is owner-gated but the underlying writes are all in the EXEMPT-ADVANCEGAME class per §16 V-001..V-198 |
| A-02 gamePurchase | DegenerusVault.sol:513 | S-09 prizePoolsPacked, S-32 mintPacked_[player], S-30 presaleStatePacked, S-24..S-29 lootboxEth/lootboxDay/lootboxBaseLevelPacked/lootboxEvScorePacked/lootboxDistressEth/lootboxBurnie, S-35 lastPurchaseDay, S-52 ticketQueue, S-53 ticketsOwedPacked | RNGLOCK-CATALOG §15 S-09 (MintModule `_processMintPayment`/`_handleMintRevenue` from `purchase`); S-32 row `MintModule._allocateMintPacked` :240/:275/:369; S-30 `_presaleCapCheck` :1026; S-24 `_allocateLootbox` :1013; S-25 :991; S-26 :992; S-27 :1155; S-28 :1031; S-52 `_queueTicketsScaled` from `_purchaseFor` :1129; S-53 co-located; S-35 purchase-path writer | VIOLATION | Cross-refs §16 V-024 (S-09 MintModule), V-089/V-091/V-095/V-098/V-101 (S-24..S-28), V-105 (S-30), V-110 (S-32), V-127 (S-35), V-174 (S-52), V-179 sub-rows (S-53). Tactic (a) `rngLockedFlag` revert at MintModule.purchase entry. Inherited via dispatcher A-02. |
| A-03 gamePurchaseTicketsBurnie | DegenerusVault.sol:534 | S-09, S-32, S-25 lootboxDay, S-29 lootboxBurnie, S-52, S-53 (BURNIE-allocation path) | §15 S-09 (MintModule.purchaseCoin); S-25 `_burnieAllocate` :1397; S-29 `_burnieAllocate` :1399; S-32 + S-52/S-53 co-located | VIOLATION | Cross-refs §16 V-024 + V-092 + V-104 + V-110 + V-174/V-179. Tactic (a) revert at MintModule.purchaseCoin entry. |
| A-04 gamePurchaseBurnieLootbox | DegenerusVault.sol:543 | S-29 lootboxBurnie, S-25 lootboxDay, S-52, S-53 | §15 S-29 `_burnieAllocate` :1399; S-25 :1397 | VIOLATION | Cross-refs §16 V-104 + V-092 + V-174/V-179. Tactic (a) revert at MintModule.purchaseBurnieLootbox entry. |
| A-05 gameOpenLootBox | DegenerusVault.sol:551 | S-22 lootboxEvBenefitUsedByLevel, S-24..S-29 self-zero writes, S-52 `_queueTickets` from `openLootBox` | §15 S-22 LootboxModule `_applyEvMultiplierWithCap` :511 (from `openLootBox`); S-24 :576 self-zero; S-26 :578; S-27 :579; S-28 :581; S-52 LootboxModule :1067 | VIOLATION | Cross-refs §16 V-081 + V-088 + V-094 + V-097 + V-100 + V-171. Tactic (b) snapshot at allocation (Phase 281 owed-salt pattern). |
| A-06 gamePurchaseDeityPassFromBoon | DegenerusVault.sol:561 | S-07 deityBySymbol, S-18 deityPassOwners, S-19 deityPassPurchasedCount, S-32 mintPacked_, S-34 boonPacked, S-52, S-53 | §15 S-07 WhaleModule `_purchaseDeityPass` :598 (EOA :538); S-18 :596; S-19 :595; S-32 :589 (`_buyDeityPass`); S-34 :202/:388/:556/:898 boon writes; S-52 :625 | VIOLATION | Cross-refs §16 V-019 (S-07) + V-069 (S-18) + V-070 (S-19) + V-114 (S-32 buyDeityPass) + V-121 (S-34) + V-170 (S-52). Tactic (a) `rngLockedFlag` revert. |
| A-07 gameClaimWinnings | DegenerusVault.sol:575 | S-16 claimablePool, S-20 address(this).balance | §15 S-16 `DegenerusGame.claimWinnings` :1408; S-20 `claimWinnings` outflow :1408 | VIOLATION | Cross-refs §16 V-063 (S-16) + V-073 (S-20). Tactic (a) gate on `!_livenessTriggered() \|\| gameOver` (subsumed by V-063 single revert covers both slots). |
| A-08 gameClaimWhalePass | DegenerusVault.sol:581 | S-09 prizePoolsPacked, S-52 ticketQueue, S-53 ticketsOwedPacked | §15 S-09 `claimWhalePass` → `_queueTicketRange` adjacent writes `:1692`/`WhaleModule:957`; S-52 `_queueTicketRange` from `claimWhalePass` `WhaleModule:973` | VIOLATION | Cross-refs §16 V-030 (S-09) + V-176 (S-52) + V-179. Tactic (a) top-level `rngLockedFlag` revert; far-future loop revert is partial coverage. |
| A-09 gameDegeneretteBet | DegenerusVault.sol:594 | S-02 dailyHeroWagers[day][q], S-43 degeneretteBets[player][nonce], S-09 prizePoolsPacked, S-45 prizePoolPendingPacked | §15 S-02 `_placeDegeneretteBetCore` :499 (vault-routed callsite `DegenerusVault.sol:607`); S-43 :479; S-09 `_collectBetFunds` from placeDegeneretteBet :367; S-45 :553 | VIOLATION | Cross-refs §16 V-005 (S-02 vault-routed), V-142 (S-43), V-031 (S-09), V-147 (S-45). Tactic (b) day-key freeze attestation (Phase 288 dailyIdx snapshot). |
| A-10 gameResolveDegeneretteBets | DegenerusVault.sol:620 | (none — `gamePlayer.resolveDegeneretteBets` is consumer-self stack via VRF; S-43 delete is consumer-self) | §15 S-43 `_resolveBet` self-delete :597 | EXEMPT-VRFCALLBACK | Self-stack post-VRF; row V-143 in §16 |
| A-11 gameSetAutoRebuy | DegenerusVault.sol:627 | S-05 autoRebuyState[beneficiary=vault] | §15 S-05 `_setAutoRebuy` :1512 (callsite :1495) | VIOLATION | Cross-refs §16 V-009 (vault is the beneficiary; same gate). Tactic (a) verify existing internal RngLocked revert at `_setAutoRebuy:1513` covers vault-routed entry. NOTE: ADMA does not emit a separate §3 entry — vault-routed reach is the same underlying writer fn as catalog V-009; handoff anchor folds into D-43N-V44-HANDOFF-04 at v44.0. |
| A-12 gameSetAutoRebuyTakeProfit | DegenerusVault.sol:634 | S-05 autoRebuyState[beneficiary=vault] | §15 S-05 `_setAutoRebuyTakeProfit` :1524 (callsite :1504) | VIOLATION | Same disposition as A-11 — folds into D-43N-V44-HANDOFF-05 |
| A-13 gameSetAfKingMode | DegenerusVault.sol:643 | S-05 autoRebuyState[beneficiary=vault] | §15 S-05 `_setAfKingMode` :1569 (callsite :1559) | VIOLATION | Same disposition as A-11 — folds into D-43N-V44-HANDOFF-06 |
| A-14 gameSetOperatorApproval | DegenerusVault.sol:655 | (none — writes `operatorApprovals[vault][operator]`; not a §14 participating slot) | n/a | N/A (pure-admin-state-only) | Operator approval mapping is not consumed in any §1..§13 SLOAD set |
| A-15 coinDepositCoinflip | DegenerusVault.sol:662 | S-55 bountyOwedTo (via BurnieCoinflip `_addDailyFlip` arming arm) | §15 S-55 `_addDailyFlip` :681 (callsite `BurnieCoinflip:229`) | VIOLATION | Cross-refs §16 V-182 (tactic (a) bounty arming gate at :664 already covers; extend to fail-closed revert). Vault-routed via depositCoinflip dispatcher; folds into D-43N-V44-HANDOFF-110 at v44.0. |
| A-16 coinClaimCoinflips | DegenerusVault.sol:670 | (none — writes player's claimable BURNIE state; no §14 participating slot) | n/a | N/A (pure-admin-state-only) | |
| A-17 coinDecimatorBurn | DegenerusVault.sol:677 | S-09 prizePoolsPacked, S-66 decBurn[lvl][player].burn (via `recordDecBurn`) | §15 S-09 `recordDecBurn` :1029 (BurnieCoin callback); S-66 `recordDecBurn` :731 | VIOLATION | Cross-refs §16 V-027 (S-09) + V-201 (S-66). Tactic (a) gate `recordDecBurn` on `decClaimRounds[lvl].poolWei == 0`; vault-routed via `coinDecimatorBurn` dispatcher. |
| A-18 coinSetAutoRebuy | DegenerusVault.sol:685 | (none — BURNIE coinflip auto-rebuy config; writes `playerState[vault].afKingMode`/auto-rebuy fields not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |
| A-19 coinSetAutoRebuyTakeProfit | DegenerusVault.sol:692 | (none — same as A-18) | n/a | N/A (pure-admin-state-only) | |
| A-20 wwxrpMint | DegenerusVault.sol:700 | (none — WWXRP ERC20 mint; WrappedWrappedXRP storage is not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |
| A-21 jackpotsClaimDecimator | DegenerusVault.sol:708 | S-16 claimablePool (via `_awardDecimatorLootbox`) | §15 S-16 `DecimatorModule._awardDecimatorLootbox` :388 (callsite EOA `claimDecimatorJackpot`) | VIOLATION | Cross-refs §16 V-054. Tactic (a) gate callsite on `!_livenessTriggered()`. |
| A-22 sdgnrsBurn | DegenerusVault.sol:719 | S-17 pendingRedemptionEthValue, S-56 redemptionPeriodIndex, S-57 pendingRedemptionEthBase, S-58 pendingRedemptionBurnieBase, S-59 pendingRedemptionBurnie, S-60 pendingRedemptions[player] | §15 S-17 `_submitGamblingClaimFrom` :789; S-56 :760; S-57 :790; S-58 :792; S-59 :791; S-60 :803/:805/:806/:810 | VIOLATION | Cross-refs §16 V-066 (S-17) + V-184 (S-56) + V-186 (S-57) + V-188 (S-58) + V-190 (S-59) + V-191 (S-60). Tactic (a) `BurnsBlockedDuringLiveness` covers + new revert if `redemptionPeriods[redemptionPeriodIndex].roll != 0`. |
| A-23 sdgnrsClaimRedemption | DegenerusVault.sol:725 | S-17 pendingRedemptionEthValue (decrement), S-60 pendingRedemptions[player] (delete/partial clear) | §15 S-17 `claimRedemption` :657; S-60 :661/:664 | VIOLATION | Cross-refs §16 V-068 (S-17) + V-192/V-193 (S-60). Tactic (a) subsumed by V-184 (S-56 re-resolution lock). |
| A-24 setRenderer | DegenerusDeityPass.sol:94 | (none — writes `renderer` pointer in DegenerusDeityPass; not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |
| A-25 setRenderColors | DegenerusDeityPass.sol:104 | (none — writes `_outlineColor`/`_backgroundColor`/`_nonCryptoSymbolColor` strings; not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |
| A-26 swapGameEthForStEth | DegenerusAdmin.sol:631 | S-20 address(this).balance (forwards `msg.value` then receives stETH out via `gameAdmin.adminSwapEthForStEth`) | §15 S-20 row "payable purchase functions inflate balance" + "`steth.transfer` out" via `adminSwapEthForStEth` | VIOLATION | Cross-refs §16 V-072 (S-20 payable in) + V-074 (S-20 sDGNRS/vault/GNRUS withdrawals — analogous swap-out class). Tactic (a) `rngLockedFlag` revert at DegenerusAdmin.swapGameEthForStEth entry. |
| A-27 setLootboxRngThreshold | DegenerusGame.sol:479 | LR_THRESHOLD field of S-46 lootboxRngPacked (NOT a participating field — only LR_INDEX and LR_MID_DAY are §14 participating per §15 S-46 rows) | n/a (LR_THRESHOLD not enumerated as a participating slot) | N/A (pure-admin-state-only) | RNGLOCK-CATALOG §14 S-46 specifically lists "LR_INDEX + LR_MID_DAY fields" as participating. LR_THRESHOLD is a pre-VRF threshold parameter, read in `requestLootboxRng` to decide whether to fire the VRF call but not consumed alongside RNG output. Documented exclusion. |
| A-28 adminSwapEthForStEth | DegenerusGame.sol:1805 | S-20 address(this).balance, S-21 stETH.balanceOf(game) | §15 S-20 "every `payable` purchase function" / "claimWinnings outflow" (analogous payable-in + transfer-out class); S-21 `steth.transfer(to, amount)` outgoing class | VIOLATION | Cross-refs §16 V-072 (S-20 payable-in) + V-080 (S-21 incoming class — symmetric outgoing handled by V-072 family). Tactic (a) `rngLockedFlag` revert at adminSwapEthForStEth entry. Despite "value-neutral" docstring, swap mutates both balances; S-20/S-21 are §5 consumer participating slots. |
| A-29 adminStakeEthForStEth | DegenerusGame.sol:1826 | S-20 address(this).balance, S-21 stETH.balanceOf(game) | §15 S-21 `AdvanceModule._stakeEth` :1555 (game → Lido) | VIOLATION | Cross-refs §16 V-079 (S-21 advanceGame stack) + V-072 (S-20 payable-in class). Tactic (a) `rngLockedFlag` revert at adminStakeEthForStEth entry; the writer reaches outside the advanceGame stack when called as a standalone admin entry, so the V-079 EXEMPT classification does NOT apply at the admin callsite. |
| A-30 wireVrf | DegenerusGameAdvanceModule.sol:498 | S-47 vrfCoordinator, S-48 vrfSubscriptionId, S-49 vrfKeyHash | §15 S-47 wireVrf :506; S-48 :507; S-49 :508 | VIOLATION (constructor-only one-shot per docstring; classified VIOLATION (d) per catalog V-156/V-158/V-160) | Cross-refs §16 V-156 + V-158 + V-160. Tactic (d) immutable: bind VRF config at deploy and remove wireVrf or seal post-init. Per `AdvanceModule.sol:493` docstring, no post-deploy caller exists on ADMIN; the function is structurally one-shot and any further write is a contract bug rather than admin attack vector. |
| A-31 updateVrfCoordinatorAndSub | DegenerusGameAdvanceModule.sol:1677 | S-47 vrfCoordinator, S-48 vrfSubscriptionId, S-49 vrfKeyHash, S-38 rngRequestTime (clear), S-46 lootboxRngPacked LR_MID_DAY (clear), S-39 rngLockedFlag (= false implicit) | §15 S-47 :1685; S-48 :1686; S-49 :1687; S-38 :1692 clear; S-46 LR_MID_DAY :1698 clear | VIOLATION | Cross-refs §16 V-157 + V-159 + V-161 (S-47/S-48/S-49) + V-137 (S-38 governance) + V-155 (S-46 governance). Tactic (c) pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout. |
| A-32 unwrapTo | DegenerusStonk.sol:187 | (none — writes DGNRS `balanceOf`, sDGNRS `wrapperTransferTo`; ERC20 balances on DGNRS/sDGNRS are NOT in §14 participating set — only sDGNRS `poolBalances[Reward]`/`poolBalances[Lootbox]` S-14/S-15 are participating; `unwrapTo` does not write those pool balances) | n/a | N/A (pure-admin-state-only) | The `if (game.rngLocked()) revert Unauthorized();` gate at `:190` is the existing rngLock defense; documented as defensive but not a participating-slot writer. |
| A-33 claimVested | DegenerusStonk.sol:202 | (none — writes `_vestingReleased`, `balanceOf[recipient]`, total `balanceOf[address(this)]` decrement; not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |
| A-34 setCharity | GNRUS.sol:378 | (none — writes `currentSlate[slot]`, `pendingEdits` slot, slot bitmap; GNRUS charity-allowlist storage is not in §14 participating set) | n/a (charity-allowlist is not consumed in §1..§13 SLOAD set; the catalog does not enumerate any S-NN slot for GNRUS allowlist mutators) | N/A (pure-admin-state-only) | NOTE: GNRUS `pickCharity:623` (called from advanceGame's jackpot stack — see RNGLOCK-CATALOG §15 S-14 mention) reads the allowlist; if setCharity mutates the allowlist mid-window, the read at advanceGame could see different output. However, the catalog does NOT enumerate the GNRUS allowlist as a §14 slot, so ADMA-02 verdict per the catalog-anchored methodology is N/A. **This is flagged as a potential §1.E-style cross-contract participating-slot gap and routed to v44.0 as a §3 governance-class recommendation (R-06) with explicit cross-reference to RNGLOCK-CATALOG §15 S-14 sDGNRS row 170 `_handleSoloBucketWinner` callsite which reaches into the GNRUS charity-allowlist read path.** |
| A-35 setPaths | Icons32Data.sol:153 | (none — writes `_paths[i]` SVG strings; Icons32Data storage is not in §14 participating set; locked post-finalize) | n/a | N/A (pure-admin-state-only) | |
| A-36 setSymbols | Icons32Data.sol:171 | (none — writes `_symQ1/Q2/Q3` symbol-name arrays; not in §14 participating set; locked post-finalize) | n/a | N/A (pure-admin-state-only) | |
| A-37 finalize | Icons32Data.sol:196 | (none — writes `_finalized = true`; not in §14 participating set) | n/a | N/A (pure-admin-state-only) | |

**§2 row count:** 37 rows (one per §1 row).

**§2 VIOLATION row count:** 21 distinct admin functions whose verdict cell is VIOLATION: A-02, A-03, A-04, A-05, A-06, A-07, A-08, A-09, A-11, A-12, A-13, A-15, A-17, A-21, A-22, A-23, A-26, A-28, A-29, A-30, A-31. Per `D-300-ADMA-LAYOUT-01` "Do NOT collapse rows", each admin function generates its own §3 entry even when the recommendation is folded against an existing catalog V-NNN handoff — v44.0 plan-phase consumes per-admin-function anchors and folding would break the per-sub-phase planning surface. The deduplicated §3 admin-class recommendation count is **22** (21 distinct VIOLATION admin functions + the sDGNRS redemption-pair A-22/A-23 yields R-21 + R-22 separately for per-admin-function handoff fidelity).

**Detailed VIOLATION reconciliation (for §3 anchor planning):**

- **All §2 VIOLATION rows generate fresh §3 entries:** A-02 → R-07, A-03 → R-08, A-04 → R-09, A-05 → R-10, A-06 → R-11, A-07 → R-18, A-08 → R-19, A-09 → R-12, A-11 → R-13, A-12 → R-14, A-13 → R-15, A-15 → R-16, A-17 → R-17, A-21 → R-20, A-22 → R-21, A-23 → R-22, A-26 → R-05, A-28 → R-03, A-29 → R-04, A-30 → R-01, A-31 → R-02. Plus A-34 (setCharity) catalog-gap candidate → R-06.
- **Catalog-handoff folding (recommendation depth, NOT row collapse):** Even when an ADMA recommendation folds into an existing catalog `D-43N-V44-HANDOFF-NN` (e.g., R-13/R-14/R-15 fold into HANDOFF-04/05/06 underlying writer-fn gate), the §3 entry still exists separately with its own `D-43N-V44-ADMA-NN` anchor for per-admin-function v44.0 sub-phase consumption.

§3 emits **22** R-NN rows for the 21 unique VIOLATION admin functions + 1 sDGNRS-pair split.

---

## §3 — Per-Admin-Function Recommendation Table (ADMA-03 + ADMA-04)

Per `D-300-ADMA-LAYOUT-01` + `D-300-GATING-MECHANISM-01`: one entry per §2 unfolded VIOLATION row. Each entry includes admin-class disposition, recommended gating mechanism (RngLocked custom error revert preferred per MintModule:1221 / BurnieCoinflip:730 / sStonk:492 convention), per-admin-function rationale (2-4 sentences: design intent + break-on-naive-gate + residual-EV), and a `D-43N-V44-ADMA-NN` handoff anchor.

**Skeptic-reviewer filter (per `feedback_skeptic_pass_before_catastrophe.md`):** admin attack vector requires admin-key compromise, which is a structural protection layer. Default tactic is (a) `rngLockedFlag` revert; recommendations stay at standard tactic depth unless a specific path bypasses admin-key trust. No CATASTROPHE-tier promotion in this §3; per-row rationale walks the design-intent / break-on-naive-gate / residual-EV axes for EVERY entry regardless of tactic.

### §3.01 — R-01: DegenerusGameAdvanceModule.wireVrf

- **Admin fn:** `wireVrf` (DegenerusGameAdvanceModule.sol:498)
- **Participating slot(s) reached:** S-47 vrfCoordinator, S-48 vrfSubscriptionId, S-49 vrfKeyHash
- **Admin-class disposition:** governance
- **Recommended gating mechanism:** **Tactic (d) immutable** — per RNGLOCK-CATALOG §16 V-156/V-158/V-160. Bind VRF config at deploy and remove `wireVrf` or seal it via a one-shot post-init flag. Do NOT use `RngLocked` revert here; the function is structurally constructor-only per `AdvanceModule.sol:493` docstring ("No post-deploy caller exists on ADMIN; emergency VRF rotation uses updateVrfCoordinatorAndSub instead"), so a runtime `rngLockedFlag` gate would be dead code relative to the one-shot semantics.
- **Per-admin-function rationale:** (a) `wireVrf` exists to wire VRF coordinator + subscription + key hash at deployment time, called once from the `DegenerusAdmin` constructor (`DegenerusAdmin.sol:458`); the chained call path is `DegenerusGame.wireVrf:308` → `IDegenerusGameAdvanceModule.wireVrf.selector` delegatecall. (b) A naive `rngLockedFlag` revert would be no-op because the function is unreachable post-deploy in normal operation — the docstring explicitly states ADMIN has no post-deploy caller for wireVrf. (c) The legitimate operational reason for any post-deploy `wireVrf` call would be a contract-deployment bug (the constructor path failed to initialize VRF state); no expected admin workflow requires it. (d) Residual EV: if ADMIN address has post-deploy code-execution capability and could synthesize a `wireVrf` call, the writes to S-47/S-48/S-49 mid-rngLock window would re-wire the VRF callback target — a CATASTROPHE-class outcome (RNG word becomes attacker-controllable). The skeptic-filter check: this requires both admin-key compromise AND a contract-level write-after-deploy capability that doesn't exist by construction. Tactic (d) immutable closes the gap structurally.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-156 (S-47), V-158 (S-48), V-160 (S-49); all VIOLATION (d).
- **Anchor:** D-43N-V44-ADMA-01 — Seal `wireVrf` post-init via immutable flag (or remove if Admin constructor wiring is sufficient) | **Admin fn:** DegenerusGameAdvanceModule.wireVrf @ DegenerusGameAdvanceModule.sol:498 | **Slot(s):** S-47, S-48, S-49 | **Tactic:** (d) immutable

### §3.02 — R-02: DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub

- **Admin fn:** `updateVrfCoordinatorAndSub` (DegenerusGameAdvanceModule.sol:1677)
- **Participating slot(s) reached:** S-47 vrfCoordinator, S-48 vrfSubscriptionId, S-49 vrfKeyHash, S-38 rngRequestTime (clear), S-46 lootboxRngPacked LR_MID_DAY (clear), S-39 rngLockedFlag (implicit reset)
- **Admin-class disposition:** governance
- **Recommended gating mechanism:** **Tactic (c) pre-lock reorder** per RNGLOCK-CATALOG §16 V-137 + V-155 + V-157 + V-159 + V-161. Queue mid-stall rotations until after the callback delivers OR a 12h+ timeout elapses; do NOT apply a blanket `rngLockedFlag` revert because the function's *purpose* is to rotate the VRF coordinator during a stall (which is precisely the state where rngLockedFlag is true).
- **Per-admin-function rationale:** (a) `updateVrfCoordinatorAndSub` exists for emergency VRF coordinator rotation when the in-use coordinator stalls; per the function's docstring at `:1690..:1705`, it deliberately resets `rngLockedFlag = false` + `vrfRequestId = 0` + `rngRequestTime = 0` + `rngWordCurrent = 0` + `LR_MID_DAY = 0` so that `advanceGame` can re-fire the daily RNG request after the swap. The Phase 296 `retryLootboxRng` precedent established that *some* admin operations legitimately fire during the rngLock window. (b) A naive `if (rngLockedFlag) revert RngLocked()` revert would break the function's primary use case — if the coordinator stalls mid-request and the admin must rotate to recover, the gate would refuse the rotation. (c) Legitimate window-internal admin operation: yes, this is the canonical use case. (d) Residual EV: if an admin rotates the coordinator while a VRF word is partially propagated through ticket / bet writes (e.g., mid-`_finalizeRngRequest`), the rotation could either (i) cause an in-flight VRF callback to drop on the floor and re-request entropy under a new coordinator — entropy from the original coordinator becomes unconsumed, no consumer relies on it post-rotation; or (ii) deliver the in-flight callback after the rotation and double-credit. Tactic (c) pre-lock reorder addresses (ii) by deferring the rotation until callback completes OR a sufficiently long timeout fences the in-flight request. Skeptic-filter: this is the canonical admin-attack edge case; admin-key compromise + mid-window rotation could let an attacker pre-commit ticket positions and then rotate the coordinator to swap in attacker-controlled VRF output. The 12h+ timeout proposed by V-137/V-155 narrows the window to where attacker visibility into pending writes is constrained.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-137 (S-38), V-155 (S-46 LR_MID_DAY), V-157 (S-47), V-159 (S-48), V-161 (S-49); all VIOLATION (c).
- **Anchor:** D-43N-V44-ADMA-02 — Reorder `updateVrfCoordinatorAndSub` to queue mid-stall rotations until callback delivers or 12h+ timeout | **Admin fn:** DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub @ DegenerusGameAdvanceModule.sol:1677 | **Slot(s):** S-47, S-48, S-49, S-38, S-46 LR_MID_DAY | **Tactic:** (c) pre-lock reorder

### §3.03 — R-03: DegenerusGame.adminSwapEthForStEth

- **Admin fn:** `adminSwapEthForStEth` (DegenerusGame.sol:1805)
- **Participating slot(s) reached:** S-20 address(this).balance, S-21 stETH.balanceOf(game)
- **Admin-class disposition:** governance
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert.** Add `if (rngLockedFlag) revert RngLocked();` at function entry (between the existing `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:1809` and the recipient zero-check). Pattern: `MintModule:1221` / `BurnieCoinflip:730` / `sStonk:492`.
- **Per-admin-function rationale:** (a) `adminSwapEthForStEth` exists as a value-neutral admin operation — the docstring at `:1798..:1804` asserts "ADMIN cannot extract funds" (the function transfers stETH out in exchange for the same amount of ETH in via `msg.value`). The function adjusts the ratio of ETH:stETH on the game contract without changing total game-held value. (b) Naive `rngLockedFlag` revert: the function has no operational requirement to fire during the rngLock window — game-overaging admin liquidity ops can wait for window unlock. (c) Legitimate window-internal need: none — admin liquidity rebalancing is non-urgent compared to drain-math correctness during the §5 game-over window. (d) Residual EV: despite value-neutrality, the swap mutates BOTH S-20 (ETH balance decreases by the stETH amount the game holds, increases by msg.value) AND S-21 (stETH balance decreases). §5 game-over drain math reads both balances directly per RNGLOCK-CATALOG §15 S-20/S-21 rows; an admin firing this swap mid-drain can perturb the math even though net value is unchanged (the ratio shift can change how `_handleGameOverPath` allocates between players claiming ETH-first vs stETH-first via `claimWinningsStethFirst`). Skeptic-filter: admin-key compromise + mid-drain swap could shift game-over payout distribution between deity-pass holders and regular claimants by ~1 wei to ~1 ETH depending on the swap size; small attack surface but non-zero and easily closed by tactic (a).
- **Cross-reference:** RNGLOCK-CATALOG §16 V-072 + V-074 (S-20 family); V-080 (S-21 inflow class).
- **Anchor:** D-43N-V44-ADMA-03 — Add `rngLockedFlag` revert at adminSwapEthForStEth entry | **Admin fn:** DegenerusGame.adminSwapEthForStEth @ DegenerusGame.sol:1805 | **Slot(s):** S-20, S-21 | **Tactic:** (a) rngLockedFlag revert

### §3.04 — R-04: DegenerusGame.adminStakeEthForStEth

- **Admin fn:** `adminStakeEthForStEth` (DegenerusGame.sol:1826)
- **Participating slot(s) reached:** S-20 address(this).balance (decrement), S-21 stETH.balanceOf(game) (increment via Lido wrap)
- **Admin-class disposition:** governance
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert.** Add `if (rngLockedFlag) revert RngLocked();` at function entry (after the existing `if (!vault.isVaultOwner(msg.sender)) revert E();` at `:1827` and the amount-zero check).
- **Per-admin-function rationale:** (a) `adminStakeEthForStEth` exists to stake game-held ETH into Lido stETH, accruing yield. Per the docstring at `:1816..:1825`, it must reserve enough ETH to cover player claims (excluding vault/DGNRS claimable which can be settled in stETH). The reserve check at `:1834..` defends against under-funded ETH state but not against rngLock-window-state racing. (b) Naive `rngLockedFlag` revert: same disposition as R-03 — admin liquidity ops are non-urgent. (c) Legitimate window-internal need: none. (d) Residual EV: similar to R-03 but more impactful because the writer also reaches `AdvanceModule._stakeEth:1555` via the underlying Lido wrap, which is the same writer fn that the catalog classifies as EXEMPT-ADVANCEGAME at the advanceGame callsite (V-075/V-079). At the admin callsite, the same writer fn writes the same slot but OUTSIDE the EXEMPT advanceGame stack — this is a textbook per-callsite-split per `D-298-EXEMPT-REACH-01`. An admin firing this stake mid-drain can fund Lido while the game-over distributor is computing player payouts based on a stale ETH-balance snapshot. Skeptic-filter: admin-key compromise + mid-stake could siphon yield-bearing stETH growth from the drain pool to Lido during the drain itself; closeable by tactic (a).
- **Cross-reference:** RNGLOCK-CATALOG §16 V-079 (S-21 advanceGame stack — EXEMPT) + V-072 (S-20 payable-in class — VIOLATION). At the admin callsite, the EXEMPT classification of V-079 does NOT apply per per-callsite-split discipline.
- **Anchor:** D-43N-V44-ADMA-04 — Add `rngLockedFlag` revert at adminStakeEthForStEth entry | **Admin fn:** DegenerusGame.adminStakeEthForStEth @ DegenerusGame.sol:1826 | **Slot(s):** S-20, S-21 | **Tactic:** (a) rngLockedFlag revert

### §3.05 — R-05: DegenerusAdmin.swapGameEthForStEth

- **Admin fn:** `swapGameEthForStEth` (DegenerusAdmin.sol:631)
- **Participating slot(s) reached:** S-20 address(this).balance (forwards `msg.value` through to `gameAdmin.adminSwapEthForStEth`)
- **Admin-class disposition:** governance
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at the DegenerusAdmin entry point. Implementation note: because this entry point delegates to `gameAdmin.adminSwapEthForStEth` (which is itself the subject of R-03), the gate can be applied at EITHER the DegenerusAdmin entry OR the underlying DegenerusGame entry; placing it at both is belt-and-suspenders but not redundant — DegenerusAdmin entry uses `vault.isVaultOwner` (broader vault-owner audience) while DegenerusGame entry uses `ContractAddresses.ADMIN == msg.sender` (narrower; sender must be DegenerusAdmin contract address). Two callers, two gates.
- **Per-admin-function rationale:** (a) `swapGameEthForStEth` exists as the vault-owner-facing entry into the underlying game-held ETH↔stETH swap; the DegenerusAdmin wrapper allows DGVE majority holders to access the swap without ADMIN-EOA privilege. (b) Naive `rngLockedFlag` revert: same as R-03 — no operational requirement. (c) Legitimate window-internal need: none. (d) Residual EV: same write target (S-20 via the cross-contract call to gameAdmin); the residual EV at the DegenerusAdmin callsite is identical to R-03's. Skeptic-filter: this entry expands the attack surface from "ADMIN-EOA compromise" to "any DGVE >50.1% holder" — a notably wider trust boundary; tactic (a) at this entry is *more* important than at the DegenerusGame entry because the access surface is broader.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-074 (cross-contract withdrawal class), V-072 (payable-in class for the corresponding ETH inflow on the game side).
- **Anchor:** D-43N-V44-ADMA-05 — Add `rngLockedFlag` revert at DegenerusAdmin.swapGameEthForStEth entry | **Admin fn:** DegenerusAdmin.swapGameEthForStEth @ DegenerusAdmin.sol:631 | **Slot(s):** S-20 | **Tactic:** (a) rngLockedFlag revert

### §3.06 — R-06: GNRUS.setCharity

- **Admin fn:** `setCharity` (GNRUS.sol:378)
- **Participating slot(s) reached:** GNRUS `currentSlate[slot]`, `pendingEdits[slot]`, slot bitmaps — these are NOT enumerated in RNGLOCK-CATALOG §14, but are READ from `GNRUS.pickCharity:623` which the catalog reaches via `AdvanceModule:1718 _finalizeEarlybird` (S-14 sDGNRS Reward pool transfer). Cross-contract participating-slot gap candidate.
- **Admin-class disposition:** governance (charity-allowlist mutator)
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at function entry (after the existing `if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();` at `:380` and the invalid-slot guard at `:383`). Recommended form: `if (game.rngLocked()) revert RngLocked();` cross-contract pattern per `BurnieCoinflip:730` / `sStonk:492`.
- **Per-admin-function rationale:** (a) `setCharity` exists for vault-owners to mutate the charity allowlist that `GNRUS.pickCharity` (called from advanceGame's jackpot stack at `AdvanceModule:1718`) reads to assign sDGNRS Reward pool grants. The setter has locked-slot guards at `:387` (slots 0/1/2 immutable once filled) but is otherwise mutable per the docstring. (b) Naive `rngLockedFlag` revert: would block legitimate slot fills between jackpot phases. (c) Legitimate window-internal need: low — charity mutations are administrative and can wait until rngLock window closes. (d) Residual EV: mid-rngLock window, the underlying `pickCharity` read fires from `_finalizeEarlybird` during `advanceGame` jackpot pay-out; an admin firing `setCharity` between VRF callback and the `pickCharity` read could redirect a sDGNRS grant to a different charity than the one the player expected when their position was committed. The catalog DOES NOT enumerate GNRUS `currentSlate` as a §14 slot — this is a **catalog gap** that ADMA flags via this R-06 entry. Skeptic-filter: admin-key compromise + window-aligned `setCharity` could redirect single-slot grants by full grant size (up to thousands of sDGNRS per level); medium-impact closeable by tactic (a).
- **Cross-reference:** RNGLOCK-CATALOG §15 S-14 sDGNRS poolBalances[Reward] row `transferFromPool` at `JackpotModule.sol:1498` (the downstream sink that the GNRUS pickCharity grant feeds) — but the catalog does NOT enumerate the GNRUS allowlist read as a participating slot. ADMA flags this as a cross-contract participating-slot gap candidate; v44.0 plan-phase may extend the catalog OR rely on the tactic-(a) gate at the GNRUS setter to close the residual.
- **Anchor:** D-43N-V44-ADMA-06 — Add cross-contract `game.rngLocked()` revert at GNRUS.setCharity entry; OPTIONAL catalog-extension to enumerate GNRUS allowlist as participating slot | **Admin fn:** GNRUS.setCharity @ GNRUS.sol:378 | **Slot(s):** (gap — GNRUS `currentSlate[slot]` not in §14; downstream feeds S-14) | **Tactic:** (a) rngLockedFlag revert

### §3.07 — R-07: DegenerusVault.gamePurchase (vault-routed `purchase`)

- **Admin fn:** `gamePurchase` (DegenerusVault.sol:513)
- **Participating slot(s) reached:** S-09, S-30, S-24..S-29, S-32, S-35, S-52, S-53 (full mint-batch participating set per RNGLOCK-CATALOG §15)
- **Admin-class disposition:** general (vault-routed mint)
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** AT THE UNDERLYING `MintModule.purchase` ENTRY (not at the DegenerusVault wrapper) — the gate at the underlying writer fn entry suffices because all callers (EOA `purchase`, vault-routed `gamePurchase`) flow through the same MintModule entry. RNGLOCK-CATALOG §16 V-024 already recommends `D-43N-V44-HANDOFF-13` ("Add top-level `if (rngLockedFlag) revert` to MintModule.purchase/purchaseCoin/purchaseBurnieLootbox").
- **Per-admin-function rationale:** (a) `gamePurchase` exists as the vault-routed entry into `MintModule.purchase` so that the vault contract can purchase tickets and lootboxes using combined `msg.value + vault.balance`. The wrapper handles the "use vault ETH balance" composition before calling the underlying purchase. (b) Naive `rngLockedFlag` revert at this wrapper: would block all vault-routed mint during the window, which is correct behavior — mint inside the window is a tactic (b) variance leak per §16 V-024..V-105 etc. (c) Legitimate window-internal need: none — mint outside the window is the normal path. (d) Residual EV: when the underlying writer is gated at MintModule.purchase entry, all callers including this vault-routed dispatcher are covered. The §3 entry exists to document the dispatcher edge — at v44.0 plan-phase, the same fix that closes V-024 (D-43N-V44-HANDOFF-13) closes this admin path. Skeptic-filter: vault-routed mint is the same writer at the same callsite; admin-class promotion does NOT widen the attack surface because the gate at the underlying entry covers both reach paths.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-024 + V-089/V-091/V-095/V-098/V-101 + V-105 + V-110 + V-127 + V-174 + V-179 sub-rows; tactic (a).
- **Anchor:** D-43N-V44-ADMA-07 — Verify D-43N-V44-HANDOFF-13 gate at MintModule.purchase entry covers vault-routed `DegenerusVault.gamePurchase` dispatcher reach | **Admin fn:** DegenerusVault.gamePurchase @ DegenerusVault.sol:513 | **Slot(s):** S-09, S-30, S-24..S-29, S-32, S-35, S-52, S-53 | **Tactic:** (a) rngLockedFlag revert at underlying MintModule.purchase

### §3.08 — R-08: DegenerusVault.gamePurchaseTicketsBurnie (vault-routed `purchaseCoin`)

- **Admin fn:** `gamePurchaseTicketsBurnie` (DegenerusVault.sol:534)
- **Participating slot(s) reached:** S-09 prizePoolsPacked, S-32 mintPacked_, S-25 lootboxDay, S-29 lootboxBurnie, S-52, S-53
- **Admin-class disposition:** general (vault-routed BURNIE mint)
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** AT THE UNDERLYING `MintModule.purchaseCoin` ENTRY (same disposition as R-07). Catalog handoff: D-43N-V44-HANDOFF-13.
- **Per-admin-function rationale:** (a) `gamePurchaseTicketsBurnie` is the vault-routed entry into BURNIE-denominated ticket purchase (`gamePlayer.purchaseCoin`). Vault burns BURNIE for tickets. (b) Naive revert at wrapper: correct closure. (c) Legitimate window need: none. (d) Residual EV: closed by the underlying-entry gate, same as R-07. Skeptic-filter: same as R-07.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-024 + V-092 (S-25 burnie) + V-104 (S-29 burnie) + V-110 + V-174 + V-179.
- **Anchor:** D-43N-V44-ADMA-08 — Verify D-43N-V44-HANDOFF-13 gate at MintModule.purchaseCoin entry covers vault-routed `gamePurchaseTicketsBurnie` | **Admin fn:** DegenerusVault.gamePurchaseTicketsBurnie @ DegenerusVault.sol:534 | **Slot(s):** S-09, S-32, S-25, S-29, S-52, S-53 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.09 — R-09: DegenerusVault.gamePurchaseBurnieLootbox (vault-routed `purchaseBurnieLootbox`)

- **Admin fn:** `gamePurchaseBurnieLootbox` (DegenerusVault.sol:543)
- **Participating slot(s) reached:** S-29 lootboxBurnie, S-25 lootboxDay, S-52, S-53
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a)** at underlying `MintModule.purchaseBurnieLootbox` entry. Catalog handoff: D-43N-V44-HANDOFF-13.
- **Per-admin-function rationale:** (a) Vault-routed BURNIE lootbox purchase; burns BURNIE for one lootbox. (b)-(c) Same as R-07/R-08. (d) Residual EV: same disposition. Skeptic-filter: same.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-104 (S-29) + V-092 (S-25) + V-174 + V-179.
- **Anchor:** D-43N-V44-ADMA-09 — Verify D-43N-V44-HANDOFF-13 covers vault-routed BURNIE lootbox purchase | **Admin fn:** DegenerusVault.gamePurchaseBurnieLootbox @ DegenerusVault.sol:543 | **Slot(s):** S-29, S-25, S-52, S-53 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.10 — R-10: DegenerusVault.gameOpenLootBox (vault-routed `openLootBox`)

- **Admin fn:** `gameOpenLootBox` (DegenerusVault.sol:551)
- **Participating slot(s) reached:** S-22 lootboxEvBenefitUsedByLevel, S-24..S-29 self-zero writes, S-52
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (b) snapshot at allocation** (NOT tactic (a)) — per RNGLOCK-CATALOG §16 V-081/V-088/V-094/V-097/V-100/V-171, the lootbox-open writers are participating-slot consumers that require snapshot-at-allocation (Phase 281 owed-salt pattern); blanket rngLock revert at open-time is insufficient because the open-time inputs are already committed at buy-time, and any RNG-window racing must be closed at allocation, not at open.
- **Per-admin-function rationale:** (a) `gameOpenLootBox` is the vault-routed entry into `LootboxModule.openLootBox`. The vault opens a lootbox it owns; the open flow rolls the lootbox payout against the lootbox-index VRF word. (b) Naive `rngLockedFlag` revert at wrapper: would block legitimate open-during-window cases when the lootbox's VRF word is fresh and the opener wants to claim immediately. (c) Legitimate window-internal need: yes — opening a lootbox whose VRF word was just published is the normal post-RNG flow. (d) Residual EV: the residual is in the buy-time → open-time delta where some inputs (lootboxEth, lootboxDay, etc.) are read at open-time from storage that the player can re-influence between buy and open (e.g., via mid-day mint cascade). Tactic (b) snapshot-at-allocation eliminates the racing window by freezing all open-time inputs at the buy callsite. Skeptic-filter: vault-routed open is the same writer at the same callsite; tactic (b) at the underlying lootbox-allocation writers covers both EOA and vault-routed opens.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-081 + V-088 + V-094 + V-097 + V-100 + V-171.
- **Anchor:** D-43N-V44-ADMA-10 — Verify D-43N-V44-HANDOFF-43..46/52/55/58/95 snapshot-at-allocation tactic covers vault-routed `gameOpenLootBox` | **Admin fn:** DegenerusVault.gameOpenLootBox @ DegenerusVault.sol:551 | **Slot(s):** S-22, S-24..S-29, S-52 | **Tactic:** (b) snapshot at allocation

### §3.11 — R-11: DegenerusVault.gamePurchaseDeityPassFromBoon (vault-routed deity-pass purchase)

- **Admin fn:** `gamePurchaseDeityPassFromBoon` (DegenerusVault.sol:561)
- **Participating slot(s) reached:** S-07 deityBySymbol, S-18 deityPassOwners, S-19 deityPassPurchasedCount, S-32 mintPacked_, S-34 boonPacked, S-52, S-53
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at underlying `WhaleModule._purchaseDeityPass` entry (catalog handoff D-43N-V44-HANDOFF-12 already established for V-019).
- **Per-admin-function rationale:** (a) `gamePurchaseDeityPassFromBoon` lets a vault owner buy a deity pass using vault ETH + claimable winnings. The wrapper claims winnings first if needed, then forwards `priceWei` to `gamePlayer.purchaseDeityPass`. (b) Naive `rngLockedFlag` revert at wrapper: correct closure. (c) Legitimate window-internal need: none — deity-pass purchases are non-urgent admin operations. (d) Residual EV: closed by the underlying WhaleModule.purchaseDeityPass entry gate at WhaleModule:543 (existing runtime `rngLockedFlag` gate per §16 V-019 disposition). Vault-routed reach folds into the same gate. Skeptic-filter: same writer, same callsite.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-019 (S-07) + V-069 (S-18) + V-070 (S-19) + V-114 (S-32 buyDeityPass) + V-121 (S-34) + V-170 (S-52).
- **Anchor:** D-43N-V44-ADMA-11 — Verify D-43N-V44-HANDOFF-12/36/37 gate at WhaleModule._purchaseDeityPass entry covers vault-routed deity-pass purchase | **Admin fn:** DegenerusVault.gamePurchaseDeityPassFromBoon @ DegenerusVault.sol:561 | **Slot(s):** S-07, S-18, S-19, S-32, S-34, S-52, S-53 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.12 — R-12: DegenerusVault.gameDegeneretteBet (vault-routed `placeDegeneretteBet`)

- **Admin fn:** `gameDegeneretteBet` (DegenerusVault.sol:594)
- **Participating slot(s) reached:** S-02 dailyHeroWagers[day][q], S-43 degeneretteBets[player][nonce], S-09 prizePoolsPacked, S-45 prizePoolPendingPacked
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (b) day-key freeze attestation** for S-02 (per catalog V-005 D-43N-V44-HANDOFF-03); **Tactic (a)** for S-09 / S-45 / S-43 (per catalog V-031/V-147/V-142 D-43N-V44-HANDOFF-18/82/81).
- **Per-admin-function rationale:** (a) `gameDegeneretteBet` is the vault-routed entry into `placeDegeneretteBet`, the degenerette gambling-game bet placement function. The wrapper composes `msg.value + ethValue from vault balance`. (b) Naive `rngLockedFlag` revert at wrapper: would block legitimate post-VRF / pre-next-day bets that are normal play. (c) Legitimate window-internal need: depends — degenerette bets fire against the daily VRF word; mid-window bets are part of normal play *between* daily VRFs. (d) Residual EV: catalog tactic-(b) day-key freeze (Phase 288 dailyIdx snapshot) closes the S-02 cross-day racing; tactic-(a) at `_placeDegeneretteBetCore` entry closes the in-window S-09/S-43/S-45 racing. Vault-routed reach is enumerated as catalog V-005 with the explicit `DegenerusVault.sol:607` callsite. Skeptic-filter: same writer, same callsite as catalog V-005; ADMA contribution is the dispatcher annotation.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-005 (S-02 vault-routed), V-142 (S-43), V-031 (S-09), V-147 (S-45).
- **Anchor:** D-43N-V44-ADMA-12 — Verify D-43N-V44-HANDOFF-03/18/81/82 tactic-mix covers vault-routed `gameDegeneretteBet` | **Admin fn:** DegenerusVault.gameDegeneretteBet @ DegenerusVault.sol:594 | **Slot(s):** S-02, S-43, S-09, S-45 | **Tactic:** (b) day-key freeze (S-02) + (a) rngLockedFlag revert (S-09/S-43/S-45)

### §3.13 — R-13: DegenerusVault.gameSetAutoRebuy (vault-routed `setAutoRebuy`)

- **Admin fn:** `gameSetAutoRebuy` (DegenerusVault.sol:627)
- **Participating slot(s) reached:** S-05 autoRebuyState[beneficiary=vault]
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** verification at underlying `_setAutoRebuy` callsite — the existing internal `RngLocked` gate at `_setAutoRebuy:1513` covers the EOA `setAutoRebuy(:1495)` callsite per catalog V-009 (D-43N-V44-HANDOFF-04); ADMA verifies the same gate also covers vault-routed reach via `DegenerusVault.gameSetAutoRebuy → gamePlayer.setAutoRebuy(:1495 entry)`.
- **Per-admin-function rationale:** (a) `gameSetAutoRebuy` is the vault-routed entry for setting the vault's auto-rebuy preference; reaches `gamePlayer.setAutoRebuy(address(this), enabled)`. The vault is itself the beneficiary of the auto-rebuy state. (b) Naive revert at wrapper: blocks vault auto-rebuy config during rngLock; correct closure if window-internal config is undesired. (c) Legitimate window-internal need: low — auto-rebuy config is non-urgent. (d) Residual EV: the underlying `_setAutoRebuy:1513` runtime gate covers; ADMA contribution is the vault-routed annotation. Skeptic-filter: vault-routed reach is the same writer at the same EOA-entry callsite; admin-class promotion does not widen attack surface since the wrapper requires `onlyVaultOwner`.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-009 (S-05).
- **Anchor:** D-43N-V44-ADMA-13 — Verify D-43N-V44-HANDOFF-04 gate at `_setAutoRebuy:1513` covers vault-routed `gameSetAutoRebuy` reach | **Admin fn:** DegenerusVault.gameSetAutoRebuy @ DegenerusVault.sol:627 | **Slot(s):** S-05 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.14 — R-14: DegenerusVault.gameSetAutoRebuyTakeProfit (vault-routed `setAutoRebuyTakeProfit`)

- **Admin fn:** `gameSetAutoRebuyTakeProfit` (DegenerusVault.sol:634)
- **Participating slot(s) reached:** S-05 autoRebuyState[beneficiary=vault]
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** verification at underlying `_setAutoRebuyTakeProfit:1528` callsite — folds against catalog V-010 (D-43N-V44-HANDOFF-05).
- **Per-admin-function rationale:** (a) Same shape as R-13 — vault-routed take-profit configuration for vault's own auto-rebuy. (b)/(c) Same as R-13. (d) Residual EV: closed by underlying `:1528` gate. Skeptic-filter: same as R-13.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-010 (S-05).
- **Anchor:** D-43N-V44-ADMA-14 — Verify D-43N-V44-HANDOFF-05 gate at `_setAutoRebuyTakeProfit:1528` covers vault-routed `gameSetAutoRebuyTakeProfit` reach | **Admin fn:** DegenerusVault.gameSetAutoRebuyTakeProfit @ DegenerusVault.sol:634 | **Slot(s):** S-05 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.15 — R-15: DegenerusVault.gameSetAfKingMode (vault-routed `setAfKingMode`)

- **Admin fn:** `gameSetAfKingMode` (DegenerusVault.sol:643)
- **Participating slot(s) reached:** S-05 autoRebuyState[beneficiary=vault]
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** verification at underlying `_setAfKingMode:1575` callsite — folds against catalog V-011 (D-43N-V44-HANDOFF-06).
- **Per-admin-function rationale:** (a) Same shape as R-13/R-14 — vault-routed AfKing mode (auto-flip-king) configuration for vault. (b)/(c) Same. (d) Residual EV: closed by underlying. Skeptic-filter: same.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-011 (S-05).
- **Anchor:** D-43N-V44-ADMA-15 — Verify D-43N-V44-HANDOFF-06 gate at `_setAfKingMode:1575` covers vault-routed `gameSetAfKingMode` reach | **Admin fn:** DegenerusVault.gameSetAfKingMode @ DegenerusVault.sol:643 | **Slot(s):** S-05 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.16 — R-16: DegenerusVault.coinDepositCoinflip (vault-routed BURNIE coinflip deposit)

- **Admin fn:** `coinDepositCoinflip` (DegenerusVault.sol:662)
- **Participating slot(s) reached:** S-55 bountyOwedTo (via BurnieCoinflip `_addDailyFlip` arming arm)
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) bounty-arming gate** verification at underlying `_addDailyFlip:681` callsite — folds against catalog V-182 (D-43N-V44-HANDOFF-110) which already gates arming on `!rngLocked()` at BurnieCoinflip:664, with the catalog recommendation to extend to fail-closed revert.
- **Per-admin-function rationale:** (a) `coinDepositCoinflip` is vault-routed BURNIE coinflip deposit; reaches BurnieCoinflip.depositCoinflip via `gamePlayer.depositCoinflip` cascade. The deposit arms a coinflip and writes `bountyOwedTo` if the bounty is unarmed. (b) Naive revert at wrapper: correct closure during rngLock; vault deposits are non-urgent. (c) Legitimate window-internal need: low. (d) Residual EV: closed by the `:664` gate at BurnieCoinflip; vault-routed reach folds into V-182's catalog coverage. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-182 (S-55).
- **Anchor:** D-43N-V44-ADMA-16 — Verify D-43N-V44-HANDOFF-110 fail-closed extension at BurnieCoinflip._addDailyFlip:681 covers vault-routed `coinDepositCoinflip` | **Admin fn:** DegenerusVault.coinDepositCoinflip @ DegenerusVault.sol:662 | **Slot(s):** S-55 | **Tactic:** (a) bounty-arming gate at underlying

### §3.17 — R-17: DegenerusVault.coinDecimatorBurn (vault-routed decimator BURNIE burn)

- **Admin fn:** `coinDecimatorBurn` (DegenerusVault.sol:677)
- **Participating slot(s) reached:** S-09 prizePoolsPacked (via `recordDecBurn`); S-66 decBurn[lvl][player].burn (via `_recordDecBurn` decimator path)
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at underlying `recordDecBurn:1029` (catalog handoff D-43N-V44-HANDOFF-16 for V-027) AND `recordDecBurn` decimator path (D-43N-V44-HANDOFF-118 for V-201 — gate on `decClaimRounds[lvl].poolWei == 0`).
- **Per-admin-function rationale:** (a) `coinDecimatorBurn` is vault-routed BURNIE→decimator burn; reaches both the prizePoolsPacked update path AND the decimator-burn record path. (b) Naive revert at wrapper: correct closure during rngLock. (c) Legitimate window-internal need: none — decimator burns can wait. (d) Residual EV: closed by both underlying gates. Skeptic-filter: same writer at same callsites.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-027 (S-09) + V-201 (S-66).
- **Anchor:** D-43N-V44-ADMA-17 — Verify D-43N-V44-HANDOFF-16/118 gates cover vault-routed `coinDecimatorBurn` reach | **Admin fn:** DegenerusVault.coinDecimatorBurn @ DegenerusVault.sol:677 | **Slot(s):** S-09, S-66 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.18 — R-18: DegenerusVault.gameClaimWinnings (vault-routed `claimWinnings`)

- **Admin fn:** `gameClaimWinnings` (DegenerusVault.sol:575)
- **Participating slot(s) reached:** S-16 claimablePool, S-20 address(this).balance
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at underlying `DegenerusGame.claimWinnings` entry (catalog handoff D-43N-V44-HANDOFF-31 for V-063 covers both S-16 + S-20 per the catalog rationale "single revert closes both `claimablePool` and balance writers" at V-073).
- **Per-admin-function rationale:** (a) `gameClaimWinnings` is the vault-routed claim path; reaches `gamePlayer.claimWinningsStethFirst()`. (b) Naive revert at wrapper: correct closure during liveness/game-over drain. (c) Legitimate window-internal need: low during drain; claim outside the window is the normal path. (d) Residual EV: closed by the underlying entry gate. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-063 (S-16) + V-073 (S-20).
- **Anchor:** D-43N-V44-ADMA-18 — Verify D-43N-V44-HANDOFF-31/40 gate at DegenerusGame.claimWinnings covers vault-routed `gameClaimWinnings` | **Admin fn:** DegenerusVault.gameClaimWinnings @ DegenerusVault.sol:575 | **Slot(s):** S-16, S-20 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.19 — R-19: DegenerusVault.gameClaimWhalePass (vault-routed `claimWhalePass`)

- **Admin fn:** `gameClaimWhalePass` (DegenerusVault.sol:581)
- **Participating slot(s) reached:** S-09 prizePoolsPacked, S-52 ticketQueue, S-53 ticketsOwedPacked
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) `rngLockedFlag` revert** at underlying `claimWhalePass` entry (catalog handoff D-43N-V44-HANDOFF-17/99 for V-030/V-176).
- **Per-admin-function rationale:** (a) `gameClaimWhalePass` is vault-routed whale-pass claim; reaches `_queueTicketRange` for ticket-pool effects. (b) Revert at wrapper: correct. (c) Legitimate window need: none. (d) Residual EV: closed by underlying. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-030 (S-09) + V-176 (S-52) + V-179 (S-53).
- **Anchor:** D-43N-V44-ADMA-19 — Verify D-43N-V44-HANDOFF-17/99 covers vault-routed `gameClaimWhalePass` | **Admin fn:** DegenerusVault.gameClaimWhalePass @ DegenerusVault.sol:581 | **Slot(s):** S-09, S-52, S-53 | **Tactic:** (a) rngLockedFlag revert at underlying

### §3.20 — R-20: DegenerusVault.jackpotsClaimDecimator (vault-routed `claimDecimatorJackpot`)

- **Admin fn:** `jackpotsClaimDecimator` (DegenerusVault.sol:708)
- **Participating slot(s) reached:** S-16 claimablePool (via `_awardDecimatorLootbox`)
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) liveness gate** at underlying `_awardDecimatorLootbox` callsite (catalog handoff D-43N-V44-HANDOFF-27 for V-054 — "gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window").
- **Per-admin-function rationale:** (a) `jackpotsClaimDecimator` is the vault-routed decimator-jackpot claim path. (b) Revert at wrapper: correct closure on `!_livenessTriggered()`. (c) Legitimate window-internal need: low during game-over drain. (d) Residual EV: closed by underlying. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-054 (S-16).
- **Anchor:** D-43N-V44-ADMA-20 — Verify D-43N-V44-HANDOFF-27 liveness gate at `_awardDecimatorLootbox` covers vault-routed `jackpotsClaimDecimator` | **Admin fn:** DegenerusVault.jackpotsClaimDecimator @ DegenerusVault.sol:708 | **Slot(s):** S-16 | **Tactic:** (a) liveness gate at underlying

### §3.21 — R-21: DegenerusVault.sdgnrsBurn (vault-routed sDGNRS burn-for-redemption)

- **Admin fn:** `sdgnrsBurn` (DegenerusVault.sol:719)
- **Participating slot(s) reached:** S-17 pendingRedemptionEthValue, S-56 redemptionPeriodIndex, S-57 pendingRedemptionEthBase, S-58 pendingRedemptionBurnieBase, S-59 pendingRedemptionBurnie, S-60 pendingRedemptions[player]
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a) revert if `redemptionPeriods[redemptionPeriodIndex].roll != 0`** at underlying `_submitGamblingClaimFrom` entry (catalog handoff D-43N-V44-HANDOFF-111 for V-184; the gate is the canonical S-56 re-resolution-lock that subsumes V-184..V-191 per the catalog).
- **Per-admin-function rationale:** (a) `sdgnrsBurn` is vault-routed sDGNRS burn-for-redemption; arms the redemption by writing pending fields against the current `redemptionPeriodIndex`. (b) Naive `rngLockedFlag` revert at wrapper: existing `BurnsBlockedDuringLiveness` covers in-flight burn during liveness, but the S-56 stale-index re-claim issue requires the V-184 re-resolution-lock gate. (c) Legitimate window-internal need: low — sDGNRS redemption is multi-day so vault can wait. (d) Residual EV: closed by the S-56 re-resolution lock at the underlying writer. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-066 (S-17) + V-184 (S-56) + V-186/V-188/V-190 (S-57/S-58/S-59) + V-191 (S-60).
- **Anchor:** D-43N-V44-ADMA-21 — Verify D-43N-V44-HANDOFF-111 S-56 re-resolution lock covers vault-routed `sdgnrsBurn` | **Admin fn:** DegenerusVault.sdgnrsBurn @ DegenerusVault.sol:719 | **Slot(s):** S-17, S-56, S-57, S-58, S-59, S-60 | **Tactic:** (a) S-56 re-resolution lock at underlying

### §3.22 — R-22: DegenerusVault.sdgnrsClaimRedemption (vault-routed sDGNRS claim)

- **Admin fn:** `sdgnrsClaimRedemption` (DegenerusVault.sol:725)
- **Participating slot(s) reached:** S-17 pendingRedemptionEthValue (decrement), S-60 pendingRedemptions[player] (delete / partial clear)
- **Admin-class disposition:** general
- **Recommended gating mechanism:** **Tactic (a)** subsumed by the same V-184 S-56 re-resolution-lock gate at underlying `_submitGamblingClaimFrom`/`claimRedemption` (D-43N-V44-HANDOFF-111).
- **Per-admin-function rationale:** (a) `sdgnrsClaimRedemption` is vault-routed redemption claim; the second leg of the burn→claim pair. Reads pendingRedemptions[vault] and credits via `sweepSdgnrsClaim`. (b) Naive `rngLockedFlag` revert at wrapper: the burn-side V-184 gate already prevents stale-index entries from forming, so the claim-side only needs to enforce that pending state is consistent. (c) Legitimate window-internal need: low — claim outside window is the normal path. (d) Residual EV: subsumed by V-184 per catalog V-192/V-193 — once the S-56 re-resolution lock is in place, the claim path's vault-routed reach has the same residual as the EOA reach. Skeptic-filter: same writer.
- **Cross-reference:** RNGLOCK-CATALOG §16 V-068 (S-17) + V-192/V-193 (S-60).
- **Anchor:** D-43N-V44-ADMA-22 — Verify D-43N-V44-HANDOFF-111 S-56 re-resolution lock covers vault-routed `sdgnrsClaimRedemption` | **Admin fn:** DegenerusVault.sdgnrsClaimRedemption @ DegenerusVault.sol:725 | **Slot(s):** S-17, S-60 | **Tactic:** (a) S-56 re-resolution lock at underlying

---

## §4 — v44.0 FIX-MILESTONE Consolidated Handoff Register

Deduplicated `D-43N-V44-ADMA-NN` ID list, ordered numerically. Each row carries the admin fn + slots reached + admin-class + tactic + a 1-line v44.0 sub-phase scope summary. The catalog-erratum entry `D-43N-V44-ADMA-ERRATUM-01` is appended outside the per-class grouping (no admin fn associated; catalog correction).

| Anchor ID | Admin fn | Slot(s) reached | Admin-class | Tactic | v44.0 sub-phase scope summary |
|---|---|---|---|---|---|
| D-43N-V44-ADMA-01 | DegenerusGameAdvanceModule.wireVrf @ DegenerusGameAdvanceModule.sol:498 | S-47, S-48, S-49 | governance | (d) immutable | Seal `wireVrf` post-init via one-shot flag, OR remove if Admin constructor wiring suffices; cross-refs catalog V-156/V-158/V-160 |
| D-43N-V44-ADMA-02 | DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub @ DegenerusGameAdvanceModule.sol:1677 | S-47, S-48, S-49, S-38, S-46 LR_MID_DAY | governance | (c) pre-lock reorder | Queue mid-stall rotations until callback delivers or 12h+ timeout; cross-refs catalog V-137/V-155/V-157/V-159/V-161 |
| D-43N-V44-ADMA-03 | DegenerusGame.adminSwapEthForStEth @ DegenerusGame.sol:1805 | S-20, S-21 | governance | (a) rngLockedFlag revert | Add `if (rngLockedFlag) revert RngLocked();` at function entry; cross-refs catalog V-072/V-074/V-080 |
| D-43N-V44-ADMA-04 | DegenerusGame.adminStakeEthForStEth @ DegenerusGame.sol:1826 | S-20, S-21 | governance | (a) rngLockedFlag revert | Add `rngLockedFlag` revert at function entry; per-callsite split: admin reach does NOT inherit V-079 EXEMPT classification |
| D-43N-V44-ADMA-05 | DegenerusAdmin.swapGameEthForStEth @ DegenerusAdmin.sol:631 | S-20 | governance | (a) rngLockedFlag revert | Add `rngLockedFlag` revert at vault-owner-facing entry point; second gate at underlying `gameAdmin.adminSwapEthForStEth` (R-03) for belt-and-suspenders |
| D-43N-V44-ADMA-06 | GNRUS.setCharity @ GNRUS.sol:378 | (cross-contract gap — GNRUS `currentSlate[slot]` not in §14; downstream feeds S-14) | governance | (a) rngLockedFlag revert | Add cross-contract `game.rngLocked()` revert at function entry; OPTIONAL catalog-extension to enumerate GNRUS allowlist as participating slot |
| D-43N-V44-ADMA-07 | DegenerusVault.gamePurchase @ DegenerusVault.sol:513 | S-09, S-30, S-24..S-29, S-32, S-35, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-13 gate at MintModule.purchase entry covers vault-routed dispatcher reach |
| D-43N-V44-ADMA-08 | DegenerusVault.gamePurchaseTicketsBurnie @ DegenerusVault.sol:534 | S-09, S-32, S-25, S-29, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-13 gate at MintModule.purchaseCoin covers vault-routed |
| D-43N-V44-ADMA-09 | DegenerusVault.gamePurchaseBurnieLootbox @ DegenerusVault.sol:543 | S-29, S-25, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-13 covers vault-routed BURNIE lootbox purchase |
| D-43N-V44-ADMA-10 | DegenerusVault.gameOpenLootBox @ DegenerusVault.sol:551 | S-22, S-24..S-29, S-52 | general | (b) snapshot at allocation | Verify D-43N-V44-HANDOFF-43..46/52/55/58/95 snapshot-at-allocation covers vault-routed open |
| D-43N-V44-ADMA-11 | DegenerusVault.gamePurchaseDeityPassFromBoon @ DegenerusVault.sol:561 | S-07, S-18, S-19, S-32, S-34, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-12/36/37 gate at WhaleModule._purchaseDeityPass covers vault-routed |
| D-43N-V44-ADMA-12 | DegenerusVault.gameDegeneretteBet @ DegenerusVault.sol:594 | S-02, S-43, S-09, S-45 | general | (b) day-key freeze (S-02) + (a) rngLockedFlag revert (rest) | Verify D-43N-V44-HANDOFF-03/18/81/82 tactic-mix covers vault-routed degenerette bet |
| D-43N-V44-ADMA-13 | DegenerusVault.gameSetAutoRebuy @ DegenerusVault.sol:627 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-04 gate at `_setAutoRebuy:1513` covers vault-routed reach |
| D-43N-V44-ADMA-14 | DegenerusVault.gameSetAutoRebuyTakeProfit @ DegenerusVault.sol:634 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-05 gate at `_setAutoRebuyTakeProfit:1528` covers vault-routed reach |
| D-43N-V44-ADMA-15 | DegenerusVault.gameSetAfKingMode @ DegenerusVault.sol:643 | S-05 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-06 gate at `_setAfKingMode:1575` covers vault-routed reach |
| D-43N-V44-ADMA-16 | DegenerusVault.coinDepositCoinflip @ DegenerusVault.sol:662 | S-55 | general | (a) bounty-arming gate at underlying | Verify D-43N-V44-HANDOFF-110 fail-closed extension at BurnieCoinflip._addDailyFlip:681 covers vault-routed reach |
| D-43N-V44-ADMA-17 | DegenerusVault.coinDecimatorBurn @ DegenerusVault.sol:677 | S-09, S-66 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-16/118 gates cover vault-routed decimator burn |
| D-43N-V44-ADMA-18 | DegenerusVault.gameClaimWinnings @ DegenerusVault.sol:575 | S-16, S-20 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-31/40 gate at DegenerusGame.claimWinnings covers vault-routed |
| D-43N-V44-ADMA-19 | DegenerusVault.gameClaimWhalePass @ DegenerusVault.sol:581 | S-09, S-52, S-53 | general | (a) rngLockedFlag revert at underlying | Verify D-43N-V44-HANDOFF-17/99 covers vault-routed whale-pass claim |
| D-43N-V44-ADMA-20 | DegenerusVault.jackpotsClaimDecimator @ DegenerusVault.sol:708 | S-16 | general | (a) liveness gate at underlying | Verify D-43N-V44-HANDOFF-27 liveness gate at `_awardDecimatorLootbox` covers vault-routed decimator claim |
| D-43N-V44-ADMA-21 | DegenerusVault.sdgnrsBurn @ DegenerusVault.sol:719 | S-17, S-56, S-57, S-58, S-59, S-60 | general | (a) S-56 re-resolution lock at underlying | Verify D-43N-V44-HANDOFF-111 S-56 re-resolution lock covers vault-routed sDGNRS burn |
| D-43N-V44-ADMA-22 | DegenerusVault.sdgnrsClaimRedemption @ DegenerusVault.sol:725 | S-17, S-60 | general | (a) S-56 re-resolution lock at underlying | Verify D-43N-V44-HANDOFF-111 S-56 re-resolution lock covers vault-routed sDGNRS claim |
| D-43N-V44-ADMA-ERRATUM-01 | (catalog erratum, no admin fn) | S-06 (phantom) | n/a | catalog-correction | RNGLOCK-CATALOG.md §15 rows 154/155/156 + §16 V-016/V-017/V-018 + §C.3.2/C.3.3 enumerate phantom admin trait-bucket writers; source verification (grep adminSeedTraitBucket / adminClearTraitBucket in contracts/) returns 0 hits; the actual S-06 writer `_raritySymbolBatch` is INTERNAL-only EXEMPT-ADVANCEGAME. v44 plan-phase MUST NOT spend a sub-phase on these phantom functions; OPTIONAL future catalog-revision phase may correct §15/§16/§C.3.2/§C.3.3. |

**Admin-class grouping recap (numbered anchors only; ERRATUM-01 excluded):**

| Admin-class | Anchor count | Anchors |
|---|---|---|
| governance | 6 | D-43N-V44-ADMA-01..06 |
| parameter-update | 0 | (none) |
| charity-allowlist | 0 | (sole charity-allowlist mutator GNRUS.setCharity classified under governance per the vault-owner-gate rather than a dedicated charity-allowlist admin class) |
| decimator-config | 0 | (none) |
| presale-config | 0 | (none) |
| general | 16 | D-43N-V44-ADMA-07..22 |
| **Total** | **22** | |

Plus 1 ERRATUM-01 entry (catalog correction; not an admin function).

**§4 ↔ §3 anchor parity:** PASS — every numbered D-43N-V44-ADMA-NN ID emitted in §3 (D-43N-V44-ADMA-01 through D-43N-V44-ADMA-22) appears in §4; the catalog-erratum entry D-43N-V44-ADMA-ERRATUM-01 is unique to §4 + §1.E by design.

Per `D-300-CONTEXT.md` <deferred> note, cross-admin-class FIX wave grouping at v44.0 is explicitly deferred to v44 plan-phase discretion. v44 plan-phase may group governance vs general per wave; many of the 16 general anchors fold against a single underlying catalog `D-43N-V44-HANDOFF-NN` handoff (e.g., R-07/R-08/R-09 all fold against HANDOFF-13 at MintModule.purchase/purchaseCoin/purchaseBurnieLootbox) — these can be batched into a single verification sub-phase rather than independent fixes.

---

## §5 — Grep Completeness Gate Attestation

Per `D-300-ADMA-LAYOUT-01` + Phase 298 §17 CAT-06 precedent. Six grep patterns executed at authoring time; each Pattern 1-4 hit reconciles against an §1 row OR an explicit-exclusion attestation. Pattern 5 records integration-trust-boundary modifier hit count (all deliberately excluded). Pattern 6 negative-confirms the phantom admin functions referenced by RNGLOCK-CATALOG §15/§16/§C.3.2/§C.3.3 are absent from source.

### Pattern 1 — formal `onlyOwner`

```
grep -rnE "\bonlyOwner\b" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/
```

Hits (5 total):

- `contracts/DegenerusAdmin.sol:436` — modifier definition (preamble; no §1 row)
- `contracts/DegenerusAdmin.sol:631` — usage at `swapGameEthForStEth` → **A-26**
- `contracts/DegenerusDeityPass.sol:80` — modifier definition (preamble)
- `contracts/DegenerusDeityPass.sol:94` — usage at `setRenderer` → **A-24**
- `contracts/DegenerusDeityPass.sol:108` — usage at `setRenderColors` (multi-line; modifier at closing-paren) → **A-25**

**Pattern 1 reconciliation: PASS** — 3 modifier-usage hits, all map to §1 rows A-24/A-25/A-26.

### Pattern 2 — formal `onlyAdmin` / `onlyRole` / `onlyVaultOwner`

```
grep -rnE "\b(onlyAdmin|onlyRole|onlyVaultOwner)\b" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/
```

Hits (24 total):

- `contracts/DegenerusVault.sol:431` — `onlyVaultOwner` modifier definition (preamble)
- 23 `onlyVaultOwner` usages at function declarations or closing-paren multi-line signatures: DegenerusVault.sol:500, :519 (multi-line gamePurchase decl :513), :534, :543, :551, :561, :575, :581, :601 (multi-line gameDegeneretteBet decl :594), :620, :627, :634, :647 (multi-line gameSetAfKingMode decl :643), :655, :662, :670, :677, :685, :692, :700, :708, :719, :725 → §1 rows **A-01..A-23**

**`onlyAdmin` hits:** 0.
**`onlyRole` hits:** 0 (codebase does not use OZ AccessControl).

**Pattern 2 reconciliation: PASS** — 23 modifier-usage hits, all map to §1 rows A-01..A-23.

### Pattern 3 — hand-rolled ADMIN/CREATOR gates

```
grep -rnE "msg\.sender\s*!=\s*ContractAddresses\.(ADMIN|CREATOR)" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/ | grep -v ContractAddresses\.sol
```

Hits (6 total):

- `contracts/Icons32Data.sol:154` — CREATOR gate at `setPaths` → **A-35**
- `contracts/Icons32Data.sol:172` — CREATOR gate at `setSymbols` → **A-36**
- `contracts/Icons32Data.sol:197` — CREATOR gate at `finalize` → **A-37**
- `contracts/modules/DegenerusGameAdvanceModule.sol:503` — ADMIN gate at `wireVrf` → **A-30**
- `contracts/modules/DegenerusGameAdvanceModule.sol:1682` — ADMIN gate at `updateVrfCoordinatorAndSub` → **A-31**
- `contracts/DegenerusGame.sol:1809` — ADMIN gate at `adminSwapEthForStEth` → **A-28**

**Pattern 3 reconciliation: PASS** — 6 hits, all map to §1 rows.

### Pattern 4 — hand-rolled vault-owner gates

```
grep -rnE "!vault\.isVaultOwner\(msg\.sender\)|!_isVaultOwner\(msg\.sender\)|vault\.isVaultOwner\(msg\.sender\)" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/
```

Hits (10 total):

- `contracts/DegenerusDeityPass.sol:81` — modifier-body `isVaultOwner` check inside `onlyOwner` definition (already accounted at Pattern 1; preamble)
- `contracts/DegenerusStonk.sol:188` — inline at `unwrapTo` → **A-32**
- `contracts/DegenerusStonk.sol:203` — inline at `claimVested` → **A-33**
- `contracts/DegenerusAdmin.sol:437` — modifier-body `isVaultOwner` check inside `onlyOwner` definition (preamble)
- `contracts/DegenerusAdmin.sol:507` — INTERNAL discriminator branch inside `proposeFeedSwap` (preamble carve-out: not external admin entry)
- `contracts/DegenerusAdmin.sol:670` — INTERNAL discriminator branch inside `propose` (preamble carve-out)
- `contracts/DegenerusVault.sol:432` — modifier-body `_isVaultOwner` check inside `onlyVaultOwner` definition (preamble)
- `contracts/GNRUS.sol:380` — inline at `setCharity` → **A-34**
- `contracts/DegenerusGame.sol:480` — inline at `setLootboxRngThreshold` → **A-27**
- `contracts/DegenerusGame.sol:1827` — inline at `adminStakeEthForStEth` → **A-29**

Plus one additional internal-helper hit:
- `contracts/modules/DegenerusGameAdvanceModule.sol:1035` — INTERNAL helper `_enforceDailyMintGate` fallback bypass (preamble carve-out: not external admin entry)

**Pattern 4 reconciliation: PASS** — 5 external-body inline hits map to §1 rows A-27/A-29/A-32/A-33/A-34; 4 modifier-definition-body hits accounted for in Pattern 1/2 preamble; 3 internal-branch/helper hits accounted for in carve-out list (DegenerusAdmin :507/:670 + AdvanceModule :1035).

### Pattern 5 — integration-trust-boundary modifiers (deliberate-exclusion attestation)

```
grep -rnE "\b(onlyGame|onlyCoin|onlyCoinflip|onlyVault|onlyBurnieCoin|onlyFlipCreditors|onlyDegenerusGameContract)\b" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/
```

Hits: **53 total.**

All Pattern 5 hits are **deliberately excluded** from §1 per D-300-ENUM-SCOPE-01 carve-out (integration trust boundaries are not admin functions). Zero Pattern 5 hits map to admin-class functions. Attestation accepted; no per-hit cross-reference required (the patterns gate calls between protocol contracts, not administrative entry).

### Pattern 6 — negative confirmation of phantom admin functions (catalog-erratum gate)

```
grep -rnE "adminSeedTraitBucket|adminClearTraitBucket" contracts/ --include="*.sol" | grep -v contracts/test/ | grep -v contracts/mocks/ | grep -v contracts/interfaces/ | wc -l
```

**Pattern 6 result: 0 hits.**

**Pattern 6 attestation: PASS** — `adminSeedTraitBucket` and `adminClearTraitBucket` are ABSENT from source. The phantom admin trait-bucket writers referenced by RNGLOCK-CATALOG.md §15 rows 154/155/156 + §16 V-016/V-017/V-018 + §C.3.2/§C.3.3 do not exist in `contracts/`. The S-06 catalog erratum is carried to v44.0 as `D-43N-V44-ADMA-ERRATUM-01` per §1.E.

### §5 Verdict: PASS

All 6 grep patterns reconcile cleanly:

- Pattern 1 (5 hits): 2 modifier-definitions (preamble) + 3 usages (A-24, A-25, A-26) — PASS
- Pattern 2 (24 hits): 1 modifier-definition (preamble) + 23 usages (A-01..A-23) — PASS
- Pattern 3 (6 hits): 6 usages (A-28, A-30, A-31, A-35, A-36, A-37) — PASS
- Pattern 4 (10 + 1 = 11 hits): 4 modifier-body checks (Pattern 1/2 preamble accounted) + 5 inline external-body hits (A-27, A-29, A-32, A-33, A-34) + 2 DegenerusAdmin internal discriminator branches (preamble carve-out) + 1 AdvanceModule internal helper fallback (preamble carve-out) — PASS
- Pattern 5 (53 hits): all deliberately excluded per D-300-ENUM-SCOPE-01 integration-trust-boundary carve-out — PASS
- Pattern 6 (0 hits): negative-confirmation of phantom admin functions — PASS

§1 row total: **37** rows = (Pattern 1 usages: 3) + (Pattern 2 usages: 23) + (Pattern 3 hits: 6) + (Pattern 4 inline hits: 5) = 3 + 23 + 6 + 5 = **37 ✓**.

No "by construction" / "single fn reaches all paths" claims per `feedback_verify_call_graph_against_source.md` discipline. Every cited file:line was source-verified pre-commit.

---

*Audit metadata footer:*

- **Generation date:** 2026-05-18
- **Dependencies:** `.planning/RNGLOCK-CATALOG.md` (Phase 298 closed artifact, UNMODIFIED) — load-bearing for §2 cross-reference + §3 catalog-handoff folds + §1.E erratum carry forward.
- **Posture (restated):** Single AGENT-COMMITTED canonical Phase 300 ADMA deliverable; AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`; ZERO `contracts/` + ZERO `test/` mutations across the phase; KNOWN-ISSUES.md UNMODIFIED per `D-300-KI-01`; RNGLOCK-CATALOG.md UNMODIFIED.
- **Source-tree mutation attestation:** `git status --porcelain contracts/ test/` returns empty across all 4 task commits.
- **Design-acceptance-token attestation:** zero occurrences of the milestone-precluded design-acceptance token anywhere in this artifact (verified per §3.E negative-grep check at task-commit time).
- **Downstream consumers:** Phase 301 FUZZ-02 action set (§1 admin function enumeration); Phase 303 TERMINAL §3.E ADMA roll-up (§0 executive summary); v44.0 FIX-MILESTONE plan-phase (§4 consolidated handoff register including ERRATUM-01).
