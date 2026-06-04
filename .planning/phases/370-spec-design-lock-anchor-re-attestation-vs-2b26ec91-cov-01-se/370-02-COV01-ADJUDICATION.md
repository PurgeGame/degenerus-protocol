# 370-02 — COV-01 Second-Model `area-solvency` Re-Run + Adjudication (vs frozen `2b26ec91`)

**Requirement:** COV-01 (close the v58.0 `area-solvency` cross-model coverage gap).
**Frozen subject:** `2b26ec91` (`2b26ec91810a733e15666a4c23e8f365a4f04f51`) — the last `contracts/*.sol`
commit at v57.0 closure; the v59.0 baseline. All cites below are `<path>:<line>` per
`git show 2b26ec91:<path>`.
**Posture:** harness + paper only — ZERO `contracts/*.sol` touched. Frozen source read via
`git show 2b26ec91:<path>` / the materialized solvency pack. The external model ran read-only
(Plan Mode), prompt in a FILE.

---

## Task 1 — The run record

### Why this leg exists (the v58 coverage gap)

In v58.0 the `area-solvency` cross-model leg ran TWO models against frozen `2b26ec91`:
- **Codex** ran and produced a real result → it raised **F-03** (BAF whale-pass remainder).
  (See `.planning/audit-v52/runs/v58/xmodel/results/area-solvency.codex.txt`.)
- **Gemini REFUSED** via Plan Mode — it never read the frozen tree. The refusal text
  (`.../v58/.../area-solvency.gemini.txt`) reads: *"I am currently operating in Plan Mode … the
  execution of shell commands (including `git show` and `git grep`) is disabled by system policy
  … Because your instructions explicitly prohibit reading the working tree … I cannot perform the
  audit."* — i.e. `ask-gemini.sh` runs `gemini --approval-mode plan`, Plan Mode disables the
  `git` shell, and the prompt forbade the working tree → a refusal, not a result.

So the v58 spine got Codex + composition + Claude, but **not a second independent model that
actually read frozen source on the solvency identity**. COV-01 closes exactly that gap *before*
the milestone relies on the F-03/F-04 corrections (which fold into the Phase-371 IMPL diff).

### Smoke-test

PONG smoke-test of the council (per LAUNCH.md §0) — **both models answered PONG**
(gemini + codex, 2026-06-04). Recorded in the run manifest
`.planning/audit-v52/runs/v59/xmodel/results/area-solvency.council.json`
(`"smoke_test": "PONG OK (gemini + codex both answered PONG, 2026-06-04)"`).

### Second model + mechanism (and why)

- **Second independent model: Gemini** (`gemini-3-pro-preview`). This is a model OTHER than the
  v58 Codex leg, so it satisfies "a SECOND independent model on the spine" (Codex was the v58
  leg → excluded; `"excluded": ["codex"]` in the manifest).
- **Mechanism: frozen source MATERIALIZED into a context FILE, read in Plan Mode.** Because the
  v58 refusal cause was *Plan Mode cannot run `git`*, the robust fix is to remove the need for a
  `git` shell entirely: every in-scope solvency module at frozen `2b26ec91` was extracted via
  `git show 2b26ec91:<path>` into a single pack
  `.planning/audit-v52/runs/v59/xmodel/context/frozen-solvency-source.txt` (8,125 lines, each
  section headed `### FILE: <path> (frozen 2b26ec91)`, line numbers 1-based per file matching
  `git show` exactly). The v59 prompt (`prompts/area-solvency.v59.txt`) instructs the model to
  read THAT FILE with its file-reading tool and cite `<path>:<line>` from it — no `git` shell, no
  working-tree read. Pack contents: `DegenerusGamePayoutUtils.sol`, `DegenerusGameAdvanceModule.sol`,
  `DegenerusGameDecimatorModule.sol`, `DegenerusGameWhaleModule.sol`, `DegenerusGameJackpotModule.sol`,
  `GameAfkingModule.sol`, the `DegenerusGame.sol` ETH-ledger entrypoints (claimWinnings /
  withdrawAfkingFunding / sellFarFutureTickets / pullRedemptionReserve), and the Degenerette
  `_addClaimableEth`.
- **Prompt in a FILE, never inline** (avoids the repo's contract-commit guard hook). Pacing:
  concurrency 1, read-only/plan mode.

### Result — a genuine frozen-source read (NOT a Plan-Mode refusal)

Raw output persisted at
**`.planning/audit-v52/runs/v59/xmodel/results/area-solvency.gemini.txt`** (non-empty; `.err` empty).
It opens `FROZEN SUBJECT — commit 2b26ec91.` and returns four blocks with concrete
`file:line` cites into the frozen tree — a real read, not a refusal. Manifest:
`.../results/area-solvency.council.json`. The raw output is on disk → the pacing checkpoint is
satisfied (Task 2 adjudication below verifies it against frozen source; nothing is lost if a
usage-cap stop lands here).

**Run artifacts (under `.planning/audit-v52/runs/v59/xmodel/`):**
- `prompts/_preamble.txt`, `prompts/solvency-focus.txt`, `prompts/area-solvency.v59.txt` (self-contained)
- `context/frozen-solvency-source.txt` (the materialized frozen pack)
- `results/area-solvency.gemini.txt` (the raw second-model result), `results/area-solvency.gemini.err` (empty)
- `results/area-solvency.council.json` (the run manifest: model, mechanism, smoke-test, exclusions)

---

## Task 2 — Per-claim adjudication (Claude owns the verdict)

_Pending — written below._
