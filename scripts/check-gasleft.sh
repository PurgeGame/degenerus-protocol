#!/usr/bin/env bash
# Determinism gate for the ticket drains. The work a crank call performs and every trait it
# assigns must be a pure function of chain state (queue contents, owed balances, the level's
# VRF word, the write budget) — never of the caller or the transaction. Two checks:
#   1. no game contract reads gasleft() (a keeper must not decide how many tickets materialize);
#   2. no drain function reads msg.sender, tx.*, block.*, blockhash or gasleft.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
hits=$(grep -rn "gasleft()" contracts --include='*.sol' | grep -v "^contracts/mocks/\|^contracts/test/" || true)
if [ -n "$hits" ]; then
  echo -e "\033[0;31mFAIL\033[0m gasleft() read in a game contract (crank work must not depend on caller gas):"
  echo "$hits"; fail=1
fi
# Drain functions: extract each body by brace depth and scan it.
DRAIN_FNS="processTicketBatch processFutureTicketBatch _processOneTicketEntry _raritySymbolBatch _drainSeatedSurvivors _drainRounds drainRounds _fillSeats _seatEntry _runRound _processFoilDrain _resolveFoilBuyer _bucketAppendRun _bucketAppendLanes _resolveZeroOwedRemainder _rollRemainder"
for f in contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameFoilPackModule.sol contracts/storage/DegenerusGameStorage.sol; do
  for fn in $DRAIN_FNS; do
    body=$(awk -v fn="$fn" '
      $0 ~ ("function " fn "\\(") { infn=1 }
      infn { print; n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m; if (started==0 && n>0) started=1; if (started && depth<=0) { exit } }
    ' "$f")
    [ -z "$body" ] && continue
    bad=$(echo "$body" | grep -n "msg\.sender\|tx\.\(origin\|gasprice\)\|block\.\(timestamp\|number\|prevrandao\|coinbase\|basefee\)\|blockhash(\|gasleft()" || true)
    if [ -n "$bad" ]; then
      echo -e "\033[0;31mFAIL\033[0m caller/transaction-dependent read inside drain function $fn ($f):"
      echo "$bad"; fail=1
    fi
  done
done
[ $fail -eq 0 ] && echo -e "\033[0;32mPASS\033[0m drains read no caller, transaction, block or gas state; crank work is a pure function of state"
exit $fail
