# The Mechanism Design of Indestructible Games: A Game-Theoretic Analysis of the Degenerus Protocol

**Working Paper — Draft for Review**

---

## Abstract

We present a formal game-theoretic analysis of the Degenerus Protocol, a zero-rake on-chain gaming system where player deposits are converted to yield-bearing assets (stETH), with yield funding all prize distributions. We model the protocol as a multi-stage stochastic game with heterogeneous players and analyze its equilibrium properties. We demonstrate that the protocol exhibits several notable mechanism design properties: (1) active participation constitutes a Nash equilibrium under broad parameter ranges, (2) the activity score system implements a form of incentive-compatible mechanism that rewards engagement over capital, (3) multiple independent forward-progression guarantees create redundant sustaining dynamics that make game stalling a measure-zero event, and (4) the illiquidity structure of rewards (future tickets, burn-on-use tokens, auto-compounding) functions as a commitment device that aligns individual rationality with collective welfare. We formalize the "indestructibility thesis" — the claim that no coalition of rational actors has a dominant strategy that weakens the protocol — and identify the precise conditions under which it holds and the edge cases where it may fail. We situate these findings within the broader mechanism design literature on self-sustaining systems, voluntary participation games, and the design of robust institutions.

**Keywords:** mechanism design, Nash equilibrium, blockchain gaming, zero-rake systems, commitment devices, stochastic games, incentive compatibility

---

## 1. Introduction

### 1.1 Motivation

The intersection of game theory and decentralized finance has produced a rich landscape of mechanism design challenges. Traditional gambling systems operate under a well-understood extractive model: the house maintains a statistical edge (2–15% in typical casinos), and players accept negative expected value in exchange for entertainment and variance. This model is sustainable but adversarial — the house profits from player losses, creating a zero-sum (or negative-sum) dynamic.

The Degenerus Protocol proposes a structural alternative: a *zero-rake* gaming system where no entity extracts value from player deposits. Instead, deposits are converted to Lido staked ETH (stETH), earning approximately 2.5% annual yield, which funds all prize distributions. This architectural choice transforms the underlying game from negative-sum to positive-sum for the player pool as a whole, introducing fundamentally different strategic dynamics.

This paper analyzes these dynamics using the tools of classical and modern game theory. We are interested in three central questions:

1. **Equilibrium existence and stability.** Does the game possess Nash equilibria? Are they stable under perturbation? What strategy profiles constitute equilibria?

2. **Incentive alignment.** Does the mechanism design ensure that individually rational behavior by each player type strengthens rather than weakens the system? Under what conditions might incentives become misaligned?

3. **Robustness and resilience.** How does the system respond to adversarial behavior, coordinated attacks, player exodus, and extreme market conditions? Can the game "die," and if so, under what precisely characterized conditions?

### 1.2 Related Work

Our analysis draws on several traditions within game theory and mechanism design:

**Mechanism design with voluntary participation.** Following Myerson (1981) and Maskin (1999), we analyze the protocol's incentive compatibility and individual rationality constraints. The key distinction from classical mechanism design is that the Degenerus Protocol has no central designer who can impose outcomes — the mechanism is immutable once deployed, and participation is entirely voluntary.

**Repeated games and folk theorems.** The multi-level structure of the protocol creates a repeated game where players' strategies at each level are informed by history and expectations about future levels. The folk theorem (Fudenberg and Maskin, 1986) suggests that cooperation can be sustained as an equilibrium in infinitely repeated games, but the Degenerus Protocol achieves cooperation-like outcomes through structural incentives rather than punishment strategies.

**Stochastic games.** The protocol's state transitions (governed by Chainlink VRF) and level-dependent payoffs place it within the framework of stochastic games (Shapley, 1953). Each level constitutes a stage game with stochastic transitions to subsequent levels.

**Commitment devices in economics.** The illiquidity structure of protocol rewards — future tickets, burn-on-use tokens, auto-compounding mechanisms — functions as a Schelling-type commitment device (Schelling, 1960). We formalize how these devices transform the game's payoff structure to make continued participation dominant.

**Contest theory and tournaments.** The jackpot system, trait-based lotteries, and leaderboard mechanics draw on the contest theory literature (Tullock, 1980; Lazear and Rosen, 1981), where players invest resources for probabilistic rewards.

### 1.3 Contribution

This paper makes several contributions:

1. We provide the first formal game-theoretic model of a zero-rake, yield-funded gaming protocol, characterizing its strategy spaces, payoff functions, and information structure.

2. We prove that active daily participation constitutes a Nash equilibrium under a broad and explicitly characterized parameter range, and identify the conditions under which deviation becomes profitable.

3. We formalize the concept of "structural indestructibility" — the property that no coalition of rational actors has a dominant strategy that weakens the protocol — and prove it holds under specified conditions while identifying the precise failure modes.

4. We analyze the protocol's mechanism design properties (incentive compatibility, individual rationality, budget balance) and show that the zero-rake architecture achieves a form of weak budget balance unusual in mechanism design.

### 1.4 Paper Organization

Section 2 introduces notation and the formal model. Section 3 describes the protocol architecture as a formal game. Section 4 characterizes player types and strategy spaces. Section 5 analyzes the mechanism design properties. Section 6 identifies Nash equilibria. Section 7 extends the analysis to the multi-stage dynamic game. Section 8 examines coordination dynamics and robustness. Section 9 analyzes failure modes and death spiral resistance. Section 10 compares to alternative systems. Section 11 concludes.

---

## 2. Model and Notation

### 2.1 Players, Types, and Heterogeneous Utility

Let $\mathcal{N} = \{1, 2, \ldots, n\}$ denote the set of active players. Players are heterogeneous, characterized by a type $\theta_i \in \Theta$ drawn from a type space:

$$\Theta = \{D, E, W, A, G, L\}$$

where the types are:
- $D$ (Degen): Entertainment-maximizing, variance-seeking, loss-tolerant
- $E$ (EV Maximizer): Risk-neutral, expected-value optimizing
- $W$ (Whale): Capital-rich, value-extracting, engagement-optimizing
- $A$ (Affiliate): Commission-seeking, network-building
- $G$ (Griefer): Disruption-seeking, potentially irrational
- $L$ (Late Entrant): Joining after level $\ell > 0$, information-disadvantaged on history

#### 2.1.1 Heterogeneous Reward Structures

A critical departure from standard mechanism design: player types in this system optimize for *fundamentally different reward currencies*. Traditional game-theoretic analysis assumes a common utility denominator (typically money). In the Degenerus Protocol, this assumption fails — and its failure is the engine of the system's sustainability.

We model this with a multi-dimensional utility function:

$$u_i(\mathbf{o}) = \alpha_i \cdot M(\mathbf{o}) + \beta_i \cdot \Psi(\mathbf{o}) + \gamma_i \cdot \Sigma(\mathbf{o})$$

where:
- $M(\mathbf{o}) \in \mathbb{R}$: **Monetary payoff** — net ETH/BURNIE/token returns minus costs
- $\Psi(\mathbf{o}) \in \mathbb{R}_{\geq 0}$: **Psychological payoff** — excitement, anticipation, dopamine from variance, near-misses, narrative participation, the felt experience of gambling
- $\Sigma(\mathbf{o}) \in \mathbb{R}_{\geq 0}$: **Social/network payoff** — reputation, community standing, referral network value, identity signaling, belonging

The type-specific weighting coefficients are:

| Type | $\alpha$ (Monetary) | $\beta$ (Psychological) | $\gamma$ (Social) | Primary Reward Currency |
|------|---------------------|------------------------|--------------------|------------------------|
| Degen ($D$) | Low (0.2–0.5) | **High (0.8–1.0)** | Low (0.1–0.3) | Dopamine, excitement, the rush |
| EV Max ($E$) | **High (0.9–1.0)** | Low (0–0.1) | Low (0–0.1) | ETH returns |
| Whale ($W$) | High (0.6–0.8) | Moderate (0.3–0.5) | **High (0.5–0.8)** | Status + returns |
| Affiliate ($A$) | High (0.7–0.9) | Low (0.1–0.2) | **High (0.6–0.9)** | Commission + network |
| Griefer ($G$) | Low (0–0.2) | **High (0.7–1.0)** | Moderate (0.3–0.5) | Chaos, disruption as entertainment |
| Late ($L$) | High (0.7–0.9) | Moderate (0.3–0.5) | Low (0.1–0.3) | Catch-up returns |

**Why this matters for mechanism design:** The protocol's sustainability depends on the insight that *actors pursuing different reward currencies can simultaneously extract their preferred payoff type without depleting each other's rewards.* A degen purchasing a 100,000x Degenerette bet is getting psychological payoff ($\Psi$) — the thrill of the spin, the dopamine of the near-miss, the fantasy of the jackpot. They are *simultaneously* funding the prize pool that pays the EV maximizer's monetary reward ($M$). Neither actor is extracting from the other's reward dimension. This is not zero-sum across utility dimensions — it is positive-sum, because the same action produces value in multiple orthogonal reward currencies.

#### 2.1.2 The Psychological Payoff Function

For Degens and other $\beta$-weighted actors, the psychological payoff $\Psi$ decomposes into several components well-documented in the behavioral economics and gambling psychology literature:

**Variance preference (Prospect Theory).** Unlike rational actors who discount variance (risk aversion) or ignore it (risk neutrality), variance-loving actors derive positive utility from variance itself. Following Kahneman and Tversky (1979), we note that in the domain of gains, individuals systematically overweight low-probability, high-magnitude outcomes. The Degenerette's 100,000x jackpot at $\sim$1/65,536 probability is precisely the kind of outcome that generates disproportionate subjective value:

$$\Psi_{variance}(\mathbf{o}) = \lambda \cdot \text{Var}[\text{payout}] + \nu \cdot \max(\text{payout})$$

where $\lambda > 0$ captures the excitement of uncertain outcomes and $\nu > 0$ captures the "dream value" — the utility derived from the *possibility* of a life-changing win, regardless of its probability. This dream value is real utility. The degen is paying for it. The protocol converts that payment into system health.

**Near-miss effects.** Psychological research (Griffiths, 1991; Clark et al., 2009) demonstrates that near-miss outcomes activate reward circuitry similarly to actual wins. Degenerette's 8-trait matching system is specifically calibrated for this effect: matching 5/8 or 6/8 traits generates $\Psi > 0$ even on economically losing bets. The 2-match payout (1.9x) and 3-match payout (4.75x) provide frequent small wins that sustain engagement through positive intermittent reinforcement — the most psychologically powerful reward schedule (Skinner, 1957). The protocol further amplifies the near-miss effect through its jackpot scratch-off mechanic: during daily jackpot draws, if a player holds *any* ticket entries in the winning trait — even if their specific entry was not among the winners — they are allowed to "scratch off" the winning trait in the UI, physically revealing the result. Since there are typically multiple winners per trait quadrant (except in the big prize quadrant, where payouts are concentrated), the player watches others in "their" trait collect prizes while they narrowly missed. This creates a visceral near-miss experience — the player held entries in the right trait, saw the reveal, but was not drawn — generating the potent cocktail of proximity-to-reward that drives continued play.

**Streak and progression satisfaction.** Quest streak maintenance, activity score growth, and trophy accumulation generate $\Psi$ through completion and progression mechanics. Game design research (Zichermann and Cunningham, 2011) has extensively documented the motivational power of progress indicators, streak counters, and achievement systems. The protocol harnesses this: the daily quest system creates a "don't break the chain" psychological commitment that converts into system-beneficial actions (daily minimum purchases, engagement maintenance). The cost to maintain the streak is one full ticket at the current level price per day (0.01 ETH at early levels, scaling with level progression); the psychological cost of *breaking* it is disproportionately large relative to this monetary cost.

**Status and identity signaling.** Deity pass ownership, whale bundle status, and BAF leaderboard positions create social signaling value ($\Sigma$) that is intrinsically non-monetary. A deity pass holder may value the status signal — being one of only 32 holders of a unique, on-chain-verifiable credential — at $\Sigma \gg 0$ even if the monetary EV calculation is marginal. The deity pass's unique symbol assignment (one of 32 quadrant symbols) creates a permanent, scarce identity marker that functions as a digital luxury good. Crucially, deity pass holders can also *issue boons* to other players (up to 3 per day) — granting bonuses like coinflip boosts, lootbox boosts, purchase discounts, or activity score bonuses. This boon-issuing power transforms the deity pass from a passive status marker into an active social role: the deity becomes a patron who can reward allies, build community, and create reciprocal relationships. The $\Sigma$ value of this social influence — the ability to materially help other players — is a powerful motivator distinct from both monetary returns and personal entertainment.

**Narrative participation.** The multi-level game structure creates an ongoing narrative ("we're on level 47, the next BAF is at 50, the prize pool is growing"). Players derive $\Psi$ from being participants in a shared narrative with uncertain but meaningful outcomes — a form of engagement documented in ARG (alternate reality game) and MMORPG research (McGonigal, 2011). This narrative payoff scales with game duration and community size, creating a positive feedback loop.

#### 2.1.3 Cross-Subsidy Equilibrium

The heterogeneous utility structure creates what we term a **cross-subsidy equilibrium**: a stable state where each actor type's pursuit of their primary reward currency generates positive externalities in a different reward dimension that benefits other types.

**Definition 2.1** (Cross-Subsidy Equilibrium). *A strategy profile $\sigma^*$ is a cross-subsidy equilibrium if, for each pair of player types $(\theta_j, \theta_k)$ with $j \neq k$, the actions optimal for type $\theta_j$ generate positive externalities in the reward dimension preferred by type $\theta_k$.*

The Degenerus Protocol exhibits the following cross-subsidy flows:

| Actor's Action | Actor's Reward | Positive Externality For |
|---------------|----------------|--------------------------|
| Degen buys Degenerette spin | $\Psi$ (thrill of the spin) | EV Max: $M$ (ETH flows to prize pools) |
| Degen opens lootbox | $\Psi$ (Christmas morning effect) | System: $M$ (90% of cost → future pool) |
| EV Max maintains activity score | $M$ (lootbox +EV, Degenerette edge) | System health (daily purchases fill pools) |
| Whale buys deity pass | $\Sigma$ (status, identity) + $M$ (EV edge) | All players: $M$ (24+ ETH directly to pools) |
| Whale dominates BAF | $\Sigma$ (leaderboard prestige) | BURNIE ecosystem (large coinflip stakes → net burn) |
| Affiliate refers players | $M$ (commissions) + $\Sigma$ (network) | All players: $M$ (new deposits to pools) |
| Degen plays coinflip daily | $\Psi$ (daily ritual, anticipation) | BURNIE ecosystem (net 1.6% deflationary burn) |
| Quest streaker completes daily | $\Psi$ (streak satisfaction) | System: $M$ (daily full-ticket purchase) |
| Deity holder issues boons | $\Sigma$ (patronage, influence) | Recipients: $M$ (coinflip/lootbox/purchase bonuses) |

This cross-subsidy structure is the engine of the protocol's sustainability. The traditional casino model has a single cross-subsidy: players provide $M$ to the house in exchange for $\Psi$ (entertainment). The cross-subsidy is adversarial — the house's gain is the player's loss. The Degenerus Protocol eliminates the house and creates *lateral cross-subsidies between player types*, where each type voluntarily provides what another type values, in exchange for what they themselves value. The subsidy is *mutualistic*, not adversarial.

**Proposition 2.1** (Non-Depletion of Cross-Subsidies). *In the cross-subsidy equilibrium, no actor type's extraction depletes the reward supply for other types, because: (a) psychological rewards ($\Psi$) are non-rivalrous — one player's excitement does not reduce another's; (b) social rewards ($\Sigma$) are positional but capped (32 deity passes, 10-level BAF resets); (c) monetary rewards ($M$) are funded by external yield ($r \cdot S$) plus the zero-rake recycling of player deposits.*

#### 2.1.4 Implications for Equilibrium Analysis

The heterogeneous utility model has four important implications for the equilibrium analysis in Sections 6–7:

1. **The active participation equilibrium is more robust than monetary analysis alone suggests.** A degen at $a_i = 0.1$ has negative monetary EV ($\mu(0.1) = 0.83$, so lootboxes return 83 cents per dollar). Under pure monetary utility, this violates individual rationality. Under heterogeneous utility, if $\beta_i \cdot \Psi > |\alpha_i \cdot M_{loss}|$, participation remains individually rational. Since Degenerette provides near-miss thrills, lootbox opens provide "Christmas morning" anticipation, and coinflip provides a daily ritual of hope — all at relatively low monetary cost — the set of individually-rational participants is substantially larger than monetary analysis predicts.

2. **The EV maximizer–degen dyad is symbiotic, not parasitic.** The EV maximizer extracts $M > 0$ from the system. The degen accepts $M < 0$ but receives $\Psi > 0$ that they value more than the monetary loss. Neither party is "subsidizing" the other in total utility terms — both achieve positive total utility from the same pool of actions. This is structurally different from casinos, where the house extracts monetary value from players whose only compensation is entertainment. Here, there is no house — only a community of differently-motivated actors whose interactions produce mutual benefit.

3. **Player retention has a ratchet effect.** As engagement deepens (longer streaks, higher activity scores, more future tickets), the psychological switching cost ($\Delta\Psi$ from breaking streaks, abandoning progression) compounds on top of the monetary switching cost ($\Delta M$ from forfeiting future tickets and EV multipliers). Total switching cost $= \alpha \cdot \Delta M + \beta \cdot \Delta\Psi$ grows faster than either component alone. This makes the commitment devices (Section 7.3) more powerful than monetary analysis predicts, because they bind on *two independent dimensions*.

4. **Griefer types face structural futility.** A griefer's psychological reward ($\Psi_{grief}$) from disruption requires visible impact on other players. The protocol's anti-manipulation mechanisms (RNG locks, VRF commitment, CREATOR bypass on advancement, 3-day emergency recovery) minimize the griefer's ability to produce visible disruption, reducing $\Psi_{grief}$ toward zero. The monetary cost of griefing (daily mint gate, ticket purchases) remains positive. Therefore griefing is strictly dominated by either genuine participation (for actors with $\beta > 0$) or exit (for $\alpha$-dominant actors), regardless of the griefer's utility weights.

We make the standard assumption that all types are rational *within their utility function* — each type maximizes $u_i$ as defined above. Type $G$ may be boundedly rational or adversarial but still utility-maximizing within their $\Psi$-weighted preference structure.

### 2.2 Game Structure

The protocol defines a multi-stage stochastic game $\Gamma = (\mathcal{N}, \mathcal{L}, \mathcal{S}, \mathcal{A}, P, u)$ where:

- $\mathcal{L} = \{0, 1, 2, \ldots, \bar{\ell}\}$ is the set of levels, with $\bar{\ell}$ the terminal level (GAMEOVER)
- $\mathcal{S}_\ell = \{PURCHASE, JACKPOT\}$ is the phase space at each level
- $\mathcal{A}_i$ is the action space for player $i$ (defined in Section 4)
- $P: \mathcal{S} \times \mathcal{A}^n \rightarrow \Delta(\mathcal{S})$ is the stochastic transition function (VRF-mediated)
- $u_i: \mathcal{H} \rightarrow \mathbb{R}$ is the payoff function mapping histories to utilities

### 2.3 State Variables

At each level $\ell$ and day $d$, the game state is characterized by:

$$\mathbf{s}_{\ell,d} = (P^{curr}_\ell, P^{next}_\ell, P^{fut}_\ell, \mathbf{a}, \mathbf{m}, \mathbf{q}, B, \phi)$$

where:
- $P^{curr}_\ell, P^{next}_\ell, P^{fut}_\ell \in \mathbb{R}_{\geq 0}$ are the current, next, and future prize pools (in ETH)
- $\mathbf{a} = (a_1, \ldots, a_n) \in [0, 3.05]^n$ is the vector of activity scores (as multipliers)
- $\mathbf{m} = (m_1, \ldots, m_n) \in \mathbb{Z}_{\geq 0}^n$ is the vector of mint streaks
- $\mathbf{q} = (q_1, \ldots, q_n) \in \mathbb{Z}_{\geq 0}^n$ is the vector of quest streaks
- $B \in \mathbb{R}_{\geq 0}$ is the total BURNIE supply
- $\phi \in \{0, 1\}$ is the jackpot phase flag

### 2.4 Prize Pool Dynamics

The prize pool evolves according to deterministic accumulation and stochastic distribution:

**Accumulation (Purchase Phase):**
For each ticket purchase of cost $c$ at level $\ell$:
$$P^{next}_\ell \leftarrow P^{next}_\ell + 0.9c$$
$$P^{fut}_\ell \leftarrow P^{fut}_\ell + 0.1c$$

**Level transition:** When $P^{next}_\ell \geq \bar{P}_\ell$ (the level target):
$$P^{curr}_{\ell+1} \leftarrow f(P^{fut}_\ell, t)$$

where $f$ is a time-dependent extraction function that draws 13–30% from the future pool (decreasing with time elapsed).

**Yield accrual (continuous):**
$$\frac{dP^{total}}{dt} = r \cdot S$$

where $r \approx 0.03\text{–}0.05$ is the stETH annual yield rate and $S$ is total staked ETH.

### 2.5 Ticket Pricing

Ticket prices follow a deterministic schedule $p: \mathcal{L} \rightarrow \mathbb{R}_{>0}$:

$$p(\ell) = \begin{cases}
0.01 & \text{if } \ell \in [0, 4] \\
0.02 & \text{if } \ell \in [5, 9] \\
0.04 & \text{if } \ell \bmod 100 \in [1, 29] \text{ and } \ell \geq 10 \\
0.08 & \text{if } \ell \bmod 100 \in [30, 59] \\
0.12 & \text{if } \ell \bmod 100 \in [60, 89] \\
0.16 & \text{if } \ell \bmod 100 \in [90, 99] \\
0.24 & \text{if } \ell \bmod 100 = 0 \text{ and } \ell \geq 100
\end{cases}$$

(All values in ETH.)

### 2.6 Activity Score Function

The activity score $a_i \in [0, 3.05]$ is computed as:

$$a_i = \min\left(\frac{m_i}{50}, 1\right) \cdot 0.50 + \min\left(\frac{c_i}{\ell}, 1\right) \cdot 0.25 + \min\left(\frac{q_i}{100}, 1\right) \cdot 1.00 + \alpha_i \cdot 0.50 + \beta_i$$

where:
- $m_i$ is the mint streak (consecutive levels with ETH purchases)
- $c_i$ is the mint count (total levels with mints)
- $q_i$ is the quest streak (consecutive daily quest completions)
- $\alpha_i \in [0, 1]$ is the normalized affiliate bonus
- $\beta_i \in \{0, 0.10, 0.40, 0.80\}$ is the pass bonus (none, 10-level whale, 100-level whale, deity)

The activity score maps to an EV multiplier $\mu: [0, 3.05] \rightarrow [0.80, 1.35]$ for lootboxes, saturating at $a = 2.55$:

$$\mu(a) = \begin{cases}
0.80 + \frac{a}{3} & \text{if } a \leq 0.60 \\
0.80 + 0.20 + \frac{(\min(a, 2.55) - 0.60) \cdot 0.35}{1.95} & \text{if } a > 0.60
\end{cases}$$

And to a Degenerette ROI $\rho: [0, 3.05] \rightarrow [0.90, 0.999]$:

$$\rho(a) \approx 0.90 + \frac{0.099 \cdot \min(a, 3.05)}{3.05}$$

### 2.7 Information Structure

The game operates under *incomplete but symmetric* information:

- **Common knowledge:** All contract code, all historical on-chain actions, all prize pool sizes, all activity scores, the pricing schedule, the VRF mechanism.
- **Private knowledge:** Each player's type $\theta_i$, future intentions, and off-chain coordination.
- **Stochastic elements:** VRF outcomes (uniformly random, unpredictable before commitment).

This places the game in the framework of Bayesian games with common prior on types but perfect observation of actions.

---

## 3. Protocol Architecture as a Formal Game

### 3.1 The Stage Game at Level $\ell$

Each level $\ell$ defines a stage game $G_\ell$ with two phases:

**Phase 1: Purchase (variable duration)**

Players simultaneously choose actions from their action sets. The purchase phase continues until the prize pool target is met: $P^{next}_\ell \geq \bar{P}_\ell$.

**Phase 2: Jackpot (fixed 5-day duration)**

Prize distribution occurs over 5 daily draws. On days 1–4, a random 6–14% of $P^{curr}_\ell$ is distributed to winners selected by VRF from the trait-ticket pool. On day 5, 100% of remaining $P^{curr}_\ell$ is distributed, plus carryover draws from adjacent levels.

**Transition:** After the jackpot phase completes, $\ell \leftarrow \ell + 1$ and Phase 1 begins for the next level.

### 3.2 Jackpot Distribution Mechanism

The jackpot is a lottery mechanism $J: \mathcal{T} \times \omega \rightarrow \Delta(\mathcal{N})$ mapping trait pools and a random seed $\omega$ (from VRF) to a probability distribution over winners.

For daily jackpots (days 1–4 of each level), a random 6–14% slice of the current prize pool is drawn. Distribution within each daily draw:
- **Trait draws (80%):** 4 traits selected, each awarding to a ticket holder in that trait pool
- **Solo bucket (20%):** Random solo winner from eligible players

For the BAF (Big-Ass Flip) jackpot, triggered every 10 levels from the future prize pool:
- **Top BAF (10%):** Awarded to highest coinflip accumulator in the current 10-level cycle
- **Top Daily Flip (10%):** Awarded to highest single-day coinflip winner
- **Random Positions (5%):** Random 3rd and 4th place selections
- **Affiliate Draw (11.25%):** Weighted draw among affiliates of eligible players
- **Scatter (~50%):** Distributed across trait-based rounds

**Proposition 3.1** (Fair Lottery). *The daily jackpot mechanism satisfies the fairness axiom: for any two players $i, j$ with identical ticket counts for a given trait, $\Pr[\text{player } i \text{ wins}] = \Pr[\text{player } j \text{ wins}]$.*

*Proof sketch.* Winners are selected by indexing into the trait-ticket array using VRF-derived entropy. Since VRF outputs are uniformly random and the indexing is linear (modular arithmetic on array length), each ticket has equal probability of selection. Players with $k$ tickets have exactly $k$ times the win probability of a player with 1 ticket. $\square$

### 3.3 The Burn Game as a Coordination Problem

The trait-ticket system creates a coordination game among players. Each ticket is assigned to one of 256 traits (4 quadrants × 64 trait values). Jackpot distributions select winning traits, meaning players benefit from holding tickets with traits that match winning draws.

However, trait assignment is *deterministic from VRF entropy* — players cannot choose their traits. This eliminates the coordination problem that would otherwise arise (where players would cluster on popular traits). The mechanism ensures trait diversity through the LCG-based generation algorithm seeded by historical VRF words.

**Proposition 3.2** (No Strategic Trait Selection). *No player can influence the trait assigned to their ticket. Trait generation is a deterministic function of: (a) the player's position in the ticket queue, and (b) the VRF-derived entropy seed, both of which are committed before the player's purchase.*

*Proof sketch.* The ticket queue ordering is determined by chronological purchase order. The entropy seed is derived from a VRF word committed in a prior block. Neither can be influenced by the purchasing player at the time of their transaction. Trait assignment follows: entropy → LCG step → XOR-shift → modular trait index, all pure functions of committed inputs. $\square$

### 3.4 Formal Properties of the State Machine

**Definition 3.1** (Liveness). *The game satisfies liveness if, for any state $\mathbf{s}$ that is not GAMEOVER, there exists a finite sequence of actions by at most one player that transitions the game to the next level.*

**Proposition 3.3** (Liveness Guarantee). *The Degenerus Protocol satisfies liveness under the assumption that sufficient purchasing activity occurs to meet the level's prize pool target ($P^{next}_\ell \geq \bar{P}_\ell$) and trigger a new level start within 365 days of the previous level's start (912 days at level 0).*

*Proof sketch.* The liveness timeout is measured from `levelStartTime` — the timestamp when the current level began. Simply calling `advanceGame()` or making a single purchase does NOT reset this timer. A new level must actually *start*, which requires the prize pool target to be met and the level to advance through its jackpot phase. This is a meaningful requirement: it demands genuine economic activity sufficient to fill the prize pool, not merely a single transaction. Three mechanisms support meeting this requirement:
1. *Multiple independent progression guarantors:* Quest streaks, afKing auto-rebuy, affiliate referrals, future ticket auto-flow, and stETH yield all contribute independently to $P^{next}_\ell$ growth (see Section 7.5).
2. *VRF retry timeout:* If the VRF callback is not received within 18 hours, any player can request a new VRF word, preventing permanent VRF stalls once the prize threshold is met.
3. *Emergency VRF recovery:* After a 3-day stall, the admin can migrate to a new VRF coordinator, restoring liveness.
4. *Graceful termination:* If no new level starts for 365 days (912 days at level 0), the game transitions to GAMEOVER, a well-defined terminal state with full prize distribution. $\square$

---

## 4. Player Typology and Strategy Spaces

### 4.1 Action Space

At each day $d$ within level $\ell$, player $i$ has the following action set:

$$\mathcal{A}_i = \mathcal{A}^{mint} \times \mathcal{A}^{loot} \times \mathcal{A}^{flip} \times \mathcal{A}^{deg} \times \mathcal{A}^{quest} \times \mathcal{A}^{dec} \times \mathcal{A}^{whale} \times \mathcal{A}^{rebuy}$$

where:
- $\mathcal{A}^{mint} = \{0\} \cup \mathbb{Z}_{>0}$: number of ticket units to purchase (0 = abstain, $k > 0$ = buy $k$ units)
- $\mathcal{A}^{loot} = \{0\} \cup \mathbb{R}_{>0}$: ETH amount to spend on lootboxes
- $\mathcal{A}^{flip} = \{0\} \cup \mathbb{R}_{\geq 100}$: BURNIE amount to stake in daily coinflip
- $\mathcal{A}^{deg} = \{0\} \cup \mathbb{R}_{>0} \times \{ETH, BRN, XRP\} \times \{1,\ldots,10\}$: Degenerette bet amount, currency, and number of spins (fixed-odds; outcome determined by trait matching, not player choice)
- $\mathcal{A}^{quest} = \{0, 1\}$: complete daily quest or not
- $\mathcal{A}^{dec} = \{0\} \cup \mathbb{R}_{\geq 1000}$: BURNIE to burn in decimator (when window open)
- $\mathcal{A}^{whale} = \{0, 1, \ldots, 100\}$: number of whale bundles to purchase
- $\mathcal{A}^{rebuy} = \{off, standard, afKing\} \times \mathbb{R}_{\geq 0}$: auto-rebuy mode and take-profit threshold

### 4.2 Strategy Profiles by Type

**Definition 4.1** (Strategy). *A strategy $\sigma_i: \mathcal{H} \rightarrow \Delta(\mathcal{A}_i)$ maps game histories to a probability distribution over actions. A pure strategy is one where $\sigma_i$ assigns probability 1 to a single action for each history.*

We characterize dominant strategies for each type:

#### 4.2.1 The Degen ($\theta = D$)

**Utility function (from Section 2.1.1):**
$$u_D(\mathbf{o}) = \underbrace{0.3 \cdot M(\mathbf{o})}_{\text{monetary (low weight)}} + \underbrace{0.9 \cdot \Psi(\mathbf{o})}_{\text{psychological (high weight)}} + \underbrace{0.2 \cdot \Sigma(\mathbf{o})}_{\text{social (low weight)}}$$

The psychological component $\Psi$ decomposes as (Section 2.1.2):
$$\Psi = \lambda \cdot \text{Var}[\text{payout}] + \nu \cdot \max(\text{payout}) + \psi_{nm} \cdot \text{near-miss frequency} + \psi_s \cdot \text{streak/progression}$$

where $\lambda > 0$ (variance-loving), $\nu > 0$ (dream value), $\psi_{nm} > 0$ (near-miss dopamine), and $\psi_s > 0$ (progression satisfaction).

**Dominant actions:**
- High-variance fixed-odds bets (Degenerette: place a bet and match 0–8 traits, with payouts from 0x to 100,000x determined entirely by the random match count — no outcome selection) — maximize $\lambda \cdot \text{Var}$ and $\nu \cdot \max$
- Daily coinflip participation — maximize $\psi_s$ (daily ritual) and $\lambda$ (50/50 variance)
- Irregular activity score optimization (streaks emerge from habit, not calculation) — some $\psi_s$ contribution
- Lootbox opens regardless of activity score — the "Christmas morning" unwrapping experience generates $\Psi > 0$ independent of monetary EV

**Key insight:** Degens are the *primary EV donors* to the system, but they are not victims — they are compensated in their preferred currency ($\Psi$). Their acceptance of monetarily sub-optimal strategies creates the surplus that funds higher $M$ returns for EV maximizers. The protocol converts their entertainment spending into prize pool growth. Critically, the degen's $\Psi$ payoff is *not diminished* by the EV maximizer's $M$ extraction — the thrill of the Degenerette spin is identical whether or not an EV maximizer also profits from the same prize pool. This non-rivalry in $\Psi$ is what makes the cross-subsidy equilibrium (Definition 2.1) sustainable.

**Individual rationality check:** The degen participates when $u_D > 0$, i.e., when:
$$0.9 \cdot \Psi > 0.3 \cdot |M_{loss}|$$
$$\Psi > \frac{1}{3} |M_{loss}|$$

For a degen spending 0.1 ETH on Degenerette at 90% ROI (activity score 0), $M_{loss} = 0.01$ ETH. The required $\Psi$ is 0.0033 ETH-equivalent — the price of a few seconds of genuine excitement. This is trivially satisfied for anyone who finds gambling entertaining, which explains why casinos (with far worse odds and no VRF fairness guarantees) have existed profitably for centuries.

#### 4.2.2 The EV Maximizer ($\theta = E$)

**Utility function:**
$$u_E(\mathbf{o}) = \mathbb{E}[\text{net payout}]$$

**Dominant strategy (Proposition 4.1):** *The EV maximizer's dominant strategy is:*

1. *Maximize activity score* $a_i \rightarrow 2.55$ for lootbox EV (achievable via deity pass OR full affiliate + whale bundle), $a_i \rightarrow 3.05$ for Degenerette ROI
2. *Purchase ETH lootboxes at $a_i \geq 2.55$* ($\mu = 1.35$, i.e., +35% EV, capped at 10 ETH benefit/level)
3. *Place ETH Degenerette bets at max activity* ($\rho = 0.999$, near-zero house edge, with +5% ETH bonus redistributed to high-match buckets)
4. *Enable afKing auto-rebuy* (1.6% base + deity bonus compounding on wins)
5. *Acquire deity pass early* (permanent +80% activity bonus)

*Proof.* We verify each component:

(1) Activity score $a_i$ is monotonically increasing in streak lengths and participation breadth. Higher $a_i$ increases $\mu(a_i)$ and $\rho(a_i)$, both of which increase expected payouts on lootboxes and Degenerette. Since all activity-building actions have marginal cost less than their marginal EV benefit at high activity levels, maximizing $a_i$ is dominant.

(2) Lootbox EV saturates at $a_i = 2.55$: $\mu(2.55) = 1.35$, meaning each ETH spent yields 1.35 ETH in expected value. This is strictly positive EV. The 10 ETH/level cap bounds total extraction but does not eliminate profitability. Note: lootbox EV caps at 255% activity — achievable with deity pass alone or full affiliate + whale bundle, without requiring both.

(3) Degenerette ETH at $a_i = 3.05$: Base ROI $\rho = 0.999$ plus the +5% ETH bonus redistributed to match buckets 5–8. The effective ROI on high-match outcomes exceeds 1.60. The overall blended EV approaches or exceeds 1.0 at maximum activity, making it weakly dominant over abstention. (Degenerette ROI continues to improve up to 305%, unlike lootbox EV which caps at 255%.)

(4) afKing auto-rebuy converts winning payouts to tickets at 145% value (45% bonus). For a 50/50 coinflip with mean reward 96.85%, the recycling bonus of 1.6% + deity bonus pushes expected retention above 1.0.

(5) Deity pass (24 ETH base) provides permanent +80% activity score. The breakeven horizon is approximately $24 / (\text{daily EV gain from +80\% activity})$. At active participation levels, this amortizes within the first few levels of play. $\square$

#### 4.2.3 The Whale ($\theta = W$)

**Utility function (from Section 2.1.1):**
$$u_W(\mathbf{o}) = \underbrace{0.7 \cdot M(\mathbf{o})}_{\text{monetary}} + \underbrace{0.4 \cdot \Psi(\mathbf{o})}_{\text{gambling thrill}} + \underbrace{0.7 \cdot \Sigma(\mathbf{o})}_{\text{status, influence}}$$

The whale is the most multi-dimensional actor type. They care about returns ($M$), but they also derive significant utility from *status* ($\Sigma$) — being one of 32 deity pass holders, dominating the BAF leaderboard, being recognized as a major player. And they enjoy the gambling itself ($\Psi$) — whales at casinos are not pure EV maximizers; they enjoy the high-stakes experience. The critical distinction from the degen is that the whale's $\alpha$ and $\gamma$ weights are both high: they need *both* monetary viability and status payoff to participate.

**Dominant actions:**
- Early deity pass acquisition (quadratic pricing favors early buyers: cost = $24 + T(n)$ ETH where $T(n) = n(n+1)/2$) — simultaneously maximizes $\Sigma$ (scarce status marker) and $M$ (permanent +80% activity bonus)
- Whale bundle purchases at levels 0–3 (2.4 ETH for 100-level coverage, ~2.5x face value) — primarily $M$ with $\Sigma$ from visible engagement
- BAF leaderboard domination through large coinflip stakes (top position earns 10% of jackpot pool) — maximizes $\Sigma$ (public leaderboard) and $M$ (jackpot share)
- Stacking deity pass with afKing mode for enhanced recycling — primarily $M$ (auto-compounding returns)
- Issuing deity boons to other players (up to 3/day) — primarily $\Sigma$ (patronage, social influence, community building) with indirect $M$ benefit (strengthening the player base that sustains prize pools)

**Whale extraction bound (Proposition 4.2):** *The maximum per-level extraction for a whale is bounded by:*

$$E_W^{max}(\ell) \leq 10\text{ ETH (lootbox cap)} + 0.1 \cdot P^{curr}_\ell \text{ (Degenerette cap)} + 0.1 \cdot P^{jackpot}_\ell \text{ (BAF share)}$$

*This bound is strictly decreasing relative to the whale's total capital commitment as the game matures.* $\square$

#### 4.2.4 The Affiliate ($\theta = A$)

**Utility function:**
$$u_A(\mathbf{o}) = \sum_{j \in \mathcal{R}_i} r(j) \cdot c_j \cdot \xi$$

where $\mathcal{R}_i$ is the set of players referred by $i$, $r(j)$ is the nominal commission rate (20–25% of referred ETH mints), $c_j$ is the mint cost of referred player $j$, and $\xi \in (0, 1)$ is the FLIP-to-ETH discount factor. Crucially, affiliates do *not* receive ETH directly — commissions are paid as FLIP credits, which must pass through a 50/50 coinflip to convert to BURNIE tokens. This means the affiliate's effective extraction is denominated in BURNIE, not ETH, and subject to both coinflip variance and BURNIE price risk. The nominal 20–25% commission rate overstates the actual ETH-equivalent extraction, since BURNIE has a variable exchange rate against ETH and the coinflip conversion has slightly negative EV (~98.5% of nominal value in expectation).

**Dominant strategy:** Build referral network early, set rakeback to balance volume vs. margin (25% rakeback maximizes referral count, 0% maximizes per-referral earnings).

**FLIP variance filter (Proposition 4.3):** *The affiliate payout mechanism (FLIP) implements a self-selection filter. Affiliates with $\lambda < 0$ (variance-averse) receive negative utility from the 50/50 coinflip conversion to BURNIE, inducing them to select out. Affiliates with $\lambda \geq 0$ (variance-neutral or variance-loving) accept the mechanism, and these affiliates better match the protocol's target user base.*

*Proof.* Let $V$ be the affiliate's pending FLIP earnings. Under coinflip payout mode, the affiliate receives either $\sim 1.97V$ BURNIE (with probability 0.5) or $0$ (with probability 0.5). Expected value: $0.5 \times 1.97V = 0.985V$ (slightly negative EV). For a variance-averse affiliate with utility $u(x) = x - \lambda \cdot \text{Var}(x)$ where $\lambda > 0$: $u = 0.985V - \lambda \cdot V^2/4$. For sufficiently large $\lambda$, $u < 0$ and the affiliate exits. For $\lambda \leq 0$ (variance-loving), the variance term contributes positively, and the affiliate remains. $\square$

#### 4.2.5 The Late Entrant ($\theta = L$)

**Utility function:**
$$u_L(\mathbf{o}) = u_E(\mathbf{o}) - \delta \cdot (\text{perceived disadvantage})$$

**Catch-up mechanisms (Proposition 4.4):** *The per-ticket EV for a late entrant at level $\ell > 0$ is approximately equal to the per-ticket EV of an early player at level 0.*

*Proof.* Ticket price at level $\ell$ is $p(\ell)$. Prize pool at level $\ell$ is funded by purchases at price $p(\ell)$, so $P_\ell \propto p(\ell) \cdot k_\ell$ where $k_\ell$ is the number of tickets sold. EV per ticket $= P_\ell / k_\ell \propto p(\ell)$. The cost per ticket is also $p(\ell)$. Therefore, $\text{EV}/\text{cost} \approx \text{constant}$ across levels.

The real late-entry disadvantages are:
1. *Deity pass pricing*: $\Delta_\text{deity}(n) = T(n) - T(0) = n(n+1)/2$ ETH premium for the $(n+1)$th buyer. This is a genuine first-mover advantage capped at 32 passes.
2. *Activity score gap*: New players start with $a_i = 0$, facing 10% lower Degenerette ROI and 55% lower lootbox EV compared to maximally engaged players. Catch-up requires ~50 levels of consistent engagement.

These disadvantages are bounded and diminishing. Whale bundles provide instant ticket coverage. Activity boons from lootboxes (10/25/50 bonus points) accelerate catch-up. $\square$

### 4.3 Budget Constraints and Bankroll Risk

The analysis in Sections 4.1–4.2 assumes players can execute their optimal strategies without resource constraints. In practice, **budget constraints** introduce a critical complication that fundamentally alters the viability of EV-maximizing play.

**Definition 4.1** (Budget Constraint). *Player $i$ has a liquid budget $B_i(t)$ at time $t$, representing the ETH available for immediate deployment. The player also holds illiquid assets $I_i(t)$ (future tickets, DGNRS tokens, vault shares, quest streak value) that have positive expected value but cannot be converted to liquid ETH within the current decision period.*

**Proposition 4.5** (Increasing Capital Requirements). *The EV-maximizing strategy requires increasing liquid capital commitment over time:*

1. *Ticket prices escalate with level progression: $p(\ell+1) > p(\ell)$*
2. *Quest streak maintenance requires one full ticket per day at the current level price $p(\ell)$*
3. *Lootbox purchases at maximum activity score require additional ETH beyond the base ticket cost*
4. *Deity pass and whale bundle costs are front-loaded lump sums*

*Therefore, the daily liquid capital requirement $C_{EV}(\ell)$ for EV-maximizing play is strictly increasing in $\ell$:*

$$C_{EV}(\ell) = p(\ell) \cdot (\text{quest ticket} + \text{optimal lootbox allocation}) > C_{EV}(\ell - 1)$$

**Theorem 4.1** (Bankroll Ruin under EV-Maximizing Play). *Even a player following a theoretically +EV strategy faces a non-zero probability of ruin (i.e., $B_i(t) < C_{EV}(\ell)$ for the current level $\ell$). This occurs because:*

1. *Jackpot payoffs are high-variance: the player may have a long run of levels without significant wins.*
2. *Future tickets and DGNRS tokens are illiquid — they contribute to $I_i(t)$ but not $B_i(t)$.*
3. *Quest streak maintenance is a daily fixed cost that cannot be deferred. Missing a single day resets the streak to zero, destroying $O(q^2)$ accumulated value (Proposition 7.2).*
4. *The player may simultaneously hold significant illiquid wealth ($I_i(t) \gg C_{EV}(\ell)$) while being unable to meet the next day's liquid cost requirement.*

*The probability of ruin is bounded by:*

$$\Pr[\text{ruin before horizon } T] \leq 1 - \prod_{t=1}^{T} \Pr[B_i(t) \geq C_{EV}(\ell(t)) \mid B_i(t-1)]$$

*This probability increases with (a) variance of per-level payoffs, (b) the rate of price escalation $p(\ell+1)/p(\ell)$, and (c) the fraction of total wealth held in illiquid form $I_i / (B_i + I_i)$.*

*Proof sketch.* The EV maximizer's budget evolves as a random walk with positive drift (since the strategy is +EV in expectation) but with absorbing barriers. The absorbing barrier at $B_i(t) < C_{EV}(\ell)$ triggers forced streak breakage, which cascades: losing the quest streak drops activity score, which reduces lootbox and Degenerette EV, which further reduces the drift of the random walk. This creates a **poverty trap**: a player who falls below the daily cost threshold loses the activity score that made their strategy +EV in the first place, making recovery progressively harder.

The key insight is that the protocol's illiquidity mechanisms — which are desirable from a system health perspective (Section 7.3) — create a tension with individual bankroll management. A player may be "rich on paper" (holding future tickets, DGNRS, and vault shares with high expected value) while being unable to afford tomorrow's quest ticket. The quadratic cost of breaking a quest streak (Proposition 7.2) makes this particularly punishing: the optimal response to budget stress is *not* to skip a day, but this may not be feasible. $\square$

**Corollary 4.1** (EV-Maximizing Play is Harder Than It Appears). *The theoretical EV calculations in Section 4.2.2 represent an upper bound on achievable returns. In practice, budget constraints, variance, and the illiquidity of rewards mean that:*

- *Players with small bankrolls relative to ticket prices face significant ruin probability even at +EV.*
- *The "correct" bankroll management strategy requires maintaining a liquid reserve buffer, which reduces capital deployed to +EV opportunities.*
- *Price escalation across levels creates a ratcheting effect: the strategy becomes more capital-intensive precisely when the player's liquid reserves may be depleted by prior variance.*

*This has an important systemic consequence: the gap between theoretical EV-maximizing returns and realized returns acts as an additional implicit "rake" that benefits the system. Players who attempt to extract maximum EV but fail due to bankroll constraints end up contributing more to prize pools (through broken streaks and suboptimal play) than the theoretical analysis would predict.*

---

## 5. Mechanism Design Analysis

### 5.1 Incentive Compatibility

**Definition 5.1** (Incentive Compatibility). *A mechanism is incentive-compatible if, for each player $i$ of type $\theta_i$, truthful revelation of type (or, equivalently, playing the strategy optimal for one's true type) is a best response regardless of other players' strategies.*

The Degenerus Protocol does not require truthful type revelation in the classical sense — types are private and never reported. Instead, we analyze a behavioral analog:

**Definition 5.2** (Behavioral Incentive Compatibility). *The protocol is behaviorally incentive-compatible if, for each player type $\theta$, the strategy that maximizes $u_\theta$ also contributes positively to system health (measured by prize pool growth, participation rate, or game progression).*

**Theorem 5.1** (Behavioral IC of the Activity Score Mechanism). *The activity score mechanism is behaviorally incentive-compatible: the individually optimal strategy for each player type (except the Griefer) involves actions that increase total prize pool value and game progression speed.*

*Proof.* We verify for each non-Griefer type:

**Degen ($D$):** Optimal actions include high-frequency betting (Degenerette, coinflip) and ticket purchases. Each bet contributes to prize pools (Degenerette ETH bets flow to future pool, ticket purchases flow 90% to next pool). Entertainment utility $\gamma_D$ makes even EV-negative actions individually rational, and these actions fund the prize pool.

**EV Maximizer ($E$):** Optimal strategy requires maximizing activity score $a_i$, which requires: (1) daily ticket purchases (funding next pool), (2) daily quest completion (requiring one full ticket purchase per day = pool contribution), (3) maintaining mint streaks (requiring consistent level-over-level purchases). Every component of $a_i$ optimization involves direct ETH contributions to the prize pool.

**Whale ($W$):** Optimal actions include deity pass purchases (funding future pool), whale bundles (30%/70% or 5%/95% split to next/future pools), large coinflip stakes (no direct pool contribution, but BAF leaderboard engagement requires level participation), and afKing auto-rebuy (automatically converts winnings into future-level tickets, directly compounding pool growth).

**Affiliate ($A$):** Optimal strategy is referral network expansion. Each referred player's purchases flow to prize pools. The affiliate's nominal commission (20–25%) is paid in BURNIE via the FLIP coinflip mechanism — not in ETH — meaning the extraction does not directly reduce the ETH prize pool. The referred player's full ETH purchase flows to the pool, while the affiliate commission is minted as BURNIE (a separate token with its own supply dynamics). This is net positive for the ETH prize pool system.

**Late Entrant ($L$):** Catch-up strategy (whale bundles, rapid quest streaks, lootbox activity boons) involves concentrated purchasing that rapidly fills prize pools.

In all cases, the individually optimal strategy for each type involves actions that increase $P^{next}_\ell + P^{fut}_\ell$, which directly measures system health. $\square$

### 5.2 Individual Rationality

**Definition 5.3** (Individual Rationality). *The mechanism is individually rational if, for each player $i$, the expected utility from participation exceeds the expected utility from non-participation (the outside option).*

$$\mathbb{E}[u_i(\sigma_i^*, \sigma_{-i})] \geq u_i(\text{outside option})$$

**Theorem 5.2** (Conditional Individual Rationality). *The Degenerus Protocol is individually rational for:*
- *EV Maximizers with activity score $a_i \geq 0.60$ (neutral EV threshold for lootboxes)*
- *Whales with deity passes (permanent +EV on lootboxes and near-zero edge on Degenerette)*
- *Degens with $\gamma_D > |EV_{loss}|$ (entertainment value exceeds expected monetary loss)*
- *Affiliates with referral network size $|\mathcal{R}_i| \geq k_{min}$ (minimum network for positive commission flow)*

*The protocol is NOT individually rational for:*
- *EV Maximizers with $a_i < 0.60$ who play only lootboxes (sub-100% EV)*
- *Pure griefers with no entertainment utility ($\gamma_G = 0$, $\lambda_G = 0$)*
- *Affiliates under the Split-Coinflip-Coin payout mode (50% BURNIE minted, 50% discarded = guaranteed 50% loss)*

*Proof sketch.* The EV threshold $a_i = 0.60$ corresponds to $\mu(0.60) = 1.00$ (neutral lootbox EV). Below this threshold, lootbox purchases have negative expected value. Above it, they are positive. The Degenerette ROI at $a_i = 0.60$ is approximately 95%, still negative but improving. The combination of multiple +EV pathways (lootboxes at $\mu > 1.0$, Degenerette at high activity, auto-rebuy compounding) creates net positive EV for sufficiently engaged players. $\square$

### 5.3 Budget Balance

**Definition 5.4** (Budget Balance). *A mechanism is (weakly) budget-balanced if total payouts do not exceed total inputs for any realization of the game.*

**Theorem 5.3** (Strict Budget Balance). *The Degenerus Protocol satisfies strict budget balance at all times:*

$$\sum_{i \in \mathcal{N}} \text{claimable}_i \leq \text{ETH balance} + \text{stETH balance}$$

*This invariant is enforced on-chain and checked in every module. Moreover, the protocol is strictly budget-positive due to stETH yield:*

$$\frac{d}{dt}\left(\text{total assets} - \sum_i \text{claimable}_i\right) = r \cdot S > 0$$

*where $r$ is the stETH yield rate and $S$ is total staked ETH.*

*Proof.* The solvency invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` is checked in every function that modifies claimable winnings. No operation can create claimable amounts exceeding total assets. The Degenerette ETH payout cap (10% of future pool per win) and the lootbox EV cap (10 ETH benefit per player per level) provide hard bounds on single-transaction outflows. The stETH yield continuously increases total assets without increasing claimable amounts, maintaining strict positivity. $\square$

### 5.4 The Zero-Rake Property

**Definition 5.5** (Zero-Rake). *A gaming mechanism is zero-rake if no entity extracts a guaranteed percentage of player deposits as profit.*

**Theorem 5.4** (Zero-Rake). *The Degenerus Protocol is zero-rake: 100% of player ETH deposits remain in the prize pool system. Protocol operator revenue derives exclusively from:*
1. *DGNRS token appreciation (as reserves grow)*
2. *Vault share claims (from DGVE/DGVB shares retained by the creator)*
3. *stETH yield accrual on reserves*

*None of these extract from player deposits; they derive from secondary market valuation and yield on assets the operator owns independently.*

**Corollary 5.1** (Positive-Sum Game). *For the player pool as a whole, the Degenerus Protocol is a positive-sum game:*

$$\sum_{i \in \mathcal{N}} \mathbb{E}[\text{net payout}_i] = \sum_{i \in \mathcal{N}} \text{deposits}_i + r \cdot S \cdot T > \sum_{i \in \mathcal{N}} \text{deposits}_i$$

*where $T$ is the time horizon and $r \cdot S \cdot T$ is total yield generated. The game creates more value than it consumes.*

---

## 6. Nash Equilibrium Analysis

### 6.1 Existence

**Theorem 6.1** (Existence of Nash Equilibrium). *The Degenerus Protocol game $\Gamma$ possesses at least one Nash equilibrium in mixed strategies.*

*Proof sketch.* The game has a finite number of player types, and at any given day, each player's action space can be discretized to a finite set (ticket purchases in integer units, BURNIE stakes in discrete increments, quest completion as binary). By Nash's theorem (1951), every finite game has at least one Nash equilibrium in mixed strategies. The stochastic elements (VRF outcomes) do not affect existence, as they enter through the payoff function as expectations over commonly known distributions. $\square$

### 6.2 The Active Participation Equilibrium

**Theorem 6.2** (Active Participation is a Nash Equilibrium). *Consider the strategy profile $\sigma^* = (\sigma_1^*, \ldots, \sigma_n^*)$ where each player $i$ plays their type-optimal strategy (as characterized in Section 4.2). This profile constitutes a Nash equilibrium when:*

1. *The player pool size $n \geq n_{min}$ (sufficient for meaningful prize pools)*
2. *The stETH yield rate $r > 0$ (positive external value injection)*
3. *At least one player has activity score $a_i < 1.0$ (existence of EV donors)*

*Proof.* We verify that no player has a profitable unilateral deviation:

**Case 1: EV Maximizer deviates to abstention.** By abstaining, player $i$ loses:
- Lootbox EV surplus: $(\mu(a_i) - 1) \cdot L_i$ where $L_i$ is lootbox spending and $\mu(a_i) > 1$ for $a_i > 0.60$
- Activity score decay: streaks break, reducing $a_i$ and future EV multipliers
- Quest rewards: 300 BURNIE/day forfeited

The opportunity cost of abstention exceeds the cost of participation for any player with $a_i > 0.60$, making deviation unprofitable.

**Case 2: EV Maximizer deviates to minimal participation.** Reducing engagement (e.g., skipping quests, breaking mint streaks) reduces $a_i$, which reduces $\mu(a_i)$ and $\rho(a_i)$. The marginal cost of maintaining streaks (full-ticket quest purchase at the current level price per day) is dominated by the marginal benefit of higher EV multipliers on all subsequent actions. Deviation is unprofitable.

**Case 3: Whale deviates to exit.** A whale exiting forfeits:
- Accumulated activity score (non-transferable, rebuilt only by re-engagement)
- Deity pass benefits (pass is transferable but costs 5 ETH in BURNIE to transfer, and the pass's value derives from active gameplay)
- Future ticket holdings (queued for levels the whale will not participate in)
- BAF leaderboard position (resets every 10 levels regardless, but requires continuous coinflip stakes to maintain)

The whale's accumulated position represents a sunk cost, but the ongoing returns from that position (lootbox EV at +35%, near-zero Degenerette edge, auto-rebuy compounding) provide continuing positive returns that exceed the opportunity cost of capital for engaged players.

**Case 4: Affiliate deviates to stop referring.** Commission flow ceases, but the affiliate retains no other edge. Since referral is the affiliate's only value proposition, cessation is equivalent to exit. The affiliate's ongoing commission (20–25% of referred players' mints) is net positive as long as the referral network remains active. Deviation eliminates income without reducing costs.

**Case 5: Degen deviates to non-participation.** The degen's entertainment utility $\gamma_D$ from playing exceeds the EV loss. If $\gamma_D < |\text{EV loss}|$, the degen was never in the individually rational set (Theorem 5.2) and would not have participated in the first place. For degens within the IR set, continued play is preferred. $\square$

### 6.3 The Inactive Equilibrium

**Theorem 6.3** (Existence of the Inactive Equilibrium). *The strategy profile where all players choose $\sigma_i = 0$ (no participation) is also a Nash equilibrium.*

*Proof.* If no one participates, prize pools do not grow beyond stETH yield on existing deposits. A single deviator who begins participating faces:
- Costs: ticket purchase price $p(\ell)$
- Benefits: 100% of any jackpot pool (since they hold all tickets), but the pool grows slowly from yield alone

For the deviation to be profitable, the yield on existing deposits must exceed the cost of participation over the time horizon until the next jackpot. Whether this holds depends on the accumulated prize pool size.

**Critical insight:** If $P^{fut}_\ell + P^{next}_\ell > 0$ (which is true after any historical deposits), the yield $r \cdot (P^{fut}_\ell + P^{next}_\ell) > 0$ creates a *standing incentive* for at least one player to deviate from the inactive equilibrium. This makes the inactive equilibrium **unstable** — it exists but is not robust to perturbation.

Moreover, the inactive equilibrium is further destabilized by a **first-mover advantage in deviation**: the earliest players to break from inactivity and begin purchasing gain the most accumulated ticket positions across the most levels, giving them the most jackpot draw opportunities once the game is active. A player who deviates early and holds tickets across levels 1–50 has far more jackpot chances than a player who enters at level 45. This creates a race-to-deviate dynamic: each player knows that if the game *eventually* starts, earlier deviators are structurally advantaged. The rational response is to deviate early, which collapses the inactive equilibrium. $\square$

**Corollary 6.1** (Instability of the Inactive Equilibrium). *The inactive equilibrium is unstable in two senses: (a) in the evolutionary game theory sense, any positive-measure perturbation (a small fraction of players experimenting with participation) shifts the system toward the active participation equilibrium, because the deviating players capture concentrated prize pool value from accumulated yield; and (b) in the strategic sense, each player has an incentive to deviate first, because the earliest entrants accumulate the most ticket positions across the most levels, maximizing their jackpot exposure if the game reaches those levels. This "race to enter" dynamic makes coordinated inactivity unstable even without communication among players.*

### 6.4 Equilibrium Selection

Between the two equilibria identified above, the active participation equilibrium is:

1. **Payoff-dominant:** All players receive higher expected payoffs under active participation than under inactivity (Theorem 5.2 establishes individual rationality for most types).

2. **Risk-dominant:** The risk of participating (potential EV loss for low-activity players) is bounded by the zero-rake property — the worst case is entertainment spending with no return, not loss of principal. The risk of non-participation is forfeiting growing prize pools.

3. **Evolutionarily stable:** Under replicator dynamics, the active participation strategy strictly dominates inactivity whenever the active player pool generates positive net prize flows, which it does as long as $r > 0$ and $n \geq 1$.

**Proposition 6.1** (Equilibrium Selection via stETH Yield). *The stETH yield rate $r > 0$ functions as an equilibrium selection device: it ensures that accumulated prize pools always grow in real terms, making the active participation equilibrium the unique trembling-hand perfect equilibrium.*

---

## 7. Multi-Stage Dynamic Game Analysis

### 7.1 The Repeated Game Structure

The protocol defines a repeated game where each level $\ell$ is a stage game. Players' strategies at level $\ell$ depend on:
- **History:** All actions and outcomes at levels $0, 1, \ldots, \ell - 1$
- **State:** Current prize pools, activity scores, BURNIE supply
- **Expectations:** Beliefs about future player behavior and prize pool growth

This creates a stochastic game in the sense of Shapley (1953), where the state transition depends on both player actions and nature's moves (VRF outcomes).

### 7.2 Subgame Perfect Equilibrium

**Definition 7.1** (Subgame). *A subgame of $\Gamma$ begins at the start of any level $\ell$ with a well-defined state $\mathbf{s}_\ell$.*

**Theorem 7.1** (Subgame Perfect Equilibrium). *The strategy profile $\sigma^*$ (active participation by all rational types) constitutes a subgame perfect equilibrium (SPE) when:*
1. *Activity score rewards are sufficiently large (the gap between $\mu(a_{max})$ and $\mu(0)$ exceeds participation costs)*
2. *The discount factor $\delta_i$ for each player is sufficiently high (players value future payoffs)*

*Proof sketch.* By backward induction from the terminal level (GAMEOVER), at each subgame starting at level $\ell$:

At GAMEOVER: The game distributes all remaining assets. No strategic choice exists.

At level $\bar{\ell} - 1$: Players know the next level is terminal. Optimal play is to maximize participation for the final jackpot distribution. Deviation to non-participation forfeits the final prize pool share.

At level $\ell < \bar{\ell} - 1$: Players anticipate active participation at $\ell + 1$ (by induction). The value of maintaining activity score (which persists across levels) makes continued engagement optimal, as:

$$V_i(\ell) = \pi_i(\ell) + \delta_i \cdot V_i(\ell + 1 | a_i(\ell))$$

where $\pi_i(\ell)$ is the stage-game payoff and $V_i(\ell + 1 | a_i(\ell))$ is the continuation value conditional on the activity score carried forward. Since $a_i(\ell)$ is increasing in engagement at level $\ell$ (streak maintenance), and $V_i(\ell+1)$ is increasing in $a_i$, the induction step holds. $\square$

### 7.3 Commitment Devices and Illiquidity

The protocol employs several commitment devices that transform the payoff structure:

**Device 1: Future Tickets.** Lootbox prizes frequently award tickets for future levels ($\ell + k$ for $k \in [0, 50]$). These tickets are:
- Non-transferable (bound to the player)
- Non-refundable (no mechanism to convert back to ETH)
- Valuable only if the player participates at the target level

This creates a commitment to future participation. A player who receives 100 future tickets has a strictly positive incentive to remain active through those levels.

**Proposition 7.1** (Future Tickets as Commitment Device). *A player holding $T$ future tickets at level $\ell + k$ has an expected future payoff of:*
$$V_{tickets}(\ell+k) = T \cdot \frac{P_{\ell+k}}{K_{\ell+k}}$$
*where $K_{\ell+k}$ is the total ticket count at level $\ell + k$. This represents a strictly positive incentive to remain active, conditional on the game reaching level $\ell + k$.*

**Device 2: Quest Streaks.** A quest streak of length $q$ contributes $\min(q, 100)\%$ to the activity score. Breaking the streak (missing one day) resets $q$ to 0. The sunk cost of building a long streak creates strong retention:

$$\text{Streak value} = \Delta\mu(q\%) \cdot \text{daily EV} \cdot \text{remaining days until cap}$$

For a player with a 50-day streak, the daily cost of maintaining the streak (minimum quest completion = one full ticket at current level price) is far exceeded by the EV uplift from 50% activity score contribution.

**Proposition 7.2** (Streak Lock-In). *For a player with quest streak $q$ and daily EV $\pi$, the cost of breaking the streak is:*
$$C_{break}(q) = \sum_{d=0}^{q-1} \Delta\mu(d) \cdot \pi \approx \frac{q^2}{2} \cdot \frac{\partial \mu}{\partial a} \cdot \pi$$
*This cost is quadratic in streak length, creating increasingly powerful retention as streaks grow.*

**Device 3: afKing Auto-Rebuy.** When enabled, jackpot winnings are automatically converted to next-level tickets at 130–145% value. This converts liquid ETH winnings into illiquid future participation, compounding the player's stake in the game.

**Device 4: BURNIE Burn-on-Use.** BURNIE tokens are destroyed when used for tickets, Degenerette bets, and decimator entries. They cannot be "saved" in a productive way — their value is realized only through gameplay actions that contribute to the system.

### 7.4 The Forward-Pushing Dynamic

**Theorem 7.2** (Forward-Pushing Nash Equilibrium). *Under the strategy profile $\sigma^*$, every action taken by every rational player type contributes to game progression (increasing $P^{next}_\ell$ toward the level target $\bar{P}_\ell$). Game progression cannot stall in $\sigma^*$ as long as at least one player participates.*

*Proof.* Enumerate the forward-pushing effects of each type's optimal actions:

| Actor | Action | Forward-Push Mechanism |
|-------|--------|----------------------|
| Degen | Ticket purchases | 90% → $P^{next}$, 10% → $P^{fut}$ |
| EV Max | Quest mints + lootboxes | Daily minimum ticket purchase + lootbox ETH to pools |
| Whale | Whale bundles | 5–30% → $P^{next}$, 70–95% → $P^{fut}$ |
| Whale | Deity pass | Full price → prize pools |
| Affiliate | Referrals | Each referred player's purchases flow to pools |
| afKing player | Auto-rebuy | Winnings → next-level tickets → pool contributions |
| Future ticket holder | Futurepool → nextpool flow | Auto-purchases at target levels |

Every row contributes positively to $P^{next}_\ell$. Since $P^{next}_\ell$ reaches $\bar{P}_\ell$ with certainty if any positive flow exists, the level advances. Since level advancement is the definition of game progression, the game cannot stall.

Moreover, these mechanisms are *redundant*: any single row suffices to ensure progression (given sufficient time). The conjunction of all rows makes stalling effectively impossible once any momentum exists. $\square$

### 7.5 Redundancy and Robustness of Progression

**Definition 7.2** (Progression Guarantor). *A mechanism is a progression guarantor if it independently ensures that $P^{next}_\ell$ reaches $\bar{P}_\ell$ within a finite time horizon, regardless of other mechanisms.*

The protocol has at least five independent progression guarantors:

1. **Quest streak maintenance:** Power users making daily minimum purchases to preserve activity score.
2. **afKing auto-compounding:** All coinflip/jackpot wins automatically converted to next-level tickets.
3. **Affiliate acquisition:** New player referrals creating fresh purchasing activity.
4. **Futurepool → nextpool auto-flow:** Tickets purchased at future levels automatically queued and processed.
5. **stETH yield accrual:** Passive growth of prize pools from staking yield.

**Proposition 7.3** (Redundant Liveness). *The probability that all five progression guarantors simultaneously fail to advance the game is:*

$$\Pr[\text{stall}] = \prod_{k=1}^{5} \Pr[\text{guarantor } k \text{ fails}]$$

*Under the assumption that guarantor failures are approximately independent (each depends on different player behavior or external factors), this product converges to zero rapidly as any individual guarantor becomes reliable.*

---

## 8. Coordination Dynamics and Robustness

### 8.1 The Burn Game as an Anti-Coordination Problem

The trait-ticket system creates an interesting strategic structure. Each ticket is assigned to one of 256 traits, and jackpots reward tickets matching the drawn traits. If players could choose their traits, this would create a classic anti-coordination problem (everyone should spread across traits to avoid competition for the same jackpot shares).

However, the protocol eliminates this problem through *forced diversification*: trait assignment is deterministic from VRF entropy and queue position, preventing strategic trait selection (Proposition 3.2). This converts what could be a complex coordination game into a simple lottery with equal per-ticket odds, regardless of strategy.

**Proposition 8.1** (Coordination-Free Design). *The Degenerus Protocol eliminates all non-trivial coordination problems from the core game. The only strategic choices are: (a) how much to invest, (b) which products to use (tickets, lootboxes, Degenerette, coinflip), and (c) whether to maintain engagement streaks. None of these choices require coordination with or knowledge of other players' specific strategies.*

### 8.2 The Affiliate Network as a Coordination Game

The affiliate system does create a mild coordination game: referred players benefit from joining under an affiliate with high rakeback (up to 25%), while affiliates benefit from setting low rakeback (keeping more commission). This is a standard bilateral negotiation.

**Equilibrium:** The competitive equilibrium converges to the maximum rakeback (25%), as affiliates compete for referrals by offering higher rakeback. This is analogous to Bertrand price competition and benefits referred players at the expense of affiliate margins.

**Default chain mitigation:** Players who don't use affiliate codes are automatically referred to the VAULT → DGNRS circular chain, ensuring that even "orphan" players' commissions contribute to the system's two primary token reserves rather than being lost.

### 8.3 Robustness to Coalitional Deviations

**Definition 8.1** (Coalition-Proof). *A strategy profile is coalition-proof if no coalition $C \subseteq \mathcal{N}$ can profitably deviate jointly.*

**Theorem 8.1** (Robustness to Small Coalitions). *The active participation equilibrium $\sigma^*$ is robust to deviations by coalitions of size $|C| \leq 0.3n$ (less than 30% of players).*

*Proof sketch.* A deviating coalition can at most:
1. **Withdraw participation:** Reduces $P^{next}_\ell$ growth rate but does not prevent progression (the remaining 70%+ of players and the five independent progression guarantors sustain the game).
2. **Coordinate ticket timing:** Cannot influence trait assignment (Proposition 3.2) or VRF outcomes. Timing of purchases affects only queue position, which affects trait assignment uniformly.
3. **Dominate BAF leaderboard:** At most, captures 10% of jackpot pool (the BAF allocation). The remaining 90% (scatter, daily flip, affiliate draw) distributes to all participants.
4. **Dump BURNIE:** Creates temporary sell pressure, but utility floor (ticket purchases, decimator entries) provides a price floor proportional to game activity.

The coalition's maximum extraction is bounded, and their departure increases per-capita EV for remaining players (the "whale departure paradox" — see Section 9.3). $\square$

### 8.4 Economic Attack Vector Analysis

We classify potential attacks by severity and feasibility:

#### Attack 1: Sybil Attack on Activity Score

**Vector:** A single entity creates multiple wallets to farm activity score bonuses across accounts.

**Analysis:** Each wallet must independently: (a) purchase tickets (real ETH cost), (b) complete daily quests (real ETH + BURNIE cost), (c) maintain streaks (daily transaction costs). The marginal cost of maintaining $k$ sybil accounts scales linearly, while the marginal benefit (lootbox EV cap of 10 ETH/level/account) also scales linearly. There is no superlinear advantage to sybil accounts.

**Verdict:** Not economically advantageous. The per-account EV cap and linear cost scaling eliminate sybil alpha.

#### Attack 2: BAF Leaderboard Manipulation

**Vector:** A whale stakes very large coinflip amounts to dominate the BAF leaderboard and capture 10% of jackpot pools.

**Analysis:** BAF credit is earned from *winning* coinflip payouts, requiring actual VRF wins (50% probability). The leaderboard resets every 10 levels, preventing permanent domination. The 10% allocation is bounded regardless of dominance level. The required capital commitment (large BURNIE stakes with 50% loss probability) creates significant variance risk.

**Verdict:** Feasible but bounded. A whale can consistently capture BAF allocations, but the extraction is capped at 10% of jackpot pools and requires continuous capital risk.

#### Attack 3: Degenerette Pool Drain

**Vector:** A high-activity player places maximum ETH bets on Degenerette, exploiting the +EV at high activity scores.

**Analysis:** ETH payouts are hard-capped at 10% of the future prize pool per win. The 8-match jackpot (100,000x payout) is extremely rare ($\approx 1/65,536$ per trait configuration). Even at maximum activity (99.9% ROI), the net extraction per bet is marginal. The 75% lootbox payout component converts extraction into future game participation, not liquid withdrawal.

**Verdict:** Not a threat. Caps and lootbox conversion prevent meaningful pool drain.

#### Attack 4: Affiliate Self-Referral Loop

**Vector:** A player creates an affiliate code and refers themselves to capture 20–25% commission on their own purchases.

**Analysis:** The protocol explicitly blocks self-referral — attempting to use your own affiliate code locks your referral to the VAULT sentinel permanently. Cross-referral between two colluding accounts is possible (A refers B, B refers A) and creating a second account has no cost. However, the key constraint is that affiliate score contributes to activity score, and a player who self-refers through a second account *cannot gain affiliate score on their main account* without actually referring external players. The "gaming" here is limited: the colluding player captures referral commissions that would otherwise flow to a legitimate affiliate, but does not gain any activity score advantage on their primary account.

**Verdict:** Low-impact by design. Self-referral is blocked. Cross-referral is costless to set up, but the benefit is strictly limited to capturing BURNIE commissions (via FLIP) that would otherwise go to a legitimate referrer — it does not boost the player's activity score. The player who cross-refers is effectively taking from the affiliate pool, not from the system itself.

---

## 9. Death Spiral Resistance and Failure Mode Analysis

### 9.1 Formal Definition of Death Spiral

**Definition 9.1** (Death Spiral). *A death spiral is a sequence of states $\mathbf{s}_1, \mathbf{s}_2, \ldots$ where:*
1. *Player count $n_t$ is monotonically decreasing: $n_{t+1} < n_t$ for all $t$*
2. *Prize pool growth rate $\dot{P}_t$ is negative: the system distributes more than it accumulates*
3. *The process is self-reinforcing: declining participation causes further participation decline*

### 9.2 Structural Death Spiral Resistance

**Theorem 9.1** (Death Spiral Resistance). *The Degenerus Protocol resists death spirals through three independent mechanisms:*

**(a) Prize pool concentration.** *As players exit, the per-capita prize pool share increases for remaining players:*

$$\text{EV per player} = \frac{P_{total}}{n} \xrightarrow{n \downarrow} \infty$$

*This creates an increasing incentive for remaining players to stay and an increasing incentive for new players to enter. The system has a natural "buy low" attractor.*

**(b) Yield independence.** *stETH yield continues regardless of player activity:*

$$\frac{dP^{total}}{dt} = r \cdot S > 0 \quad \text{even if } n = 0$$

*Prize pools grow from yield alone, independent of deposits. During a player exodus, pools continue accumulating, creating larger prizes for fewer players.*

**(c) Locked liquidity.** *Prize pools are not withdrawable. Player exit does not reduce prize pool assets — it only reduces competition for those assets. This is structurally different from DeFi protocols where whale departure causes liquidity crises.*

*Proof.* Formally, a death spiral requires condition (3): self-reinforcing decline. In the Degenerus Protocol, player departure has two effects:

Effect A (negative): Reduced prize pool *growth rate* (fewer deposits).
Effect B (positive): Increased per-capita *share* of existing pools (fewer competitors).

For remaining players, Effect B dominates Effect A when:

$$\frac{P_{total}}{n - 1} - \frac{P_{total}}{n} > \frac{r \cdot c_{exit}}{n}$$

where $c_{exit}$ is the exiting player's contribution rate. This simplifies to:

$$\frac{P_{total}}{n(n-1)} > \frac{r \cdot c_{exit}}{n}$$

$$P_{total} > (n-1) \cdot r \cdot c_{exit}$$

For any accumulated pool $P_{total}$ that exceeds the annual yield on a single player's contribution, remaining players benefit from the departure. Since $P_{total}$ accumulates over the entire game history and $c_{exit}$ is a single player's annual contribution, this inequality holds once the game has been active for more than a few levels.

Therefore, condition (3) of Definition 9.1 fails: player departure does not cause further departure for remaining rational players. The "spiral" breaks because the incentive to stay *increases* as others leave. $\square$

### 9.3 The Whale Departure Paradox

**Proposition 9.1** (Whale Departure is Net Positive for Remaining Players). *When a whale (high-activity, capital-intensive player) exits the protocol, the remaining players' per-capita expected value increases.*

*Proof.* A whale with activity score $a_W \geq 2.55$ extracts more than they deposit (that is the definition of a successful whale — they earn positive EV on lootboxes at $\mu = 1.35$, near-zero edge Degenerette, BAF leaderboard prizes, etc.). When they exit:

1. Their deposits cease: $P^{next}_\ell$ growth decreases by $c_W$ per level.
2. Their extractions cease: Prize distributions lose a player who was winning $> c_W$ in expectation.

Since $\mathbb{E}[\text{extraction}_W] > c_W$ (the whale is +EV by construction), the net effect is:

$$\Delta \text{pool} = c_W - \mathbb{E}[\text{extraction}_W] < 0 \text{ (whale was a net extractor)}$$

Wait — this means the whale's departure is *positive* for remaining players, because the net extraction that was flowing to the whale now remains in the prize pool for distribution to others.

More precisely: all remaining players' activity scores improve in relative ranking (the compression effect), their lootbox EV per ETH is unchanged (individual, not relative), but their share of jackpot distributions increases (fewer competitors). $\square$

### 9.4 BURNIE Token Stability

**Proposition 9.2** (BURNIE Price Floor). *The BURNIE token has a structural price floor set by its ETH-denominated utility:*

$$p_{BURNIE}^{floor} = \min\left(\frac{p(\ell)}{1000}, \frac{\mathbb{E}[\text{Decimator ETH per BURNIE burn}]}{1000}\right)$$

*The first term is the implied price from ticket purchasing (1000 BURNIE buys 1 ticket at the current level price). The second is the implied price from decimator expected value.*

*Proof.* If the market price of BURNIE falls below $p(\ell)/1000$, rational players buy BURNIE on the open market and use it for ticket purchases, paying less than $p(\ell)$ per ticket. This arbitrage creates buy pressure that restores the price. Similarly, if BURNIE is cheap relative to decimator expected value, rational players buy BURNIE to burn for decimator entries. Both arbitrage mechanisms create structural price floors. $\square$

### 9.5 Conditions for Protocol Failure

**Theorem 9.2** (Necessary Conditions for Game Death). *The Degenerus Protocol reaches GAMEOVER if and only if:*

$$\text{time since last level start} \geq \begin{cases} 912 \text{ days} & \text{if } \ell = 0 \\ 365 \text{ days} & \text{if } \ell \geq 1 \end{cases}$$

*This requires that for 365 consecutive days (or 912 at level 0), insufficient purchasing activity occurs to meet the current level's prize pool target and trigger a new level start. A single transaction does not suffice — the cumulative deposits must reach $\bar{P}_\ell$, which requires meaningful economic activity. Given that accumulated prize pools create increasing incentives for re-entry over this period, this remains a tail event, but it is more demanding than a single-action requirement.*

**Proposition 9.3** (Game Death Probability Bound). *Under the assumption that at least one player monitors on-chain prize pool sizes and acts rationally, the probability of game death is bounded by the probability that the total purchasing activity across all players over a 365-day window fails to meet the current level's prize pool target. For levels with small targets (early levels at 0.01 ETH/ticket) this requires very little activity; for later levels with higher targets, stETH yield on accumulated deposits contributes passively to pool growth.*

*For any non-trivial accumulated pool (e.g., $P > 10$ ETH), the combination of stETH yield and the "buy low" attractor (growing prize pools with fewer competitors) makes failure to reach the target improbable under standard rational actor assumptions.*

### 9.6 Endgame Distribution

Even in the GAMEOVER state, the protocol provides well-defined terminal payoffs:

1. **Deity pass refunds:** Level 0 → full refund; levels 1–9 → 20 ETH/pass; level 10+ → no refund
2. **BAF jackpot:** 50% of remaining assets distributed to trait-ticket holders
3. **Decimator jackpot:** Remaining surplus to decimator participants
4. **Final sweep:** After 30 days, unclaimed funds → vault and DGNRS reserves

This ensures that the game's terminal state is well-defined and that accumulated value is distributed rather than destroyed.

---

## 10. Comparison to Alternative Systems

### 10.1 Traditional Casino Gambling

| Property | Casino | Degenerus Protocol |
|----------|--------|--------------------|
| House edge | 2–15% | 0% (zero rake) |
| Value source | Player losses | stETH yield (external) |
| Sum type | Negative-sum | Positive-sum |
| Fairness | Opaque RNG | Chainlink VRF (verifiable) |
| Mutability | House can change rules | Immutable contracts |
| Engagement rewards | Loyalty programs (opaque) | Activity score (transparent, on-chain) |

The fundamental structural difference is the positive-sum nature of the Degenerus Protocol. In a casino, every dollar won by a player is a dollar lost by another player (minus the house edge). In Degenerus, stETH yield injects external value, making it possible for the player pool to collectively earn more than they deposit.

### 10.2 DeFi Yield Protocols

| Property | DeFi Yield | Degenerus Protocol |
|----------|------------|--------------------|
| Yield source | Similar (staking, lending) | stETH staking |
| Variance | Low (predictable APY) | High (jackpots, lotteries) |
| Engagement model | Passive deposits | Active participation rewarded |
| Token value | Often inflationary (farm-and-dump) | BURNIE: burn-on-use, deflationary |
| Capital efficiency | Extractive (yield farmers rotate) | Illiquid (future tickets, streaks) |

The key innovation is *variance as a defensive moat*. Traditional DeFi protocols suffer from extractive capital: yield farmers who deposit, harvest yield, and exit. The Degenerus Protocol's high variance, *level-advancement-gated* rewards, and illiquid prize structure (future tickets, burn-on-use tokens) naturally repel extractive capital. Critically, the "time" gating is not calendar-based but *progression-based*: rewards unlock as new levels are reached, and new levels require the prize pool threshold to be met, which requires ETH to enter the system. This means reward velocity is directly tied to economic activity rather than the passage of time — a design that further penalizes passive or extractive strategies. Only players who value the entertainment and engagement aspects remain, and these players' continued participation *is* the system's health.

**Proposition 10.1** (Variance as Filter). *Let the set of potential participants be $\mathcal{P} = \mathcal{P}_{engage} \cup \mathcal{P}_{extract}$, where $\mathcal{P}_{engage}$ values entertainment ($\gamma > 0$) and $\mathcal{P}_{extract}$ values only expected returns ($\gamma = 0$). A system with high variance $\text{Var}[\text{payout}]$ and moderate expected value $\mathbb{E}[\text{payout}] \approx 1$ will attract $\mathcal{P}_{engage}$ (who value variance positively or neutrally) and repel $\mathcal{P}_{extract}$ (who discount variance and see only the moderate EV after accounting for opportunity cost). The resulting participant pool is concentrated in $\mathcal{P}_{engage}$, whose continued participation sustains the system.*

### 10.3 Speculative Token Projects

| Property | Speculative Token | Degenerus Protocol |
|----------|-------------------|--------------------|
| Yield source | New buyers (ponzi dynamics) | stETH yield (real, external) |
| Terminal value | Zero (no intrinsic utility) | Non-zero (game utility, yield claims) |
| Supply dynamics | Inflationary (vesting, farming) | BURNIE: net deflationary; DGNRS: fixed |
| Growth dependency | Fatal (requires perpetual growth) | Non-fatal (yield continues without growth) |

The critical distinction is the *source of returns*. Speculative tokens fail when growth stalls because earlier investors' returns depend on later investors' capital. In the Degenerus Protocol, investor returns (DGNRS holders, vault participants) derive *primarily* from the spending of the degen player class — entertainment-motivated players whose ticket purchases, Degenerette bets, and lootbox openings fund prize pools and generate commissions. The stETH yield (~2.5%) functions as a *backstop* rather than the primary return driver: it ensures prize pools grow even during low-activity periods, preventing the system from stalling entirely. This means the protocol is not growth-*dependent* (new players are beneficial but not necessary for survival), while the primary economic engine is the cross-subsidy from entertainment spenders to strategic investors (see Section 2.1.3).

### 10.4 Prediction Markets

| Property | Prediction Market | Degenerus Protocol |
|----------|-------------------|--------------------|
| Information requirement | Domain expertise required | No information advantage possible |
| Outcome basis | Real-world events | On-chain randomness (VRF) |
| Skill component | High (informed trading) | Moderate (engagement optimization) |
| Zero-sum | Yes (winner's gain = loser's loss) | No (positive-sum from yield) |

---

## 11. Conclusion

### 11.1 Summary of Results

We have established the following results for the Degenerus Protocol:

1. **Equilibrium existence:** The game possesses at least two Nash equilibria — active participation and inactivity — with the active participation equilibrium being payoff-dominant, risk-dominant, and evolutionarily stable (Theorems 6.1–6.3).

2. **Behavioral incentive compatibility:** The activity score mechanism ensures that individually optimal behavior for all rational player types contributes positively to system health (Theorem 5.1). This is achieved without explicit coordination or punishment strategies — the mechanism design structurally aligns incentives.

3. **Strict budget balance:** The protocol maintains strict budget balance at all times, with a continuous surplus generated by stETH yield (Theorem 5.3). This is enforced on-chain through invariant checks in every contract module.

4. **Death spiral resistance:** The protocol resists death spirals through prize pool concentration (per-capita share increases as players exit), yield independence (stETH yield continues regardless of activity), and locked liquidity (prize pools are non-withdrawable) (Theorem 9.1).

5. **Forward-pushing dynamics:** Every rational player type's optimal strategy involves actions that advance the game, creating multiple independent progression guarantors that make game stalling a near-impossibility under active play (Theorem 7.2).

6. **Commitment devices:** The illiquidity structure of rewards (future tickets, burn-on-use tokens, streak-breaking costs, auto-compounding) creates powerful commitment devices that transform the game's payoff structure to favor continued participation, with retention forces that are quadratic in engagement depth (Propositions 7.1–7.2).

### 11.2 The Indestructibility Thesis

We can now formally state and evaluate the protocol's central claim:

**Thesis (Indestructibility by Design).** *Once the Degenerus Protocol has reached a state with positive prize pools and at least one rational participant, the game will continue to advance through levels indefinitely, because:*

*(a) Every rational player type's dominant strategy pushes the game forward (Theorem 7.2)*

*(b) Prize pool accumulation from stETH yield ensures growing incentives to participate, even during low-activity periods (Theorem 9.1)*

*(c) The commitment device structure makes exit increasingly costly as engagement deepens (Propositions 7.1–7.2)*

*(d) Multiple redundant progression guarantors make stalling require simultaneous failure of all independent mechanisms (Proposition 7.3)*

**Evaluation:** The thesis holds under the following conditions:
- stETH yield rate $r > 0$ (Lido continues functioning)
- At least one rational actor monitors and acts on prize pool opportunities
- Ethereum remains operational as a settlement layer
- Smart contract code is free of critical bugs (assured by immutability post-deployment)

The thesis *fails* if:
- Lido staking yield goes to zero permanently (systemic ETH staking failure)
- All participants simultaneously become irrational or cease to value the entertainment product
- A critical smart contract vulnerability is discovered (mitigated by immutability but not impossible)
- Regulatory action prevents all participation globally

These failure modes represent tail risks outside the protocol's design scope — they would affect any on-chain system equally.

### 11.3 Limitations and Future Work

This analysis has several limitations:

1. **Behavioral assumptions.** We assume standard rationality for most player types. Real participants exhibit bounded rationality, loss aversion, and behavioral biases that could shift equilibrium dynamics.

2. **Market externalities.** We treat ETH price and stETH yield as exogenous parameters. In reality, large prize pool accumulation could create MEV opportunities or influence ETH staking dynamics.

3. **Regulatory risk.** The game-theoretic analysis assumes a permissionless environment. Regulatory constraints on on-chain gambling could alter the participant pool and invalidate equilibrium results.

4. **Empirical validation.** All results are theoretical, derived from contract code analysis and rational actor modeling. Empirical validation requires observing actual player behavior post-deployment.

5. **Long-horizon dynamics.** The analysis focuses on stage-game and medium-horizon dynamics. Very long-horizon effects (hundreds of levels, years of play) may reveal emergent dynamics not captured by the current model.

Future work should address these limitations through agent-based simulation, empirical observation of the deployed protocol, and extension of the model to include behavioral types with non-standard utility functions.

### 11.4 Concluding Remarks

The Degenerus Protocol represents a novel point in the mechanism design space: a zero-rake, yield-funded gaming system where the dominant strategy for all participant types is continued engagement. The combination of external value injection (stETH yield), structural incentive alignment (activity score), and commitment devices (illiquidity, streaks, auto-compounding) creates a system that is formally robust to extraction, deviation, and coordinated attack under the conditions specified.

Whether this theoretical robustness translates to empirical resilience is an open question that only deployment and observation can answer. The game theory, however, is sound: the incentives point the right direction, the equilibria are stable, and the failure modes are extreme. By the standards of mechanism design, this is a well-constructed system.

---

## References

- Clark, L., Lawrence, A. J., Astley-Jones, F., and Gray, N. (2009). "Gambling Near-Misses Enhance Motivation to Gamble and Recruit Win-Related Brain Circuitry." *Neuron*, 61(3), 481–490.
- Fudenberg, D. and Maskin, E. (1986). "The Folk Theorem in Repeated Games with Discounting or with Incomplete Information." *Econometrica*, 54(3), 533–554.
- Griffiths, M. D. (1991). "Psychobiology of the Near-Miss in Fruit Machine Gambling." *The Journal of Psychology*, 125(3), 347–357.
- Kahneman, D. and Tversky, A. (1979). "Prospect Theory: An Analysis of Decision under Risk." *Econometrica*, 47(2), 263–291.
- Lazear, E. P. and Rosen, S. (1981). "Rank-Order Tournaments as Optimum Labor Contracts." *Journal of Political Economy*, 89(5), 841–864.
- Maskin, E. (1999). "Nash Equilibrium and Welfare Optimality." *Review of Economic Studies*, 66(1), 23–38.
- McGonigal, J. (2011). *Reality Is Broken: Why Games Make Us Better and How They Can Change the World*. Penguin Press.
- Myerson, R. B. (1981). "Optimal Auction Design." *Mathematics of Operations Research*, 6(1), 58–73.
- Nash, J. (1951). "Non-Cooperative Games." *Annals of Mathematics*, 54(2), 286–295.
- Schelling, T. C. (1960). *The Strategy of Conflict*. Harvard University Press.
- Shapley, L. S. (1953). "Stochastic Games." *Proceedings of the National Academy of Sciences*, 39(10), 1095–1100.
- Skinner, B. F. (1957). "Schedules of Reinforcement." *Journal of the Experimental Analysis of Behavior*, 1(1).
- Tullock, G. (1980). "Efficient Rent Seeking." In *Toward a Theory of the Rent-Seeking Society*, ed. Buchanan, Tollison, and Tullock. Texas A&M University Press.
- Zichermann, G. and Cunningham, C. (2011). *Gamification by Design: Implementing Game Mechanics in Web and Mobile Apps*. O'Reilly Media.

---

## Appendix A: Parameter Summary

| Parameter | Symbol | Value | Role in Analysis |
|-----------|--------|-------|-----------------|
| stETH yield rate | $r$ | 0.03–0.05 | External value injection |
| Activity score range | $a_i$ | [0, 3.05] | Incentive multiplier |
| Lootbox EV range | $\mu(a)$ | [0.80, 1.35] | Engagement reward (saturates at $a = 2.55$) |
| Degenerette ROI range | $\rho(a)$ | [0.90, 0.999] | Engagement reward |
| Lootbox EV cap | — | 10 ETH/level/account | Extraction bound |
| Degenerette ETH cap | — | 10% of future pool | Solvency guarantee |
| Coinflip win rate | — | 0.50 | Fair game |
| Coinflip reward mean | — | 0.9685 | Slight negative EV |
| Affiliate commission | — | 0.20–0.25 | Referral incentive |
| Ticket price range | $p(\ell)$ | 0.01–0.24 ETH | Entry cost scaling |
| Whale bundle price | — | 2.4–4 ETH | Catch-up mechanism |
| Deity pass base price | — | 24 ETH + $T(n)$ | Whale commitment |
| Deity pass cap | — | 32 total | Concentration limit |
| Pre-game timeout | — | 912 days | Liveness guard |
| Post-game timeout | — | 365 days | Liveness guard |
| VRF retry timeout | — | 18 hours | RNG liveness |
| Emergency stall gate | — | 3 days | VRF recovery |
| Quest daily reward | — | 300 BURNIE | Engagement incentive |
| Bootstrap prize pool | — | 50 ETH | Minimum pool guarantee |
| BAF leaderboard reset | — | Every 10 levels | Anti-concentration |
| Jackpots per level | — | 5 daily | Distribution frequency |
| Scatter share of jackpot | — | ~50% | Broad distribution |
| Auto-rebuy ticket bonus | — | 30%/45% | Compounding incentive |

## Appendix B: Formal Game-Theoretic Definitions

For reference, we collect the formal definitions used throughout the paper.

**Nash Equilibrium.** A strategy profile $\sigma^* = (\sigma_1^*, \ldots, \sigma_n^*)$ is a Nash equilibrium if for all players $i$ and all alternative strategies $\sigma_i'$:
$$u_i(\sigma_i^*, \sigma_{-i}^*) \geq u_i(\sigma_i', \sigma_{-i}^*)$$

**Subgame Perfect Equilibrium.** A strategy profile $\sigma^*$ is a subgame perfect equilibrium if it induces a Nash equilibrium in every subgame of $\Gamma$.

**Dominant Strategy.** A strategy $\sigma_i^*$ is dominant for player $i$ if for all $\sigma_{-i}$:
$$u_i(\sigma_i^*, \sigma_{-i}) \geq u_i(\sigma_i', \sigma_{-i}) \quad \forall \sigma_i'$$

**Individual Rationality.** A mechanism is individually rational if participation yields at least the outside option for all types: $\mathbb{E}[u_i(\sigma^*)] \geq u_i(\emptyset)$.

**Incentive Compatibility.** A mechanism is incentive-compatible if truthful behavior (or type-optimal play) is a best response for all types.

**Budget Balance.** A mechanism is budget-balanced if total payouts never exceed total inputs: $\sum_i \text{payout}_i \leq \sum_i \text{input}_i + \text{external value}$.

**Commitment Device.** An irreversible action that constrains future choice, transforming a multi-stage game's payoff structure to make cooperation or continuation incentive-compatible even when it would not be in a one-shot game.
