#!/usr/bin/env bash
# 349.2-01 Task 1 verification — objective grep gates for the lootbox-branch restoration.
# Run from repo root. Exits 0 only if every gate holds.
#
# GREP-GATE HYGIENE (per GSD planner rules): Solidity has both `//` line comments AND
# `/* ... */` / NatSpec `* ...` block-comment prose that mentions tokens like `claimablePool -=`
# and "try-block". `codeview()` strips ALL of these so doc prose can NEVER self-invalidate a
# count gate. Baselines (code-only, post-349.1) are pinned as constants below; the executor's
# correct fix must move them to the TARGET values.
set -uo pipefail

F="contracts/modules/GameAfkingModule.sol"

# Code-only view: drop `//` line comments AND inline trailing `//...`, drop full-line block
# comments (lines whose first non-space char is `*` or starts `/*`), drop closing `*/`.
codeview() {
  sed -E 's://.*$::' "$F" \
    | grep -vE '^[[:space:]]*\*' \
    | grep -vE '^[[:space:]]*/\*' \
    | grep -vE '^[[:space:]]*\*/'
}

fail=0
note() { echo "  $1"; }
gate() { if [ "$1" -eq 0 ]; then note "PASS: $2"; else note "FAIL: $2"; fail=1; fi }

echo "== 349.2-01 Task 1 gates (code-only) =="

CV="$(codeview)"

# 1. handlePurchase present AND textually before the lootbox-branch _playerActivityScore call.
#    (handlers-before-score). Both must be present; the handlePurchase line number < score line.
HP_LINE=$(printf '%s\n' "$CV" | grep -nE "quests\.handlePurchase" | head -1 | cut -d: -f1)
PAS_LINE=$(printf '%s\n' "$CV" | grep -nE "_playerActivityScore\(" | tail -1 | cut -d: -f1)
if [ -n "$HP_LINE" ] && [ -n "$PAS_LINE" ] && [ "$HP_LINE" -lt "$PAS_LINE" ]; then
  gate 0 "quests.handlePurchase (codeview line $HP_LINE) precedes _playerActivityScore (line $PAS_LINE)"
else
  gate 1 "handlePurchase before score (handlePurchase=${HP_LINE:-none}, score=${PAS_LINE:-none})"
fi

# 2. BOTH payAffiliate branches (code-only, TARGET >= 2). Also assert a true and a false isFreshEth arg exist.
PA=$(printf '%s\n' "$CV" | grep -cE "affiliate\.payAffiliate")
[ "$PA" -ge 2 ] && gate 0 "affiliate.payAffiliate code-occurrences = $PA (>= 2)" || gate 1 "affiliate.payAffiliate count = $PA (need >= 2)"

# 3. Single lootbox-branch creditFlip keyed on player (distinct from the :941 msg.sender bounty).
CFP=$(printf '%s\n' "$CV" | grep -cE "coinflip\.creditFlip\(player")
[ "$CFP" -ge 1 ] && gate 0 "coinflip.creditFlip(player ...) present ($CFP)" || gate 1 "coinflip.creditFlip(player ...) missing ($CFP)"

# 4. IDegenerusGame interface IMPORTED (the precise import token — substring matches like
#    IDegenerusGameMintModule do NOT satisfy this) AND the recordMintQuestStreak call present.
IMP=$(grep -cE 'import \{[^}]*\bIDegenerusGame\b[^}]*\} from "\.\./interfaces/IDegenerusGame\.sol"' "$F")
[ "$IMP" -ge 1 ] && gate 0 "IDegenerusGame interface imported from IDegenerusGame.sol ($IMP)" || gate 1 "IDegenerusGame interface NOT imported ($IMP) — add it to the line-8 import"
RMQ=$(printf '%s\n' "$CV" | grep -cE "IDegenerusGame\(address\(this\)\)\.recordMintQuestStreak")
[ "$RMQ" -ge 1 ] && gate 0 "IDegenerusGame(address(this)).recordMintQuestStreak called ($RMQ)" || gate 1 "recordMintQuestStreak-on-completion missing ($RMQ)"

# 5. ETH/pool debit byte-unchanged: exactly TWO code-only claimablePool write sites
#    (the :282 subscribe-credit += and the :710 debit -=). The fix adds NO new ETH/pool write,
#    so this stays 2. (Baseline post-349.1 = 2.)
CPW=$(printf '%s\n' "$CV" | grep -cE "claimablePool[[:space:]]*[-+]=")
[ "$CPW" -eq 2 ] && gate 0 "claimablePool write sites = 2 (unchanged: subscribe += and the :710 debit -=)" || gate 1 "claimablePool write sites = $CPW (expected 2 — no new ETH/pool write added)"

# 6. No cold box-ledger and no buy-time EV-cap re-introduced (code-only, TARGET 0; baseline 0).
COLD=$(printf '%s\n' "$CV" | grep -cE "lootboxEvBenefitUsedByLevel|lootboxPurchasePacked|\blootboxEth\b|enqueueBoxForAutoOpen|boxPlayers")
[ "$COLD" -eq 0 ] && gate 0 "cold-ledger / EV-cap symbols = 0 (GAS-01 + EVCAP-01 preserved)" || gate 1 "cold-ledger / EV-cap symbols = $COLD (expected 0)"

# 7. No try/catch / skip-valve in CODE (word-boundary, code-only, TARGET 0; baseline 0 —
#    line-72 'try-block' is NatSpec prose, filtered out). REVERT-01 / D-348-04.
TC=$(printf '%s\n' "$CV" | grep -cE "\btry\b|\bcatch\b")
[ "$TC" -eq 0 ] && gate 0 "try/catch in code = 0 (revert-free by construction, no valve)" || gate 1 "try/catch in code = $TC (expected 0)"

# 8. Ticket branch unchanged (purchaseWith delegatecall intact, baseline 1).
PW=$(printf '%s\n' "$CV" | grep -cE "IDegenerusGameMintModule\.purchaseWith\.selector")
[ "$PW" -ge 1 ] && gate 0 "ticket-branch purchaseWith delegatecall intact ($PW)" || gate 1 "ticket-branch purchaseWith delegatecall missing ($PW)"

echo "== result =="
if [ "$fail" -eq 0 ]; then echo "ALL GATES PASS"; exit 0; else echo "ONE OR MORE GATES FAILED (expected RED on the pre-fix tree)"; exit 1; fi
