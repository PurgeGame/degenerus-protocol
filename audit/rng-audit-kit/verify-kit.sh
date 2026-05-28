#!/usr/bin/env bash
# ==============================================================================
# verify-kit.sh — the TERMINAL VALIDATION GATE for the Degenerus RNG-Audit Kit.
#
# Runs the RESEARCH section-8 lint set as concrete, machine-decidable checks and
# proves the kit's correctness WITHOUT ever running it through an external model.
# It re-attests all four RNGAUDIT requirements structurally: every cited anchor
# resolves at HEAD, the freeze-invariant target is verbatim, the kit is
# self-contained + answer-key-free, and the rounds + context pack + packaging are
# all present.
#
# USAGE:   bash audit/rng-audit-kit/verify-kit.sh        (run from the repo root)
# EXIT:    0 if ALL checks pass; 1 if ANY check fails.
# OUTPUT:  one "PASS — <check>" or "FAIL — <check>" line per check, then a summary.
#
# SCOPING DISCIPLINE (load-bearing — see 337-04-PLAN <critical_scoping_rule>):
#   The self-containment and no-answer-key checks would self-match this script's
#   own source + the 337-KIT-VALIDATION.md ledger (both contain the forbidden
#   literals AS grep patterns / recorded commands). Those two checks therefore
#   scope to the SHIPPED KIT artifacts only — RNG-AUDIT-KIT.md (the paste-into-
#   model artifact) and CHUNK-MANIFEST.md (the operator manual) — NOT the whole
#   directory. The anchor-resolution + stale-marker checks legitimately scan the
#   kit docs (kit + attestation) and are scoped to that explicit file list.
#
# This script is a VALIDATION ARTIFACT, not a contract. It reads contracts/ at
# HEAD (sed/wc) but MUTATES nothing. It uses only git/grep/sed/wc — no installs.
# ==============================================================================

set -u  # treat unset variables as errors; do NOT set -e (we want all checks to run)

# --- Resolve paths relative to the repo root regardless of CWD ----------------
KIT_DIR="audit/rng-audit-kit"
KIT="$KIT_DIR/RNG-AUDIT-KIT.md"               # the paste-into-model artifact
MANIFEST="$KIT_DIR/CHUNK-MANIFEST.md"         # the operator chunking manual
ATTEST="$KIT_DIR/337-ANCHOR-ATTESTATION.md"   # the internal anchor attestation

# The SHIPPED kit docs the answer-key/self-containment checks scope to.
SHIPPED=("$KIT" "$MANIFEST")
# The docs the anchor-resolution + stale-marker checks scan (kit + attestation).
ANCHOR_DOCS=("$KIT" "$ATTEST")

FAILURES=0
PASSES=0

pass() { echo "PASS — $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL — $1"; FAILURES=$((FAILURES + 1)); }

# Guard: the kit files must exist before any check runs.
for f in "$KIT" "$MANIFEST" "$ATTEST"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: required kit file missing: $f (run from the repo root)" >&2
    exit 1
  fi
done

echo "=================================================================="
echo "Degenerus RNG-Audit Kit — verify-kit.sh"
echo "HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "=================================================================="

# ------------------------------------------------------------------------------
# CHECK 1 — ANCHOR-RESOLUTION
#   Extract every `contracts/...sol:NNN` token from the kit + the attestation and
#   assert the file exists and `sed -n 'NNNp'` returns a NON-EMPTY line (in-range
#   at HEAD). Tokens are pulled with grep -oE so a markdown header/comment `#`
#   cannot self-invalidate the count. Also assert the stale pre-v50 markers
#   (:716, 1250-1260) are absent.
# ------------------------------------------------------------------------------
CHECK="1. anchor-resolution (every cited contracts/...:NNN resolves in-range at HEAD)"
UNRESOLVED=""
TOKEN_COUNT=0
# -h suppresses filenames; -oE pulls bare tokens out of prose/tables/code-spans.
while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  TOKEN_COUNT=$((TOKEN_COUNT + 1))
  file="${tok%:*}"
  line="${tok##*:}"
  if [ ! -f "$file" ]; then
    UNRESOLVED="$UNRESOLVED\n    $tok  (file not found)"
    continue
  fi
  # sed -n 'Np' returns the Nth line; empty => out of range at HEAD.
  content="$(sed -n "${line}p" "$file")"
  if [ -z "$content" ]; then
    UNRESOLVED="$UNRESOLVED\n    $tok  (line out of range / blank at HEAD)"
  fi
done < <(grep -hoE 'contracts/[A-Za-z0-9_/]+\.sol:[0-9]+' "${ANCHOR_DOCS[@]}" | sort -u)

if [ -n "$UNRESOLVED" ]; then
  fail "$CHECK"
  echo -e "    UNRESOLVED tokens:$UNRESOLVED"
else
  pass "$CHECK ($TOKEN_COUNT unique tokens, all resolve)"
fi

# 1b — stale pre-v50 markers absent in the kit docs.
CHECK1B="1b. stale pre-v50 markers absent (':716' / '1250-1260' == 0 in kit docs)"
STALE=$(grep -REho ':716|1250-1260' "${ANCHOR_DOCS[@]}" | wc -l | tr -d ' ')
if [ "$STALE" -eq 0 ]; then
  pass "$CHECK1B"
else
  fail "$CHECK1B (found $STALE)"
  grep -REn ':716|1250-1260' "${ANCHOR_DOCS[@]}"
fi

# ------------------------------------------------------------------------------
# CHECK 2 — FREEZE-INVARIANT VERBATIM
#   The canonical '+' form must appear exactly once; the 'and' variant must be
#   absent. grep -F = fixed string (the canonical sentence has backticks + '+').
# ------------------------------------------------------------------------------
CHECK="2. freeze-invariant verbatim ('+' form == 1, 'and' form == 0)"
CANON='while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown'
PLUS_HITS=$(grep -cF "$CANON" "$KIT")
AND_HITS=$(grep -c 'VRF word and its deterministic derivations' "$KIT")
if [ "$PLUS_HITS" -eq 1 ] && [ "$AND_HITS" -eq 0 ]; then
  pass "$CHECK ('+' form: $PLUS_HITS, 'and' form: $AND_HITS)"
else
  fail "$CHECK ('+' form: $PLUS_HITS [want 1], 'and' form: $AND_HITS [want 0])"
fi

# ------------------------------------------------------------------------------
# CHECK 3 — SELF-CONTAINMENT (scoped to SHIPPED kit docs only)
#   The kit must carry zero pointer to any internal findings/catalog document.
#   Scoped to RNG-AUDIT-KIT.md + CHUNK-MANIFEST.md so this script's own source +
#   the ledger (which use these strings AS patterns) cannot cause a self-FAIL.
# ------------------------------------------------------------------------------
CHECK="3. self-containment (no FINDINGS-v*/audit-FINDINGS/RNGLOCK-CATALOG in shipped docs)"
SC_HITS=$(grep -riE 'FINDINGS-v[0-9]|audit/FINDINGS|RNGLOCK-CATALOG' "${SHIPPED[@]}" | wc -l | tr -d ' ')
if [ "$SC_HITS" -eq 0 ]; then
  pass "$CHECK"
else
  fail "$CHECK (found $SC_HITS)"
  grep -rinE 'FINDINGS-v[0-9]|audit/FINDINGS|RNGLOCK-CATALOG' "${SHIPPED[@]}"
fi

# ------------------------------------------------------------------------------
# CHECK 4 — NO-ANSWER-KEY (scoped to SHIPPED kit docs only)
#   The kit must leak no freeze verdict / reassurance. Two parts:
#     4a — genuine verdict/reassurance phrasings must be ZERO. These are the
#          conclusion-bearing strings (a leaked per-slot freeze verdict or a
#          "we found / no escape / safe by construction / invariant holds").
#     4b — the R2 OUTPUT-CATEGORY labels ('proven-non-participating' /
#          'reverts-if-written-during-lock') are the allowed METHODOLOGY phrasing
#          (RESEARCH section-8 allow-list). They are printed for hand-review and
#          asserted to occur ONLY in the R2 category-definition bullets (lines
#          beginning '- **<label>**' under "### R2"), i.e. as definitions, never
#          as a verdict applied to a named slot. If they appear anywhere else,
#          this FAILS so a human looks.
#   Scoped to the shipped docs so the ledger's recorded patterns don't self-match.
# ------------------------------------------------------------------------------
CHECK="4a. no-answer-key — genuine verdict/reassurance phrasings == 0"
# 'we concluded' is deliberately NOT matched (it appears only negated: "no
# statement of what we concluded"); the alternation below catches only true leaks.
VERDICT_RE='is frozen because|we (found|verified|confirmed)|no (writer )?escape|safe by construction|the invariant holds'
AK_HITS=$(grep -riE "$VERDICT_RE" "${SHIPPED[@]}" | wc -l | tr -d ' ')
if [ "$AK_HITS" -eq 0 ]; then
  pass "$CHECK"
else
  fail "$CHECK (found $AK_HITS — leaked verdict/reassurance)"
  grep -rinE "$VERDICT_RE" "${SHIPPED[@]}"
fi

CHECK="4b. no-answer-key — R2 category labels are methodology-only (hand-review)"
# Pull every hit of the two category-label tokens with line numbers.
CAT_RE='proven-non-participating|reverts-if-written-during-lock'
CAT_LINES=$(grep -rinE "$CAT_RE" "${SHIPPED[@]}")
# Allowed form: an R2 output-category DEFINITION bullet, i.e. the line is a
# markdown bullet that bolds the label: '- **<label>** — ...'. Any hit NOT in
# that definitional form is a potential leaked verdict -> FAIL for hand-review.
BAD_CAT=$(grep -rinE "$CAT_RE" "${SHIPPED[@]}" | grep -vE '^[^:]+:[0-9]+:- \*\*(proven-non-participating|reverts-if-written-during-lock)\*\* —')
if [ -z "$BAD_CAT" ]; then
  pass "$CHECK"
  echo "    HAND-REVIEW (allowed methodology output-category definitions only):"
  echo "$CAT_LINES" | sed 's/^/      /'
else
  fail "$CHECK — a category label appears outside an R2 definition bullet:"
  echo "$BAD_CAT" | sed 's/^/      /'
fi

# ------------------------------------------------------------------------------
# CHECK 5 — EXEMPT SET
#   All four exempt entries must be named in the kit (>=4 hits over the 4 names).
# ------------------------------------------------------------------------------
CHECK="5. exempt set (advanceGame/rawFulfillRandomWords/retryLootboxRng/rngGate >= 4)"
EXEMPT_HITS=$(grep -cE 'advanceGame|rawFulfillRandomWords|retryLootboxRng|rngGate' "$KIT")
# Confirm each of the four names is individually present (not just 4 hits of one).
MISSING_EXEMPT=""
for name in advanceGame rawFulfillRandomWords retryLootboxRng rngGate; do
  grep -q "$name" "$KIT" || MISSING_EXEMPT="$MISSING_EXEMPT $name"
done
if [ "$EXEMPT_HITS" -ge 4 ] && [ -z "$MISSING_EXEMPT" ]; then
  pass "$CHECK ($EXEMPT_HITS hits; all four names present)"
else
  fail "$CHECK ($EXEMPT_HITS hits; missing:${MISSING_EXEMPT:- none})"
fi

# ------------------------------------------------------------------------------
# CHECK 6 — R1->R4
#   The four round headings must all be present.
# ------------------------------------------------------------------------------
CHECK="6. R1->R4 rounds present (grep -cE '^### R[1-4] ' == 4)"
ROUND_HITS=$(grep -cE '^### R[1-4] ' "$KIT")
if [ "$ROUND_HITS" -eq 4 ]; then
  pass "$CHECK ($ROUND_HITS)"
else
  fail "$CHECK ($ROUND_HITS [want 4])"
fi

# ------------------------------------------------------------------------------
# CHECK 7 — CONTEXT PACK
#   The five cold-start context-pack section headings (4a-4e) must all be present.
# ------------------------------------------------------------------------------
CHECK="7. context pack 4a-4e present (grep -cE '^## Context Pack 4[a-e]' == 5)"
CP_HITS=$(grep -cE '^## Context Pack 4[a-e]' "$KIT")
if [ "$CP_HITS" -eq 5 ]; then
  pass "$CHECK ($CP_HITS)"
else
  fail "$CHECK ($CP_HITS [want 5])"
fi

# ------------------------------------------------------------------------------
# CHECK 8 — MANIFEST SUMS
#   Every contract file in the CHUNK-MANIFEST.md Corpus Inventory must have its
#   recorded Lines (wc -l) AND Chars (wc -c) match HEAD. The inventory rows are
#       | `contracts/....sol` | <lines> | <chars> | ~<tokens> | <group> |
#   (leading '|' => awk -F'|' fields: $2=path $3=Lines $4=Chars $5=~tokens).
#   NOTE: the three per-GROUP tables later in the manifest repeat each path in a
#   2-column `| path | ~tokens |` shape — those rows have an EMPTY Chars field
#   ($4). We therefore only parse rows where BOTH the Lines and Chars cells are
#   non-empty integers, which uniquely selects the inventory rows and skips the
#   group tables (preventing a false parse). Each file is checked once.
# ------------------------------------------------------------------------------
CHECK="8. manifest sums (each recorded wc -l / wc -c matches HEAD)"
MISMATCH=""
ROWS_CHECKED=0
while IFS='|' read -r _lead c_path c_lines c_chars _rest; do
  # Trim surrounding whitespace + the backticks from the path cell.
  file=$(echo "$c_path" | sed -E 's/^[[:space:]]*`?//; s/`?[[:space:]]*$//')
  case "$file" in contracts/*.sol) : ;; *) continue ;; esac
  rec_lines=$(echo "$c_lines" | tr -dc '0-9')
  rec_chars=$(echo "$c_chars" | tr -dc '0-9')
  # Inventory rows have BOTH cells numeric; group-table rows leave Chars empty.
  [ -z "$rec_lines" ] && continue
  [ -z "$rec_chars" ] && continue
  ROWS_CHECKED=$((ROWS_CHECKED + 1))
  if [ ! -f "$file" ]; then
    MISMATCH="$MISMATCH\n    $file (file not found)"
    continue
  fi
  act_lines=$(wc -l < "$file" | tr -d ' ')
  act_chars=$(wc -c < "$file" | tr -d ' ')
  if [ "$rec_lines" != "$act_lines" ] || [ "$rec_chars" != "$act_chars" ]; then
    MISMATCH="$MISMATCH\n    $file  recorded(L=$rec_lines C=$rec_chars) vs HEAD(L=$act_lines C=$act_chars)"
  fi
done < "$MANIFEST"

if [ -n "$MISMATCH" ]; then
  fail "$CHECK"
  echo -e "    MISMATCHES:$MISMATCH"
elif [ "$ROWS_CHECKED" -lt 1 ]; then
  fail "$CHECK (no inventory rows parsed — manifest format changed?)"
else
  pass "$CHECK ($ROWS_CHECKED files; every recorded wc -l / wc -c matches HEAD)"
fi

# ------------------------------------------------------------------------------
# CHECK 9 — MODEL-AGNOSTIC + PACKAGE-ONLY
#   The kit must name both models and carry the package-only framing.
# ------------------------------------------------------------------------------
CHECK="9. model-agnostic + package-only (Gemini, ChatGPT, PACKAGE-ONLY, future cycle)"
G_HITS=$(grep -ci 'Gemini' "$KIT")
C_HITS=$(grep -ci 'ChatGPT' "$KIT")
P_HITS=$(grep -c 'PACKAGE-ONLY' "$KIT")
F_HITS=$(grep -ci 'future cycle' "$KIT")
if [ "$G_HITS" -ge 1 ] && [ "$C_HITS" -ge 1 ] && [ "$P_HITS" -ge 1 ] && [ "$F_HITS" -ge 1 ]; then
  pass "$CHECK (Gemini:$G_HITS ChatGPT:$C_HITS PACKAGE-ONLY:$P_HITS 'future cycle':$F_HITS)"
else
  fail "$CHECK (Gemini:$G_HITS ChatGPT:$C_HITS PACKAGE-ONLY:$P_HITS 'future cycle':$F_HITS — each must be >=1)"
fi

# ------------------------------------------------------------------------------
# SUMMARY + aggregate exit code
# ------------------------------------------------------------------------------
echo "=================================================================="
echo "SUMMARY: $PASSES passed, $FAILURES failed"
if [ "$FAILURES" -eq 0 ]; then
  echo "GATE: PASS — the kit is grep-validated; RNGAUDIT-01..04 structurally re-attested."
  echo "=================================================================="
  exit 0
else
  echo "GATE: FAIL — $FAILURES check(s) failed. Fix the offending kit file and re-run."
  echo "=================================================================="
  exit 1
fi
