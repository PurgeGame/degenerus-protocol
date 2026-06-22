# v74.0 — Owner-stated constraints (gathered during /gsd-new-milestone)

Captured 2026-06-21, pre-roadmap. These are inputs to REQUIREMENTS.md.

## Two goals
1. **Live adversarial agent** — runs continuously, holds funded wallet(s), probes the
   upcoming testnet deployment trying to (a) brick/break the protocol or (b) extract more
   value than the rules allow, and **attempts** the exploits it hypothesizes (not just theory).
2. **Final C4A audit prep** — squash anything that could be a *legitimate/payable* Code4rena
   finding given the README; make the **README + known-issues list 100% ready** (a precise
   known-issues perimeter so documented issues are ineligible, without burying a real bug).

## Testnet environment (owner-stated)
- The upcoming testnet run uses **accelerated 15-minute game-days.**
  → A real **live public-testnet 24/7 soak is practical** (the agent can watch days/levels
    actually progress in near-real-time; no need to fast-forward a real chain by hand).
- **Local attack plans are also welcome.** → forked-anvil with fast time-travel is in scope
  as the *fast bug-finder* (simulate months of game-days in minutes, run thousands of
  sequences), complementing the live 15-min-day soak for realism.
- Working model: **both** — build/iterate the agent against a local fork (speed), then point
  the same agent at the live 15-min-day testnet (realistic 24/7 soak).
- The live testnet will have **normal honest actors playing 24/7** (real/bot users running
  the game legitimately). The adversarial agent therefore operates in a **live multi-actor
  environment**, NOT a clean room. Implications:
  - The "win more than you should" oracle must be **per-actor net P&L vs expected EV**, robust
    to honest background flow (the adversary is one actor among many; solvency/backing
    invariants must hold globally across ALL actors).
  - Opens **interaction/MEV attack surface** the adversary can target: front-run / sandwich /
    race honest actors' txs, grief shared windows (redemption / advanceGame / jackpot), steal
    or block honest rewards. These are first-class attack ideas for the agent.
  - A successful brick affects honest actors too — acceptable on testnet (that IS the finding),
    but the agent should log/repro rather than silently wedge the shared chain.
  - Honest background traffic is also a free realism multiplier for the local fork: replay or
    simulate honest actors alongside the adversary.

## Owner context
- Not a pro dev; wants the orchestrator to drive design + explain mechanics.
- Lead with grounded prose + a recommendation; reserve multiple-choice for bounded forks
  (per repo process memory).

## Posture
- v73.0 shipped/tagged/pushed; HEAD is 1 unpushed commit ahead (the standalone gas faucet —
  owner deprioritized it: "pretty simple and essentially third party, not a big deal").
- Phase numbering continues from 456 → 457+.
