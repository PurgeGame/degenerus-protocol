import { formatEther, formatUnits } from "ethers";

function formatWithCommas(value) {
  return value.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatEth(wei) {
  if (wei === 0n) return "0 ETH";
  const ethValue = formatEther(wei);
  const [whole, frac = ""] = ethValue.split(".");

  // For very small values (< 0.0001), show more precision
  if (whole === "0" && frac.startsWith("0000")) {
    let nonZeroPos = 0;
    while (nonZeroPos < frac.length && frac[nonZeroPos] === "0") nonZeroPos++;
    const trimmedFrac = frac.slice(0, nonZeroPos + 3);
    return `0.${trimmedFrac} ETH`;
  }

  const trimmedFrac = frac.slice(0, 4);
  const base = formatWithCommas(whole);
  return trimmedFrac ? `${base}.${trimmedFrac} ETH` : `${base} ETH`;
}

function formatBurnie(wei) {
  const [whole] = formatUnits(wei, 18).split(".");
  return `${formatWithCommas(whole)} BURNIE`;
}

function formatTickets(count) {
  return formatWithCommas(count.toString());
}

function buildTable(title, headers, rows) {
  const widths = headers.map((header, idx) => {
    let max = header.length;
    for (const row of rows) {
      if (row[idx].length > max) max = row[idx].length;
    }
    return max;
  });

  const line = (left, mid, right, fill) =>
    left +
    widths.map((w) => fill.repeat(w + 2)).join(mid) +
    right;

  const rowLine = (left, mid, right, row) =>
    left +
    row
      .map((cell, idx) => ` ${cell.padEnd(widths[idx])} `)
      .join(mid) +
    right;

  const totalWidth =
    widths.reduce((sum, w) => sum + w + 2, 0) + (widths.length - 1);
  const center = (text, width) => {
    if (text.length >= width) return text.slice(0, width);
    const leftPad = Math.floor((width - text.length) / 2);
    const rightPad = width - text.length - leftPad;
    return " ".repeat(leftPad) + text + " ".repeat(rightPad);
  };

  const lines = [];
  lines.push(line("\u2554", "\u2564", "\u2557", "\u2550"));
  lines.push(`\u2551${center(title, totalWidth)}\u2551`);
  lines.push(line("\u2560", "\u256A", "\u2563", "\u2550"));
  lines.push(rowLine("\u2551", "\u2502", "\u2551", headers));
  lines.push(line("\u2560", "\u256A", "\u2563", "\u2550"));
  for (const row of rows) {
    lines.push(rowLine("\u2551", "\u2502", "\u2551", row));
  }
  lines.push(line("\u255A", "\u2567", "\u255D", "\u2550"));
  return lines.join("\n");
}

export class StatsTracker {
  constructor(players) {
    this.players = players;
    this.stats = players.map((player) => ({
      player: player.address,
      group: player.group,
      totalTickets: 0n,
      ethSpent: 0n,
      claimableWinnings: 0n,
      coinflipClaimable: 0n,
      totalFlipWins: 0,
      totalFlipLosses: 0,
      lootboxesPurchased: 0,
      passType: player.passType
    }));
    this.totalEthSpent = 0n;
    this.totalTicketsSold = 0n;
    this.totalCoinflipVolume = 0n;
    this.pendingFlipsByDay = new Map();
    this.levelSnapshots = new Map();
  }

  recordEthSpend(playerIndex, amount) {
    if (amount === 0n) return;
    this.stats[playerIndex].ethSpent += amount;
    this.totalEthSpent += amount;
  }

  recordTickets(playerIndex, count) {
    if (count === 0n) return;
    this.stats[playerIndex].totalTickets += count;
    this.totalTicketsSold += count;
  }

  recordLootboxPurchase(playerIndex, amount) {
    this.stats[playerIndex].lootboxesPurchased += 1;
    this.recordEthSpend(playerIndex, amount);
  }

  recordCoinflipDeposit(playerIndex, amount, targetDay) {
    if (amount === 0n) return;
    this.totalCoinflipVolume += amount;
    const list = this.pendingFlipsByDay.get(targetDay) || [];
    list.push(playerIndex);
    this.pendingFlipsByDay.set(targetDay, list);
  }

  recordCoinflipOutcome(day, win) {
    const list = this.pendingFlipsByDay.get(day) || [];
    if (list.length === 0) return;
    for (const idx of list) {
      if (win) {
        this.stats[idx].totalFlipWins += 1;
      } else {
        this.stats[idx].totalFlipLosses += 1;
      }
    }
    this.pendingFlipsByDay.delete(day);
  }

  recordCoinflipClaimable(playerIndex, amount) {
    this.stats[playerIndex].coinflipClaimable = amount;
  }

  async refreshCoinflipClaimables(coin) {
    for (let i = 0; i < this.players.length; i += 1) {
      try {
        const amount = await coin.previewClaimCoinflips(this.players[i].address);
        this.recordCoinflipClaimable(i, amount);
      } catch {
        // previewClaimCoinflips may not exist or revert
      }
    }
  }

  recordClaimableWinnings(playerIndex, amount) {
    this.stats[playerIndex].claimableWinnings = amount;
  }

  async refreshClaimableWinnings(game) {
    for (let i = 0; i < this.players.length; i += 1) {
      const amount = await game.claimableWinningsOf(this.players[i].address);
      this.recordClaimableWinnings(i, amount);
    }
  }

  recordLevelSnapshot(level, phase, data) {
    const key = `${level}-${phase}`;
    this.levelSnapshots.set(key, {
      level,
      phase,
      day: data.day,
      currentPrizePool: data.currentPrizePool,
      nextPrizePool: data.nextPrizePool,
      futurePrizePool: data.futurePrizePool,
      claimablePool: data.claimablePool,
      yieldPool: data.yieldPool || 0n,
      target: data.target,
      currentLevelTickets: data.currentLevelTickets || 0n,
      futureLevelTickets: data.futureLevelTickets || 0n
    });
  }

  getLevelSnapshot(level, phase) {
    return this.levelSnapshots.get(`${level}-${phase}`);
  }

  renderReport({ totalDays, finalLevel, mintPrice }) {
    const headers = ["Player", "Group", "Tickets", "ETH Spent", "Claimable ETH", "Coinflip"];
    const rows = this.stats.map((stat, idx) => [
      `${idx}`,
      stat.group,
      formatTickets(stat.totalTickets),
      formatEth(stat.ethSpent),
      formatEth(stat.claimableWinnings),
      formatBurnie(stat.coinflipClaimable)
    ]);

    const table = buildTable("PLAYER FINANCIAL SUMMARY", headers, rows);

    const totalClaimable = this.stats.reduce((sum, s) => sum + s.claimableWinnings, 0n);
    const totalCoinflip = this.stats.reduce((sum, s) => sum + s.coinflipClaimable, 0n);

    const ticketPrice = mintPrice ? mintPrice / 4n : 0n;
    const totalTicketValue = this.totalTicketsSold * ticketPrice;

    const aggregate = [
      "",
      "AGGREGATE FINANCIAL STATS:",
      `- Total Days Simulated: ${totalDays}`,
      `- Final Level Reached: ${finalLevel}`,
      `- Total Tickets Sold: ${formatTickets(this.totalTicketsSold)}`,
      `- Total ETH Spent: ${formatEth(this.totalEthSpent)}`,
      `- Total Ticket Value (at current price): ${formatEth(totalTicketValue)}`,
      `- Total Claimable Winnings: ${formatEth(totalClaimable)}`,
      `- Total Coinflip Claimable: ${formatBurnie(totalCoinflip)}`,
      `- Total Coinflip Volume: ${formatBurnie(this.totalCoinflipVolume)}`
    ];

    return `${table}\n${aggregate.join("\n")}`;
  }

  renderLevelPoolReport() {
    const lines = ["", "END-OF-LEVEL POOL & TICKET SUMMARY", "=".repeat(80)];

    const levels = new Set();
    for (const key of this.levelSnapshots.keys()) {
      const level = parseInt(key.split("-")[0]);
      levels.add(level);
    }

    for (const level of [...levels].sort((a, b) => a - b)) {
      const end = this.getLevelSnapshot(level, "end");
      if (!end) continue;

      lines.push(`\nLevel ${level} END (Day ${end.day}):`);
      lines.push(`  POOLS:`);
      lines.push(`    Claimable:  ${formatEth(end.claimablePool)}`);
      lines.push(`    Next:       ${formatEth(end.nextPrizePool)}`);
      lines.push(`    Current:    ${formatEth(end.currentPrizePool)}`);
      lines.push(`    Future:     ${formatEth(end.futurePrizePool)}`);
      lines.push(`    Yield:      ${formatEth(end.yieldPool)}`);
      lines.push(`  TICKETS:`);
      lines.push(`    Current Level: ${formatTickets(end.currentLevelTickets)}`);
      lines.push(`    Future Levels: ${formatTickets(end.futureLevelTickets)}`);
    }

    return lines.join("\n");
  }
}
