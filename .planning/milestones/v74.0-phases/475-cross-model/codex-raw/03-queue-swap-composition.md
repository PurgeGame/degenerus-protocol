Static review found one terminal RNG-freeze defect. The widened returns, decode guards, and fail-open swap were sound.

FINDINGS:

1. CATASTROPHE | contracts/storage/DegenerusGameStorage.sol:644 | Post-reveal tickets can be ground into the terminal jackpot | Near-level tickets may be queued during liveness/RNG lock, while game-over later swaps and drains the write slot using the disclosed terminal word. Concrete trigger: keep the read queue larger than one batch, let game-over commit its word and process one partial batch, then selectively open precommitted lootboxes that award level+1 tickets; those tickets enter the write slot and are subsequently included. An attacker can simulate candidate addresses, opening order, generated traits, and terminal bucket indexes off-chain, making capture of a disproportionate share of the 90% terminal ticket pool profitable when that pool is material.
