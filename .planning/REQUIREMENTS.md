# Requirements: Degenerus Protocol — Contract Hardening & Parity Verification

**Defined:** 2026-03-06
**Core Value:** Every constant, comment, and documented number in the codebase matches actual contract behavior, and every post-audit change has dedicated test coverage.

## v6.0 Requirements

Requirements for contract hardening milestone. Each maps to roadmap phases.

### Governance & Admin (ADMIN)

- [ ] **ADMIN-01**: Test that only accounts holding >50.1% DGVE supply pass `onlyOwner` check in DegenerusAdmin (CREATOR address alone must fail)
- [ ] **ADMIN-02**: Test that only accounts holding >50.1% DGVE supply pass `onlyVaultOwner` check in DegenerusVault (threshold is `balance * 1000 > supply * 501`)
- [ ] **ADMIN-03**: Test that `shutdownVrf()` reverts when called by any address except GAME contract
- [ ] **ADMIN-04**: Test that `shutdownVrf()` cancels subscription, sweeps LINK to VAULT, and sets subscriptionId to 0
- [ ] **ADMIN-05**: Test that `shutdownVrf()` silently succeeds (no revert) when subscriptionId is already 0
- [ ] **ADMIN-06**: Test that `shutdownVrf()` try/catch paths handle coordinator failure and LINK transfer failure gracefully

### Advance Module Gating (GATE)

- [ ] **GATE-01**: Test tiered advanceGame mint gate — caller must have minted on the current purchase day to advance
- [ ] **GATE-02**: Test time-based unlock — gate relaxes after configured delay
- [ ] **GATE-03**: Test DGVE majority holder bypasses mint gate entirely
- [ ] **GATE-04**: Test that non-minter, non-DGVE-holder reverts with `MustMintToday()`

### Affiliate System (AFF)

- [ ] **AFF-01**: Test per-referrer commission cap — affiliate earns at most 0.5 ETH BURNIE from a single sender per level
- [ ] **AFF-02**: Test that cap tracks cumulative spend — multiple small purchases from same sender hit cap
- [ ] **AFF-03**: Test that cap resets per level — same sender/affiliate pair can earn again at next level
- [ ] **AFF-04**: Test that cap is per-affiliate — different affiliates have independent caps for same sender
- [ ] **AFF-05**: Test lootbox activity taper — score <15000 BPS: 100% payout, no taper
- [ ] **AFF-06**: Test lootbox activity taper — score 15000-25500 BPS: linear taper from 100% to 50%
- [ ] **AFF-07**: Test lootbox activity taper — score >=25500 BPS: floor at 50% payout
- [ ] **AFF-08**: Test leaderboard tracking uses full untapered amount (even when payout is tapered)
- [ ] **AFF-09**: Test `lootboxActivityScore` parameter flows correctly through `payAffiliate`

### Security Fixes (FIX)

- [ ] **FIX-01**: Test whale bundle purchase reverts after gameOver
- [ ] **FIX-02**: Test lazy pass purchase reverts after gameOver
- [ ] **FIX-03**: Test deity pass purchase reverts after gameOver
- [ ] **FIX-04**: Test `receive()` reverts after gameOver (plain ETH transfers blocked)
- [ ] **FIX-05**: Test deity pass refund clears deityPassPurchasedCount for the refunded buyer
- [ ] **FIX-06**: Test no voluntary deity refund path exists — only gameOver-triggered refund
- [ ] **FIX-07**: Test gameOver deity payout: flat 20 ETH/pass, levels 0-9 only, FIFO by purchase order, budget-capped
- [ ] **FIX-08**: Test BURNIE ticket purchases revert within 30 days of liveness-guard timeout
- [ ] **FIX-09**: Test subscriptionId stored as uint256 (not uint64) — large subscription IDs handled correctly
- [ ] **FIX-10**: Test 1 wei sentinel preserved in degenerette bet collection — claimable set to 1 not 0 after claim
- [ ] **FIX-11**: Test capBucketCounts does not underflow — zero-count buckets handled safely
- [ ] **FIX-12**: Test carryover floor — minimum carryover amount enforced

### Economic Hardening (ECON)

- [ ] **ECON-01**: Test JackpotModule uses explicit 46% futureShare (2300+2300 BPS) — ~8% buffer stays unextracted
- [ ] **ECON-02**: Test MintModule has no level-dependent coin cost modifiers (removed step 13/18 multipliers)
- [ ] **ECON-03**: Test multi-level scatter targeting for BAF rounds — tickets distributed across correct level range
- [ ] **ECON-04**: Test compressed jackpot — when target met in <=2 days, counter advances 2 per physical day (5 logical days in 3 physical)
- [ ] **ECON-05**: Test LINK reward formula correctness (post-fix)

### Game Theory Paper Parity (PAR)

- [ ] **PAR-01**: Verify PriceLookupLib prices match game theory paper at every tier boundary (levels 0,4,5,9,10,29,30,59,60,89,90,99,100,129,130,159,160,189,190,199,200)
- [ ] **PAR-02**: Verify ticket cost formula `costWei = (priceWei * qty) / 400` matches paper's "one entry = P_l/4 ETH"
- [ ] **PAR-03**: Verify prize pool split BPS (90/10 ticket, 10/90 lootbox, 40/40/20 presale lootbox) match paper
- [ ] **PAR-04**: Verify jackpot day structure (5 days, 6-14% days 1-4, 100% day 5) matches paper
- [ ] **PAR-05**: Verify jackpot bucket shares (20/20/20/20 days 1-4, 60/13.33/13.33/13.34 day 5) match paper
- [ ] **PAR-06**: Verify activity score components and caps (50% streak, 25% mint count, 100% quest, 50% affiliate, +10%/+40%/+80% passes) match paper
- [ ] **PAR-07**: Verify lootbox EV breakpoints (80%->100% at 0-60%, 100%->135% at 60-255%) match paper
- [ ] **PAR-08**: Verify affiliate commission rates (25% fresh L1-3, 20% fresh L4+, 5% recycled) match paper
- [ ] **PAR-09**: Verify affiliate tier structure (direct -> upline1 at 20% -> upline2 at 4%) matches paper
- [ ] **PAR-10**: Verify whale bundle pricing (2.4 ETH levels 0-3, 4 ETH level 4+) matches paper
- [ ] **PAR-11**: Verify lazy pass pricing (0.24 ETH flat levels 0-2, sum-of-10-level-prices level 3+) matches paper
- [ ] **PAR-12**: Verify deity pass T(n) pricing (24 + k*(k+1)/2 ETH) matches paper
- [ ] **PAR-13**: Verify coinflip payout distribution (5%/90%/5% tiers, mean ~1.97x) matches paper
- [ ] **PAR-14**: Verify yield distribution split (23% vault, 23% DGNRS, 46% futurePool, 8% buffer) matches paper
- [ ] **PAR-15**: Verify BURNIE entry cost (250 BURNIE = 1 entry, 1000 BURNIE = 1 full ticket) matches paper
- [ ] **PAR-16**: Verify Degenerette base payouts and ROI curve match paper
- [ ] **PAR-17**: Verify pass capital injection splits (30/70 level 0, 5/95 level 1+ for whale/deity; 90/10 all levels for lazy) match paper
- [ ] **PAR-18**: Verify future ticket odds (95% near k in [0,5], 5% far k in [5,50]) match paper

### NatSpec Comment Accuracy (DOC)

- [x] **DOC-01**: Audit all NatSpec `@notice` and `@dev` comments in DegenerusAdmin — every claim verified against code
- [x] **DOC-02**: Audit all NatSpec comments in DegenerusAffiliate — rates, tiers, caps match implementation
- [x] **DOC-03**: Audit all NatSpec comments in AdvanceModule — stage descriptions, timing, gates match implementation
- [ ] **DOC-04**: Audit all NatSpec comments in MintModule — cost formulas, split ratios, quest rewards match implementation
- [ ] **DOC-05**: Audit all NatSpec comments in JackpotModule — bucket sizes, share splits, carryover logic match implementation
- [x] **DOC-06**: Audit all NatSpec comments in WhaleModule — pricing, eligibility, bonus tiers match implementation
- [x] **DOC-07**: Audit all NatSpec comments in remaining modules (Endgame, GameOver, Lootbox, Boon, Decimator, Degenerette, MintStreakUtils)
- [x] **DOC-08**: Audit all NatSpec comments in standalone contracts (BurnieCoin, BurnieCoinflip, DegenerusVault, DegenerusStonk, DegenerusQuests, DegenerusJackpots)
- [ ] **DOC-09**: Verify all error message descriptions match their actual trigger conditions
- [ ] **DOC-10**: Verify all event parameter descriptions match actual emitted values

## v7 Requirements

Deferred to future release.

### Extended Parity

- **PAR2-01**: Automated CI check that NatSpec constants match contract constants
- **PAR2-02**: Formal specification document auto-generated from contract constants

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Separate concern |
| Simulation engine | Paused, separate milestone |
| Testnet contracts | Mainnet is the target |
| Deployment scripts | Operational, not testing surface |
| Foundry/Halmos tests | Hardhat suite is the primary test framework for this milestone |
| Pre-audit contract changes | Earlier commits already tested through 951-test suite |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ADMIN-01 | Phase 43 | Pending |
| ADMIN-02 | Phase 43 | Pending |
| ADMIN-03 | Phase 43 | Pending |
| ADMIN-04 | Phase 43 | Pending |
| ADMIN-05 | Phase 43 | Pending |
| ADMIN-06 | Phase 43 | Pending |
| GATE-01 | Phase 43 | Pending |
| GATE-02 | Phase 43 | Pending |
| GATE-03 | Phase 43 | Pending |
| GATE-04 | Phase 43 | Pending |
| AFF-01 | Phase 44 | Pending |
| AFF-02 | Phase 44 | Pending |
| AFF-03 | Phase 44 | Pending |
| AFF-04 | Phase 44 | Pending |
| AFF-05 | Phase 44 | Pending |
| AFF-06 | Phase 44 | Pending |
| AFF-07 | Phase 44 | Pending |
| AFF-08 | Phase 44 | Pending |
| AFF-09 | Phase 44 | Pending |
| FIX-01 | Phase 45 | Pending |
| FIX-02 | Phase 45 | Pending |
| FIX-03 | Phase 45 | Pending |
| FIX-04 | Phase 45 | Pending |
| FIX-05 | Phase 45 | Pending |
| FIX-06 | Phase 45 | Pending |
| FIX-07 | Phase 45 | Pending |
| FIX-08 | Phase 45 | Pending |
| FIX-09 | Phase 45 | Pending |
| FIX-10 | Phase 45 | Pending |
| FIX-11 | Phase 45 | Pending |
| FIX-12 | Phase 45 | Pending |
| ECON-01 | Phase 45 | Pending |
| ECON-02 | Phase 45 | Pending |
| ECON-03 | Phase 45 | Pending |
| ECON-04 | Phase 45 | Pending |
| ECON-05 | Phase 45 | Pending |
| PAR-01 | Phase 46 | Pending |
| PAR-02 | Phase 46 | Pending |
| PAR-03 | Phase 46 | Pending |
| PAR-04 | Phase 46 | Pending |
| PAR-05 | Phase 46 | Pending |
| PAR-06 | Phase 46 | Pending |
| PAR-07 | Phase 46 | Pending |
| PAR-08 | Phase 46 | Pending |
| PAR-09 | Phase 46 | Pending |
| PAR-10 | Phase 46 | Pending |
| PAR-11 | Phase 46 | Pending |
| PAR-12 | Phase 46 | Pending |
| PAR-13 | Phase 46 | Pending |
| PAR-14 | Phase 46 | Pending |
| PAR-15 | Phase 46 | Pending |
| PAR-16 | Phase 46 | Pending |
| PAR-17 | Phase 46 | Pending |
| PAR-18 | Phase 46 | Pending |
| DOC-01 | Phase 47 | Complete |
| DOC-02 | Phase 47 | Complete |
| DOC-03 | Phase 47 | Complete |
| DOC-04 | Phase 47 | Pending |
| DOC-05 | Phase 47 | Pending |
| DOC-06 | Phase 47 | Complete |
| DOC-07 | Phase 47 | Complete |
| DOC-08 | Phase 47 | Complete |
| DOC-09 | Phase 47 | Pending |
| DOC-10 | Phase 47 | Pending |

**Coverage:**
- v6.0 requirements: 64 total
- Mapped to phases: 64
- Unmapped: 0

---
*Requirements defined: 2026-03-06*
*Last updated: 2026-03-06 after roadmap creation*
