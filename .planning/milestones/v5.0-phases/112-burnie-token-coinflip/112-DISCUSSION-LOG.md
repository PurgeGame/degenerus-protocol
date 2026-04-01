# Phase 112: BURNIE Token + Coinflip - Discussion Log

**Phase:** 112-burnie-token-coinflip
**Created:** 2026-03-25

---

## Context Gathering

**Decision:** Categories B/C/D only, full Mad Genius treatment, MULTI-PARENT standalone analysis for shared helpers.

**Key architectural observation:** Unlike prior module phases (104-111) which operate via delegatecall in Game's storage context, BurnieCoin and BurnieCoinflip are STANDALONE contracts with their own storage. The BAF cache-overwrite pattern here manifests through cross-contract external call callbacks, not shared storage writes.

**Priority investigation areas identified:**
1. Auto-claim callback chain (transfer -> _claimCoinflipShortfall -> BurnieCoinflip -> mintForCoinflip)
2. Vault redirect correctness in _transfer/_mint/_burn (supply invariant preservation)
3. Auto-rebuy carry mechanics during RNG lock
4. Bounty manipulation timing with RNG knowledge
5. uint128 truncation risks in PlayerCoinflipState

**Contract sizes:** BurnieCoin ~1,075 lines, BurnieCoinflip ~1,129 lines. Total ~2,204 lines across 2 contracts.

---

## Planning Decisions

Plans follow established 4-plan structure from Phases 103-111.

No deviations from standard audit methodology required.
