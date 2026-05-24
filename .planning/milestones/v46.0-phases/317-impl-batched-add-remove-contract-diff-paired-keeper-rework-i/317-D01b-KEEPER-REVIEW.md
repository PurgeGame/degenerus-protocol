# Phase 317 — D-01b Keeper Single-Source Reconciliation (Option A) — D-02 Review Note

**Built:** 2026-05-23 (D-01b IMPL, Option A — user-chosen).
**Scope:** `../degenerus-utilities` only. The audit repo (`degenerus-audit/contracts/`) is UNTOUCHED.
**Status:** Implemented + compile-verified. NOTHING committed in either repo (D-02 = USER reviews the keeper diff before commit).

---

## Mechanism: foundry remapping (single-source, no vendored copy)

The utilities build consumes the canonical, audited keeper directly from the sibling
audit repo — no divergent copy. Exact lines added:

`../degenerus-utilities/foundry.toml` (`[profile.default]`):
```toml
allow_paths = ["../degenerus-audit"]
remappings = [
    "forge-std/=lib/forge-std/src/",
    "degenerus-audit/=../degenerus-audit/",
]
```
`fs_permissions` extended with a read entry so cheatcode-backed fs access (and the
out-of-root source read) is permitted:
```toml
fs_permissions = [
    { access = "read-write", path = "./" },
    { access = "read", path = "../degenerus-audit" },
]
```
`../degenerus-utilities/remappings.txt` (kept in sync with foundry.toml so both
remapping sources agree):
```
forge-std/=lib/forge-std/src/
degenerus-audit/=../degenerus-audit/
```

**Transitive resolution verified (the load-bearing correctness check):** AfKing.sol does
`import {ContractAddresses} from "./ContractAddresses.sol"`. Compiled through the remapping,
AfKing's source path is `../degenerus-audit/contracts/AfKing.sol`, so its relative
`./ContractAddresses.sol` resolves to **`../degenerus-audit/contracts/ContractAddresses.sol`**
(the AUDIT repo's complete library, with AF_KING/COIN/COINFLIP/GAME/SDGNRS/VAULT) — NOT
utilities' incomplete one (which lacks AF_KING/SDGNRS/VAULT). Confirmed in the AfKing build
artifact metadata: both `../degenerus-audit/contracts/AfKing.sol` and
`../degenerus-audit/contracts/ContractAddresses.sol` appear as the resolved sources.
Utilities' own `contracts/ContractAddresses.sol` still resolves independently for the deploy
script's pin gate — the two same-named libraries coexist (solc namespaces by full path), no
collision.

## Deploy-script repoint

`script/DeployStreakKeeperV2.s.sol` now imports `AfKing` via the remapping and deploys
`new AfKing(_subCostEthTarget, _bountyEthTarget, _lootboxMin)` — the canonical 3-arg ctor
(LOCKED order: cost, bounty, lootbox — read verbatim from AfKing.sol:263-270, identical arg
shape to the retired StreakKeeperV2 ctor, so the per-network literal selection + the
ZeroSubCostTarget/ZeroBountyTarget/ZeroLootboxFloor pre-broadcast gates carry forward
unchanged). The script CONTRACT name, file path, artifact identity
(`deployments/streakkeeperv2-{chain}.json`, JSON key `streakkeeperV2`), and the
`STREAK_KEEPER_V2` pin are intentionally PRESERVED so the existing
`PatchAddressesForFork.sh` pin pipeline keeps working with zero churn. Stale NatSpec
source-line cites (`StreakKeeperV2.sol:489-491`) and contract-name references were
updated to the canonical AfKing.

## Pinned-address alignment (AF_KING ↔ STREAK_KEEPER_V2)

`contracts/ContractAddresses.sol`: `STREAK_KEEPER_V2 = address(0)` placeholder is retained
as the keeper's pin slot; its header NatSpec was rewritten to describe the canonical model
(it pins the deployed AfKing address; that literal MUST equal the audit-side
`ContractAddresses.AF_KING` the protocol gates key on — burnForKeeper `onlyAfKing`,
creditFlip `onlyFlipCreditors` extension, batchPurchase AF_KING gate; the deploy pipeline
patches both repos' constant to the same address; the AfKing keeper reads the audit-side
AF_KING, not this constant). Both `AF_KING` (audit) and `STREAK_KEEPER_V2` (utilities) remain
`address(0)` placeholders patched at deploy — alignment mechanism unchanged.

## StreakKeeperV2.sol — RETIRED (user's partial work SUPERSEDED)

`contracts/StreakKeeperV2.sol` is DELETED. It was an INCOMPLETE partial hand-rework (it had
aligned burnForKeeper/creditFlip but kept the OLD 2-arg `subscribe(bool,uint8)`, range-based
`sweep(startIdx,count)`, per-player `IGame.purchase`, and lacked `reinvestPct`/`windowPaid`
and the two-tier funding-skip kill). Under Option A it is RETIRED, not finished — the
canonical `degenerus-audit/contracts/AfKing.sol` is more complete and is now the single
source. **The user's in-progress partial keeper rework is explicitly superseded by this
retirement, not silently dropped.** The user's partial edits to
`contracts/interfaces/IBurnie.sol` and `contracts/interfaces/ICoinflip.sol`
(pullForKeeper→burnForKeeper swap + creditFlip add) were also keeper-rework artifacts; since
the canonical AfKing carries its OWN file-scope IGame/IBurnie/ICoinflip interfaces and no
other utilities contract (drone/manager/legacy StreakKeeper) consumes those keeper-only
members, both files were REVERTED to HEAD to keep utilities free of divergent keeper
plumbing. (Drone/manager use only ERC20 IBurnie members — approve/balanceOf/transferFrom —
verified unaffected.)

## Test-harness compile-fixes (bar = COMPILE, not deep coverage)

- `test/StreakKeeperV2.unit.t.sol` — **DROPPED** (deleted). 2570-line suite that imported the
  retired `StreakKeeperV2` type and deeply exercised the removed surface (37 pullForKeeper,
  25 mintForKeeper, 69 old-2-arg-subscribe, 31 range-sweep, 16 purchase refs). Not adaptable
  to the canonical surface without inventing deep new coverage — out of Phase-317 scope.
- `test/StreakKeeperV2.fork.t.sol` — **DROPPED** (deleted). Imported the retired type;
  7 pullForKeeper / 5 mintForKeeper refs against the removed surface.
- `test/Readme.t.sol` — **ADAPTED** (partial). The four StreakKeeperV2-surface doc-sync gates
  (`test_readmeListsAllStreakKeeperV2Functions`, `..FourCallFlow`, `..Deploy`,
  `test_readmeDocumentsPrivilegedFunctionDependency`) were RETIRED: they ran
  `forge inspect StreakKeeperV2` (nonexistent post-retirement) and asserted the retired
  divergent surface (2-arg subscribe, range sweep) + the removed pullForKeeper/mintForKeeper
  README prose. They are pure FFI/readFile string gates (never compile blockers); retired
  with an in-place note. The independent drone/manager + legacy-v2.0 doc-sync gates and the
  shared `_countOccurrences` helper are PRESERVED.
- `test/AfKing.smoke.t.sol` — **ADDED** (new, minimal). Imports AfKing via the remapping and
  constructs it through the cross-repo path — the concrete proof that the paired keeper
  compiles against the canonical surface and that AfKing's transitive ContractAddresses
  resolves to the audit repo. Two passing tests (construct + read immutables; ctor zero-arg
  revert). NOT deep coverage — full AfKing surface re-coverage is a follow-up.

## forge build result (SC#1 part 2)

```
$ FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build --force
Compiling 48 files with Solc 0.8.34
Compiler run successful with warnings   (only benign "state mutability can be restricted to view")
exit: 0
```
Smoke test: `forge test --match-path test/AfKing.smoke.t.sol` → 2 passed, 0 failed.

## Dirty set for USER review (`git -C ../degenerus-utilities status --porcelain`)

```
 M .planning/config.json            <- PRE-EXISTING, unrelated (_auto_chain_active flip); NOT touched by this work
 M contracts/ContractAddresses.sol  <- STREAK_KEEPER_V2 header NatSpec rewrite (single-source alignment)
 D contracts/StreakKeeperV2.sol      <- divergent keeper RETIRED (superseded by canonical AfKing)
 M foundry.toml                     <- remapping + allow_paths + fs_permissions read entry
 M remappings.txt                   <- degenerus-audit/ remapping
 M script/DeployStreakKeeperV2.s.sol <- repoint import + `new AfKing(...)`; identity preserved
 M test/Readme.t.sol                <- four V2-surface doc-sync gates retired
 D test/StreakKeeperV2.fork.t.sol    <- retired (removed-surface fork harness)
 D test/StreakKeeperV2.unit.t.sol    <- retired (removed-surface unit harness)
?? test/AfKing.smoke.t.sol          <- NEW compile-smoke (SC#1 proof)
```

**NOTHING committed. NOTHING pushed.** The audit repo is fully clean (`git -C
../degenerus-audit status --porcelain` empty). `.planning/config.json` is left exactly as
found (pre-existing, out of scope).
```
