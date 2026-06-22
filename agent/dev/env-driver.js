// DEV-ONLY environment driver — a local stand-in for the SEPARATE sim repo.
//
// On the real testnet the sim repo runs the environment: the 15-min-day clock,
// real Chainlink VRF, stETH rebases, and honest 24/7 actors. To BUILD/validate
// the (purely connect-and-play) agent locally we need that environment too, so
// this fixture supplies it against a local hardhat/anvil node:
//   - advanceDay()      warp block.timestamp +86400 and mine (one game-day)
//   - fulfilPendingVrf() deliver a FAIR uniform random word to the mock VRF
//   - honest actors      a couple of wallets making honest purchases each day
//
// THIS IS NOT THE ATTACKER. The agent client never imports this file and never
// calls evm_* / VRF / stETH. Guard: refuses to run unless mode==="local".

import { ethers } from "ethers";

const MOCK_VRF_ABI = [
  "function lastRequestId() view returns (uint256)",
  "function fulfillRandomWords(uint256 requestId, uint256 randomWord)",
  "function resetFulfilled(uint256 requestId)",
];

export class EnvDriver {
  constructor(conn, cfg, walletPool) {
    if (cfg.mode !== "local") {
      throw new Error("EnvDriver refuses to run outside mode=local — driving the environment on a live testnet would not be an external attacker.");
    }
    this.conn = conn;
    this.cfg = cfg;
    this.provider = conn.provider;
    this.pool = walletPool;
    // Account 0 (deployer) drives — unlocked, well-funded.
    this.driver = ethers.HDNodeWallet.fromPhrase(
      "test test test test test test test test test test test junk", undefined, "m/44'/60'/0'/0/0"
    ).connect(this.provider);
    this.mockVrf = new ethers.Contract(conn.address("VRF_COORDINATOR"), MOCK_VRF_ABI, this.driver);
    this.game = conn.write("GAME", this.driver);
    this.honestCount = cfg.devDriver.honestActors ?? 2;
  }

  async warpOneDay() {
    await this.provider.send("evm_increaseTime", [this.cfg.devDriver.dayWarpSeconds]);
    await this.provider.send("evm_mine", []);
  }

  // Deliver a FAIR uniform 256-bit word (never steered). word==0 -> 1.
  async fulfilPendingVrf() {
    let reqId;
    try { reqId = await this.mockVrf.lastRequestId(); } catch { return { fulfilled: false }; }
    let word = BigInt(ethers.hexlify(ethers.randomBytes(32)));
    if (word === 0n) word = 1n;
    try {
      const tx = await this.mockVrf.fulfillRandomWords(reqId, word);
      await tx.wait();
      return { fulfilled: true, requestId: reqId.toString() };
    } catch (e) {
      // already fulfilled / no pending request — benign for a driver loop.
      return { fulfilled: false, reason: e.shortMessage || e.message };
    }
  }

  // Honest background traffic that also FILLS the level prize pool so levels
  // actually advance and the game stays live (a trickle of tiny buys would let
  // the idle-liveness backstop fire a premature game-over before any level
  // completes — mirrors MultiLevelHandler's heavy fill-to-target purchases).
  async honestActorsBuy() {
    if (await this.game.gameOver().catch(() => false)) return 0;
    let n = 0;
    for (let fill = 0; fill < 6; fill++) {
      const info = await this.game.purchaseInfo().catch(() => null);
      if (!info || info[3] /* rngLocked */ || info[1] /* jackpotPhase */) break;
      let next = 0n, target = 0n;
      try { next = await this.game.nextPrizePoolView(); target = await this.game.prizePoolTargetView(); } catch { /* */ }
      if (target > 0n && next >= target) break; // level ready to advance
      const price = info[4];
      const qty = 4000; // 10 whole tickets; trivial cost at /1e6 scale
      const cost = (price * BigInt(qty)) / 400n;
      const w = this.pool.get(fill % this.honestCount);
      try {
        const g = this.conn.write("GAME", w.signer);
        await (await g.purchase(w.address, qty, 0, ethers.ZeroHash, 0, false, { value: cost })).wait();
        n++;
      } catch { break; }
    }
    return n;
  }

  // Drive one full game-day honestly: honest buys -> cross boundary -> advance
  // (fire VRF) -> fulfil -> drain. Returns a small status object.
  async driveDay() {
    const bought = await this.honestActorsBuy();
    await this.warpOneDay();
    // A daily cycle needs advance(fire request) -> fulfil -> advance(seal/drain).
    // Mirror the handler pattern: advance-then-fulfil, looped, until the window
    // seals (rngLocked false) or no further progress. fulfil is a no-op when no
    // request is pending (the mock reverts "already fulfilled", caught benignly).
    const max = this.cfg.devDriver.maxAdvancePerTick ?? 4;
    let advanced = 0, fulfils = 0;
    for (let i = 0; i < max; i++) {
      // Clear any pending request FIRST — advanceGame reverts while a daily VRF
      // request is in flight and unfulfilled, so fulfil before advancing.
      let locked = false;
      try { locked = await this.game.rngLocked(); } catch { /* */ }
      if (locked) {
        const r = await this.fulfilPendingVrf();
        if (r.fulfilled) fulfils++;
      }
      try { await (await this.game.advanceGame()).wait(); advanced++; }
      catch { /* NotTimeYet once the day is sealed — stop */ break; }
    }
    let level = 0;
    try { level = Number(await this.game.level()); } catch { /* */ }
    return { bought, advanced, fulfils, vrf: { fulfilled: fulfils > 0 }, level };
  }
}
