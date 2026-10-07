// SPDX-License-Identifier: AGPL-3.0-only
// Public event ABI contracts. Runtime event/payout/queue correspondence lives in
// LootboxTicketLanesFlush, LootboxOpenGoldens, BoxResolutionIds and DailyEthTicketLegEntries.
import { expect } from "chai";
import hre from "hardhat";

async function eventFragment(contract, name) {
  const { abi } = await hre.artifacts.readArtifact(contract);
  return new hre.ethers.Interface(abi).getEvent(name);
}

describe("Gameplay event ABI", function () {
  it("LootBoxOpened identifies the account and exposes scaled tickets with rounding", async function () {
    const event = await eventFragment("DegenerusGameLootboxModule", "LootBoxOpened");
    expect(event.inputs.map((field) => [field.name, field.type, field.indexed])).to.deep.equal([
      ["id", "uint32", true],
      ["lootboxIndex", "uint48", true],
      ["amount", "uint256", false],
      ["futureLevel", "uint24", false],
      ["futureTickets", "uint32", false],
      ["flip", "uint256", false],
      ["roundedUp", "bool", false],
    ]);
  });

  it("JackpotTicketWin has the same ID and rounding ABI in both emitting modules", async function () {
    for (const module of ["DegenerusGameTicketModule", "DegenerusGameJackpotDrawModule"]) {
      const event = await eventFragment(module, "JackpotTicketWin");
      expect(event.inputs.map((field) => [field.type, field.indexed]), module).to.deep.equal([
        ["uint32", true], ["uint24", true], ["uint16", true],
        ["uint32", false], ["uint24", false], ["uint256", false], ["bool", false],
      ]);
      expect(event.inputs.at(-1).name).to.equal("roundedUp");
    }
  });
});
