#!/bin/bash
# Payout Specification Document Verification
# Checks all 6 SPEC requirements against audit/PAYOUT-SPECIFICATION.html

FILE="audit/PAYOUT-SPECIFICATION.html"
PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "$result" -gt 0 ] 2>/dev/null || [ "$result" = "PASS" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== SPEC-01: HTML file exists at audit/PAYOUT-SPECIFICATION.html ==="
if [ -f "$FILE" ]; then
    check "File exists" 1
    check "Contains DOCTYPE" "$(grep -c '<!DOCTYPE html>' "$FILE")"
    check "Contains <style> tag" "$(grep -c '<style>' "$FILE")"
    check "No external URLs in link/script/import" "$(if grep -qE '(src|href)="https?://' "$FILE"; then echo 0; else echo 1; fi)"
else
    check "File exists" 0
fi

echo ""
echo "=== SPEC-02: All 17+ distribution systems covered ==="
# Check for all 19 PAY system references
for req in PAY-01 PAY-02 PAY-03 PAY-04 PAY-05 PAY-06 PAY-07 PAY-08 PAY-09 PAY-10 PAY-11 PAY-12 PAY-13 PAY-14 PAY-15 PAY-16 PAY-17 PAY-18 PAY-19; do
    check "$req present" "$(grep -c "$req" "$FILE")"
done
# Check for GAMEOVER systems
for req in GO-01 GO-02 GO-07 GO-08; do
    check "$req present" "$(grep -c "$req" "$FILE")"
done
# Check info table fields
check "Trigger fields present" "$(grep -c 'Trigger' "$FILE")"
check "Source Pool fields present" "$(grep -c 'Source Pool' "$FILE")"
check "Claim Mechanism fields present" "$(grep -c 'Claim' "$FILE")"

echo ""
echo "=== SPEC-03: Flow diagrams for every distribution system ==="
SVG_COUNT=$(grep -c '<svg' "$FILE")
check "SVG count >= 15 (expect ~18-22 diagrams)" "$([ "$SVG_COUNT" -ge 15 ] && echo 1 || echo 0)"
check "All SVGs have viewBox" "$(if grep '<svg' "$FILE" | grep -v 'viewBox' | grep -q '<svg'; then echo 0; else echo 1; fi)"
echo "  INFO: Found $SVG_COUNT SVG elements"

echo ""
echo "=== SPEC-04: Edge cases documented per system ==="
EDGE_COUNT=$(grep -c 'edge-case\|Edge Case' "$FILE")
check "Edge case sections present (>= 10)" "$([ "$EDGE_COUNT" -ge 10 ] && echo 1 || echo 0)"
echo "  INFO: Found $EDGE_COUNT edge case references"

echo ""
echo "=== SPEC-05: File:line references ==="
# Check for contract file references with line numbers
check "JackpotModule.sol references" "$(grep -c 'JackpotModule.sol:[0-9]' "$FILE")"
check "DecimatorModule.sol references" "$(grep -c 'DecimatorModule.sol:[0-9]' "$FILE")"
check "GameOverModule.sol references" "$(grep -c 'GameOverModule.sol:[0-9]' "$FILE")"
check "EndgameModule.sol references" "$(grep -c 'EndgameModule.sol:[0-9]' "$FILE")"
check "BurnieCoinflip.sol references" "$(grep -c 'BurnieCoinflip.sol:[0-9]' "$FILE")"
check "PayoutUtils.sol references" "$(grep -c 'PayoutUtils.sol:[0-9]' "$FILE")"
check "StakedDegenerusStonk.sol references" "$(grep -c 'StakedDegenerusStonk.sol:[0-9]' "$FILE")"
check "Commit hash 3fa32f51 present" "$(grep -c '3fa32f51' "$FILE")"

echo ""
echo "=== SPEC-06: Formulas use exact variable names ==="
for var in futurePrizePool currentPrizePool claimablePool baseFuturePool futurePoolLocal yieldAccumulator ethDaySlice JACKPOT_SHARES_PACKED bafPoolWei decPoolWei totalMoney supplyBefore bountyPool; do
    check "Variable $var present" "$(grep -c "$var" "$FILE")"
done

echo ""
echo "=== SUMMARY ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL checks"

if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: ALL CHECKS PASS"
    exit 0
else
    echo "RESULT: $FAIL CHECKS FAILED"
    exit 1
fi
