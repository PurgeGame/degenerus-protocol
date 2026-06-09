# Council Sweep 386 — PERIPHERAL CONTRACTS + cross-contract call seams

You are an external auditor on a cross-model council auditing the **Degenerus Protocol** before a Code4rena
audit. Read the EXACT frozen source at `c4d48008` via `git show c4d48008:contracts/<File>.sol` (ignore the
working tree). Concrete + reachable only.

**Threat priority:** solvency (redemption / reserve accounting) + RNG/freeze where the peripheral feeds the
game; then delegatecall selector correctness + reentrancy on external token calls.

**ALREADY FOUND (do NOT re-report):** V62-01 (lootbox auto-open off-by-one).

**KNOWN BY-DESIGN (do NOT flag):** Degenerette RTP>100% + worthless WWXRP; affiliate `claim` single-step
direct-mint; operator-approval IS the trust boundary; the C-2 stETH-strand redemption fix (`0f4e2a54`) is
in place; plus the other standing rulings (lootbox timing, claimBingo, PRESALE-01).

## Focus (PERIPH-01..06)

1. **`DegenerusVault` + `StakedDegenerusStonk` (PERIPH-02).** Redemption: re-verify the stETH-strand fix
   held; the redemption reserve + per-day accounting; can a redeemer strand ETH/stETH, double-redeem, or
   break the reserve identity? The protocol self-subscriber bootstrap exemptions (Vault / sStonk).
2. **`DegenerusAffiliate` (PERIPH-03).** The single-step direct-mint `claim` (≤3 creditFlips A/U1/U2):
   attribution correctness, double-claim, score→DGNRS allocation. (Cross-check the carried affiliate-score
   ~2500× magnitude + FC4 frozen-cancel `affiliateBase` drain if 382 did not resolve them.)
3. **`BurnieCoin` + `BurnieCoinflip` (PERIPH-04).** Mint/burn authority; the flip-credit RTP; the
   curse/decurse/smite burn sinks; can BURNIE be minted or a flip credited without authority / without the
   paired burn?
4. **`DegenerusStonk`/`GNRUS` + `DegenerusDeityPass` (PERIPH-05).** Soulbound ERC721 transfer gating; the
   smite `ownerOf` gate; the governance surface (GNRUS) + `DegenerusAdmin` VRF wiring / coordinator-swap.
5. **Cross-contract call seams (PERIPH-01/06).** delegatecall interface/selector correctness — does
   `IDegenerusGame` (and the other module interfaces) match the impls (a missing/renamed dispatch stub is
   the F-356-01 / claimAfkingBurnie bug class)? Reentrancy on the external token calls (stETH, BURNIE).

## Output (per finding)
PROPERTY · reachable CALL SEQUENCE · contract + `file:line` at `c4d48008` · SEVERITY · why protections don't
stop it. State explicitly any peripheral you verified clean and why.
