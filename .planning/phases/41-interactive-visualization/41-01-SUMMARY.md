---
phase: 41-interactive-visualization
plan: 01
subsystem: viz
tags: [react, vite, d3, typescript, simulation]

requires:
  - phase: 40-archetype-decision-system
    provides: "Simulation engine with archetype-driven decisions"
provides:
  - "Vite React scaffold for visualization dashboard"
  - "useSimulation hook with DaySnapshot time-series"
  - "ParameterPanel with normalized archetype sliders"
  - "Responsive DashboardShell with 2x2 chart grid"
affects: [41-02-charts, 41-03-drilldown-comparison]

tech-stack:
  added: [react-19, vite-6, d3-7, typescript-5.7]
  patterns: [useSimulation-hook, DaySnapshot-time-series, bigint-to-number-conversion]

key-files:
  created:
    - "../simulator/viz/package.json"
    - "../simulator/viz/vite.config.ts"
    - "../simulator/viz/src/types.ts"
    - "../simulator/viz/src/hooks/useSimulation.ts"
    - "../simulator/viz/src/components/ParameterPanel.tsx"
    - "../simulator/viz/src/components/DashboardShell.tsx"
    - "../simulator/viz/src/App.tsx"
  modified: []

key-decisions:
  - "Import simulator source directly via Vite alias rather than compiled dist/ (avoids build dependency)"
  - "Non-blocking simulation via requestAnimationFrame batches of 50 steps"
  - "CSS inline styles instead of Tailwind for minimal embeddable footprint"

requirements-completed: [VIZ-01, VIZ-07, VIZ-08, VIZ-10]

duration: 8min
completed: 2026-03-05
---

# Phase 41 Plan 01: Vite + React Scaffold Summary

**Vite React-TS dashboard scaffold with useSimulation hook collecting DaySnapshot time-series and responsive 2x2 chart grid layout**

## Performance

- **Duration:** 8 min
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Vite React-TS project at simulator/viz/ builds in 559ms to 237KB (74KB gzipped)
- useSimulation hook runs engine step-by-step via requestAnimationFrame, collecting DaySnapshot[] with bigint-to-ETH conversion
- ParameterPanel with linked archetype sliders that normalize to sum 1.0
- DashboardShell with sticky sidebar (280px) + 2x2 chart grid + drilldown area
- Embeddable via relative asset paths and data-degenerus-viz attribute

## Task Commits

1. **Task 1: Vite + React scaffold** - `1012ec5` (feat)
2. **Task 2: Simulation hook, parameter panel, dashboard shell** - `1b00b22` (feat)

## Files Created/Modified
- `simulator/viz/package.json` - Vite + React + D3 project scaffold
- `simulator/viz/vite.config.ts` - Vite config with simulator alias and relative base
- `simulator/viz/src/types.ts` - DaySnapshot interface and simulator re-exports
- `simulator/viz/src/hooks/useSimulation.ts` - Step-by-step simulation runner with UI-safe batching
- `simulator/viz/src/components/ParameterPanel.tsx` - All SimConfig controls with archetype normalization
- `simulator/viz/src/components/DashboardShell.tsx` - Responsive grid layout with sidebar and chart slots
- `simulator/viz/src/App.tsx` - Root component wiring hook to shell with placeholder charts

## Decisions Made
- Import simulator source directly via Vite alias rather than compiled dist/ (simulator has type errors in dist build that are pre-existing; source imports work fine via Vite's TS transform)
- Use requestAnimationFrame batches of 50 steps for non-blocking simulation (avoids freezing UI for multi-second sims)
- CSS inline styles (no Tailwind or CSS framework) for minimal embeddable footprint

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator dist/ not built, used source imports instead**
- **Found during:** Task 1 (scaffold)
- **Issue:** Simulator package has pre-existing TS errors preventing tsc build; dist/ does not exist
- **Fix:** Configured Vite alias to resolve @degenerus/simulator to ../src/index.ts (source)
- **Files modified:** viz/vite.config.ts, viz/tsconfig.json
- **Verification:** npx vite build succeeds, all simulator types resolve

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minimal - Vite handles TS source directly, no behavioral difference.

## Issues Encountered
None

## Next Phase Readiness
- Dashboard shell with placeholder chart slots ready for D3 charts (plan 41-02)
- useSimulation hook provides DaySnapshot[] and SimResult to all chart components
- ParameterPanel and run button functional

---
*Phase: 41-interactive-visualization*
*Completed: 2026-03-05*
