# Storage packing

Bit ranges are inclusive and count from the least significant bit. A lane-relative range must be
offset by the lane position in its containing word. Unlisted bits are unused unless a row explicitly
names a retained sentinel. A nonzero retained word does not imply a live entitlement. Check tags,
counts and cursors before reading reused data. Monetary units are in [Token units](TOKEN-UNITS.md);
the accounting consequences are in [Accounting](ACCOUNTING.md).

The manual tables follow the production shifts, masks, casts and assembly writers. The compiler
appendix gives every storage field and storage-resident struct for EIP-170 hosts, including
namespaced Quests and Affiliate structs. The source links identify the corresponding accessors.
Slots for Game, CrapsBattle, Coinflip, sDGNRS and the other buildable hosts can be cross-checked
with `forge inspect <Contract> storageLayout --json --skip test` using the scratch environment in
[Testing](TESTING.md). The reference generator regenerates the compiler appendix without editing
production Solidity. The temporary namespace harness only requests type layout metadata.

## Game balances, identity and control

Source: [contracts/storage/DegenerusGameStorage.sol](../contracts/storage/DegenerusGameStorage.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `prizePoolsPacked` | 0–127; 128–255 | Next pool; future pool (`POOL_FUTURE_SHIFT`). |
| `prizePoolPendingPacked` | 0–127; 128–254; 255 | Pending next; pending future; retained sentinel. |
| `balancesPacked[id]` | 0–127; 128–255 | Claimable including the 1-wei sentinel; prepaid AFKing. |
| `wallets[id]` | 0–159; 160–191; 192–255 | Payout/seller address; parent/buyer wallet ID; whale half-pass count. |
| `walletIds[address]` | 0–31; 32–63 | Current gameplay account; immutable wallet identity. |
| `_smurfWords[id][i/8]` | 32k–32k+31, k=i%8 | Eight child wallet IDs. |
| `dailyTicketBudgetsPacked` | 0–7; 8–71; 72; 73; 74–143; 144–207; 208–255 | Reserved; daily entries; battle pending; retained; unused; early-bird entries; purchase entries. |
| `gameOverStatePacked` | 0–47; 48–55; 56–63; 64–71; 72–103 | Terminal payout timestamp; jackpot paid; swept; loan-step offset; loan index (`GO_*`). |
| `playerClaimWord[id]` | 0–24; 25–49; 50–73 | Even/odd bingo level+1 stamps; affiliate-claim level. |
| `levelDgnrsPacked` | 0–127; 128–254; 255 | Allocation; claimed amount; retained. |
| `levelPrizePool[lvl&3]` | 0–127; 128–255 | Pool amount; level+1 tag. |
| `ticketGenerationStartBlock` | 0–23; 24–255 | Level; first generation block. |
| `rngFlagsAndNudges` | 0–7; 8; 9; 10; 11; 12; 13; 14; 15 | Nudge count; RNG complete; redemption open; retry spent; growth pending; write buffer; terminal; request active; published. |
| `decimatorFlags` | 0; 1; 2 | Burn window open; opening-day quest/entry; loans due pending. |
| `jackpotFlags` | 0; 1 | Turbo schedule; turbo coinflip bonus pending. |
| `ticketBufferLevels` | 0–23; 24–47 | Even/odd physical ticket buffer level tags. |
| `rngDayTags` | 0–23; 24–47 | Absolute day tags for the two RNG slots. |
| `centuryBonusUsed[id]` | 0–223; 224–255 | Used bonus value; level stamp. |
| `_loans[id]` | 0–95; 96–103; 104–127; 128–151; 152–183; 184–191; 255 | Principal wei; lender ID; start level; due level; due-list index; family subscriptions; retained. |
| `_loansDue[due][i/8]` | 32k–32k+31, k=i%8 | Eight due account IDs. |
| `degenesisActive` | 0–79; 80–159; 160–183; 184–215 | Q budget; paid sDGNRS; bound day; settlement cursor (`GA_*`). |
| `degenesisDays[day]` | 0–47; 48–79; 80 | Volume in `DEGENESIS_UNIT`; order count; split flag. |
| `degenesisOrders[key]` | Three 85-bit lanes at 85k | Lane: ID 0–31; amount units 32–69; seconds into day 70–84. Bit 255 unused. |

## Mint history

Source: [contracts/libraries/BitPackingLib.sol](../contracts/libraries/BitPackingLib.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `mintPacked_[id]` | 0–23 | Last purchased level (`LAST_LEVEL_SHIFT`). |
| `mintPacked_[id]` | 24–47 | Level count (`LEVEL_COUNT_SHIFT`). |
| `mintPacked_[id]` | 48–71 | Level streak (`LEVEL_STREAK_SHIFT`). |
| `mintPacked_[id]` | 72–95 | Last purchase day (`DAY_SHIFT`). |
| `mintPacked_[id]` | 96–119 | Unit-tracking level (`LEVEL_UNITS_LEVEL_SHIFT`). |
| `mintPacked_[id]` | 120–143 | Frozen-until level (`FROZEN_UNTIL_LEVEL_SHIFT`). |
| `mintPacked_[id]` | 144–145; 146; 147 | Pass type; seat claimed; smurf flag. |
| `mintPacked_[id]` | 148–171; 172 | Last streak-completed level; deity-pass flag. |
| `mintPacked_[id]` | 173–196; 197–202; 203–207 | Affiliate bonus level; bonus points; curse count. |
| `mintPacked_[id]` | 208–223; 224–239; 240–255 | Level units; lifetime smurf count; base smurf allowance. |

## Game RNG, queues and ticket buckets

Source: [contracts/storage/DegenerusGameStorage.sol](../contracts/storage/DegenerusGameStorage.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `lootboxRngPacked` | 0–23; 24–29; 30–37; 38 | Hero request day; three valid-quadrant bits per buffer; basefee ceiling; hero write buffer. |
| `lootboxRngPacked` | 48–87; 88–119 | Pending ETH and threshold, both in 0.001 ETH units (`LR_*`). |
| `lootboxRngPacked` | 120–151; 152–183; 184–223 | Box count; bet count; pending whole FLIP. |
| `lootboxRngPacked` | 224–231; 232–239; 240–247; 248; 250–251 | Mid-day kind; dead ending; terminal level latch; terminal request; Craps pending per buffer. |
| `boxQueue[buffer]` | Three 85-bit lanes at 85k | Lane: ID 0–31, value units 32–52, score code 53–64, boost 65–76, quantity 77–83, distress 84. Bit 255 unused. |
| `boxOrder (input)` | 0–6; 7–8; 9–29 | Quantity; kind; custom units (`BO_*`). |
| `degeneretteQueue[buffer]` | Two 128-bit lanes at 128k | Lane: ID 0–31; symbol 32–36; spins 37–41; currency 42; record 43; activity 44–59; stake 60–123; reserved 124–127. |
| `ticketQueue[key] header` | 0–31; 32–55 | Queued-owner count; exact level. Array payload is eight uint32 IDs per word, not eight Solidity elements. |
| `ticketPending[id]` | Four 42-bit lanes at 0, 42, 84, 126 | Even A/B then odd A/B: remainder 0–7; owed 8–39; snap 40; present 41. |
| `ticketPending[id]` | 168–191; 192–215; 255 | Even/odd exact level tags; retained sentinel. |
| `farFutureOwed[id]` | Eight 32-bit lanes per word, 100 circular levels | Lane: owed 0–29; snap 30; present 31. Thirteen words hold the ring; queue tags authenticate the cycle. |
| `entryPacked (memory)` | 0–7; 8–39; 40; 48–79 | Remainder; owed; snap; wallet ID (`OWNER_IDX_SHIFT`). |
| `lvlTraitEntry[parity][trait]` | 0–31; seven 32-bit lanes from 32 | Occurrence count; unfinished tail IDs. Full groups use hashed payload words with eight uint32 IDs. |
| `traitBucketLive[parity]` | Bit t | Trait header t is initialized for the buffer tag. |
| `ticketSeats` | Eight 32-bit lanes | Queue indices plus one; zero lane is empty. |
| `deadClaimed[key]` | Bit occurrence%256 | Claim bitmap; key combines trait and occurrence/256. |
| `dailyHeroWagers[buffer][quadrant]` | Eight 32-bit lanes | Saturating weights by symbol; validity is in `lootboxRngPacked`. |
| `deityPassIds payload` | Eight 32-bit lanes | Registered deity wallet IDs; `_deityIdAt` decodes them. |
| `deityBySymbol[symbol]` | 0–31 | Deity wallet ID; remaining bits are not another holding. |
| `lootboxEvCapPacked[id]` | 0–71; 72–95; 96–167; 168–191 | Used bonus spend A; level A; used spend B; level B. |

## Game boon, subscriber, foil and battle words

Source: [contracts/storage/DegenerusGameStorage.sol](../contracts/storage/DegenerusGameStorage.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `boonPacked[id].slot0` | 0–23; 24–47; 48–55 | Coinflip award day; deity day; tier (`BP_*`). |
| `boonPacked[id].slot0` | 56–79; 80–103; 104–111 | Lootbox award day; deity day; tier. |
| `boonPacked[id].slot0` | 112–135; 136–159; 160–167 | Purchase award day; deity day; tier. |
| `boonPacked[id].slot0` | 168–175; 176–199 | Decimator tier; deity day. |
| `boonPacked[id].slot0` | 200–223; 224–247; 248–249; 255 | Whale award day; deity day; tier; retained. |
| `boonPacked[id].slot1` | 0–23; 24; 72–79; 80–103; 104–127 | Craps lane; retained; deity-pass tier; award day; deity day. |
| `boonPacked[id].slot1` | 128–151; 152–175; 176–183 | Lazy-pass award day; deity day; tier. |
| `boonPacked[id].slot1` | 184–207; 208–231; 232–255 | Degenerette ETH, Degenerette FLIP and WWXRP lanes. |
| `24-bit boon lane` | 0–1; 2; 3–23 | Tier; deity-source flag; low 21 bits of award day (`BP_LANE_*`). |
| `deityBoonPacked[id]` | 0–23; 24–31; 32–36 | Assignment day; used-slot mask; registration ordinal. |
| `deityRecipientBoonCount[id]` | Thirty-two 4-bit lanes | Lifetime recipient gift counts by deity ordinal, capped at ten; `GameBoonActions._issueDeityBoon`. |
| `_subscribers payload` | Three 85-bit lanes at 85k | Lane: ID 0–31; quantity-minus-one 32–34; tickets 35; score code 36–45; day 46–67; removal 68; streak 69–84. |
| `_subCursor` | 0–14; 15 | Section offset; ticket-section flag (otherwise boxes). |
| `_afkingProtocolFlags` | 0; 1; 2; 3; 4 | Vault bought; sDGNRS bought; Vault owner pause; Vault unfunded; sDGNRS unfunded. |
| `_subMeta[id>>2]` | Four 64-bit lanes | Lane: position+1 0–10; run-start day 11–32; retained 63. |
| `foilMatchClaimed[id]` | Two 32-bit lanes | Lane: exact day 0–23; four claim bits 24–27. |
| `foilRecord[level&3][id]` | 0–23; 24–39; 40–55; 56–183 | First eligible day; multiplier; activity; four uint32 ticket lines. |
| `foilRecord[level&3][id]` | 184–207; 208–231; 232; 255 | Generation day; exact level; gold paid; ready. |
| `dailyFoilDraw[day&1]` | 0–31; 64–87; 88–215; 216; 217–240 | Traits; level; payout seed; seed present; exact day. |
| `foilQueue[buffer] payload` | Eight 32-bit lanes | Wallet IDs; read/write counts are separate control fields. |
| `goldenTicket` | 0–31; 160–161; 162–164; 165–188; 189 | Armed wallet ID; quadrant; symbol; day; armed flag. |
| `goldenTicket` | 190; 191–192; 193–216 | Resolve-day ban flag; ban quadrant; ban day. |
| `decBattleEntries[(id-1)/2]` | Two 128-bit lanes | Lane: ID 0–31; board 32–61; whole-FLIP stack 62–127. |
| `decBattlePlayers[id]` | 0–63; 64–87 | Entry ID; level. |
| `decBattleQueue` | 0–23; 24–47 | Head level; tail level. |
| `decBattleHeap[i]` | 0–63; 64–255 | Entry ID; score (tie-breaking also uses entropy in the comparator). |
| `DecJackpotPlan.weights` | Four 16-bit lanes | Quadrant weights. |

## Quests namespace

Source: [contracts/DegenerusQuests.sol](../contracts/DegenerusQuests.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `activeQuestsPacked` | 0–23; 24–31; 64–87; 88–95 | Daily quest 0 day/type; daily quest 1 day/type. Each occupies a 64-bit record. |
| `activeQuestsPacked` | 128–135; 136–159 | Level quest type; 24-bit version (`LEVEL_QUEST_*`). |
| `levelQuestPlayerState[id]` | 0–23; 24–151; 152; 153 | 24-bit version; uint128 progress; completion; growth-bet quest flag. |
| `PlayerQuestState.completionMask` | 0; 1 | Daily slots 0 and 1; level-quest completion has its own word. |

The namespace root is `QUESTS_STORAGE_ROOT`; `activeQuestsPacked` is at root+0, `questPlayerState`
at root+1 and `levelQuestPlayerState` at root+2. The compiler appendix gives the `PlayerQuestState`
byte packing. The level version spans 24 bits in both words.

## Craps storage and lifecycle

Source: [contracts/storage/CrapsBattleStorage.sol](../contracts/storage/CrapsBattleStorage.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `_bets[key]` | Three 72-bit lanes at 72k; day 216–239 | Lane: ID 0–31; ten 3-bit board counts 32–61; boon 62–64; high flags 65–70; unused 71. Awarded-seat bit 72 exists only in memory. |
| `_battles[key]` | 0–31; 32–63; 64–168; 169–200 | Entrants; resolved count; composite score; leading seat (`_BG_*`). |
| `_battles[key]` | 201–218; 219–249; 250–251; 252; 253; 255 | Stake units; seed units; tier; high-tail; skipped period; terms frozen. |
| `_slotState[slot]` | 0–47; 48–111; 112–223; 232–255 | RNG index; settlement cursor; reserve draw; scheduled day tag. |
| `_slotState reserve draw` | 112–143; 144–175; 176–207; 208–215; 216–223 | Nominee; eligible count; cursor; resolved byte; won byte. |
| `_highField[key]` | 0–31; 32–136; 137–168; 169; 170–188; 232–255 | High seats; best score; winning seat; done; hottest hand; scheduled day tag. |
| `_customBattle[slot]` | 0–27; 28–32; 33–42; 43–60; 61–100; 101; 102–109 | Played FLIP; bank multiplier; goal multiplier; bounty units; close time; multi-entry flag; high multiplier. |
| `_passCreditsById[id]` | 0–31; 32–63; 64–84; 85; 118 | Normal/high passes; compact board; initialized; retained. Memory-only ID uses 86–117. |
| `_dayTickets[day&63]` | 0–31; six 32-bit lanes from 32; 232–255 | Total seats; six period high counts; exact day. |
| `_dayStaked[day&63]` | 0–111; 112–223; 232–255 | Total and high bankroll; exact day. |
| `_boostBudget[day&63]` | 0–111; 112–223; 224–231; 232–255 | Main/high budgets; routine weight; exact day. |
| `_battleDays[day&63]` | 0–7; 232–255 | Initialized scheduled-window bitmap; exact day. |
| `_daySeated[(day&63)/4][id]` | Four 64-bit lanes | Lane: day-seat index 0–31; period flags 33–38; exact day 40–63. |
| `JackpotRound.drawCursor` | 0–31; 32–130; 131–137; 138–169; 170–201; 207 | Visit ordinal; eligible-level bitset; offset; position; entries left; prepared flag. Source: `DegenerusGameJackpotDrawModule` and `_ROUND_PREPARED`. |
| `compact preferred board` | Nine 2-bit lanes 0–17; 18–20 | First nine legs; three-bit Dont Pass, positioned at 64 in the pass word (`CrapsPreferenceLib`). |
| `comp code (input)` | 0–159; 160–167; 168; 176–199; 200–207; 208–215 | Account address; kind; high flag; argument; count; period (`_COMP_*`). |

## Coinflip

Source: [contracts/modules/CoinflipCore.sol](../contracts/modules/CoinflipCore.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `coinflipStakeRing[id][page%15]` | Seven 32-bit lanes 0–223; 224–247; 248–255 | Whole-FLIP daily stakes; absolute page+1; overflow hint. Page is day/7. |
| `coinflipStakeOverflow[id][page]` | Same stake-page format | Readers require the full page tag; consumed lanes remain behind the claim cursor. |
| `coinflipDayResultPacked[day>>5]` | 32 byte lanes at 8*(day&31) | 0 unresolved; 1 loss; 50–156 winning reward percent. |
| `bafDrawHeader[day]` | 0–95; 96–127 | Cumulative weight; entry count. |
| `bafDrawEntry[index>>1]` | Two 128-bit lanes | Lane: cumulative endpoint 0–95; wallet ID 96–127. |

## sDGNRS redemption records

Source: [contracts/sDGNRS.sol](../contracts/sDGNRS.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `_claimLocations[id]` | Two 64-bit lanes | Parity lane: exact batch ID 0–31; entry index 32–63. |
| `_batchPlayerCounts` | 0–31; 32–63 | Even/odd batch queue counts; compiler slot 6, byte offset 24. |
| `_batchPlayers[parity][index>>1]` | Two 128-bit lanes | Lane: amount units 0–79; wallet ID 80–111; activity score+1 112–127 (`BATCH_PLAYER_*`). |

## Affiliate and BAF

Source: [contracts/DegenerusAffiliate.sol](../contracts/DegenerusAffiliate.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `affiliateCoinEarned[id]` | 0–34; 35–69 | Exact capped scores at latest level T and T-1 (`AffiliateEarningsLib`). |
| `affiliateCoinEarned[id]` | Five 19-bit lanes 70–164 | Clipped score inputs at T-2 through T-6. |
| `affiliateCoinEarned[id]` | 165–188; 189–220; 221–252; 253; 254 | Latest level; first/second upline IDs; validity flags. |
| `_levelScore[lvl&3]` | 0–127; 128–162; 163–194; 232–255 | Level total; leader score; leader ID; exact level. |
| `playerReferralCode[id]` | 0–31 plus tag 32, or custom bytes32 | Default owner ID with `DEFAULT_ID_TAG`; special locked/custom values require the code decoder. |
| `account code (input)` | 0–31; 160 | Wallet ID; `ACCOUNT_CODE_TAG`. |
| `bafTop word` | Two 128-bit lanes | Score 0–95, wallet ID 96–127; source `DegenerusJackpots`. |
| `bafTopLevels` | Four 24-bit lanes | Exact bracket tags for the four leaderboard banks. |

Affiliate fields live at `AFFILIATE_STORAGE_ROOT`: code mapping +0, earnings +1, referral +2, and
four score words +3 through +6. `BafPlayer` and `BafLevel` use compiler struct packing below.

## Other state owners

Source: [contracts/DegenerusParimutuel.sol](../contracts/DegenerusParimutuel.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `growthCounts[round]` | 0–127; 128–255 | Over/under entry counts. |
| `growthOutcomeWords[round>>7]` | Two-bit lane at 2*(round&127) | Settled side code. |
| `growthSettlement` | 0–23; 24–87 | Round; uint64 settlement position. |
| `growthSideLanes / lastBetRounds` | Eight 32-bit lanes | Wallet IDs per round/side word; last round per wallet word, respectively. |
| `AFKingSubscriptionToken._traitWords` | Four 64-bit lanes | Lane: symbol 0–4; background RGB 5–28; trim RGB 29–52. |
| `GNRUS._voterWord[id/5]` | Five 48-bit lanes | Lane: charity-slot bitmap 0–19; level 20–43; unused 44–47. |
| `GNRUS._slotApproveWeight[slot]` | 0–231; 232–255 | Approval weight; exact level. |
| `DegenerusAdmin voter records` | Five 48-bit lanes | Lane: `Vote` enum byte 0–7; uint40 vote weight 8–47. |
| `WWXRP draw header` | 0–95; 96–191; 192–223; 224–255 | Raw burns; effective score; entry count; day+1 tag. |
| `WWXRP._drawEntry[key]` | 0–95; 96–127 | Cumulative score endpoint; wallet ID. |
| `WWXRP._dayClaimed[day>>8]` | Bit day&255 | Claimed day bitmap. |
| `WWXRP._incinHeader` | 0–191; 192–223; 224–247 | Total score; count; bracket. |
| `WWXRP.IncinEntry` | 0–191; 192–223 | Cumulative score; wallet ID (also compiler-packed struct). |

The last rows follow [AFKingSubscriptionToken](../contracts/AFKingSubscriptionToken.sol),
[GNRUS](../contracts/GNRUS.sol), [Admin](../contracts/DegenerusAdmin.sol) and
[WWXRP](../contracts/WWXRP.sol). Scalar token balances and full RNG words are not bit fields.

## Shared wire and scratch encodings

Source: [contracts/Craps.sol](../contracts/Craps.sol).

| Word / field | Bits or lanes | Meaning |
| --- | --- | --- |
| `canonical chips` | Ten 3-bit lanes 0–29 | Pass Line, Place 4/5/6/8/9/10, Hard 4/8, Dont Pass. |
| `Craps composite score` | 0–15; 16–59; 60–103; 104 | Reserved; ending bankroll; primary rank; goal flag. For busts primary has peak 60–92, retained remainder flag 93, hands 94–103. |
| `JackpotBattleFieldLib field entry` | 0–31; 160–180; 181–255 | Wallet ID; compressed board; units (admitted entries require one unit). |
| `FLIP grossAndFlags` | 0–7; 8–255 | Action flags; whole-FLIP amount. |
| `packed ticket traits` | Four byte lanes 0–31 | Each byte has symbol 0–2, color 3–5 and quadrant 6–7; see `DegenerusTraitUtils`. |
| `Degenerette lane` | Four byte lanes 0–31 | Symbol 0–2; color 3–5; wild flag 6; unused 7. Quadrant is the byte position. Wild clears color bits. |

<!-- compiler-layouts -->

## Compiler storage layouts

Slots and offsets below come from solc 0.8.38 `storageLayout`. Bits count from the
least significant bit of each 256-bit slot. Mapping/array rows identify their root slots;
their elements use Solidity hashed/indexed addressing. Struct slots are relative to the
struct base. Only structs used in storage appear here; memory-only work structs do not pack
their fields into storage. Namespaced Quests/Affiliate layouts use a temporary compiler
harness declaring the production struct types, without changing production sources.

### DegenerusGame

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–23 | `purchaseStartDay` | `uint24` |
| 0 | 24–47 | `dailyIdx` | `uint24` |
| 0 | 48–95 | `rngRequestTime` | `uint48` |
| 0 | 96–119 | `level` | `uint24` |
| 0 | 120–127 | `jackpotPhaseFlag` | `bool` |
| 0 | 128–135 | `jackpotCounter` | `uint8` |
| 0 | 136–143 | `lastPurchaseDay` | `bool` |
| 0 | 144–151 | `decimatorFlags` | `uint8` |
| 0 | 152–159 | `rngLockedFlag` | `bool` |
| 0 | 160–167 | `phaseTransitionActive` | `bool` |
| 0 | 168–175 | `gameOver` | `bool` |
| 0 | 176–183 | `dailyJackpotCoinTicketsPending` | `bool` |
| 0 | 184–191 | `jackpotFlags` | `uint8` |
| 0 | 192–199 | `ticketsFullyProcessed` | `bool` |
| 0 | 200–207 | `ticketWriteSlot` | `bool` |
| 0 | 208–215 | `prizePoolFrozen` | `bool` |
| 0 | 216–223 | `degenesisClosed` | `uint8` |
| 0 | 224–231 | `subsFullyProcessed` | `bool` |
| 0 | 232–239 | `humanReadComplete` | `bool` |
| 0 | 240–255 | `rngFlagsAndNudges` | `uint16` |
| 1 | 0–127 | `currentPrizePool` | `uint128` |
| 1 | 128–255 | `claimablePool` | `uint128` |
| 2 | 0–255 | `prizePoolsPacked` | `uint256` |
| 3 | 0–255 | `rngWordCurrent` | `uint256` |
| 4 | 0–23 | `rngRequestDay` | `uint24` |
| 4 | 24–31 | `dailyComplete` | `bool` |
| 4 | 32–79 | `lastVrfProcessedTimestamp` | `uint48` |
| 4 | 80–127 | `ticketBufferLevels` | `uint48` |
| 4 | 128–159 | `loanSeizeCursor` | `uint32` |
| 4 | 160–183 | `vaultFlipSettledDay` | `uint24` |
| 4 | 184–191 | `traitBucketStale` | `uint8` |
| 4 | 192–215 | `decEntriesLevel` | `uint24` |
| 4 | 216–239 | `lastDailyRequestWallDay` | `uint24` |
| 5 | 0–255 | `dailyTicketBudgetsPacked` | `uint256` |
| 6 | 0–255 | `balancesPacked` | `mapping(uint32 => uint256)` |
| 7 | 0–255 | `mintPacked_` | `mapping(uint32 => uint256)` |
| 8 | 0–255 | `prizePoolPendingPacked` | `uint256` |
| 9 | 0–255 | `ticketQueue` | `mapping(uint24 => uint256[])` |
| 10 | 0–255 | `wallets` | `uint256[]` |
| 11 | 0–31 | `ticketCursor` | `uint32` |
| 11 | 32–55 | `ticketLevel` | `uint24` |
| 11 | 56–63 | `snapShift` | `uint8` |
| 11 | 64–87 | `snapLevel` | `uint24` |
| 11 | 88–95 | `snapPendingShift` | `uint8` |
| 11 | 96–127 | `ticketRound` | `uint32` |
| 11 | 128–159 | `ticketSoloOffset` | `uint32` |
| 11 | 160–207 | `degeneretteCursor` | `uint48` |
| 11 | 208–239 | `degeneretteReadCount` | `uint32` |
| 12 | 0–127 | `degenesisVaultBudget` | `uint128` |
| 12 | 128–175 | `lastDailyCompletedAt` | `uint48` |
| 12 | 176–223 | `degenesisOpenedAt` | `uint48` |
| 13 | 0–255 | `degenesisCredit` | `mapping(uint32 => uint256)` |
| 14 | 0–255 | `gameOverStatePacked` | `uint256` |
| 15 | 0–255 | `operatorApprovals` | `mapping(uint32 => mapping(address => bool))` |
| 16 | 0–255 | `playerClaimWord` | `mapping(uint32 => uint256)` |
| 17 | 0–255 | `levelDgnrsPacked` | `uint256` |
| 18 | 0–255 | `deityPassPricePaid` | `mapping(uint32 => uint96)` |
| 19 | 0–255 | `deityPassIds` | `uint256[]` |
| 20 | 0–255 | `degenesisActive` | `uint256` |
| 21 | 0–159 | `vrfCoordinator` | `contract IVRFCoordinator` |
| 21 | 160–191 | `vrfCallbackGasLimit` | `uint32` |
| 21 | 192–255 | `vrfRequestId` | `uint64` |
| 22 | 0–255 | `vrfKeyHash` | `bytes32` |
| 23 | 0–255 | `vrfSubscriptionId` | `uint256` |
| 24 | 0–255 | `lootboxRngPacked` | `uint256` |
| 25 | 0–255 | `rngDayTags` | `uint256` |
| 26 | 0–255 | `deityBoonPacked` | `mapping(uint32 => uint64)` |
| 27 | 0–255 | `degeneretteRecordBounty` | `mapping(uint256 => uint256)` |
| 28 | 0–23 | `earlyTicketLevel` | `uint24` |
| 29 | 0–255 | `lootboxEvCapPacked` | `mapping(uint32 => uint256)` |
| 30 | 0–255 | `decBattleEntries` | `mapping(uint256 => uint256)` |
| 31 | 0–255 | `decBattleRounds` | `mapping(uint24 => struct DegenerusGameStorage.DecBattleRound)` |
| 32 | 0–255 | `decBattlePlayers` | `mapping(uint32 => uint256)` |
| 33 | 0–255 | `yieldAccumulator` | `uint256` |
| 34 | 0–255 | `centuryBonusUsed` | `mapping(uint32 => uint256)` |
| 35 | 0–7 | `deityPassSales` | `uint8` |
| 36 | 0–255 | `boonPacked` | `mapping(uint32 => struct DegenerusGameStorage.BoonPacked)` |
| 37 | 0–255 | `_subMeta` | `mapping(uint256 => uint256)` |
| 38 | 0–255 | `_subscribers` | `uint256[]` |
| 39 | 0–15 | `_subCursor` | `uint16` |
| 39 | 16–31 | `_subOpenCursor` | `uint16` |
| 39 | 32–55 | `_afkingResetDay` | `uint24` |
| 39 | 56–103 | `boxCursor` | `uint48` |
| 39 | 104–135 | `boxReadCount` | `uint32` |
| 39 | 136–159 | `_sdgnrsBonusLevel` | `uint24` |
| 39 | 160–175 | `_pendingBoxCount` | `uint16` |
| 39 | 176–191 | `_subBoxCount` | `uint16` |
| 39 | 192–207 | `_afkingCohortPriceMilli` | `uint16` |
| 39 | 208–215 | `_afkingProtocolFlags` | `uint8` |
| 39 | 216–239 | `_afkingEndpointDay` | `uint24` |
| 40 | 0–255 | `foilMatchClaimed` | `mapping(uint32 => uint256)` |
| 41 | 0–31 | `foilCursor` | `uint32` |
| 41 | 32–55 | `foilGenerationDay` | `uint24` |
| 41 | 56–79 | `foilFirstDrawDay` | `uint24` |
| 41 | 80–87 | `foilWriteSlot` | `bool` |
| 41 | 88–119 | `foilWriteCount` | `uint32` |
| 41 | 120–151 | `foilReadCount` | `uint32` |
| 41 | 152–159 | `foilSlotRetained` | `bool` |
| 42 | 0–255 | `deityRecipientBoonCount` | `mapping(uint32 => uint128)` |
| 43 | 0–255 | `goldenTicket` | `uint256` |
| 44 | 0–255 | `middayRngCredit` | `mapping(uint32 => uint256)` |
| 45 | 0–255 | `centuryPrizePools` | `uint128[]` |
| 46 | 0–255 | `ticketSeats` | `uint256` |
| 47 | 0–255 | `ticketGenerationStartBlock` | `uint256` |
| 48 | 0–31 | `deadTallyPos` | `uint32` |
| 48 | 32–55 | `deadTallyFoilDay` | `uint24` |
| 48 | 56–87 | `deadTallyFoilIdx` | `uint32` |
| 48 | 88–95 | `deadTallyStage` | `uint8` |
| 48 | 96–111 | `deadTraitCount` | `uint16` |
| 48 | 112–175 | `deadUncreated` | `uint64` |
| 48 | 176–239 | `deadCreated` | `uint64` |
| 49 | 0–127 | `deadPot` | `uint128` |
| 49 | 128–191 | `deadTotal` | `uint64` |
| 49 | 192–255 | `deadUncreatedLeft` | `uint64` |
| 50 | 0–255 | `deadClaimed` | `mapping(uint256 => uint256)` |
| 51 | 0–255 | `decBattleQueue` | `uint256` |
| 52 | root / multiple slots | `traitBucketLive` | `uint256[2]` |
| 54 | 0–255 | `ticketPending` | `mapping(uint32 => uint256)` |
| 55 | root / multiple slots | `jackpotWork` | `struct DegenerusGameStorage.JackpotWork` |
| 57 | 0–255 | `farFutureOwed` | `mapping(uint32 => uint256[13])` |
| 58 | 0–63 | `decPreviousStack` | `uint64` |
| 58 | 64–103 | `decPreviousCount` | `uint40` |
| 59 | 0–255 | `decJackpotPlans` | `mapping(uint24 => struct DegenerusGameStorage.DecJackpotPlan)` |
| 60 | 0–255 | `decGeneratedOwners` | `mapping(uint256 => uint32)` |
| 61 | 0–255 | `walletIds` | `mapping(address => uint64)` |
| 62 | 0–255 | `_smurfWords` | `mapping(uint32 => mapping(uint256 => uint256))` |
| 63 | 0–255 | `_loans` | `mapping(uint32 => uint256)` |
| 64 | 0–255 | `_loansDue` | `mapping(uint24 => mapping(uint256 => uint256))` |
| 65 | 0–255 | `_loansDueCount` | `mapping(uint24 => uint256)` |
| 66 | 0–255 | `degenesisWord` | `uint256` |
| 67 | 0–255 | `degenesisDays` | `mapping(uint256 => uint256)` |
| 68 | 0–255 | `degenesisOrders` | `mapping(uint256 => uint256)` |
| 69 | 0–127 | `_redemptionReserveStored` | `uint128` |
| 70 | root / multiple slots | `lvlTraitEntry` | `uint256[256][2]` |
| 582 | root / multiple slots | `dailyHeroWagers` | `uint256[3][2]` |
| 588 | root / multiple slots | `rngWordByDay` | `uint256[2]` |
| 590 | root / multiple slots | `levelPrizePool` | `uint256[4]` |
| 594 | root / multiple slots | `dailyFoilDraw` | `uint256[2]` |
| 596 | root / multiple slots | `deityBySymbol` | `uint256[32]` |
| 628 | root / multiple slots | `decBattleHeap` | `uint256[200]` |
| 828 | root / multiple slots | `foilRecord` | `mapping(uint32 => uint256)[4]` |
| 832 | root / multiple slots | `protocolBoonPools` | `struct DegenerusGameStorage.ProtocolBoonPool[2][2]` |
| 836 | root / multiple slots | `protocolBoonEntries` | `mapping(uint32 => struct DegenerusGameStorage.ProtocolBoonEntry)[2][2]` |
| 840 | root / multiple slots | `boxQueue` | `uint256[][2]` |
| 842 | root / multiple slots | `foilQueue` | `uint256[][2]` |
| 844 | root / multiple slots | `degeneretteQueue` | `uint256[][2]` |

#### struct DegenerusGameStorage.BoonPacked

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `slot0` | `uint256` |
| 1 | 0–255 | `slot1` | `uint256` |

#### struct DegenerusGameStorage.DecBattleRound

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–95 | `poolWei` | `uint96` |
| 0 | 96–135 | `count` | `uint40` |
| 0 | 136–199 | `totalCreditedStack` | `uint64` |
| 0 | 200–223 | `openedDay` | `uint24` |
| 0 | 224–231 | `phase` | `uint8` |
| 0 | 232–239 | `capacity` | `uint8` |
| 0 | 240–247 | `winners` | `uint8` |
| 0 | 248–255 | `paid` | `uint8` |
| 1 | 0–63 | `cursor` | `uint64` |
| 1 | 64–127 | `champion` | `uint64` |
| 1 | 128–151 | `next` | `uint24` |

#### struct DegenerusGameStorage.DecJackpotPlan

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `soloAmount` | `uint128` |
| 0 | 128–191 | `weights` | `uint64` |
| 0 | 192–231 | `generatedEntries` | `uint40` |
| 0 | 232–247 | `cursor` | `uint16` |
| 0 | 248–255 | `mode` | `uint8` |

#### struct DegenerusGameStorage.JackpotWork

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `budget` | `uint128` |
| 0 | 128–255 | `paid` | `uint128` |
| 1 | 0–31 | `traits` | `uint32` |
| 1 | 32–55 | `lvl` | `uint24` |
| 1 | 56–71 | `winner` | `uint16` |
| 1 | 72–79 | `kind` | `uint8` |
| 1 | 80–87 | `quadrant` | `uint8` |
| 1 | 88–95 | `finalDay` | `bool` |
| 1 | 96–127 | `directTicketRound` | `uint32` |
| 1 | 128–135 | `directTickets` | `bool` |

#### struct DegenerusGameStorage.ProtocolBoonEntry

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–31 | `playerId` | `uint32` |
| 0 | 32–95 | `cumulativeWeight` | `uint64` |
| 0 | 96–111 | `scoreSnapshot` | `uint16` |

#### struct DegenerusGameStorage.ProtocolBoonPool

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–111 | `totalWageredWei` | `uint112` |
| 0 | 112–175 | `totalWeight` | `uint64` |
| 0 | 176–207 | `entryCount` | `uint32` |
| 0 | 208–215 | `awardedMask` | `uint8` |
| 0 | 216–239 | `day` | `uint24` |

### CrapsBattle

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_bets` | `mapping(uint256 => uint256)` |
| 1 | 0–63 | `_customBattleCount` | `uint64` |
| 2 | 0–255 | `_battles` | `mapping(bytes32 => uint256)` |
| 3 | 0–255 | `_bonusSeated` | `mapping(bytes32 => mapping(uint32 => bool))` |
| 4 | 0–255 | `_bonus` | `uint256` |
| 5 | 0–255 | `_slotState` | `mapping(uint256 => uint256)` |
| 6 | 0–255 | `_battleCreator` | `mapping(address => bool)` |
| 7 | 0–255 | `_highField` | `mapping(bytes32 => uint256)` |
| 8 | 0–255 | `_customBattle` | `mapping(uint256 => uint256)` |
| 9 | 0–255 | `_passCreditsById` | `mapping(uint32 => uint256)` |
| 10 | 0–255 | `_progressive` | `uint256` |
| 11 | 0–63 | `_minerSlot` | `uint64` |
| 11 | 64–127 | `_activeJackpotSlot` | `uint64` |
| 11 | 128–151 | `_firstWindowDay` | `uint24` |
| 12 | 0–255 | `_highRollerReserve` | `uint256` |
| 13 | 0–255 | `_rngSlotCursor` | `uint64[2]` |
| 14 | 0–255 | `_fundedCustomSlots` | `uint64[4]` |
| 15 | root / multiple slots | `_dayTickets` | `uint256[64]` |
| 79 | root / multiple slots | `_dayStaked` | `uint256[64]` |
| 143 | root / multiple slots | `_boostBudget` | `uint256[64]` |
| 207 | root / multiple slots | `_battleDays` | `uint256[64]` |
| 271 | root / multiple slots | `_jackpotRounds` | `struct CrapsBattleStorage.JackpotRound[512]` |
| 2831 | root / multiple slots | `_rngSlots` | `uint64[][2]` |
| 2833 | root / multiple slots | `_daySeated` | `mapping(uint32 => uint256)[16]` |

#### struct CrapsBattleStorage.JackpotRound

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `drawWord` | `uint256` |
| 1 | 0–127 | `added` | `uint128` |
| 1 | 128–255 | `totalPool` | `uint128` |
| 2 | 0–127 | `potRemainder` | `uint128` |
| 2 | 128–191 | `paidUnits` | `uint64` |
| 2 | 192–223 | `bankroll` | `uint32` |
| 2 | 224–255 | `bountyUnits` | `uint32` |
| 3 | 0–207 | `drawCursor` | `uint208` |
| 3 | 208–231 | `level` | `uint24` |
| 3 | 232–255 | `requestDay` | `uint24` |
| 4 | 0–31 | `multiplierBps` | `uint32` |
| 4 | 32–63 | `paidCount` | `uint32` |
| 4 | 64–95 | `drawnCount` | `uint32` |
| 4 | 96–127 | `drawnUnits` | `uint32` |
| 4 | 128–159 | `awardTarget` | `uint32` |
| 4 | 160–191 | `entryPrice` | `uint32` |
| 4 | 192–223 | `subsidyMultiplierBps` | `uint32` |
| 4 | 224–231 | `started` | `bool` |
| 4 | 232–255 | `day` | `uint24` |

### Coinflip

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `coinflipStakeRing` | `mapping(uint32 => uint256[15])` |
| 1 | 0–255 | `coinflipDayResultPacked` | `mapping(uint24 => uint256)` |
| 2 | 0–255 | `playerState` | `mapping(uint32 => struct CoinflipCore.PlayerCoinflipState)` |
| 3 | 0–127 | `recordPool` | `uint128` |
| 3 | 128–255 | `biggestFlipEver` | `uint128` |
| 4 | 0–23 | `flipsClaimableDay` | `uint24` |
| 4 | 24–31 | `sdgnrsAutoRebuyArmed` | `bool` |
| 4 | 32–55 | `recordDayFlip` | `uint24` |
| 4 | 56–79 | `recordDaySpin` | `uint24` |
| 4 | 80–103 | `recordDayLuckbox` | `uint24` |
| 4 | 104–127 | `recordDayBuy` | `uint24` |
| 4 | 128–151 | `bafDrawDay` | `uint24` |
| 4 | 152–175 | `recordDayDiceRun` | `uint24` |
| 4 | 176–199 | `requestedDailyIdx` | `uint24` |
| 5 | 0–255 | `bafDrawHeader` | `mapping(uint24 => uint256)` |
| 6 | 0–127 | `biggestSpinEver` | `uint128` |
| 6 | 128–255 | `biggestLuckboxEver` | `uint128` |
| 7 | 0–127 | `biggestBuyEver` | `uint128` |
| 7 | 128–255 | `biggestDiceRunEver` | `uint128` |
| 8 | 0–255 | `bafDrawEntry` | `mapping(uint256 => uint256)` |
| 9 | 0–255 | `coinflipStakeOverflow` | `mapping(uint32 => mapping(uint24 => uint256))` |

#### struct CoinflipCore.PlayerCoinflipState

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `claimableStored` | `uint128` |
| 0 | 128–151 | `lastClaim` | `uint24` |
| 0 | 152–175 | `autoRebuyStartDay` | `uint24` |
| 0 | 176–183 | `autoRebuyEnabled` | `bool` |
| 0 | 184–191 | `autoRebuyUnlimited` | `bool` |
| 0 | 192–199 | `initialized` | `bool` |
| 1 | 0–127 | `autoRebuyStop` | `uint128` |
| 1 | 128–255 | `autoRebuyCarry` | `uint128` |

### sDGNRS

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `_totalSupply` | `uint128` |
| 0 | 128–223 | `_pendingRedemptionEthValue` | `uint96` |
| 0 | 224–255 | `_openBatch` | `uint32` |
| 1 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 2 | root / multiple slots | `poolBalances` | `uint128[5]` |
| 5 | 0–255 | `_claimLocations` | `mapping(uint32 => uint128)` |
| 6 | 0–127 | `_escrowedSupply` | `uint128` |
| 6 | 128–159 | `_settlingBatch` | `uint32` |
| 6 | 160–191 | `_redemptionCursor` | `uint32` |
| 6 | 192–255 | `_batchPlayerCounts` | `uint64` |
| 7 | 0–127 | `centurySupplyCheckpoint` | `uint128` |
| 7 | 128–151 | `lastRecycledCentury` | `uint24` |
| 7 | 152–159 | `recyclingClosed` | `bool` |
| 7 | 160–255 | `_settlingReserveLeft` | `uint96` |
| 8 | root / multiple slots | `_batchPlayers` | `mapping(uint256 => uint256)[2]` |
| 10 | root / multiple slots | `_redemptionBatches` | `struct sDGNRS.RedemptionBatch[2]` |

#### struct sDGNRS.RedemptionBatch

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–79 | `tokens` | `uint80` |
| 0 | 80–175 | `ethPayout` | `uint96` |
| 1 | 0–95 | `ethBase` | `uint96` |
| 1 | 96–191 | `flipEscrow` | `uint96` |
| 1 | 192–207 | `roll` | `uint16` |
| 1 | 208–223 | `flipReward` | `uint16` |
| 1 | 224–255 | `id` | `uint32` |

### Icons32Data

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | root / multiple slots | `_paths` | `string[33]` |
| 33 | root / multiple slots | `_symQ1` | `string[8]` |
| 41 | root / multiple slots | `_symQ2` | `string[8]` |
| 49 | root / multiple slots | `_symQ3` | `string[8]` |
| 57 | 0–7 | `_finalized` | `bool` |
| 57 | 8–71 | `initializedMask` | `uint64` |
| 57 | 72–79 | `bootstrapClosed` | `bool` |

### FLIP

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_supply` | `struct FLIP.Supply` |
| 1 | 0–7 | `_tombstoneFlooded` | `bool` |
| 1 | 8–135 | `_crapsCompAllowance` | `uint128` |
| 2 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 3 | 0–255 | `allowance` | `mapping(address => mapping(address => uint256))` |

#### struct FLIP.Supply

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `totalSupply` | `uint128` |
| 0 | 128–255 | `vaultAllowance` | `uint128` |

### DegenerusJackpots

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `bafPlayer` | `mapping(uint32 => struct DegenerusJackpots.BafPlayer[2])` |
| 1 | 0–255 | `bafLevel` | `mapping(uint24 => struct DegenerusJackpots.BafLevel)` |
| 2 | 0–23 | `lastBafResolvedDay` | `uint24` |
| 2 | 24–119 | `bafTopLevels` | `uint96` |
| 3 | root / multiple slots | `bafTop` | `uint256[2][4]` |

#### struct DegenerusJackpots.BafLevel

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–63 | `epoch` | `uint64` |
| 0 | 64–71 | `topLen` | `uint8` |
| 0 | 72–79 | `skipped` | `bool` |

#### struct DegenerusJackpots.BafPlayer

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–167 | `total` | `uint168` |
| 0 | 168–231 | `epoch` | `uint64` |
| 0 | 232–255 | `bracket` | `uint24` |

### DegenerusDeityPass

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_owners` | `mapping(uint256 => address)` |
| 1 | 0–255 | `_balances` | `mapping(address => uint256)` |
| 2 | 0–159 | `renderer` | `address` |
| 3 | 0–255 | `_outlineColor` | `string` |
| 4 | 0–255 | `_backgroundColor` | `string` |
| 5 | 0–255 | `_nonCryptoSymbolColor` | `string` |

### DegenerusVault

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–7 | `_liquidationBuyEnabled` | `bool` |
| 0 | 8–103 | `_liquidationVaultFloorWei` | `uint96` |
| 1 | 0–255 | `crapsCompAllowanceOf` | `mapping(address => uint256)` |

### DGNRS

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `totalSupply` | `uint256` |
| 1 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 2 | 0–255 | `allowance` | `mapping(address => mapping(address => uint256))` |
| 3 | 0–127 | `_vestingReleased` | `uint128` |
| 3 | 128–255 | `totalUnwrapped` | `uint128` |

### DegenerusAdmin

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–159 | `coordinator` | `address` |
| 1 | 0–255 | `subscriptionId` | `uint256` |
| 2 | 0–255 | `vrfKeyHash` | `bytes32` |
| 3 | 0–255 | `proposalCount` | `uint256` |
| 4 | 0–255 | `proposals` | `mapping(uint256 => struct DegenerusAdmin.Proposal)` |
| 5 | 0–255 | `voterRecords` | `mapping(uint256 => mapping(uint32 => uint256))` |
| 6 | 0–255 | `_activeProposalId` | `mapping(uint32 => uint256)` |
| 7 | 0–255 | `validFromId` | `uint256` |

#### struct DegenerusAdmin.Proposal

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–31 | `proposer` | `uint32` |
| 0 | 32–71 | `createdAt` | `uint40` |
| 0 | 72–111 | `votingSnapshot` | `uint40` |
| 0 | 112–119 | `path` | `enum DegenerusAdmin.ProposalPath` |
| 0 | 120–127 | `state` | `enum DegenerusAdmin.ProposalState` |
| 0 | 128–159 | `callbackGasLimit` | `uint32` |
| 1 | 0–159 | `coordinator` | `address` |
| 1 | 160–199 | `approveWeight` | `uint40` |
| 1 | 200–239 | `rejectWeight` | `uint40` |
| 2 | 0–255 | `keyHash` | `bytes32` |

### GNRUS

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `totalSupply` | `uint256` |
| 1 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 2 | 0–23 | `currentLevel` | `uint24` |
| 2 | 24–31 | `finalized` | `bool` |
| 2 | 32–63 | `currentActiveBitmap` | `uint32` |
| 2 | 64–95 | `pendingEditSet` | `uint32` |
| 2 | 96–135 | `sweptAt` | `uint40` |
| 3 | 0–255 | `_voterWord` | `mapping(uint32 => uint256)` |
| 4 | root / multiple slots | `currentSlate` | `address[20]` |
| 24 | 0–159 | `lastWinningRecipient` | `address` |
| 25 | root / multiple slots | `pendingEdit` | `address[20]` |
| 45 | root / multiple slots | `_slotApproveWeight` | `uint256[20]` |

### AFKingSubscriptionToken

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_owners` | `mapping(uint256 => address)` |
| 1 | 0–255 | `_balances` | `mapping(address => uint256)` |
| 2 | 0–255 | `_tokenApprovals` | `mapping(uint256 => address)` |
| 3 | 0–255 | `_operatorApprovals` | `mapping(address => mapping(address => bool))` |
| 4 | 0–255 | `_traitWords` | `mapping(uint256 => uint256)` |
| 5 | 0–159 | `renderer` | `address` |
| 5 | 160–191 | `nextSerial` | `uint32` |
| 5 | 192–207 | `freeClaims` | `uint16` |
| 5 | 208–223 | `liveSeats` | `uint16` |

### DegenerusParimutuel

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `growthCounts` | `mapping(uint24 => uint256)` |
| 1 | 0–255 | `growthOutcomeWords` | `mapping(uint24 => uint256)` |
| 2 | 0–255 | `growthSideLanes` | `mapping(uint256 => uint256)` |
| 3 | 0–255 | `lastBetRounds` | `mapping(uint32 => uint256)` |
| 4 | 0–255 | `growthSettlement` | `uint256` |

### DegenerusRecordBounty

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | root / multiple slots | `_holders` | `address[5]` |
| 5 | root / multiple slots | `_marks` | `uint128[5]` |
| 8 | 0–255 | `_sinceDays` | `uint24[5]` |
| 9 | 0–255 | `_balances` | `mapping(address => uint256)` |
| 10 | 0–159 | `renderer` | `address` |
| 11 | 0–255 | `_outlineColor` | `string` |
| 12 | 0–255 | `_backgroundColor` | `string` |

### Eip170JackpotBattle

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_bets` | `mapping(uint256 => uint256)` |
| 1 | 0–63 | `_customBattleCount` | `uint64` |
| 2 | 0–255 | `_battles` | `mapping(bytes32 => uint256)` |
| 3 | 0–255 | `_bonusSeated` | `mapping(bytes32 => mapping(uint32 => bool))` |
| 4 | 0–255 | `_bonus` | `uint256` |
| 5 | 0–255 | `_slotState` | `mapping(uint256 => uint256)` |
| 6 | 0–255 | `_battleCreator` | `mapping(address => bool)` |
| 7 | 0–255 | `_highField` | `mapping(bytes32 => uint256)` |
| 8 | 0–255 | `_customBattle` | `mapping(uint256 => uint256)` |
| 9 | 0–255 | `_passCreditsById` | `mapping(uint32 => uint256)` |
| 10 | 0–255 | `_progressive` | `uint256` |
| 11 | 0–63 | `_minerSlot` | `uint64` |
| 11 | 64–127 | `_activeJackpotSlot` | `uint64` |
| 11 | 128–151 | `_firstWindowDay` | `uint24` |
| 12 | 0–255 | `_highRollerReserve` | `uint256` |
| 13 | 0–255 | `_rngSlotCursor` | `uint64[2]` |
| 14 | 0–255 | `_fundedCustomSlots` | `uint64[4]` |
| 15 | root / multiple slots | `_dayTickets` | `uint256[64]` |
| 79 | root / multiple slots | `_dayStaked` | `uint256[64]` |
| 143 | root / multiple slots | `_boostBudget` | `uint256[64]` |
| 207 | root / multiple slots | `_battleDays` | `uint256[64]` |
| 271 | root / multiple slots | `_jackpotRounds` | `struct CrapsBattleStorage.JackpotRound[512]` |
| 2831 | root / multiple slots | `_rngSlots` | `uint64[][2]` |
| 2833 | root / multiple slots | `_daySeated` | `mapping(uint32 => uint256)[16]` |

### WWXRP

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `totalSupply` | `uint256` |
| 1 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 2 | 0–255 | `allowance` | `mapping(address => mapping(address => uint256))` |
| 3 | 0–255 | `_drawEntry` | `mapping(uint256 => uint256)` |
| 4 | 0–255 | `_dayClaimed` | `mapping(uint24 => uint256)` |
| 5 | 0–255 | `_incinEntry` | `mapping(uint256 => struct WWXRP.IncinEntry)` |
| 6 | 0–255 | `trustedMinter` | `mapping(address => bool)` |
| 7 | 0–255 | `gameMintScale` | `uint256` |
| 8 | 0–255 | `_claimable` | `mapping(uint32 => uint256)` |
| 9 | root / multiple slots | `_drawHeader` | `uint256[10][3]` |
| 39 | 0–255 | `_incinHeader` | `uint256` |

#### struct WWXRP.IncinEntry

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–191 | `cum` | `uint192` |
| 0 | 192–223 | `id` | `uint32` |

### DegenerusOwnerGovernance

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–31 | `proposalCount` | `uint32` |
| 1 | 0–255 | `totalEscrowed` | `uint256` |
| 2 | 0–255 | `positions` | `mapping(address => struct DegenerusOwnerGovernance.Position)` |
| 3 | 0–255 | `_proposals` | `mapping(uint256 => struct DegenerusOwnerGovernance.Proposal)` |

#### struct DegenerusOwnerGovernance.Position

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–127 | `amount` | `uint128` |
| 0 | 128–159 | `proposalId` | `uint32` |
| 0 | 160–199 | `assignedBlock` | `uint40` |
| 0 | 200–239 | `depositBlock` | `uint40` |
| 1 | 0–159 | `votingDelegate` | `address` |

#### struct DegenerusOwnerGovernance.Proposal

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–159 | `proposer` | `address` |
| 0 | 160–255 | `value` | `uint96` |
| 1 | 0–159 | `target` | `address` |
| 1 | 160–199 | `expiresAt` | `uint40` |
| 1 | 200–239 | `recentBlock` | `uint40` |
| 1 | 240–247 | `executed` | `bool` |
| 2 | 0–127 | `lockedWeight` | `uint128` |
| 2 | 128–255 | `recentWeight` | `uint128` |
| 3 | 0–255 | `dataHash` | `bytes32` |

### DeityPassCustomizationRenderer

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_customizations` | `mapping(uint256 => struct DeityPassCustomizationRenderer.Customization)` |

#### struct DeityPassCustomizationRenderer.Colors

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `rimColor` | `string` |
| 1 | 0–255 | `badgeBackgroundColor` | `string` |
| 2 | 0–255 | `symbolColor` | `string` |
| 3 | 0–255 | `backgroundColor` | `string` |
| 4 | 0–255 | `outlineColor` | `string` |

#### struct DeityPassCustomizationRenderer.Customization

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | root / multiple slots | `colors` | `struct DeityPassCustomizationRenderer.Colors` |
| 5 | 0–255 | `geometry` | `struct DeityPassCustomizationRenderer.Geometry` |
| 6 | 0–7 | `overrideMask` | `uint8` |

#### struct DeityPassCustomizationRenderer.Geometry

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–15 | `radius` | `uint16` |
| 0 | 16–31 | `centerX` | `int16` |
| 0 | 32–47 | `centerY` | `int16` |

### DegenerusVaultShare

| Slot | Bits | Field | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `name` | `string` |
| 1 | 0–255 | `symbol` | `string` |
| 2 | 0–255 | `totalSupply` | `uint256` |
| 3 | 0–255 | `balanceOf` | `mapping(address => uint256)` |
| 4 | 0–255 | `allowance` | `mapping(address => mapping(address => uint256))` |

### Namespaced storage types


#### struct DegenerusAffiliate.AffiliateCodeInfo

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–31 | `ownerId` | `uint32` |
| 0 | 32–39 | `kickback` | `uint8` |
| 0 | 40–71 | `upline1` | `uint32` |
| 0 | 72–103 | `upline2` | `uint32` |
| 0 | 104–111 | `flags` | `uint8` |

#### struct DegenerusAffiliate.DegenerusAffiliateStorage

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `_affiliateCode` | `mapping(bytes32 => struct DegenerusAffiliate.AffiliateCodeInfo)` |
| 1 | 0–255 | `affiliateCoinEarned` | `mapping(uint32 => uint256)` |
| 2 | 0–255 | `playerReferralCode` | `mapping(uint32 => bytes32)` |
| 3 | root / multiple slots | `_levelScore` | `uint256[4]` |

#### struct DegenerusQuests.DegenerusQuestsStorage

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–255 | `activeQuestsPacked` | `uint256` |
| 1 | 0–255 | `questPlayerState` | `mapping(uint32 => struct DegenerusQuests.PlayerQuestState)` |
| 2 | 0–255 | `levelQuestPlayerState` | `mapping(uint32 => uint256)` |

#### struct DegenerusQuests.PlayerQuestState

| Relative slot | Bits | Member | Type |
| --- | --- | --- | --- |
| 0 | 0–23 | `lastCompletedDay` | `uint24` |
| 0 | 24–47 | `lastActiveDay` | `uint24` |
| 0 | 48–71 | `lastSyncDay` | `uint24` |
| 0 | 72–87 | `streak` | `uint16` |
| 0 | 88–103 | `baseStreak` | `uint16` |
| 0 | 104–111 | `shieldCenturyHighWater` | `uint8` |
| 0 | 112–135 | `lastProgressDay0` | `uint24` |
| 0 | 136–159 | `lastProgressDay1` | `uint24` |
| 0 | 160–175 | `progress0` | `uint16` |
| 0 | 176–191 | `progress1` | `uint16` |
| 0 | 192–199 | `completionMask` | `uint8` |
| 0 | 200–207 | `streakShield` | `uint8` |
| 0 | 208–231 | `afkingSince` | `uint24` |
