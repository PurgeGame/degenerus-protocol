# Council Sweep 382 — PRIME: v61 new code (afking-as-payment · cashout-curse · deity-smite)

You are an external auditor on a cross-model council auditing the **Degenerus Protocol** before a Code4rena
audit. Read the EXACT frozen source at git commit `c4d48008` via `git show c4d48008:contracts/<File>.sol`
(ignore the working tree — it has test-only additions). Be concrete and reachable: a finding needs a real
ordered call sequence (actor / level / timing). Speculative "could maybe" gaps without a reachable sequence
are not useful.

**Threat priority for THIS protocol:** DOMINANT = RNG/freeze manipulability + solvency
(`claimablePool` / pool backing identity); HIGH = gas-DoS in the `advanceGame` chain (16,777,216 gas =
permanent game-over brick); LOW/confirmatory = access-control, reentrancy, MEV.

**ALREADY FOUND (do NOT re-report):** V62-01 — the permissionless lootbox auto-open
(`openBoxes`/`_openHumanBoxes`) reads the active `LR_INDEX` but VRF words land at `LR_INDEX − 1`, so
human/presale boxes never auto-open.

**KNOWN BY-DESIGN (do NOT flag):** lootbox open TIMING via the permissionless open is not a player edge
(seed frozen at `keccak(rngWord,player,amount)`); Degenerette RTP>100% + near-worthless WWXRP are
calibrated; operator-approval IS the trust boundary (no "tricked into approving" actor); afking
pass-eviction inclusive boundary (`<=` validThroughLevel) is intentional; lootbox queue-then-materialize
is intentional UX; `claimBingo` has no level guard by design; affiliate `claim` is single-step direct-mint
by design; PRESALE-01 tiny reinvest over-credit is wontfix.

## Focus — the v61-new contract surface (PRIME-01..04)

1. **afking-as-payment spine (PRIME-02).** The new `msg.value → claimable → afking` fund-flow. Verify the
   SOLVENCY identity `claimablePool == Σ (claimableWinnings + afkingFunding)` holds across EVERY spend
   path; the `msg.value` path vs the existing `_settleShortfall` logic; the **claimable/afking
   slot-packing** (`balancesPacked` slot 7 = `[afking:hi128 | claimable:lo128]`) for truncation, a 127→128
   cross-half carry, or a collision between the two halves. Trace `GameAfkingModule.sol` fund/cover/cashout.
2. **combo funding-mix parity tweak (PRIME-02).** `purchaseWithPresaleBox` is now `payable` and splits
   `msg.value` mint/box via `_purchaseForWith`. Does the `mintCost` recompute match the canonical price
   path (level vs level+1 by `jackpotPhaseFlag`, `TICKET_SCALE`)? Does the `msg.value − mintFresh` box
   remainder strand or double-count? Does it match the funding logic of every OTHER ETH-consuming path
   (it removes an asymmetry — verify it adds none)?
3. **cashout-curse spine (PRIME-03).** The state machine (SET on stale cashout, CURE on a ≥1-ticket buy,
   the cap, permissionless `decurse`). Find an exploitable nudge, a griefing vector, or a cure-bypass.
4. **deity-smite spine (PRIME-04).** The immunity check is a PARALLEL-PATH with afking eviction
   `validThroughLevel` — do they AGREE on "active afker"? The curse-stack accounting; interaction with the
   decimator / jackpot / activity-score consumers.
5. **Carried candidate FC4:** does a frozen-account cancel auto-claim + drain `affiliateBase` correctly,
   or strand/double-spend it? (`DegenerusAffiliate` + the afking cancel path.)

## Output (per finding)
PROPERTY violated · concrete reachable CALL SEQUENCE (actor/level/timing) · STATE VAR + `file:line` at
`c4d48008` · SEVERITY (CRIT/HIGH/MED/LOW) · why existing protections don't stop it. If an area is clean,
say so explicitly and why.
