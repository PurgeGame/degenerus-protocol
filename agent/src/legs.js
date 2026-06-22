// Per-actor value-leg reader — normalizes every leg to ONE numeraire: ETH wei.
//
// Numeraire rule (from the frozen source): stETH is valued 1:1 with ETH (the
// protocol sums ETH+stETH at parity everywhere). FLIP and the in-game soft
// tokens have NO fixed ETH price; their realizable ETH value is read LIVE from
// the redemption/preview views (never hardcoded — the /1e6 testnet would break
// any hardcoded rate). WWXRP has no backing at all (ETH value 0; tracked only
// as a Degenerette bet input).
//
// ETH-equivalent realizable position of an actor =
//   walletETH + claimable + afking
//   + sDGNRS.previewBurn(bal).eth+steth + DGNRS.previewBurn(bal).eth+steth
//   + (optional) vault DGVE/DGVF, GNRUS share
// FLIP / WWXRP are tracked raw for the betting-EV oracle, NOT in the numeraire
// total (counting protocol-minted FLIP as ETH would falsely break conservation).

import { ethers } from "ethers";

const ERC20_BAL = ["function balanceOf(address) view returns (uint256)"];

export async function readLegs(conn, address) {
  const a = ethers.getAddress(address);
  const g = conn.game;
  const legs = {
    address: a,
    wei: { eth: 0n, claimable: 0n, afking: 0n, sdgnrsEth: 0n, dgnrsEth: 0n },
    raw: { flip: 0n, sdgnrs: 0n, dgnrs: 0n, wwxrp: 0n },
    notes: [],
  };

  // Real ETH legs ------------------------------------------------------------
  legs.wei.eth = await conn.provider.getBalance(a);

  await safe(legs, "claimable", async () => {
    const raw = await g.claimableWinningsOf(a); // includes 1-wei sentinel
    legs.wei.claimable = raw > 1n ? raw - 1n : 0n; // spendable value strips sentinel
  });
  await safe(legs, "afking", async () => {
    legs.wei.afking = await g.afkingFundingOf(a);
  });

  // Redemption-backed soft tokens — priced live via previewBurn -------------
  await safe(legs, "sdgnrs", async () => {
    const bal = await conn.sdgnrs.balanceOf(a);
    legs.raw.sdgnrs = bal;
    if (bal > 0n) {
      const [ethOut, stethOut] = await conn.sdgnrs.previewBurn(bal);
      legs.wei.sdgnrsEth = ethOut + stethOut; // FLIP leg tracked separately
    }
  });
  await safe(legs, "dgnrs", async () => {
    const bal = await conn.dgnrs.balanceOf(a);
    legs.raw.dgnrs = bal;
    if (bal > 0n) {
      const [ethOut, stethOut] = await conn.dgnrs.previewBurn(bal);
      legs.wei.dgnrsEth = ethOut + stethOut;
    }
  });

  // Non-numeraire tracked legs (FLIP position; WWXRP bet input) --------------
  await safe(legs, "flip", async () => {
    // balanceOfWithClaimable = held + claimable coinflip winnings (true position)
    legs.raw.flip = await conn.coin.balanceOfWithClaimable(a);
  });
  await safe(legs, "wwxrp", async () => {
    const w = new ethers.Contract(conn.address("WWXRP"), ERC20_BAL, conn.provider);
    legs.raw.wwxrp = await w.balanceOf(a);
  });

  legs.ethEquivWei =
    legs.wei.eth +
    legs.wei.claimable +
    legs.wei.afking +
    legs.wei.sdgnrsEth +
    legs.wei.dgnrsEth;
  return legs;
}

async function safe(legs, leg, fn) {
  try {
    await fn();
  } catch (e) {
    legs.notes.push(`${leg}: read failed (${e.shortMessage || e.message})`);
  }
}

// Convenience: ETH-equivalent realizable total only.
export async function ethEquiv(conn, address) {
  return (await readLegs(conn, address)).ethEquivWei;
}
