# Technology Stack: Value-Transfer Audit + Payout Specification

**Project:** Degenerus Protocol -- Full Contract Audit + Payout Specification (v3.0)
**Researched:** 2026-03-17
**Confidence:** HIGH (tools verified against installed versions and official docs)

---

## Scope Boundary

This stack covers ONLY what is needed for v3.0: comprehensive audit of all value-transfer paths (ETH/stETH/BURNIE/DGNRS/WWXRP) and generation of a Payout Specification HTML document with flow diagrams.

**Already in place (DO NOT re-add):**
- Hardhat 2.28.3 + @nomicfoundation/hardhat-toolbox 6.1.0
- Foundry (forge) with fuzz + invariant testing configured
- solidity-coverage 0.8.17
- Slither 0.11.5 (installed globally, npm script configured)
- Halmos 0.3.3 (deferred to v3.1 per PROJECT.md)
- OpenZeppelin Contracts 5.4.0

**This research adds:** targeted Slither invocations for value-transfer analysis, diagram generation tooling, and HTML document build pipeline.

---

## Recommended Stack

### Static Analysis -- Slither (Already Installed)

| Tool | Version | Purpose | Why |
|------|---------|---------|-----|
| slither-analyzer | 0.11.5 | Static analysis of all value-transfer paths | Already installed; 90+ detectors including all reentrancy, arbitrary-send, unchecked-transfer classes; supports Solidity >= 0.4 |

Slither is the only static analysis tool needed. Mythril is NOT recommended -- it duplicates Slither's coverage with significantly longer execution times (symbolic execution vs. static analysis), and its Solidity 0.8.34 support is less reliable than Slither's.

#### Value-Transfer Detector Suite

Run against the full contract set (not just DegenerusAdmin as in v2.1):

```bash
# Full value-transfer audit: all contracts, all relevant detectors
slither . --filter-paths 'node_modules|mocks' \
  --detect reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events,\
arbitrary-send-eth,arbitrary-send-erc20,arbitrary-send-erc20-permit,\
unchecked-transfer,unchecked-lowlevel,unchecked-send,\
controlled-delegatecall,delegatecall-loop,calls-loop,\
erc20-interface,locked-ether
```

#### Value-Transfer Printer Suite

These printers extract structural information for manual audit cross-referencing:

| Printer | Purpose | Output |
|---------|---------|--------|
| `call-graph` | Full cross-contract call graph -- reveals every path from external entry to value transfer | DOT file (render with Graphviz or online viewer) |
| `function-summary` | State variable reads/writes per function -- identifies which functions touch pool balances | Text table |
| `vars-and-auth` | Authorization + state writes -- maps who can call what and what storage changes | Text table |
| `data-dependency` | Data flow from inputs to value-bearing operations -- reveals if user input reaches transfer amounts | Text table |
| `human-summary` | Quick contract-level overview (ERCs implemented, assembly usage, external calls) | Text |

```bash
# Generate all value-transfer-relevant printer outputs
slither . --filter-paths 'node_modules|mocks' \
  --print call-graph,function-summary,vars-and-auth,data-dependency,human-summary

# Call graph outputs DOT files -- convert to SVG for the payout spec
dot -Tsvg contracts.dot -o audit/payout-spec/call-graph.svg
```

#### Per-Contract Targeted Analysis

For the highest-risk contracts, run focused analysis:

| Contract | Why Critical | Focused Command |
|----------|-------------|-----------------|
| DegenerusGame.sol | Central hub; delegatecalls to all modules; `claimWinnings()` sends ETH | `slither contracts/DegenerusGame.sol --print function-summary,vars-and-auth` |
| DegenerusGameGameOverModule.sol | Terminal distribution, final sweep, stETH transfers, sDGNRS deposits | `slither contracts/modules/DegenerusGameGameOverModule.sol --print function-summary,data-dependency` |
| DegenerusGameDecimatorModule.sol | Decimator payout, pool draws | Same as above |
| DegenerusVault.sol | stETH yield distribution, ETH deposits/withdrawals | Same as above |
| BurnieCoinflip.sol | ETH wagers, payout calculation, bounty claims | Same as above |
| BurnieCoin.sol | BURNIE mint/burn, token transfers | Same as above |
| DegenerusStonk.sol / StakedDegenerusStonk.sol | DGNRS/sDGNRS transfers, wrap/unwrap, reserve accounting | Same as above |
| DegenerusAffiliate.sol | Affiliate payout distribution | Same as above |
| DegenerusJackpots.sol | Jackpot pool management, draw payouts | Same as above |

### Diagram Generation -- Mermaid.js

| Tool | Version | Purpose | Why |
|------|---------|---------|-----|
| @mermaid-js/mermaid-cli (mmdc) | latest (via npx) | Render Mermaid diagram source to SVG/PNG for HTML embedding | Text-based diagram source lives in version control; renders to SVG for the payout spec HTML; no binary diagram files to maintain |

**Why Mermaid over alternatives:**

| Tool | Verdict | Reason |
|------|---------|--------|
| Mermaid | **USE** | Text-based (diffable, auditable), renders client-side in HTML, CLI for pre-rendering, supports flowcharts + sequence diagrams + sankey |
| sol2uml | Skip | Generates UML class diagrams and storage layouts -- useful for structure, not money flows; does not model value-transfer paths |
| Surya | Skip | Generates call graphs and function traces -- overlaps with Slither's call-graph printer; does not model economic flows |
| Solgraph | Skip | Unmaintained; last meaningful update years ago; Slither call-graph supersedes it |
| Graphviz (dot) | **Supporting** | Only for rendering Slither's DOT output to SVG; not for authoring new diagrams |

#### Mermaid Diagram Types for Payout Spec

| Diagram Type | Mermaid Syntax | Use Case |
|-------------|----------------|----------|
| `flowchart TD` | Top-down flow | Individual payout path (entry -> pool split -> distribution -> claim) |
| `flowchart LR` | Left-right flow | Pool accounting (ETH in -> BPS split -> pool balances) |
| `sequenceDiagram` | Actor interactions | Multi-contract payout sequences (Game -> Module -> Vault -> Player) |
| `graph` | Generic directed graph | GAMEOVER terminal flow (the most complex single path) |

#### Rendering Pipeline

```bash
# Render a single diagram
npx -y @mermaid-js/mermaid-cli mmdc -i diagram.mmd -o diagram.svg -t neutral

# Render all diagrams in a directory
for f in audit/payout-spec/diagrams/*.mmd; do
  npx -y @mermaid-js/mermaid-cli mmdc -i "$f" -o "${f%.mmd}.svg" -t neutral
done
```

The `npx -y` approach avoids adding mermaid-cli to package.json -- it is a documentation build tool, not a runtime dependency.

### HTML Document Generation

| Tool | Version | Purpose | Why |
|------|---------|---------|-----|
| Hand-authored HTML + inline CSS | N/A | Self-contained payout specification document | Single-file deliverable; no build dependencies; embeds SVG diagrams inline; opens in any browser |

**Why NOT Pandoc/markdown-it/marked.js:**

The payout specification is a formal audit deliverable, not developer documentation. It needs:
1. Precise control over layout (side-by-side code references + diagrams)
2. Inline SVG embedding (not external image references)
3. Zero runtime dependencies (no CDN links, no JavaScript required for viewing)
4. Consistent rendering across all browsers/PDF exporters

A hand-authored HTML file with inline `<style>` achieves all of this. Markdown-to-HTML converters add complexity without benefit for a single document.

#### HTML Document Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Degenerus Protocol -- Payout Specification</title>
  <style>
    /* Self-contained CSS -- no external dependencies */
    /* Monospace for code refs, clean sans-serif for prose */
    /* Print-friendly styles for PDF export */
  </style>
</head>
<body>
  <!-- Table of Contents (anchor links) -->
  <!-- Per-system sections: diagram + code references + invariants -->
  <!-- Inline SVG diagrams (rendered from Mermaid source) -->
</body>
</html>
```

#### SVG Inline Embedding

Mermaid CLI renders to SVG files. These get embedded directly into the HTML:

```bash
# After rendering all .mmd -> .svg, inline them into the HTML
# The build script reads each SVG and inserts it at the marked location
# This produces a single self-contained HTML file
```

This can be done manually (copy SVG content into the HTML) or with a simple script. The Mermaid `.mmd` source files are the source of truth; the HTML is the rendered deliverable.

### Supporting Tools

| Tool | Version | Purpose | Why |
|------|---------|---------|-----|
| Graphviz (dot) | system package | Render Slither call-graph DOT output to SVG | Slither's call-graph printer outputs DOT format; need `dot` CLI to convert to viewable SVG |

```bash
# Install Graphviz if not present (for Slither call-graph rendering only)
# Fedora/Nobara:
sudo dnf install graphviz
# Or skip -- call graphs can be viewed at https://dreampuf.github.io/GraphvizOnline/
```

---

## What NOT to Add

| Tool | Why Not |
|------|---------|
| Mythril | Symbolic execution is slow (minutes per contract vs. seconds for Slither); duplicates Slither's detector coverage; Solidity 0.8.34 compatibility unverified; the project already defers formal verification to v3.1 via Halmos |
| Echidna | Foundry invariant testing already covers fuzz/invariant needs; adding Echidna duplicates capability with a separate Haskell dependency |
| Certora | Formal verification is explicitly deferred to v3.1+ per PROJECT.md |
| solhint / solidity-docgen | Linting and NatSpec generation are outside audit scope; the payout spec is hand-authored for precision |
| Additional npm test libraries | Hardhat + Foundry dual stack already covers unit, integration, edge, adversarial, and simulation tests |

---

## Audit Methodology -- Value Transfer Paths

This is not a tool but a systematic approach. The audit must enumerate every code path that moves value:

### Value Types to Track

| Asset | Transfer Mechanism | Contracts |
|-------|--------------------|-----------|
| ETH | `{value: ...}` calls, `.call{value}()`, `claimableWinnings` credits | DegenerusGame, all modules, BurnieCoinflip, DegenerusVault |
| stETH | `IERC20.transfer()`, `IERC20.approve()` + external calls | DegenerusGameGameOverModule, DegenerusVault |
| BURNIE | `mint()`, `burn()`, internal balance tracking | BurnieCoin, BurnieCoinflip |
| DGNRS | `transfer()`, `wrap()`/`unwrap()` between sDGNRS and DGNRS | DegenerusStonk, StakedDegenerusStonk |
| sDGNRS | `mint()` (game rewards), soulbound (no transfer) | StakedDegenerusStonk, game modules |
| WWXRP | `transfer()` | WrappedWrappedXRP |

### Slither-Assisted Enumeration

1. Run `slither . --print call-graph` to get the full cross-contract call graph
2. Run `slither . --print function-summary` to identify every function that writes to balance/pool state variables
3. Run `slither . --print vars-and-auth` to map authorization requirements per function
4. Cross-reference with the 72 value-transfer call sites already identified (`.call{`, `.transfer(`, `safeTransfer`, `payable` across 17 files)

### Invariant Classes for Value Transfer

| Invariant | What It Verifies |
|-----------|-----------------|
| Pool conservation | `sum(all pool balances) + claimablePool <= address(this).balance` at all times |
| No ETH locked | Every ETH path either credits claimableWinnings, burns via sDGNRS, or is distributed -- no dead ends |
| BURNIE supply integrity | `totalMinted - totalBurned == totalSupply()` across all mint/burn paths |
| sDGNRS supply integrity | `sum(balanceOf[*]) == totalSupply()` and supply only changes via game reward mints |
| stETH accounting | stETH received == stETH distributed + stETH held in vault |
| Rounding dust | Rounding in BPS splits does not accumulate to material amounts over game lifetime |

---

## Installation

```bash
# Slither is already installed (0.11.5) -- verify:
slither --version

# Graphviz for rendering Slither call-graph output (optional):
sudo dnf install graphviz

# Mermaid CLI is used via npx (no install needed):
npx -y @mermaid-js/mermaid-cli mmdc --help

# No changes to package.json required.
# No new npm dependencies.
# No new pip dependencies.
```

---

## Sources

- Slither 0.11.5 verified installed locally (`slither --version` = 0.11.5)
- [Slither GitHub Repository](https://github.com/crytic/slither) -- 90+ detectors, 18 printers
- [Slither Printer Documentation](https://github.com/crytic/slither/wiki/Printer-documentation) -- full printer list with descriptions
- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation) -- all detector names, severities, and descriptions
- [PyPI slither-analyzer 0.11.5](https://pypi.org/project/slither-analyzer/) -- released 2026-01-16, supports Solidity >= 0.4
- [Mermaid.js CLI GitHub](https://github.com/mermaid-js/mermaid-cli) -- mmdc CLI for SVG/PNG rendering from .mmd source
- [sol2uml GitHub](https://github.com/naddison36/sol2uml) -- evaluated and excluded (class/storage diagrams, not money flow)
- [Surya GitHub](https://github.com/Consensys/surya) -- evaluated and excluded (call graph overlaps Slither)
- Existing repo: `package.json`, `foundry.toml`, `hardhat.config.js` -- confirmed existing toolchain
- Existing repo: 72 value-transfer call sites across 17 contract files (grep verified)
- Existing repo: 25,357 total lines of Solidity across contracts + modules + storage

**Confidence notes:**
- Slither version and capabilities: HIGH (verified locally + PyPI)
- Mermaid CLI: HIGH (well-documented, used via npx so version is always latest)
- "No Mythril" recommendation: HIGH (Slither covers the same detector classes faster; Halmos deferred to v3.1 handles formal verification)
- HTML document approach: MEDIUM (hand-authored HTML is the simplest correct approach, but the team may prefer a Markdown-based pipeline -- the key constraint is self-contained single-file output with inline SVGs)
