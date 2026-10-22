// Ordered CREATE deployments. Aliases share an owner and never consume a nonce.
export const DEPLOYMENTS = [
  {
    "key": "ICONS_32",
    "contract": "Icons32Data",
    "aliases": [
      "ICONS_32"
    ],
    "fixtureField": "icons32",
    "fixtureType": "Icons32Data"
  },
  {
    "key": "GAME_MINT_MODULE",
    "contract": "DegenerusGameMintModule",
    "aliases": [
      "GAME_MINT_MODULE"
    ],
    "fixtureField": "mintModule",
    "fixtureType": "DegenerusGameMintModule"
  },
  {
    "key": "GAME_ADVANCE_MODULE",
    "contract": "DegenerusGameAdvanceModule",
    "aliases": [
      "GAME_ADVANCE_MODULE"
    ],
    "fixtureField": "advanceModule",
    "fixtureType": "DegenerusGameAdvanceModule"
  },
  {
    "key": "GAME_WHALE_MODULE",
    "contract": "DegenerusGameWhaleModule",
    "aliases": [
      "GAME_WHALE_MODULE"
    ],
    "fixtureField": "whaleModule",
    "fixtureType": "DegenerusGameWhaleModule"
  },
  {
    "key": "GAME_JACKPOT_MODULE",
    "contract": "DegenerusGameJackpotModule",
    "aliases": [
      "GAME_JACKPOT_MODULE"
    ],
    "fixtureField": "jackpotModule",
    "fixtureType": "DegenerusGameJackpotModule"
  },
  {
    "key": "GAME_DECIMATOR_MODULE",
    "contract": "DegenerusGameDecimatorModule",
    "aliases": [
      "GAME_DECIMATOR_MODULE"
    ],
    "fixtureField": "decimatorModule",
    "fixtureType": "DegenerusGameDecimatorModule"
  },
  {
    "key": "GAME_GAMEOVER_MODULE",
    "contract": "DegenerusGameGameOverModule",
    "aliases": [
      "GAME_GAMEOVER_MODULE"
    ],
    "fixtureField": "gameOverModule",
    "fixtureType": "DegenerusGameGameOverModule"
  },
  {
    "key": "GAME_LOOTBOX_MODULE",
    "contract": "DegenerusGameBoxModule",
    "aliases": [
      "GAME_LOOTBOX_MODULE",
      "GAME_BOON_MODULE",
      "GAME_DEGENERETTE_MODULE",
      "GAME_AFKING_MODULE"
    ],
    "fixtureField": "boxModule",
    "fixtureType": "DegenerusGameBoxModule",
    "fixtureAliases": {
      "GAME_LOOTBOX_MODULE": {
        "field": "lootboxModule",
        "type": "DegenerusGameLootboxModule"
      },
      "GAME_BOON_MODULE": {
        "field": "boonModule",
        "type": "DegenerusGameBoonModule"
      },
      "GAME_DEGENERETTE_MODULE": {
        "field": "degeneretteModule",
        "type": "DegenerusGameDegeneretteModule"
      },
      "GAME_AFKING_MODULE": {
        "field": "afkingModule",
        "type": "GameAfkingModule"
      }
    }
  },
  {
    "key": "GAME_BINGO_MODULE",
    "contract": "DegenerusGameBingoModule",
    "aliases": [
      "GAME_BINGO_MODULE"
    ],
    "fixtureField": "bingoModule",
    "fixtureType": "DegenerusGameBingoModule"
  },
  {
    "key": "COIN",
    "contract": "FLIP",
    "aliases": [
      "COIN"
    ],
    "fixtureField": "coin",
    "fixtureType": "FLIP"
  },
  {
    "key": "COINFLIP",
    "contract": "Coinflip",
    "aliases": [
      "COINFLIP"
    ],
    "fixtureField": "coinflip",
    "fixtureType": "Coinflip"
  },
  {
    "key": "GAME",
    "contract": "DegenerusGame",
    "aliases": [
      "GAME"
    ],
    "fixtureField": "game",
    "fixtureType": "DegenerusGame"
  },
  {
    "key": "GAME_TICKET_MODULE",
    "contract": "DegenerusGameTicketModule",
    "aliases": [
      "GAME_TICKET_MODULE"
    ],
    "fixtureField": "ticketModule",
    "fixtureType": "DegenerusGameTicketModule"
  },
  {
    "key": "AFFILIATE",
    "contract": "DegenerusAffiliate",
    "aliases": [
      "AFFILIATE"
    ],
    "fixtureField": "affiliate",
    "fixtureType": "DegenerusAffiliate"
  },
  {
    "key": "JACKPOTS",
    "contract": "DegenerusJackpots",
    "aliases": [
      "JACKPOTS"
    ],
    "fixtureField": "jackpots",
    "fixtureType": "DegenerusJackpots"
  },
  {
    "key": "QUESTS",
    "contract": "DegenerusQuests",
    "aliases": [
      "QUESTS"
    ],
    "fixtureField": "quests",
    "fixtureType": "DegenerusQuests"
  },
  {
    "key": "DEITY_PASS",
    "contract": "DegenerusDeityPass",
    "aliases": [
      "DEITY_PASS"
    ],
    "fixtureField": "deityPass",
    "fixtureType": "DegenerusDeityPass"
  },
  {
    "key": "VAULT",
    "contract": "DegenerusVault",
    "aliases": [
      "VAULT"
    ],
    "fixtureField": "vault",
    "fixtureType": "DegenerusVault"
  },
  {
    "key": "SDGNRS",
    "contract": "sDGNRS",
    "aliases": [
      "SDGNRS"
    ],
    "fixtureField": "sdgnrs",
    "fixtureType": "sDGNRS"
  },
  {
    "key": "DGNRS",
    "contract": "DGNRS",
    "aliases": [
      "DGNRS"
    ],
    "fixtureField": "dgnrs",
    "fixtureType": "DGNRS"
  },
  {
    "key": "ADMIN",
    "contract": "DegenerusAdmin",
    "aliases": [
      "ADMIN"
    ],
    "fixtureField": "admin",
    "fixtureType": "DegenerusAdmin"
  },
  {
    "key": "GNRUS",
    "contract": "GNRUS",
    "aliases": [
      "GNRUS"
    ],
    "fixtureField": "gnrus",
    "fixtureType": "GNRUS"
  },
  {
    "key": "GAME_FOILPACK_MODULE",
    "contract": "DegenerusGameFoilPackModule",
    "aliases": [
      "GAME_FOILPACK_MODULE"
    ],
    "fixtureField": "foilModule",
    "fixtureType": "DegenerusGameFoilPackModule"
  },
  {
    "key": "AFKING_SUB_TOKEN",
    "contract": "AFKingSubscriptionToken",
    "aliases": [
      "AFKING_SUB_TOKEN"
    ],
    "fixtureField": "afkingSubToken",
    "fixtureType": "AFKingSubscriptionToken"
  },
  {
    "key": "PARIMUTUEL",
    "contract": "DegenerusParimutuel",
    "aliases": [
      "PARIMUTUEL"
    ],
    "fixtureField": "parimutuel",
    "fixtureType": "DegenerusParimutuel"
  },
  {
    "key": "RECORD_BOUNTY",
    "contract": "DegenerusRecordBounty",
    "aliases": [
      "RECORD_BOUNTY"
    ],
    "fixtureField": "recordBounty",
    "fixtureType": "DegenerusRecordBounty"
  },
  {
    "key": "CRAPS",
    "contract": "CrapsBattle",
    "aliases": [
      "CRAPS"
    ],
    "fixtureField": "crapsBattle",
    "fixtureType": "CrapsViews"
  },
  {
    "key": "CRAPS_ENGINE",
    "contract": "CrapsEngine",
    "aliases": [
      "CRAPS_ENGINE"
    ],
    "fixtureField": "crapsEngine",
    "fixtureType": "CrapsEngine"
  },
  {
    "key": "JACKPOT_BATTLE",
    "contract": "JackpotBattle",
    "aliases": [
      "JACKPOT_BATTLE"
    ],
    "fixtureField": "jackpotBattle",
    "fixtureType": "JackpotBattle"
  },
  {
    "key": "WWXRP",
    "contract": "WWXRP",
    "aliases": [
      "WWXRP"
    ],
    "fixtureField": "wwxrp",
    "fixtureType": "WWXRP"
  },
  {
    "key": "GAME_MINER_MODULE",
    "contract": "DegenerusGameMinerModule",
    "aliases": [
      "GAME_MINER_MODULE"
    ],
    "fixtureField": "minerModule",
    "fixtureType": "DegenerusGameMinerModule"
  },
  {
    "key": "GAME_RNG_MODULE",
    "contract": "DegenerusGameRngModule",
    "aliases": [
      "GAME_RNG_MODULE"
    ],
    "fixtureField": "rngModule",
    "fixtureType": "DegenerusGameRngModule"
  },
  {
    "key": "GAME_JACKPOT_DRAW_MODULE",
    "contract": "DegenerusGameJackpotDrawModule",
    "aliases": [
      "GAME_JACKPOT_DRAW_MODULE"
    ],
    "fixtureField": "jackpotDrawModule",
    "fixtureType": "DegenerusGameJackpotDrawModule"
  },
  {
    "key": "GAME_DEGENESIS_MODULE",
    "contract": "DegenerusGameDegenesisModule",
    "aliases": [
      "GAME_DEGENESIS_MODULE"
    ],
    "fixtureField": "degenesisModule",
    "fixtureType": "DegenerusGameDegenesisModule"
  },
  {
    "key": "OWNER_GOVERNANCE",
    "contract": "DegenerusOwnerGovernance",
    "aliases": [
      "OWNER_GOVERNANCE"
    ],
    "fixtureField": "ownerGovernance",
    "fixtureType": "DegenerusOwnerGovernance"
  }
];

export function aliasOwners(rows = DEPLOYMENTS) {
  const owners = new Map();
  for (const row of rows) {
    if (!row.aliases.includes(row.key)) throw new Error(`Missing canonical alias: ${row.key}`);
    for (const alias of row.aliases) {
      if (owners.has(alias)) throw new Error(`Duplicate alias: ${alias}`);
      owners.set(alias, row.key);
    }
  }
  return owners;
}
export function expandAliases(values, rows = DEPLOYMENTS) {
  const result = new Map();
  for (const [alias, owner] of aliasOwners(rows)) {
    if (!values.has(owner)) throw new Error(`Missing deployment: ${owner}`);
    result.set(alias, values.get(owner));
  }
  return result;
}
