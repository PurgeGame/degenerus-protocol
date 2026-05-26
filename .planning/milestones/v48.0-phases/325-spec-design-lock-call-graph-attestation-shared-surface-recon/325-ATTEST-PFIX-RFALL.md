# 325 — Call-Graph Attestation: PFIX (item 1) + RFALL (item 2)

## Scope

READ-ONLY grep-attestation of every `file:line` anchor cited in the v48.0 plan docs for
**item 1 (PFIX — presale-box DGNRS drain fix, F-47-01)** and **item 2 (RFALL — redemption
ETH-empty stETH fallback, F-47-02)** against the v47.0-closure baseline HEAD
`da5c9d50989707c8964a9411e68c51ca1b1a25f2`.

Plan docs attested:
- `.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` (item 1)
- `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` (item 2)

## Sources of truth (this attestation)

- `contracts/modules/DegenerusGameLootboxModule.sol` (1897 lines) — PFIX
- `contracts/StakedDegenerusStonk.sol` (965 lines) — RFALL (sDGNRS-side reservation + claim payout)
- `contracts/DegenerusGame.sol` (2748 lines) — RFALL (`pullRedemptionReserve`)

**Attestation-method note (baseline-anchored):** The working tree's `contracts/` is byte-identical
to baseline HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2` — verified `git diff --name-only
da5c9d50 HEAD -- contracts/` returns ZERO files. So every grep is against the live tree and is
implicitly resolved at the baseline. Belt-and-suspenders spot-checks (`git show da5c9d50:contracts/...
| grep -n`) confirmed the divisor line (`:720`) and `pullRedemptionReserve` open (`:1888`) land at the
same lines in the baseline blob as in the live tree. Read from `contracts/` ONLY.

## Verdict legend

- `MATCH` — anchor lands on the claimed line.
- `SHIFTED(±N)` — content present, N lines off the claimed line/range.
- `ABSENT` — content not found / materially diverged (surfaced as an IMPL blocker).

---

## A. PFIX (item 1) — `DegenerusGameLootboxModule.sol` anchor reconciliation

| # | Anchor (claimed) | ACTUAL (contracts/modules/DegenerusGameLootboxModule.sol) | Verdict |
|---|---|---|---|
| P1 | `:671` `dgnrsOut = _presaleBoxDgnrsReward(player, amount, soldBefore);` (the 40%-DGNRS branch call) | `dgnrsOut = _presaleBoxDgnrsReward(player, amount, soldBefore);` at **:671**, inside the `else if (outcome < 90)` 40%-DGNRS branch (:669-671) | **MATCH** |
| P2 | `:686` closing-box `swept = dgnrs.transferFromPool(...)` (the windfall sweep — F-47-01 root) | closing-box block `if (closing)` :681; `uint256 remaining = dgnrs.poolBalance(Pool.PresaleBox)` :682-684; `swept = dgnrs.transferFromPool(Pool.PresaleBox, player, remaining);` at **:686-690**; `dgnrsOut += swept;` :691 | **MATCH** (sweep call opens at :686 exactly) |
| P3 | `:705` `function _presaleBoxDgnrsReward(` | `function _presaleBoxDgnrsReward(` opens at **:705**; params :706-708; body :710-726; closes :727 | **MATCH** |
| P4 | `:717` `uint256 tierTenths = _presaleBoxDgnrsTierTenths(soldBefore);` | `uint256 tierTenths = _presaleBoxDgnrsTierTenths(soldBefore);` at **:717** | **MATCH** |
| P5 | `:719-720` the `base = poolStart/100` derivation comment + the `/(1_000 * 1 ether)` divisor (the F-47-01 1-line fix target) | derivation comment `// amount (wei) * (poolStart/100) per ETH * tier/10:` :718 + `//   = poolStart * tierTenths * amount / (100 * 10 * 1 ether)` at **:719**; divisor line `uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (1_000 * 1 ether);` at **:720** | **MATCH** (the `1_000` divisor is at :720; the `poolStart/100` derivation comment at :716+:718-719 — the exact F-47-01 fix target: `1_000`→`400`, `poolStart/100`→`poolStart/40`) |
| P6 | `transferFromPool` clamps to live pool balance (PFIX safety: a run of early DGNRS hits cannot over-draw) | `StakedDegenerusStonk.sol:475` `function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred)`; clamp `if (amount > available) { amount = available; }` at **:481-483** (returns the clamped `amount`); `if (available == 0) return 0;` :480 | **MATCH** (clamp-to-live-balance confirmed; the closing sweep and per-box draw both route through it → cannot over-draw) |
| P7 | tier-curve `[3.0,2.5,2.0,1.5,1.0]` / 5×10-ETH tiers (`_presaleBoxDgnrsTierTenths`) unchanged by the fix (scale-only) | `function _presaleBoxDgnrsTierTenths(uint256 soldBefore)` :733-747: 5-tier ladder on `PRESALE_BOX_DGNRS_TIER_WIDTH` returning `PRESALE_BOX_DGNRS_TIER1..5_TENTHS` (:737/:739/:741/:743/:745) — the fix touches the divisor only, NOT this function | **MATCH** (tier function present + untouched by the locked fix) |

### PFIX exact fix-target body (`DegenerusGameLootboxModule.sol:716-720`)

```solidity
        // base = poolStart / 100 DGNRS per ETH; tier multiplier in tenths.
        uint256 tierTenths = _presaleBoxDgnrsTierTenths(soldBefore);
        // amount (wei) * (poolStart/100) per ETH * tier/10:
        //   = poolStart * tierTenths * amount / (100 * 10 * 1 ether)
        uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (1_000 * 1 ether);
```

The locked F-47-01 fix (`PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` §"Fix"): `1_000`→`400` (= `base =
poolStart/40`), plus the two derivation comments (`:716` `poolStart / 100` and `:718-719` `(100 * 10
* 1 ether)`) rewritten to `poolStart / 40` / `(40 * 10 * 1 ether)`. The plan doc's own anchor citation
(`:678-693` for the sweep, `:705-727` for the function, `:720` for the divisor) lands EXACT.

---

## B. RFALL (item 2) — `StakedDegenerusStonk.sol` + `DegenerusGame.sol` anchor reconciliation

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| R1 | sStonk `:844-848` `totalMoney = address(this).balance + steth.balanceOf(this) + claimable[SDGNRS] − pendingRedemptionEthValue` (the 4-term submit base) | `StakedDegenerusStonk.sol`: `uint256 ethBal = address(this).balance;` :844; `uint256 stethBal = steth.balanceOf(address(this));` :845; `uint256 claimableEth = _claimableWinnings();` :846; `uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;` at **:847**; `uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;` :848 | **MATCH** (4-term basis: ETH balance + stETH balance + claimable[SDGNRS] − pendingRedemptionEthValue, exactly as claimed) |
| R2 | sStonk `:880-887` the `maxIncrement` 175% reservation pull (`game.pullRedemptionReserve`) | `uint256 prevBaseWei = uint256(pool.ethBase) * 1e9;` :880; `pool.ethBase += uint64(ethValueOwed / 1e9);` :881; `uint256 newBaseWei = uint256(pool.ethBase) * 1e9;` :882; `uint256 maxIncrement = (newBaseWei * MAX_ROLL) / 100 - (prevBaseWei * MAX_ROLL) / 100;` at **:883**; `if (maxIncrement != 0) { game.pullRedemptionReserve(maxIncrement); }` :884-886; `pendingRedemptionEthValue += maxIncrement;` :887 | **MATCH** (the 175% `MAX_ROLL` telescoping-delta increment + the `pullRedemptionReserve` pull site land in the claimed :880-887 envelope; pull call at :885) |
| R3 | DegenerusGame `:1888-1899` `pullRedemptionReserve` is a CHECKED single-asset `claimableWinnings[SDGNRS]`-only debit with NO ETH/stETH fallback today (the F-47-02 gap to confirm present) | `function pullRedemptionReserve(uint256 amount) external` opens at **:1888**; `if (msg.sender != ContractAddresses.SDGNRS) revert E();` :1889; `if (amount == 0) return;` :1890; CHECKED debit `claimableWinnings[ContractAddresses.SDGNRS] -= amount;` :1893 + `claimablePool -= uint128(amount);` :1894; CEI ETH move `payable(SDGNRS).call{value: amount}("")` :1897; `if (!ok) revert E();` :1898; closes :1899 | **MATCH** + **GAP CONFIRMED PRESENT** (single CHECKED `claimableWinnings[SDGNRS]` debit; NO stETH leg, NO fallback to sDGNRS's own ETH/stETH balance — reverts fail-closed via 0.8 checked subtraction at :1893 when claimable < amount; this is exactly the F-47-02 mid-game-ETH-depletion brick the fix addresses) |
| R4 | sStonk `:622` + `:932` the two existing stETH-transfer claim paths | `:622` `if (!steth.transfer(beneficiary, stethOut)) revert TransferFailed();` — the **game-over** burn payout path (NatSpec :588 "ETH/stETH goes to beneficiary"); `:932` `if (!steth.transfer(player, stethOut)) revert TransferFailed();` — the `_payEth` deterministic ETH→stETH fallback (:918-933, NatSpec :914-917) | **MATCH** (both stETH-transfer call sites land exactly at :622 and :932; `_payEth` already does ETH-insufficient→stETH fallback AT CLAIM, but the SUBMIT-side reservation `pullRedemptionReserve` does NOT — the fix extends the claim-side fallback pattern to the submit-side reservation per the plan's REDEEM-04 reference) |
| R5 | v47 OPEN-E 6-arg ctor `subscribe` + SUB-09 self-sub that drains `claimable[SDGNRS]` | sStonk inline `interface IAfKingSubscribe { function subscribe(address player, bool drainGameCreditFirst, bool useTickets, uint8 dailyQuantity, uint8 reinvestPct, address fundingSource) external payable; }` :57-67 (6-arg, declares ONLY `subscribe`); SUB-09 ctor self-sub `afKing.subscribe(address(this), true, false, 1, 2, address(0));` at **:384** (NatSpec :378 "SUB-09 protocol-owned self-subscription: claimable-only daily lootbox"); the submit-time comment at :871 names "AfKing SUB-09 self-sub" as a concurrent `claimable[SDGNRS]` drainer the MAX pull defends against | **MATCH** (6-arg subscribe + SUB-09 self-sub both present; the SUB-09 self-sub is exactly why `pullRedemptionReserve` pulls the MAX 175% — confirms the reservation's defend-against-concurrent-drain rationale) |
| R6 | `pendingRedemptionEthValue` single tracked value (D-06: pure-ETH OR pure-stETH, no separate stETH-denominated reservation) | `uint256 public pendingRedemptionEthValue;` :263 ("total physically-segregated ETH across all periods"); subtracted in all three bases (submit :847, preview :598, resolve :758); decremented at roll-resolve :668 + :719; the fix per D-06 keeps THIS single value (no new stETH-denominated reservation slot) | **MATCH** (single tracked value confirmed; the F-47-02 fix per D-06 reuses it — coverage checked against the same asset basis the base is inflated by) |

### RFALL exact fix-target bodies

**`StakedDegenerusStonk.sol:847` (the 4-term submit base — what the reservation inflates by):**
```solidity
        uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
```

**`StakedDegenerusStonk.sol:883-887` (the MAX 175% reservation increment + pull):**
```solidity
        uint256 maxIncrement = (newBaseWei * MAX_ROLL) / 100 - (prevBaseWei * MAX_ROLL) / 100;
        if (maxIncrement != 0) {
            game.pullRedemptionReserve(maxIncrement);
        }
        pendingRedemptionEthValue += maxIncrement;
```

**`DegenerusGame.sol:1888-1899` (the claimable-only CHECKED debit — F-47-02 gap; needs the ETH-vs-stETH coverage branch):**
```solidity
    function pullRedemptionReserve(uint256 amount) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert E();
        if (amount == 0) return;

        // CHECKED debit (no unchecked): reverts fail-closed if claimable < amount.
        claimableWinnings[ContractAddresses.SDGNRS] -= amount;
        claimablePool -= uint128(amount);

        // CEI: move the real ETH out to sDGNRS after the state decrement.
        (bool ok, ) = payable(ContractAddresses.SDGNRS).call{value: amount}("");
        if (!ok) revert E();
    }
```

**Key RFALL finding:** the submit-time reservation (`maxIncrement` → `pullRedemptionReserve`) is
ETH-only and fail-closed; if `claimableWinnings[SDGNRS]` (the ETH side) cannot cover the 175% MAX, the
burn reverts with NO fallback to sDGNRS's stETH/ETH balance — the F-47-02 mid-game-ETH-depletion +
stETH-donation brick. The claim-side `_payEth` (:918-933) ALREADY has a deterministic ETH→stETH
fallback; the locked fix extends that same pure-ETH-OR-pure-stETH segregation to the submit-side
reservation (`pullRedemptionReserve` gets the ETH-vs-stETH coverage branch), keeping the single
`pendingRedemptionEthValue` tracker per D-06. The `:622`/`:932` stETH-transfer call sites already
exist (no new external-call selector needed at claim — the payout asset selection composes on top).

---

## C. Roll-up

- **PFIX (item 1) anchors:** 7 attested — **7 MATCH / 0 SHIFTED / 0 ABSENT.** All anchors land
  EXACT (the plan doc's `:671`/`:686`/`:705`/`:717`/`:720` citations are byte-accurate against
  baseline; the `/(1_000 * 1 ether)` divisor + `poolStart/100` derivation comment fix target verified
  at :720/:716-719; `transferFromPool` clamp-to-live-balance verified; tier function untouched).
- **RFALL (item 2) anchors:** 6 attested — **6 MATCH / 0 SHIFTED / 0 ABSENT.** The totalMoney 4-term
  basis (:847), maxIncrement 175% pull (:880-887), `pullRedemptionReserve` CHECKED claimable-only
  debit with NO stETH/ETH fallback (:1888-1899 — the F-47-02 gap **confirmed present**), the two
  existing stETH-transfer claim paths (:622/:932), the SUB-09 6-arg self-sub (:384), and the single
  `pendingRedemptionEthValue` tracker (:263) all verify exactly.

**IMPL-blocker count for items 1+2: 0.** Every cited anchor is accurate against the baseline; the
two F-47-01 / F-47-02 fix targets land on verified current code. No "by construction" claim survives
un-grepped: the PFIX `transferFromPool` clamp and the RFALL claim-side `_payEth` fallback were both
grep-confirmed so the fix reasoning carries no unverified reachability assumption.

*Anchors will shift once the Phase 326 batched diff lands — re-grep at IMPL time per the standard
footer. The shared `pullRedemptionReserve` signature is consumed by Plan 03's shared-surface
reconciliation (it is edited by item 2 here AND read by the renamed item-3 crank surface in
DegenerusGame.sol).*
