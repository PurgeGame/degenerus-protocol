# Requirements — v65.0 BURNIE → FLIP Currency Rename

> Scope = this repo only (contracts + forge/JS tests + deploy scripts). Website/papers repo is separate (out of scope). **BROAD rebrand** chosen. Authoritative surface: `.planning/v65-FLIP-RENAME-SURFACE-MAP.md`. Hard invariant across all reqs: **full FUNCTIONAL PARITY — only names/selectors/metadata strings change, zero logic change.**

## Contract & file renames (CTR)
- [ ] **CTR-01**: `BurnieCoin` contract → `FLIP`; file `BurnieCoin.sol` → `FLIP.sol`.
- [ ] **CTR-02**: `BurnieCoinflip` contract → `Coinflip`; file `BurnieCoinflip.sol` → `Coinflip.sol`.
- [ ] **CTR-03**: `IBurnieCoinflip` (+ `Player`/`LinkReward`/`Affiliate` variants) → `ICoinflip*`; file `interfaces/IBurnieCoinflip.sol` → `interfaces/ICoinflip.sol`.
- [ ] **CTR-04**: `IBurnieCoin` → `IFLIP`; `IBurnieTombstone` → `IFlipTombstone`.

## On-chain metadata strings (STR)
- [ ] **STR-01**: `name "Burnies"` → `"Degenerus Gambling Token"`.
- [ ] **STR-02**: `symbol "BURNIE"` → `"FLIP"`.

## Identifier renames — BROAD (IDT)
- [ ] **IDT-01**: every `burnie*`/`Burnie*`/`BURNIE*` token identifier (functions, params, constants, state vars, struct fields, events, errors, modifiers) → `flip*`/`Flip*`/`FLIP*` per the canonical table (§3), in dependency/longest-first order.
- [ ] **IDT-02**: the 11 `coin`-as-the-token identifiers (§4: `coinOut`, `coinShare`, `coinToken`, `coin`, `coinPlayer`, `COIN_JACKPOT_TAG`/`COIN_LEVEL_TAG`, `_runCoinJackpot`, `payDailyCoinJackpot`, `redeemableCoinBacking`, `FarFutureCoinJackpotWinner`, `FAR_FUTURE_COIN_*`) → `flip*`.
- [ ] **IDT-03**: comments / docstrings / string-literals naming the token (~200 `BURNIE` tokens / 17 files) → `FLIP`.

## Carve-outs / parity (KEEP)
- [ ] **KEEP-01**: creator persona untouched — `@author Burnie Degenerus` (17 files), `burnie@degener.us`.
- [ ] **KEEP-02**: the verb `burn` untouched — `_burn`, `burnCoin`, `burnForCoinflip`, decimator burn-tracking, `mint*`, `traitBurnTicket`, etc.
- [ ] **KEEP-03**: the `coinflip`/`flip` action untouched (incl. `consumeCoinflipsForBurn`); generic `coin` untouched (`burnCoin`, `mintForGame`, `PRICE_COIN_UNIT`, `IDegenerusCoin`, `IVaultCoin`).

## External-impact manifest (EXT)
- [ ] **EXT-01**: produce the selector / event-topic / artifact-name change manifest (old→new) so the off-chain indexer & ABI consumers can re-vendor.

## Tests & scripts (TST)
- [ ] **TST-01**: rename the 8 test files; update all ~45 test files' contract/identifier refs + ERC20 `name`/`symbol` assertions.
- [ ] **TST-02**: update artifact-name dependencies — `scripts/lib/predictAddresses.js` `KEY_TO_CONTRACT`, `test/helpers/deployFixture.js`, `package.json` test glob, any hardcoded `forge-out/*` paths.
- [ ] **TST-03**: full forge + JS suites green post-rename (name-identical / non-widening vs the green baseline).

## Verify & re-attest (VER)
- [ ] **VER-01**: functional-parity proof — diff review confirms logic-identical (only names/selectors/strings differ); no behavior change.
- [ ] **VER-02**: EIP-170 size check — Game + renamed contracts within the 24,576 ceiling (logic unchanged → expect ~neutral).
- [ ] **VER-03**: re-attest / re-freeze the renamed subject; record the closure.

## Future / Out of scope
- Website + papers repo BURNIE→FLIP (separate repo; papers-first pilot `theory/index.html`, `whitepaper/burnie/`→`whitepaper/flip/` + redirect).
- Indexer re-vendor itself (external consumer; this milestone delivers the EXT-01 manifest only).
- Coin art / logo (unchanged per USER).

## Traceability
| Phase | Requirements |
|---|---|
| 406 FOUNDATION | KEEP-01, KEEP-02, KEEP-03, EXT-01 (draft) |
| 407 CONTRACT REFACTOR | CTR-01, CTR-02, CTR-03, CTR-04, STR-01, STR-02, IDT-01, IDT-02, IDT-03, KEEP-01, KEEP-02, KEEP-03 |
| 408 TESTS & SCRIPTS | TST-01, TST-02, TST-03 |
| 409 VERIFY & RE-ATTEST | VER-01, VER-02, VER-03, EXT-01 (final) |

All 18 requirements mapped; KEEP-* and EXT-01 span phases (defined at 406, enforced/finalized downstream). 100% coverage.
