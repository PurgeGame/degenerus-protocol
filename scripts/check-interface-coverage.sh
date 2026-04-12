#!/usr/bin/env bash
# Interface coverage check.
#
# For every function declared in contracts/interfaces/, verifies a matching
# implementation (by 4-byte selector) exists on the target contract. Catches
# the class of bug where a function is declared in an interface but never
# implemented, causing silent staticcall reverts at the call site.
#
# Prior incident: mintPackedFor was declared in IDegenerusGame but never
# implemented on DegenerusGame. Calls from DegenerusQuests._isLevelQuestEligible
# reverted with empty revertdata, surfacing as generic E() on lootbox purchases
# that tipped a level quest to completion.
#
# Usage: scripts/check-interface-coverage.sh
# Exit code: 0 if all interface functions are implemented, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

# Interface -> implementation mapping.
# Skipped (external protocols): IStETH (Lido), IVRFCoordinator (Chainlink).
MAPPINGS=(
  "contracts/interfaces/IBurnieCoinflip.sol:IBurnieCoinflip|contracts/BurnieCoinflip.sol:BurnieCoinflip"
  "contracts/interfaces/IDegenerusAffiliate.sol:IDegenerusAffiliate|contracts/DegenerusAffiliate.sol:DegenerusAffiliate"
  "contracts/interfaces/IDegenerusCoin.sol:IDegenerusCoin|contracts/BurnieCoin.sol:BurnieCoin"
  "contracts/interfaces/IDegenerusGame.sol:IDegenerusGame|contracts/DegenerusGame.sol:DegenerusGame"
  "contracts/interfaces/IDegenerusJackpots.sol:IDegenerusJackpots|contracts/DegenerusJackpots.sol:DegenerusJackpots"
  "contracts/interfaces/IDegenerusQuests.sol:IDegenerusQuests|contracts/DegenerusQuests.sol:DegenerusQuests"
  "contracts/interfaces/IStakedDegenerusStonk.sol:IStakedDegenerusStonk|contracts/StakedDegenerusStonk.sol:StakedDegenerusStonk"
  "contracts/interfaces/IVaultCoin.sol:IVaultCoin|contracts/BurnieCoin.sol:BurnieCoin"
  # IDegenerusGameModules.sol contains 9 module interfaces. Each module is deployed
  # as a separate contract that DegenerusGame delegatecalls into. Check the module
  # contract itself (code runs from the module, storage lives on DegenerusGame via
  # shared DegenerusGameStorage inheritance).
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameAdvanceModule|contracts/modules/DegenerusGameAdvanceModule.sol:DegenerusGameAdvanceModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameGameOverModule|contracts/modules/DegenerusGameGameOverModule.sol:DegenerusGameGameOverModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameJackpotModule|contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameDecimatorModule|contracts/modules/DegenerusGameDecimatorModule.sol:DegenerusGameDecimatorModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameWhaleModule|contracts/modules/DegenerusGameWhaleModule.sol:DegenerusGameWhaleModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameMintModule|contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameLootboxModule|contracts/modules/DegenerusGameLootboxModule.sol:DegenerusGameLootboxModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameBoonModule|contracts/modules/DegenerusGameBoonModule.sol:DegenerusGameBoonModule"
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameDegeneretteModule|contracts/modules/DegenerusGameDegeneretteModule.sol:DegenerusGameDegeneretteModule"
)

# Extract "<selector>\t<signature>" rows from `forge inspect ... methods` output.
get_methods() {
  local target="$1"
  forge inspect "$target" methods 2>/dev/null \
    | awk -F'|' '/^\|/ && $2 ~ /\(/ {
        gsub(/^[ \t]+|[ \t]+$/, "", $2);
        gsub(/^[ \t]+|[ \t]+$/, "", $3);
        if ($3 ~ /^[0-9a-fA-F]{8}$/) print $3 "\t" $2;
      }'
}

# Check if an interface function has any call site in contracts/ (excluding
# its own interface declaration). Matches both call patterns used by the codebase:
#   1. abi.encodeWithSelector(IFace.fn.selector, ...)      (delegatecall pattern)
#   2. IFace(addr).fn(...)                                  (direct external call)
# Returns 0 (true/found) if the function is referenced, 1 otherwise.
has_call_site() {
  local iface_name="$1"
  local fn_name="$2"
  # Selector pattern: IDegenerusGameFoo.fnName.selector
  if grep -rqE "${iface_name}\.${fn_name}\.selector\b" \
       --include='*.sol' \
       --exclude-dir=interfaces \
       --exclude-dir=mocks \
       contracts/ 2>/dev/null; then
    return 0
  fi
  # Direct call pattern: IFace(...).fnName(
  if grep -rqE "${iface_name}\s*\([^)]*\)\s*\.\s*${fn_name}\s*\(" \
       --include='*.sol' \
       --exclude-dir=interfaces \
       --exclude-dir=mocks \
       contracts/ 2>/dev/null; then
    return 0
  fi
  return 1
}

missing_total=0
dead_total=0
warn_total=0

printf "Interface coverage check\n"
printf "========================\n\n"

for mapping in "${MAPPINGS[@]}"; do
  iface="${mapping%|*}"
  impl="${mapping#*|}"
  iface_name="${iface#*:}"
  impl_name="${impl#*:}"

  iface_methods=$(get_methods "$iface")
  impl_methods=$(get_methods "$impl")

  if [[ -z "$iface_methods" ]]; then
    printf "%bWARN%b %-45s no methods extracted from interface\n" "$YELLOW" "$NC" "$iface_name"
    warn_total=$((warn_total + 1))
    continue
  fi

  if [[ -z "$impl_methods" ]]; then
    printf "%bWARN%b %-45s no methods extracted from implementation %s\n" "$YELLOW" "$NC" "$iface_name" "$impl_name"
    warn_total=$((warn_total + 1))
    continue
  fi

  impl_selectors=$(printf '%s\n' "$impl_methods" | awk '{print $1}' | sort -u)
  missing=$(printf '%s\n' "$iface_methods" \
    | awk -v sels="$impl_selectors" '
        BEGIN { n = split(sels, arr, "\n"); for (i = 1; i <= n; i++) have[arr[i]] = 1 }
        { if (!have[$1]) print $0 }
      ')

  count=$(printf '%s\n' "$iface_methods" | grep -c . || true)
  if [[ -z "$missing" ]]; then
    printf "%bOK%b   %-45s -> %-25s (%d fns covered)\n" "$GREEN" "$NC" "$iface_name" "$impl_name" "$count"
    continue
  fi

  # Classify each missing function: real bug (has call site) vs dead declaration (no call site).
  real_bugs=""
  dead_decls=""
  while IFS=$'\t' read -r sel sig; do
    [[ -z "$sel" ]] && continue
    fn_name="${sig%%(*}"
    if has_call_site "$iface_name" "$fn_name"; then
      real_bugs+="${sel}	${sig}"$'\n'
    else
      dead_decls+="${sel}	${sig}"$'\n'
    fi
  done <<< "$missing"

  real_count=$(printf '%s' "$real_bugs" | grep -c . || true)
  dead_count=$(printf '%s' "$dead_decls" | grep -c . || true)
  missing_total=$((missing_total + real_count))
  dead_total=$((dead_total + dead_count))

  if [[ $real_count -gt 0 ]]; then
    printf "%bMISS%b %-45s -> %-25s (%d real, %d dead of %d)\n" \
      "$RED" "$NC" "$iface_name" "$impl_name" "$real_count" "$dead_count" "$count"
    printf '%s' "$real_bugs" | awk -F'\t' 'NF>1 { printf "       %bBUG%b   %s  %s  (has call site in contracts/)\n", "\033[0;31m", "\033[0m", $1, $2 }'
    printf '%s' "$dead_decls" | awk -F'\t' 'NF>1 { printf "       %bDEAD%b  %s  %s  (no call site — safe to delete)\n", "\033[1;33m", "\033[0m", $1, $2 }'
  else
    printf "%bDEAD%b %-45s -> %-25s (%d dead declarations, no call site)\n" \
      "$YELLOW" "$NC" "$iface_name" "$impl_name" "$dead_count"
    printf '%s' "$dead_decls" | awk -F'\t' 'NF>1 { printf "       %s  %s\n", $1, $2 }'
  fi
done

echo
if [[ $missing_total -eq 0 && $warn_total -eq 0 && $dead_total -eq 0 ]]; then
  printf "%bPASS%b all interface functions have matching implementations\n" "$GREEN" "$NC"
  exit 0
fi

if [[ $missing_total -gt 0 ]]; then
  printf "%bFAIL%b %d unimplemented interface function(s) with active call sites — will revert at runtime\n" "$RED" "$NC" "$missing_total"
fi
if [[ $dead_total -gt 0 ]]; then
  printf "%bWARN%b %d dead interface declaration(s) — no call site, safe to remove\n" "$YELLOW" "$NC" "$dead_total"
fi
if [[ $warn_total -gt 0 ]]; then
  printf "%bWARN%b %d interface(s) could not be inspected\n" "$YELLOW" "$NC" "$warn_total"
fi

# Fail only on real bugs or inspection failures. Dead declarations are a warning.
if [[ $missing_total -gt 0 || $warn_total -gt 0 ]]; then
  exit 1
fi
exit 0
