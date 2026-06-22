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
- The testnet build uses **costs / prices scaled down by 1e6** ("/1m ETH costs") on top of the
  15-min days. Implications for the agent:
  - **Funding is trivial** — a ticket costs ~1e-8 ETH, so many wallets fund cheaply (fork =
    setBalance instant; live = a tiny drip).
  - **The agent must READ prices / EV inputs from the deployed contract** (PriceLookupLib /
    the on-chain price + payout views), NOT hardcode mainnet constants — that makes the
    ledger + EV model auto-correct at /1e6 (and at any scale). This is the load-bearing design
    principle for the P&L oracle.
  - **A real solvency / value-extraction violation is scale-invariant** — an unbacked payout
    or a net-positive-vs-EV win is a bug at any price scale — so the oracle still catches real
    bugs on the scaled testnet.
  - **Gas is NOT a real cost on testnet** (free testnet ETH) and is normal-magnitude vs the
    /1e6 stakes, so "is it an exploit" must be gated on **protocol-value extraction in the
    scaled units**, with **mainnet-gas-profitability flagged as a SEPARATE annotation** (a
    tiny extraction that mainnet gas would eat is still logged, but tagged "not gas-viable on
    mainnet") — do NOT let free testnet gas mask, or fake, a finding.
- The testnet uses a **MOCK VRF coordinator**; **on live it is real Chainlink VRF V2.5.** VRF
  is **OUT OF SCOPE as an attack surface** — DO NOT attack the mock.
  - The agent uses the mock ONLY to *supply* randomness to drive the game forward on the
    fork/testnet, and supplies it **HONESTLY** — a fair uniform random word, mimicking what
    real Chainlink would deliver. It MUST NOT choose/steer the VRF word to force outcomes.
  - **RNG prediction / manipulation / steering / the mock's controllability is NOT a valid
    finding class.** Any "win" that requires choosing or predicting the VRF word is a MOCK
    ARTIFACT, not a real bug — it cannot exist on live (real Chainlink). VRF is a trusted
    black-box oracle, exactly as on mainnet. (RNG-freeze-at-commitment was already audited
    clean in v66/v67/v68 — the agent does NOT re-litigate it.)
  - **CORRECTION to the design deep-read prompts (R1/R4):** where they said the agent "fulfils
    the mock adversarially / chooses the word," that is WRONG — replace with "fulfils with a
    fair random word." The agent's edge is value-extraction / brick / MEV under HONEST
    randomness, never RNG control.
- **stETH / MockStETH driving is NOT this agent's concern** (owner correction 2026-06-21: "this
  repo doesn't need to worry about that — taken care of in the sim repo"). The testnet
  ENVIRONMENT — deploy, the 15-min-day clock, stETH rebases/yield, the honest 24/7 actors — is
  driven by a SEPARATE SIM REPO. The adversarial agent **connects to that already-running
  testnet and plays adversarially**; it does NOT set up or drive the environment. (Exact
  agent↔sim boundary pending owner confirmation — see open question below.)
  - The backing oracle still **READS `stETH.balanceOf(game)`** live on the backing side of
    `claimablePool <= gameETH + stETH` — read, don't drive.
  - **Don't attack the mocks** (stETH OR VRF): mock-only quirks / test helpers (`mint()`,
    `setRebaseYieldBps()`, choosing the VRF word) are NOT findings; only the protocol's
    *handling* of stETH / randomness is in scope.
  - Real stETH **cannot go down** (owner ruling: a 1:1 claim on staked ETH, backed 1:1 at
    worst) → **no stETH-decline / slashing coverage concern; dropped.**

## OPEN QUESTION (blocks the agent architecture)
- **Where is the agent↔sim-repo boundary?** Does the sim repo provide the running environment in
  BOTH modes (a local/fast instance AND the live 15-min-day testnet), so the agent is purely a
  *connect-and-play* adversary that never drives time/VRF/stETH/honest-actors? Or does the agent
  still need its own local-fork fast-bug-finder (driving everything itself), with the sim repo
  owning only the live testnet? This decides whether the agent has deploy/time/VRF/stETH-driver
  modules at all, or is just a client + ledger + oracle + strategy engine.

## Owner context
- Not a pro dev; wants the orchestrator to drive design + explain mechanics.
- Lead with grounded prose + a recommendation; reserve multiple-choice for bounded forks
  (per repo process memory).

## Posture
- v73.0 shipped/tagged/pushed; HEAD is 1 unpushed commit ahead (the standalone gas faucet —
  owner deprioritized it: "pretty simple and essentially third party, not a big deal").
- Phase numbering continues from 456 → 457+.
