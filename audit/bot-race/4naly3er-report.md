# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings) | 275 |
| [GAS-2](#GAS-2) | Use assembly to check for `address(0)` | 88 |
| [GAS-3](#GAS-3) | Using bools for storage incurs overhead | 5 |
| [GAS-4](#GAS-4) | Cache array length outside of loop | 1 |
| [GAS-5](#GAS-5) | State variables should be cached in stack variables rather than re-reading them from storage | 3 |
| [GAS-6](#GAS-6) | Use calldata instead of memory for function arguments that do not get mutated | 1 |
| [GAS-7](#GAS-7) | For Operations that will not overflow, you could use unchecked | 1054 |
| [GAS-8](#GAS-8) | Avoid contract existence checks by using low level calls | 58 |
| [GAS-9](#GAS-9) | Stack variable used as a cheaper cache for a state variable is only used once | 13 |
| [GAS-10](#GAS-10) | State variables only set in the constructor should be declared `immutable` | 10 |
| [GAS-11](#GAS-11) | Functions guaranteed to revert when called by normal users can be marked `payable` | 39 |
| [GAS-12](#GAS-12) | `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`) | 48 |
| [GAS-13](#GAS-13) | Using `private` rather than `public` for constants, saves gas | 21 |
| [GAS-14](#GAS-14) | Use shift right/left instead of division/multiplication if possible | 18 |
| [GAS-15](#GAS-15) | Use of `this` instead of marking as `public` an `external` function | 1 |
| [GAS-16](#GAS-16) | Increments/decrements can be unchecked in for-loops | 12 |
| [GAS-17](#GAS-17) | Use != 0 instead of > 0 for unsigned integer comparison | 12 |
| [GAS-18](#GAS-18) | `internal` functions not called by the contract should be removed | 12 |
### <a name="GAS-1"></a>[GAS-1] `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings)
This saves **16 gas per instance.**

*Instances (275)*:
```solidity
File: BurnieCoin.sol

42:       +======================================================================+

46:       +======================================================================+*/

113:       +======================================================================+

116:       +======================================================================+*/

153:       +======================================================================+

165:       +======================================================================+*/

215:       +======================================================================+

218:       +======================================================================+*/

230:       +======================================================================+

238:       +======================================================================+*/

256:       +======================================================================+

260:       +======================================================================+*/

268:       +======================================================================+*/

277:       +======================================================================+

279:       +======================================================================+*/

298:             spendable += uint256(_supply.vaultAllowance);

301:             spendable += IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);

345:       +======================================================================+

360:       +======================================================================+*/

375:       +======================================================================+*/

383:       +======================================================================+

387:       +======================================================================+*/

463:                 _supply.vaultAllowance += amount128;

471:         balanceOf[to] += amount;

484:                 _supply.vaultAllowance += amount128;

489:         _supply.totalSupply += amount128;

490:         balanceOf[to] += amount;

519:       +======================================================================+

522:       +======================================================================+*/

618:       +======================================================================+

632:       +======================================================================+*/

679:       +======================================================================+

683:       +======================================================================+*/

696:             _supply.vaultAllowance += amount128;

712:             _supply.totalSupply += amount128;

713:             balanceOf[to] += amount;

749:       +======================================================================+

753:       +======================================================================+*/

879:       +======================================================================+

882:       +======================================================================+*/

954:             baseAmount += boost;

970:       +======================================================================+

973:       +======================================================================+*/

1011:       +======================================================================+

1013:       +======================================================================+*/

1024:       +======================================================================+*/

```

```solidity
File: BurnieCoinflip.sol

39:       +======================================================================+*/

94:       +======================================================================+*/

110:       +======================================================================+*/

177:       +======================================================================+*/

188:       +======================================================================+*/

210:       +======================================================================+*/

305:             creditedFlip += bonus;

320:       +======================================================================+*/

433:             mintable += oldCarry;

491:                 stake += carry;

510:                         winningBafCredit += payout;

517:                                 mintable += reserved;

525:                                 carry += _afKingRecyclingBonus(

530:                                 carry += _recyclingBonus(carry);

534:                         mintable += payout;

605:       +======================================================================+*/

626:                 coinflipDeposit += boost;

671:       +======================================================================+*/

736:                 mintable += carry;

775:       +======================================================================+*/

805:                 rewardPercent += 6;

866:       +======================================================================+*/

896:       +======================================================================+*/

982:                     total += payout;

994:       +======================================================================+*/

```

```solidity
File: DegenerusAdmin.sol

490:             p.approveWeight += weight;

492:             p.rejectWeight += weight;

```

```solidity
File: DegenerusAffiliate.sol

541:         _totalAffiliateScore[lvl] += scaledAmount;

698:                 sum += affiliateCoinEarned[lvl][player];

871:             running += amounts[i];

```

```solidity
File: DegenerusGame.sol

55:   +==============================================================================+

58:   +==============================================================================+*/

97:       +======================================================================+

100:       +======================================================================+*/

114:       +======================================================================+

117:       +======================================================================+*/

135:       +=======================================================================+

138:       +=======================================================================+*/

168:       +======================================================================+

171:       +======================================================================+*/

211:       +======================================================================+

227:       +======================================================================+*/

231:       +======================================================================+

234:       +======================================================================+*/

260:       +======================================================================+*/

264:       +========================================================================================+

284:       +========================================================================================+*/

321:       +========================================================================================+

323:       +========================================================================================+*/

352:       +======================================================================+

355:       +======================================================================+*/

462:       +======================================================================+*/

501:       +======================================================================+*/

992:       +======================================================================+

995:       +======================================================================+*/

999:       +================================================================================================================+

1016:       +================================================================================================================+*/

1053:       +========================================================================================+*/

1287:       +========================================================================================+

1296:       +========================================================================================+*/

1411:         levelDgnrsClaimed[currLevel] += paid;

1431:       +======================================================================+*/

1690:       +======================================================================+*/

1715:       +======================================================================+*/

1779:       +===============================================================================================+

1787:       +===============================================================================================+*/

1791:       +======================================================================+

1799:       +======================================================================+*/

1853:       +======================================================================+

1868:       +======================================================================+*/

1951:       +======================================================================+

1954:       +======================================================================+*/

2022:       +======================================================================+

2025:       +======================================================================+*/

2245:       +======================================================================+

2247:       +======================================================================+*/

2329:       +======================================================================+

2332:       +======================================================================+*/

2395:       +======================================================================+

2408:       +======================================================================+*/

2449:                 bonusBps += 25 * 100;

2468:                 bonusBps += mintCountPoints * 100;

2477:             bonusBps += questStreak * 100;

2481:             bonusBps +=

2486:                 bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;

2490:                     bonusBps += 1000; // +10% for 10-level bundle

2492:                     bonusBps += 4000; // +40% for 100-level bundle

2525:       +======================================================================+

2527:       +======================================================================+*/

2584:       +======================================================================+

2587:       +======================================================================+*/

2710:       +======================================================================+

2712:       +======================================================================+*/

2758:       +======================================================================+*/

2825:       +======================================================================+

2828:       +======================================================================+*/

2832:       +======================================================================+

2835:       +======================================================================+*/

```

```solidity
File: DegenerusJackpots.sol

9:   +==============================================================================+*/

42:       +======================================================================+

45:       +======================================================================+*/

55:       +======================================================================+

57:       +======================================================================+*/

73:       +======================================================================+

75:       +======================================================================+*/

88:       +======================================================================+

90:       +======================================================================+*/

101:       +======================================================================+

103:       +======================================================================+*/

111:       +======================================================================+

113:       +======================================================================+*/

135:       +======================================================================+

137:       +======================================================================+*/

155:       +======================================================================+

158:       +======================================================================+*/

176:         unchecked { total += amount; }

185:       +======================================================================+

207:       +======================================================================+*/

249:                 toReturn += topPrize;

262:                 toReturn += topPrize;

280:                 toReturn += prize;

317:                 toReturn += farFirst;

322:                 toReturn += farSecond;

359:                 toReturn += farFirst;

364:                 toReturn += farSecond;

456:             toReturn += scatterTop - perRoundFirst * firstCount;

457:             toReturn += scatterSecond - perRoundSecond * secondCount;

495:       +======================================================================+

497:       +======================================================================+*/

525:       +======================================================================+

527:       +======================================================================+*/

644:       +======================================================================+*/

```

```solidity
File: DegenerusQuests.sol

510:                     totalReward += reward;

1335:             total += weight;

1418:                 newStreak += 1;

1486:             reward += extraReward;

```

```solidity
File: DegenerusStonk.sol

217:             balanceOf[to] += amount;

```

```solidity
File: DegenerusTraitUtils.sol

11:   +==============================================================================+

13:   +==============================================================================+

64:   +==============================================================================+

66:   +==============================================================================+

82:   +==============================================================================+*/

93:       +======================================================================+

96:       +======================================================================+*/

132:       +======================================================================+

135:       +======================================================================+*/

154:       +======================================================================+

156:       +======================================================================+*/

```

```solidity
File: DegenerusVault.sol

73: +========================================================================================================+

76: +========================================================================================================+

129: +========================================================================================================+*/

261:             totalSupply += amount;

262:             balanceOf[to] += amount;

296:             balanceOf[to] += amount;

458:             coinTracked += coinAmount;

771:             coinBal += vaultBal + claimable;

994:                 mainReserve += vaultBal + claimable;

```

```solidity
File: DeityBoonViewer.sol

115:         cursor += W_COINFLIP_5;

117:         cursor += W_COINFLIP_10;

119:         cursor += W_COINFLIP_25;

121:         cursor += W_LOOTBOX_5;

123:         cursor += W_LOOTBOX_15;

125:         cursor += W_LOOTBOX_25;

127:         cursor += W_PURCHASE_5;

129:         cursor += W_PURCHASE_15;

131:         cursor += W_PURCHASE_25;

134:             cursor += W_DECIMATOR_10;

136:             cursor += W_DECIMATOR_25;

138:             cursor += W_DECIMATOR_50;

141:         cursor += W_WHALE_10;

143:         cursor += W_WHALE_25;

145:         cursor += W_WHALE_50;

148:             cursor += W_DEITY_PASS_10;

150:             cursor += W_DEITY_PASS_25;

152:             cursor += W_DEITY_PASS_50;

155:         cursor += W_ACTIVITY_10;

157:         cursor += W_ACTIVITY_25;

159:         cursor += W_ACTIVITY_50;

161:         cursor += W_WHALE_PASS;

163:         cursor += W_LAZY_PASS_10;

165:         cursor += W_LAZY_PASS_25;

167:         cursor += W_LAZY_PASS_50;

```

```solidity
File: GNRUS.sol

421:             weight += uint48((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / BPS_DENOM);

426:             proposals[proposalId].approveWeight += weight;

428:             proposals[proposalId].rejectWeight += weight;

496:             balanceOf[recipient] += distribution;

534:             totalSupply += amount;

535:             balanceOf[to] += amount;

```

```solidity
File: Icons32Data.sol

7: +=======================================================================================================+

10: +=======================================================================================================+

46: +=======================================================================================================+

73: +=======================================================================================================+

81: +=======================================================================================================+

```

```solidity
File: StakedDegenerusStonk.sol

275:             lootboxAmount += dust;

317:             balanceOf[to] += amount;

388:             balanceOf[to] += amount;

413:         poolBalances[toIdx] += amount;

719:         redemptionPeriodBurned += amount;

744:         pendingRedemptionEthValue += ethValueOwed;

745:         pendingRedemptionEthBase += ethValueOwed;

746:         pendingRedemptionBurnie += burnieOwed;

747:         pendingRedemptionBurnieBase += burnieOwed;

758:         claim.ethValueOwed += uint96(ethValueOwed);

760:         claim.burnieOwed += uint96(burnieOwed);

832:             totalSupply += amount;

833:             balanceOf[to] += amount;

```

```solidity
File: WrappedWrappedXRP.sol

43:       +======================================================================+

45:       +======================================================================+*/

80:       +======================================================================+

82:       +======================================================================+*/

113:       +======================================================================+

115:       +======================================================================+*/

143:       +======================================================================+

146:       +======================================================================+*/

166:       +======================================================================+

168:       +======================================================================+*/

188:       +======================================================================+

190:       +======================================================================+*/

246:         balanceOf[to] += amount;

257:         totalSupply += amount;

258:         balanceOf[to] += amount;

278:       +======================================================================+

280:       +======================================================================+*/

323:         wXRPReserves += amount;

330:       +======================================================================+

332:       +======================================================================+*/

```

```solidity
File: libraries/JackpotBucketLib.sol

157:                 scaledTotal += scaled;

191:                     capped[idx] += 1;

230:                 distributed += share;

```

### <a name="GAS-2"></a>[GAS-2] Use assembly to check for `address(0)`
*Saves 6 gas per instance*

*Instances (88)*:
```solidity
File: BurnieCoin.sol

454:         if (from == address(0) || to == address(0)) revert ZeroAddress();

480:         if (to == address(0)) revert ZeroAddress();

500:         if (from == address(0)) revert ZeroAddress();

557:         if (player == address(0) || amount == 0) return;

585:         if (player == address(0) || amount == 0) return;

706:         if (to == address(0)) revert ZeroAddress();

730:         if (player == address(0) || amount == 0) return 0;

892:         if (player == address(0) || player == msg.sender) {

983:         if (player == address(0) || player == msg.sender) {

```

```solidity
File: BurnieCoinflip.sol

228:         if (player == address(0) || player == msg.sender) {

656:                 if (currentBountyOwner != address(0)) {

680:         if (player == address(0)) {

824:         if (bountyOwner != address(0) && currentBounty_ > 0) {

873:         if (player == address(0) || amount == 0) return;

885:             if (player != address(0) && amount != 0) {

1099:         if (score > dayLeader.score || dayLeader.player == address(0)) {

1114:         if (player == address(0)) return msg.sender;

```

```solidity
File: DegenerusAdmin.sol

361:             feed != address(0) &&

404:         if (newCoordinator == address(0) || newKeyHash == bytes32(0))

738:         if (feed == address(0) || amount == 0) return 0;

778:         if (feed == address(0)) return false;

```

```solidity
File: DegenerusAffiliate.sol

329:         if (referrer == address(0) || referrer == msg.sender) revert Insufficient();

332:         if (existing != bytes32(0) && !_vaultReferralMutable(existing)) revert Insufficient();

425:         if (storedCode == bytes32(0)) {

427:             if (code == bytes32(0)) {

436:                 if (resolved == address(0) || resolved == sender) {

446:                     if (customInfo.owner != address(0)) {

457:             if (code != bytes32(0) && code != storedCode && _vaultReferralMutable(storedCode)) {

459:                 if (resolved != address(0) && resolved != sender) {

462:                     if (customInfo.owner != address(0)) {

479:                     if (customInfo.owner != address(0)) {

692:         if (player == address(0) || currLevel == 0) return 0;

736:         if (owner != address(0)) return owner;

752:         if (code == bytes32(0) || code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) return ContractAddresses.VAULT;

754:         if (owner == address(0)) return ContractAddresses.VAULT;

764:         if (owner == address(0)) revert Zero();

766:         if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();

773:         if (info.owner != address(0)) revert Insufficient();

783:         if (player == address(0)) revert Zero();

786:         if (referrer == address(0) || referrer == player) revert Insufficient();

787:         if (playerReferralCode[player] != bytes32(0)) revert Insufficient();

798:         if (player == address(0) || amount == 0) return;

```

```solidity
File: DegenerusDeityPass.sol

90:         if (newOwner == address(0)) revert ZeroAddress();

130:         if (_owners[tokenId] == address(0)) revert InvalidToken();

148:         if (renderer != address(0)) {

334:         if (account == address(0)) revert ZeroAddress();

340:         if (ownerAddr == address(0)) revert InvalidToken();

344:         if (_owners[tokenId] == address(0)) revert InvalidToken();

384:         if (_owners[tokenId] != address(0)) revert InvalidToken();

385:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: DegenerusGame.sol

445:         if (winningBet < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;

470:         operatorApprovals[msg.sender][operator] = approved;

495:         if (player != msg.sender) _requireApproved(player);

1817:         uint256 stBal = steth.balanceOf(address(this));

2428:         uint256 packed = mintPacked_[player];

2691:                     }

```

```solidity
File: DegenerusJackpots.sol

302:                 if (score > bestScore || best == address(0)) {

307:                 } else if ((score > secondScore || second == address(0)) && cand != best) {

344:                 if (score > bestScore || best == address(0)) {

349:                 } else if ((score > secondScore || second == address(0)) && cand != best) {

433:                 if (best != address(0)) {

439:                 if (second != address(0)) {

515:         if (candidate != address(0)) {

```

```solidity
File: DegenerusQuests.sol

332:         if (player == address(0) || amount == 0 || currentDay == 0) return;

452:         if (player == address(0) || quantity == 0 || currentDay == 0) {

549:         if (player == address(0) || flipCredit == 0 || currentDay == 0) {

604:         if (player == address(0) || burnAmount == 0 || currentDay == 0) {

655:         if (player == address(0) || amount == 0 || currentDay == 0) {

708:         if (player == address(0) || amountWei == 0 || currentDay == 0) {

762:         if (player == address(0) || amount == 0 || currentDay == 0) {

```

```solidity
File: DegenerusStonk.sol

155:         if (recipient == address(0)) revert ZeroAddress();

211:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: DegenerusVault.sol

259:         if (to == address(0)) revert ZeroAddress();

291:         if (to == address(0)) revert ZeroAddress();

751:             player = msg.sender;

821:             player = msg.sender;

```

```solidity
File: GNRUS.sol

357:         if (recipient == address(0)) revert ZeroAddress();

371:             if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = proposer;

419:         if (voter == levelVaultOwner[level] || (levelVaultOwner[level] == address(0) && vault.isVaultOwner(voter))) {

420:             if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = voter;

532:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: StakedDegenerusStonk.sol

312:         if (to == address(0)) revert ZeroAddress();

378:         if (to == address(0)) revert ZeroAddress();

830:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: WrappedWrappedXRP.sol

242:         if (from == address(0) || to == address(0)) revert ZeroAddress();

255:         if (to == address(0)) revert ZeroAddress();

267:         if (from == address(0)) revert ZeroAddress();

365:         if (to == address(0)) revert ZeroAddress();

```

### <a name="GAS-3"></a>[GAS-3] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (5)*:
```solidity
File: GNRUS.sol

159:     bool public finalized;

173:     mapping(uint24 => bool) public levelResolved;

176:     mapping(uint24 => mapping(address => bool)) public hasProposed;

182:     mapping(uint24 => mapping(address => mapping(uint48 => bool))) public hasVoted;

```

```solidity
File: Icons32Data.sol

129:     bool private _finalized;

```

### <a name="GAS-4"></a>[GAS-4] Cache array length outside of loop
If not cached, the solidity compiler will always read the length of the array during each iteration. That is, if it is a storage array, this is an extra sload operation (100 additional extra gas for each iteration except for the first) and if it is a memory array, this is an extra mload operation (3 additional gas for each iteration except for the first).

*Instances (1)*:
```solidity
File: Icons32Data.sol

159:         for (uint256 i = 0; i < paths.length; ++i) {

```

### <a name="GAS-5"></a>[GAS-5] State variables should be cached in stack variables rather than re-reading them from storage
The instances below point to the second+ access of a state variable within a function. Caching of a state variable replaces each Gwarmaccess (100 gas) with a much cheaper stack read. Other less obvious fixes/optimizations include having local memory caches of state variable structs, or having local caches of state variable contracts/addresses.

*Saves 100 gas per instance*

*Instances (3)*:
```solidity
File: BurnieCoinflip.sol

854:             currentBounty,

```

```solidity
File: DegenerusDeityPass.sol

204:             _nonCryptoSymbolColor,

```

```solidity
File: StakedDegenerusStonk.sol

721:         uint256 supplyBefore = totalSupply;

```

### <a name="GAS-6"></a>[GAS-6] Use calldata instead of memory for function arguments that do not get mutated
When a function with a `memory` array is called externally, the `abi.decode()` step has to use a for-loop to copy each index of the `calldata` to the `memory` index. Each iteration of this for-loop costs at least 60 gas (i.e. `60 * <mem_array>.length`). Using `calldata` directly bypasses this loop. 

If the array is passed to an `internal` function which passes the array to another internal function where the array is modified and therefore `memory` is used in the `external` call, it's still more gas-efficient to use `calldata` when the `external` function uses modifiers, since the modifiers may prevent the internal functions from being called. Structs have the same overhead as an array of length one. 

 *Saves 60 gas per instance*

*Instances (1)*:
```solidity
File: Icons32Data.sol

172:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

```

### <a name="GAS-7"></a>[GAS-7] For Operations that will not overflow, you could use unchecked

*Instances (1054)*:
```solidity
File: BurnieCoin.sol

25: import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

26: import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";

27: import {ContractAddresses} from "./ContractAddresses.sol";

42:       +======================================================================+

43:       |  Lightweight ERC20 events plus gameplay signals for off-chain        |

44:       |  indexers/clients. Events are the primary mechanism for UIs to       |

46:       +======================================================================+*/

113:       +======================================================================+

114:       |  Custom errors for gas-efficient reverts. Each error corresponds     |

116:       +======================================================================+*/

153:       +======================================================================+

154:       |  Minimal ERC20 metadata/state. Transfers are protected by Solidity   |

155:       |  0.8+ overflow checks. No SafeMath needed.                           |

158:       |  +-----------------------------------------------------------------+ |

160:       |  +------+-----------------------------+----------------------------+ |

161:       |  |  0   | _supply (total/vault)       | uint128 + uint128          | |

164:       |  +-----------------------------------------------------------------+ |

165:       +======================================================================+*/

215:       +======================================================================+

216:       |  Packed structs for gas-efficient storage. Each struct fits within   |

217:       |  a single 32-byte slot where possible.                               |

218:       +======================================================================+*/

230:       +======================================================================+

231:       |  All external dependencies are compile-time constants sourced from  |

233:       |  the references cannot be updated post-deploy.                       |

238:       +======================================================================+*/

256:       +======================================================================+

260:       +======================================================================+*/

268:       +======================================================================+*/

277:       +======================================================================+

278:       |  Read-only functions for UIs and external contracts to query state.  |

279:       +======================================================================+*/

298:             spendable += uint256(_supply.vaultAllowance);

301:             spendable += IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);

333:         return uint256(_supply.totalSupply) + uint256(_supply.vaultAllowance);

345:       +======================================================================+

346:       |  Global bounty pool for record-breaking flips. The bounty pool       |

348:       |  a new all-time high flip, they arm the bounty. On their next        |

353:       |  +-----------------------------------------------------------------+ |

355:       |  +------+------------------+----------+----------+-----------------+ |

357:       |  |      | biggestFlipEver  | uint128  | 16 bytes | All-time record | |

359:       |  +-----------------------------------------------------------------+ |

360:       +======================================================================+*/

375:       +======================================================================+*/

383:       +======================================================================+

384:       |  Standard ERC20 interface with game-contract bypass for transferFrom.|

387:       +======================================================================+*/

433:                 uint256 newAllowance = allowed - amount;

456:         balanceOf[from] -= amount;

462:                 _supply.totalSupply -= amount128;

463:                 _supply.vaultAllowance += amount128;

471:         balanceOf[to] += amount;

484:                 _supply.vaultAllowance += amount128;

489:         _supply.totalSupply += amount128;

490:         balanceOf[to] += amount;

506:                 _supply.vaultAllowance = allowanceVault - amount128;

512:         balanceOf[from] -= amount;

513:         _supply.totalSupply -= amount128;

519:       +======================================================================+

520:       |  Permission functions for BurnieCoinflip contract to burn/mint      |

522:       +======================================================================+*/

529:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

538:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

598:                 amount - balance

611:                 amount - balance

618:       +======================================================================+

623:       |  +-----------------------------------------------------------------+ |

625:       |  +------------------------+----------------------------------------+ |

631:       |  +-----------------------------------------------------------------+ |

632:       +======================================================================+*/

679:       +======================================================================+

681:       |  increases the allowance (called by game/modules), vaultMintTo()     |

683:       +======================================================================+*/

696:             _supply.vaultAllowance += amount128;

711:             _supply.vaultAllowance = allowanceVault - amount128;

712:             _supply.totalSupply += amount128;

713:             balanceOf[to] += amount;

749:       +======================================================================+

751:       |  to route quest-related calls to the quest module while maintaining  |

753:       +======================================================================+*/

770:                     ++i;

874:         _burn(target, amount - consumed);

879:       +======================================================================+

882:       +======================================================================+*/

908:         _burn(caller, amount - consumed);

930:         uint256 baseAmount = amount + questReward;

953:             uint256 boost = (cappedBase * boonBps) / BPS_DENOMINATOR;

954:             baseAmount += boost;

970:       +======================================================================+

971:       |  Always-open burn betting on GAMEOVER. Time multiplier rewards       |

973:       +======================================================================+*/

998:         _burn(caller, amount - consumed);

1011:       +======================================================================+

1012:       |  Read-only functions for querying coinflip stake amounts.            |

1013:       +======================================================================+*/

1024:       +======================================================================+*/

1039:         uint256 range = uint256(DECIMATOR_BUCKET_BASE) - uint256(minBucket);

1040:         uint256 reduction = (range * bonusBps + (DECIMATOR_ACTIVITY_CAP_BPS / 2)) / DECIMATOR_ACTIVITY_CAP_BPS;

1041:         uint256 bucket = uint256(DECIMATOR_BUCKET_BASE) - reduction;

1049:         return BPS_DENOMINATOR + (bonusBps / 3);

```

```solidity
File: BurnieCoinflip.sol

22: import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

23: import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";

24: import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";

25: import {ContractAddresses} from "./ContractAddresses.sol";

39:       +======================================================================+*/

94:       +======================================================================+*/

110:       +======================================================================+*/

133:     uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;

177:       +======================================================================+*/

188:       +======================================================================+*/

210:       +======================================================================+*/

220:             state.claimableStored = uint128(uint256(state.claimableStored) + mintable);

257:             state.claimableStored = uint128(uint256(state.claimableStored) + mintable);

286:         uint256 creditedFlip = amount + questReward;

305:             creditedFlip += bonus;

320:       +======================================================================+*/

380:         uint256 stored = state.claimableStored + mintable;

388:             state.claimableStored = uint128(stored - toClaim);

433:             mintable += oldCarry;

449:                 minClaimableDay = latest > windowDays ? latest - windowDays : 0;

461:             cursor = start + 1;

467:             uint48 available = latest - start;

484:                 unchecked { ++cursor; --remaining; }

491:                 stake += carry;

502:                     uint256 payout = stake +

503:                         (stake * uint256(rewardPercent)) /

510:                         winningBafCredit += payout;

514:                             uint256 reserved = (payout / takeProfit) *

517:                                 mintable += reserved;

519:                             carry = payout - reserved;

525:                                 carry += _afKingRecyclingBonus(

530:                                 carry += _recyclingBonus(carry);

534:                         mintable += payout;

538:                         ++lossCount;

548:                 ++cursor;

549:                 --remaining;

597:             wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);

605:       +======================================================================+*/

621:                 uint256 maxDeposit = 100_000 ether; // Cap at 100k BURNIE for boost calc

625:                 uint256 boost = (cappedDeposit * boonBps) / 10_000;

626:                 coinflipDeposit += boost;

634:         uint256 newStake = prevStake + coinflipDeposit;

657:                     uint256 onePercent = uint256(record) / 100;

659:                     threshold = uint256(record) + (onePercent == 0 ? 1 : onePercent);

670:       |                    AUTO-REBUY FUNCTIONS                              |

671:       +======================================================================+*/

736:                 mintable += carry;

775:       +======================================================================+*/

792:             rewardPercent = 50; // Unlucky: 50% bonus (1.5x total)

794:             rewardPercent = 150; // Lucky: 150% bonus (2.5x total)

798:                 (seedWord % COINFLIP_EXTRA_RANGE) + COINFLIP_EXTRA_MIN_PERCENT

805:                 rewardPercent += 6;

825:             slice = currentBounty_ >> 1; // pay/delete half of the bounty pool

827:                 currentBounty_ -= uint128(slice);

847:             currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT);

866:       +======================================================================+*/

889:                 ++i;

896:       +======================================================================+*/

902:         return daily + stored;

954:                 ? latestDay - windowDays

964:             cursor = startDay + 1;

971:                 unchecked { ++cursor; --remaining; }

979:                     uint256 payout = flipStake +

980:                         (flipStake * uint256(result.rewardPercent)) /

982:                     total += payout;

986:                 ++cursor;

987:                 --remaining;

994:       +======================================================================+*/

1020:         bonus = amount / 100;

1032:         uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;

1034:             uint256 totalHalfBps = baseHalfBps + uint256(deityBonusHalfBps);

1035:             return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1037:         uint256 fullHalfBps = baseHalfBps + uint256(deityBonusHalfBps);

1038:         return (DEITY_RECYCLE_CAP * fullHalfBps + (amount - DEITY_RECYCLE_CAP) * baseHalfBps)

1039:             / (uint256(BPS_DENOMINATOR) * 2);

1051:         uint24 levelsActive = currentLevel - activationLevel;

1052:         uint24 bonus = levelsActive * uint24(AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS);

1061:         return degenerusGame.currentDayView() + 1;

1084:         uint256 wholeTokens = s / 1 ether;

1107:         uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;

```

```solidity
File: DegenerusAdmin.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

412:                 block.timestamp - uint256(ep.createdAt) < PROPOSAL_LIFETIME) {

418:         uint256 stall = block.timestamp - uint256(lastVrf);

427:             if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)

432:         proposalId = ++proposalCount;

455:         if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD)

463:         if (block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME) {

478:                 p.approveWeight -= oldWeight;

480:                 p.rejectWeight -= oldWeight;

490:             p.approveWeight += weight;

492:             p.rejectWeight += weight;

502:             p.approveWeight * BPS >= uint256(t) * p.circulatingSnapshot &&

512:             p.rejectWeight * BPS >= uint256(t) * p.circulatingSnapshot

522:             - sDGNRS.balanceOf(ContractAddresses.SDGNRS)

523:             - sDGNRS.balanceOf(ContractAddresses.DGNRS);

531:         uint256 elapsed = block.timestamp - uint256(proposals[proposalId].createdAt);

533:         if (elapsed >= 144 hours) return 500;   // 5%

534:         if (elapsed >= 120 hours) return 1000;  // 10%

535:         if (elapsed >= 96 hours)  return 2000;  // 20%

536:         if (elapsed >= 72 hours)  return 3000;  // 30%

537:         if (elapsed >= 48 hours)  return 4000;  // 40%

538:         return 5000; // 50%

547:         if (block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME) return false;

551:         if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD) return false;

554:         return p.approveWeight * BPS >= uint256(t) * p.circulatingSnapshot

632:         uint256 start = voidedUpTo + 1;

634:         for (uint256 i = start; i <= count; i++) {

721:         uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;

722:         uint256 credit = (baseCredit * mult) / 1e18;

751:             if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE) return 0;

754:         ethAmount = (amount * uint256(answer)) / 1 ether;

763:             uint256 delta = (subBal * 2e18) / 200 ether;

765:                 return 3e18 - delta;

768:         uint256 excess = subBal - 200 ether;

769:         uint256 delta2 = (excess * 1e18) / 800 ether;

772:             return 1e18 - delta2;

790:                 if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE)

```

```solidity
File: DegenerusAffiliate.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

6: import {GameTimeLib} from "./libraries/GameTimeLib.sol";

143:         address player; // 20 bytes - address of top affiliate

144:         uint96 score; // 12 bytes - raw 18-decimal amount (capped to uint96 max)

159:         address owner; // 20 bytes - receives affiliate rewards

160:         uint8 kickback; // 1 byte - percentage returned to referred player (0-25)

181:     bytes32 private constant AFFILIATE_ROLL_TAG = keccak256("affiliate-payout-roll-v1");

272:                 ++i;

283:                 ++i;

334:         emit Affiliate(0, code_, msg.sender); // 0 = player referred

513:         uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;

531:             uint256 remainingCap = MAX_COMMISSION_PER_REFERRER_PER_LEVEL - alreadyEarned;

535:             affiliateCommissionFromSender[lvl][affiliateAddr][sender] = alreadyEarned + scaledAmount;

539:         uint256 newTotal = earned[affiliateAddr] + scaledAmount;

541:         _totalAffiliateScore[lvl] += scaledAmount;

564:             kickbackShare = (scaledAmount * uint256(kickbackPct)) / 100;

565:             affiliateShareBase = scaledAmount - kickbackShare;

577:             uint256 totalAmount = scaledAmount + scaledAmount / 5 + scaledAmount / 25;

604:             amounts[0] = affiliateShareBase + questReward;

608:             uint256 baseBonus = scaledAmount / 5;

611:             amounts[1] = baseBonus + questRewardUpline;

615:             uint256 bonus2 = scaledAmount / 25;

618:             amounts[2] = bonus2 + questReward2;

622:             uint256 totalAmount = amounts[0] + amounts[1] + amounts[2];

697:                 uint24 lvl = currLevel - offset;

698:                 sum += affiliateCoinEarned[lvl][player];

699:                 ++offset;

705:         points = sum / ethUnit;

778:         emit Affiliate(1, code_, owner); // 1 = code created

789:         emit Affiliate(0, code_, player); // 0 = player referred

838:             return (amt * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

840:         uint256 excess = uint256(score) - LOOTBOX_TAPER_START_SCORE;

841:         uint256 range = uint256(LOOTBOX_TAPER_END_SCORE) - LOOTBOX_TAPER_START_SCORE;

842:         uint256 reductionBps = (BPS_DENOMINATOR - LOOTBOX_TAPER_MIN_BPS) * excess / range;

843:         return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;

871:             running += amounts[i];

874:                 ++i;

```

```solidity
File: DegenerusDeityPass.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

6: import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

134:         uint8 quadrant = uint8(tokenId / 8);

138:             symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));

163:             '{"name":"Deity Pass #', Strings.toString(tokenId), ' - ', symbolName,

165:             symbolName, ' symbol.","image":"data:image/svg+xml;base64,',

171:             "data:application/json;base64,",

183:         uint32 sSym1e6 = uint32((uint256(2) * SYMBOL_HALF_SIZE * fitSym1e6) / ICON_VB);

191:                     ? "'><g style='vector-effect:non-scaling-stroke'>"

192:                     : "'><g class='nonCrypto' style='vector-effect:non-scaling-stroke'>",

194:                 "</g></g>"

199:             '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'

201:             '<style>.nonCrypto *{fill:',

205:             '!important;}</style>'

206:             '</defs>'

207:             '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',

211:             '" stroke-width="2.2"/>',

213:             "</svg>"

246:         for (uint256 i = 1; i < 7; ++i) {

270:         int256 w1e6 = int256(uint256(w)) * scale;

271:         int256 h1e6 = int256(uint256(h)) * scale;

272:         txm = -w1e6 / 2;

273:         tyn = -h1e6 / 2;

298:         uint256 i = x / 1_000_000;

305:             return string(abi.encodePacked("-", _dec6(uint256(-x))));

312:         for (uint256 k; k < 6; ++k) {

313:             b[5 - k] = bytes1(uint8(48 + (f % 10)));

314:             f /= 10;

324:         return id == 0x80ac58cd  // IERC721

325:             || id == 0x5b5e139f  // IERC721Metadata

326:             || id == 0x01ffc9a7; // IERC165

387:         _balances[to]++;

```

```solidity
File: DegenerusGame.sol

30: import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";

31: import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";

32: import {IDegenerusAffiliate} from "./interfaces/IDegenerusAffiliate.sol";

33: import {IStakedDegenerusStonk} from "./interfaces/IStakedDegenerusStonk.sol";

34: import {IStETH} from "./interfaces/IStETH.sol";

45: } from "./interfaces/IDegenerusGameModules.sol";

46: import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";

49: } from "./modules/DegenerusGameMintStreakUtils.sol";

50: import {ContractAddresses} from "./ContractAddresses.sol";

51: import {BitPackingLib} from "./libraries/BitPackingLib.sol";

55:   +==============================================================================+

58:   +==============================================================================+*/

97:       +======================================================================+

98:       |  Custom errors for gas-efficient reverts. Each error maps to a       |

100:       +======================================================================+*/

114:       +======================================================================+

115:       |  Events for off-chain indexers and UIs. All critical state changes   |

117:       +======================================================================+*/

135:       +=======================================================================+

138:       +=======================================================================+*/

168:       +======================================================================+

171:       +======================================================================+*/

174:     uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365; // 1 year

211:       +======================================================================+

215:       |  [0-23]   lastEthLevel     - Last level where player minted with ETH |

216:       |  [24-47]  ethLevelCount    - Total levels with ETH mints             |

217:       |  [48-71]  ethLevelStreak   - Consecutive levels with ETH mints       |

218:       |  [72-103] lastEthDay       - Day index of last ETH mint              |

219:       |  [104-127] unitsLevel      - Level index for unitsAtLevel tracking   |

220:       |  [128-151] frozenUntilLevel - Whale bundle freeze level (0 = none)   |

221:       |  [152-153] whaleBundleType  - Bundle type (0=none,1=10,3=100)        |

222:       |  [154-159] (reserved)       - 6 unused bits                           |

223:       |  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |

224:       |  [184-227] (reserved)      - 44 unused bits                          |

225:       |  [228-243] unitsAtLevel    - Mints at current level                  |

226:       |  [244]    (deprecated)     - Previously used for bonus tracking      |

227:       +======================================================================+*/

231:       +======================================================================+

234:       +======================================================================+*/

253:                 ++i;

260:       +======================================================================+*/

264:       +========================================================================================+

276:       |  • Anyone — bypasses after 30+ min since level start                                   |

277:       |  • Pass holder (lazy/whale) — bypasses after 15+ min                                   |

283:       |  • Auto-ends when PURCHASE→JACKPOT, or admin can end manually (one-way, cannot re-enable) |

284:       +========================================================================================+*/

321:       +========================================================================================+

322:       |  One-time VRF setup function called by ADMIN during deployment phase.                  |

323:       +========================================================================================+*/

352:       +======================================================================+

355:       +======================================================================+*/

393:             uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) /

395:             uint256 nextShare = prizeContribution - futureShare;

399:                     pNext + uint128(nextShare),

400:                     pFuture + uint128(futureShare)

405:                     next + uint128(nextShare),

406:                     future + uint128(futureShare)

451:         uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;

462:       +======================================================================+*/

501:       +======================================================================+*/

881:         deityPassAvailable = deityPassOwners.length < 32; // DEITY_PASS_MAX_TOTAL (see LootboxModule)

947:                 newClaimableBalance = claimable - amount;

955:             uint256 remaining = amount - msg.value;

959:                     uint256 available = claimable - 1; // Preserve 1 wei sentinel

965:                             newClaimableBalance = claimable - claimableUsed;

968:                         remaining -= claimableUsed;

972:             if (remaining != 0) revert E(); // Must fully cover cost

973:             prizeContribution = msg.value + claimableUsed;

979:             claimablePool -= claimableUsed;

992:       +======================================================================+

995:       +======================================================================+*/

999:       +================================================================================================================+

1004:       |  • GAME_ADVANCE_MODULE      - Daily advance, VRF, daily processing                                             |

1005:       |  • GAME_BOON_MODULE         - Deity boon effects and activation                                                |

1006:       |  • GAME_DECIMATOR_MODULE    - Decimator claim credits and lootbox payouts                                       |

1007:       |  • GAME_DEGENERETTE_MODULE  - Degenerette bet placement and resolution                                          |

1008:       |  • GAME_ENDGAME_MODULE      - Endgame settlement (payouts, wipes, jackpots)                                     |

1009:       |  • GAME_JACKPOT_MODULE      - Jackpot calculations and payouts                                                  |

1010:       |  • GAME_LOOTBOX_MODULE      - Lootbox open, credit, and payout                                                  |

1011:       |  • GAME_MINT_MODULE         - Mint data recording, airdrop multipliers                                          |

1012:       |  • GAME_WHALE_MODULE        - Whale bundle purchases                                                            |

1016:       +================================================================================================================+*/

1023:         assembly ("memory-safe") {

1053:       +========================================================================================+*/

1267:             (round.poolWei * uint256(entryBurn)) /

1281:         uint8 shift = (denom - 2) << 2;

1287:       +========================================================================================+

1292:       |  • Uses CEI pattern (Checks-Effects-Interactions)                                      |

1296:       +========================================================================================+*/

1363:             claimableWinnings[player] = 1; // Leave sentinel

1364:             payout = amount - 1;

1366:         claimablePool -= payout; // CEI: update state before external call

1401:         uint256 reward = (allocation * score) / denominator;

1411:         levelDgnrsClaimed[currLevel] += paid;

1414:             uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;

1415:             uint256 cap = (AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH *

1416:                 PRICE_COIN_UNIT) / price;

1430:       |                    AUTO-REBUY TOGGLE                                |

1431:       +======================================================================+*/

1679:             uint256 unlockLevel = uint256(activationLevel) + AFKING_LOCK_LEVELS;

1690:       +======================================================================+*/

1715:       +======================================================================+*/

1741:             claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;

1743:         claimablePool -= amount;

1748:             _setPendingPools(pNext, pFuture + uint128(amount));

1751:             _setPrizePools(next, future + uint128(amount));

1772:             remaining -= box;

1779:       +===============================================================================================+

1784:       |  • Daily jackpot - Paid each day to burn ticket holders (day 5 = full pool payout)             |

1785:       |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |

1786:       |  • BAF - Big-ass-flip jackpot (20% of pool at L%100=0)                                        |

1787:       +===============================================================================================+*/

1791:       +======================================================================+

1792:       |  Admin-only functions for managing ETH/stETH liquidity.              |

1796:       |  • Admin-only access (VRF owner contract)                            |

1798:       |  • All operations are value-preserving (no fund extraction)          |

1799:       +======================================================================+*/

1836:         uint256 stethSettleable = claimableWinnings[ContractAddresses.VAULT] +

1839:             ? claimablePool - stethSettleable

1842:         uint256 stakeable = ethBal - reserve;

1853:       +======================================================================+

1865:       |  • 12-hour timeout allows recovery from stale requests               |

1866:       |  • Governance-gated coordinator rotation via Admin                   |

1868:       +======================================================================+*/

1951:       +======================================================================+

1952:       |  Internal functions for ETH/stETH payouts.                           |

1954:       +======================================================================+*/

1981:         uint256 remaining = amount - ethSend;

1990:         uint256 leftover = remaining - stSend;

2011:         uint256 remaining = amount - stSend;

2022:       +======================================================================+

2023:       |  Lightweight view functions for UI/frontend consumption. These       |

2024:       |  provide read-only access to game state without gas costs.           |

2025:       +======================================================================+*/

2079:         amount = packed & ((1 << 232) - 1);

2167:         uint256 totalBalance = address(this).balance +

2169:         uint256 obligations = currentPrizePool +

2170:             _getNextPrizePool() +

2171:             claimablePool +

2172:             _getFuturePrizePool() +

2175:         return totalBalance - obligations;

2225:         if (rngWordByDay[day - 1] != 0) return false;

2226:         if (day < 2 || rngWordByDay[day - 2] != 0) return false;

2245:       +======================================================================+

2247:       +======================================================================+*/

2283:                 uint256(ts) + 10 days >

2284:                 uint256(lst) + uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;

2286:         return uint256(ts) + 5 days > uint256(lst) + 120 days;

2293:         return jackpotPhaseFlag ? level : level + 1;

2329:       +======================================================================+

2330:       |  Unpack player mint history from the bit-packed mintPacked_ storage. |

2332:       +======================================================================+*/

2395:       +======================================================================+

2398:       |  Activity Score Components (player engagement/loyalty metrics):      |

2399:       |  • Mint streak: +1% per consecutive level minted (cap 50%)           |

2400:       |  • Mint count: +25% for 100% participation, scaled proportionally    |

2401:       |  • Quest streak: +1% per consecutive quest (cap 100%)                |

2402:       |  • Affiliate points: +1% per affiliate point (cap 50%)               |

2404:       |    - 10-level bundle: +10%                                           |

2405:       |    - 100-level bundle: +40%                                          |

2406:       |  • Deity pass bonus: +80% (always active)                            |

2408:       +======================================================================+*/

2448:                 bonusBps = 50 * 100;

2449:                 bonusBps += 25 * 100;

2467:                 bonusBps = streakPoints * 100;

2468:                 bonusBps += mintCountPoints * 100;

2477:             bonusBps += questStreak * 100;

2481:             bonusBps +=

2482:                 affiliate.affiliateBonusPointsBest(currLevel, player) *

2486:                 bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;

2490:                     bonusBps += 1000; // +10% for 10-level bundle

2492:                     bonusBps += 4000; // +40% for 100-level bundle

2520:         return (uint256(mintCount) * 25) / uint256(currLevel);

2525:       +======================================================================+

2526:       |  Read-only accessors for claim balances and deferred lootbox totals. |

2527:       +======================================================================+*/

2537:             return stored - 1;

2584:       +======================================================================+

2587:       +======================================================================+*/

2608:         uint24 maxOffset = currentLvl - 1;

2614:             offset = uint24(word % maxOffset) + 1; // 1..maxOffset

2615:             lvlSel = currentLvl - offset;

2618:         traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word

2625:         uint256 take = len > 4 ? 4 : len; // only need a small sample for scatter draws

2627:         uint256 start = (word >> 40) % len; // consume another slice for the start offset

2629:             tickets[i] = arr[(start + i) % len];

2631:                 ++i;

2658:             tickets[i] = arr[(start + i) % len];

2660:                 ++i;

2680:             uint24 candidate = currentLvl + 5 + uint24(word % 95);

2690:                         ++found;

2695:                 ++s;

2703:                 ++i;

2710:       +======================================================================+

2711:       |  Read-only functions for querying trait state and game history.      |

2712:       +======================================================================+*/

2735:         uint256 end = offset + limit;

2739:             if (a[i] == player) count++;

2741:                 ++i;

2758:       +======================================================================+*/

2772:         wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;

2787:         for (uint8 q = 0; q < 4; ++q) {

2789:             for (uint8 s = 0; s < 8; ++s) {

2790:                 uint256 amount = (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;

2825:       +======================================================================+

2826:       |  Admin-only functions for testing and simulation purposes.           |

2828:       +======================================================================+*/

2832:       +======================================================================+

2835:       +======================================================================+*/

2843:             _setPendingPools(pNext, pFuture + uint128(msg.value));

2846:             _setPrizePools(next, future + uint128(msg.value));

```

```solidity
File: DegenerusJackpots.sol

9:   +==============================================================================+*/

11: import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

12: import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";

13: import {ContractAddresses} from "./ContractAddresses.sol";

42:       +======================================================================+

43:       |  Custom errors for gas-efficient reverts. Each error maps to a       |

45:       +======================================================================+*/

55:       +======================================================================+

57:       +======================================================================+*/

73:       +======================================================================+

75:       +======================================================================+*/

88:       +======================================================================+

90:       +======================================================================+*/

101:       +======================================================================+

103:       +======================================================================+*/

111:       +======================================================================+

112:       |  Per-player BAF totals and top-4 leaderboard per level.              |

113:       +======================================================================+*/

135:       +======================================================================+

137:       +======================================================================+*/

155:       +======================================================================+

158:       +======================================================================+*/

176:         unchecked { total += amount; }

185:       +======================================================================+

189:       |  +-----------------------------------------------------------------+ |

193:       |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)  | |

194:       |  |  5% | Far-future ticket holders 2nd draw (3% 1st / 2% 2nd)      | |

195:       |  | 45% | Scatter 1st place (50 rounds x 4 multi-level trait tickets) | |

196:       |  | 25% | Scatter 2nd place (50 rounds x 4 multi-level trait tickets) | |

197:       |  +-----------------------------------------------------------------+ |

200:       |  * Non-zero address only (no streak requirement)                     |

203:       |  • VRF-derived randomness for all random selections                  |

207:       +======================================================================+*/

242:             uint256 topPrize = P / 10;

246:                     ++n;

249:                 toReturn += topPrize;

255:             uint256 topPrize = P / 20;

259:                     ++n;

262:                 toReturn += topPrize;

268:                 ++salt;

271:             uint256 prize = P / 20;

272:             uint8 pick = 2 + uint8(entropy & 1);

277:                     ++n;

280:                 toReturn += prize;

286:             unchecked { ++salt; }

290:             uint256 farFirst = (P * 3) / 100;

291:             uint256 farSecond = P / 50;

311:                 unchecked { ++i; }

315:                 unchecked { ++n; }

317:                 toReturn += farFirst;

320:                 unchecked { ++n; }

322:                 toReturn += farSecond;

328:             unchecked { ++salt; }

332:             uint256 farFirst = (P * 3) / 100;

333:             uint256 farSecond = P / 50;

353:                 unchecked { ++i; }

357:                 unchecked { ++n; }

359:                 toReturn += farFirst;

362:                 unchecked { ++n; }

364:                 toReturn += farSecond;

372:             uint256 scatterTop = (P * 45) / 100;

373:             uint256 scatterSecond = P / 4;

383:                     ++salt;

393:                     else if (round < 8) targetLvl = lvl + 1 + uint24(entropy % 3);

394:                     else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);

396:                         uint24 maxBack = lvl > 99 ? 99 : lvl - 1;

397:                         targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;

401:                     else targetLvl = lvl + 1 + uint24(entropy % 4);

428:                         ++i;

436:                         ++firstCount;

442:                         ++secondCount;

447:                     ++round;

452:             uint256 perRoundFirst = scatterTop / BAF_SCATTER_ROUNDS;

453:             uint256 perRoundSecond = scatterSecond / BAF_SCATTER_ROUNDS;

456:             toReturn += scatterTop - perRoundFirst * firstCount;

457:             toReturn += scatterSecond - perRoundSecond * secondCount;

463:                     ++n;

464:                     ++i;

472:                     ++n;

473:                     ++i;

481:         assembly ("memory-safe") {

488:         unchecked { ++bafEpoch[lvl]; }

495:       +======================================================================+

497:       +======================================================================+*/

525:       +======================================================================+

526:       |  Maintain sorted top-4 leaderboard per level.                        |

527:       +======================================================================+*/

542:         uint256 wholeTokens = s / 1 ether;

561:         uint8 existing = 4; // sentinel: not found

568:                 ++i;

574:             if (score <= board[existing].score) return; // No improvement

578:             while (idx > 0 && board[idx].score > board[idx - 1].score) {

579:                 PlayerScore memory tmp = board[idx - 1];

580:                 board[idx - 1] = board[idx];

583:                     --idx;

592:             while (insert > 0 && score > board[insert - 1].score) {

593:                 board[insert] = board[insert - 1];

595:                     --insert;

599:             bafTopLen[lvl] = len + 1;

604:         if (score <= board[3].score) return; // Not good enough

606:         while (idx2 > 0 && score > board[idx2 - 1].score) {

607:             board[idx2] = board[idx2 - 1];

609:                 --idx2;

637:                 ++i;

644:       +======================================================================+*/

```

```solidity
File: DegenerusQuests.sol

4: import "./interfaces/IDegenerusQuests.sol";

5: import "./interfaces/IDegenerusGame.sol";

6: import {ContractAddresses} from "./ContractAddresses.sol";

185:     uint256 private constant QUEST_BURNIE_TARGET = 2 * PRICE_COIN_UNIT;

224:         uint48 day;       // Quest day identifier (derived by caller, not block timestamp)

225:         uint8 questType;  // One of the QUEST_TYPE_* constants

226:         uint8 flags;      // Difficulty flags (HIGH/VERY_HIGH)

227:         uint24 version;     // Bumped when quest mutates mid-day to reset stale player progress

228:         uint16 difficulty;  // Unused (fixed to 0); retained for storage compatibility

252:         uint24 lastCompletedDay;                    // Last day where a streak was credited (first slot completion)

253:         uint24 lastActiveDay;                       // Last day where ANY quest slot completed

254:         uint24 streak;                              // Current streak of days with full completion

255:         uint24 baseStreak;                          // Snapshot of streak at start of day (for rewards)

256:         uint24 lastSyncDay;                         // Day we last reset progress/completionMask

257:         uint24[QUEST_SLOT_COUNT] lastProgressDay;   // Per-slot: day when progress was recorded

258:         uint24[QUEST_SLOT_COUNT] lastQuestVersion;  // Per-slot: quest version when progress was recorded

259:         uint128[QUEST_SLOT_COUNT] progress;         // Per-slot: accumulated progress toward targets

260:         uint8 completionMask;                       // Bits 0-1: slot completion; bit 7: streak credited

338:         uint32 updated = uint32(prevStreak) + uint32(amount);

472:                     ++slot;

482:                     uint256 delta = uint256(quantity) * mintPrice;

510:                     totalReward += reward;

517:                 ++slot;

808:                 ++slot;

848:                 ++slot;

869:         if (anchorDay != 0 && currentDay > uint48(anchorDay + 1)) {

870:             uint32 missedDays = uint32(currentDay - uint48(anchorDay) - 1);

891:                 ++slot;

975:         slotIndex = type(uint8).max; // Sentinel for "not found"

984:                 ++slot;

1026:             uint256 sum = uint256(current) + delta;

1040:         newVersion = questVersionCounter++;

1114:         if (anchorDay != 0 && currentDay > uint48(anchorDay + 1)) {

1115:             uint32 missedDays = uint32(currentDay - uint48(anchorDay) - 1);

1119:                 questStreakShieldCount[player] = shields - uint16(used);

1129:                     state.streak = 0; // Missed more days than shields available

1132:                 state.streak = 0; // Full miss (no quest completion) for at least one day

1142:             state.baseStreak = state.streak; // Snapshot for consistent rewards

1252:             uint256 target = mintPrice * mult;

1256:             uint256 target = mintPrice * QUEST_LOOTBOX_TARGET_MULTIPLIER;

1305:                     ++candidate;

1311:                     ++candidate;

1318:                     ++candidate;

1335:             total += weight;

1338:                 ++candidate;

1355:                 roll -= weight;

1358:                 ++candidate;

1418:                 newStreak += 1;

1476:         uint8 otherSlot = slot ^ 1; // XOR to flip 0↔1

1486:             reward += extraReward;

```

```solidity
File: DegenerusStonk.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {IStETH} from "./interfaces/IStETH.sol";

131:                 allowance[from][msg.sender] = allowed - amount;

157:         if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 5 hours)

216:             balanceOf[from] = bal - amount;

217:             balanceOf[to] += amount;

227:             balanceOf[from] = bal - amount;

228:             totalSupply -= amount;

253:         if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

261:         uint256 stethToGnrus = stethOut / 2;

262:         uint256 stethToVault = stethOut - stethToGnrus;

263:         uint256 ethToGnrus = ethOut / 2;

264:         uint256 ethToVault = ethOut - ethToGnrus;

300:             balanceOf[player] = bal - amount;

301:             totalSupply -= amount;

```

```solidity
File: DegenerusTraitUtils.sol

11:   +==============================================================================+

13:   +==============================================================================+

16:   |  +------------------------------------------------------------------------+  |

17:   |  |  Bits 7-6: Quadrant identifier (0-3)                                   |  |

18:   |  |  Bits 5-3: Category bucket (0-7)                                       |  |

19:   |  |  Bits 2-0: Sub-bucket (0-7)                                            |  |

25:   |  |  • Sub-bucket: Variant within category (8 options, weighted)           |  |

26:   |  +------------------------------------------------------------------------+  |

29:   |  +------------------------------------------------------------------------+  |

30:   |  |  Bits 31-24: Trait D (quadrant 3)                                      |  |

31:   |  |  Bits 23-16: Trait C (quadrant 2)                                      |  |

32:   |  |  Bits 15-8:  Trait B (quadrant 1)                                      |  |

33:   |  |  Bits 7-0:   Trait A (quadrant 0)                                      |  |

36:   |  +------------------------------------------------------------------------+  |

39:   |  +------------------------------------------------------------------------+  |

41:   |  |  -------+----------+-------+------------                               |  |

42:   |  |    0    |  0-9     |  10   |  13.3%                                    |  |

43:   |  |    1    | 10-19    |  10   |  13.3%                                    |  |

44:   |  |    2    | 20-29    |  10   |  13.3%                                    |  |

45:   |  |    3    | 30-39    |  10   |  13.3%                                    |  |

46:   |  |    4    | 40-48    |   9   |  12.0%                                    |  |

47:   |  |    5    | 49-57    |   9   |  12.0%                                    |  |

48:   |  |    6    | 58-66    |   9   |  12.0%                                    |  |

49:   |  |    7    | 67-74    |   8   |  10.7%                                    |  |

50:   |  |  -------+----------+-------+------------                               |  |

52:   |  +------------------------------------------------------------------------+  |

55:   |  +------------------------------------------------------------------------+  |

56:   |  |  256-bit seed divided into 4 × 64-bit words:                           |  |

58:   |  |  [bits 255-192] → Trait D (category from low 32, sub from high 32)     |  |

59:   |  |  [bits 191-128] → Trait C (category from low 32, sub from high 32)     |  |

60:   |  |  [bits 127-64]  → Trait B (category from low 32, sub from high 32)     |  |

61:   |  |  [bits 63-0]    → Trait A (category from low 32, sub from high 32)     |  |

62:   |  +------------------------------------------------------------------------+  |

64:   +==============================================================================+

66:   +==============================================================================+

69:   |     • No state reads/writes - purely computational                           |

70:   |     • No external calls - no reentrancy risk                                 |

80:   |     • Critical for on-chain trait verification                               |

82:   +==============================================================================+*/

93:       +======================================================================+

94:       |  Maps random values to 0-7 with weighted probability distribution.   |

95:       |  Lower buckets (0-3) have ~13.3% each, higher buckets less common.   |

96:       +======================================================================+*/

116:             uint32 scaled = uint32((uint64(rnd) * 75) >> 32);

132:       +======================================================================+

133:       |  Derives 6-bit trait from 64-bit random word.                        |

134:       |  Combines category (3 bits) and sub-bucket (3 bits).                 |

135:       +======================================================================+*/

154:       +======================================================================+

155:       |  Packs 4 traits into 32-bit value for efficient storage.             |

156:       +======================================================================+*/

174:         uint8 traitA = traitFromWord(uint64(rand)); // Quadrant 0: bits 7-6 = 00

175:         uint8 traitB = traitFromWord(uint64(rand >> 64)) | 64; // Quadrant 1: bits 7-6 = 01

176:         uint8 traitC = traitFromWord(uint64(rand >> 128)) | 128; // Quadrant 2: bits 7-6 = 10

177:         uint8 traitD = traitFromWord(uint64(rand >> 192)) | 192; // Quadrant 3: bits 7-6 = 11

```

```solidity
File: DegenerusVault.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {IDegenerusGame, MintPaymentKind} from "./interfaces/IDegenerusGame.sol";

6: import {IStETH} from "./interfaces/IStETH.sol";

7: import {IVaultCoin} from "./interfaces/IVaultCoin.sol";

73: +========================================================================================================+

75: |                     Multi-Asset Vault with Independent Share Classes                                   |

76: +========================================================================================================+

79: |  ---------------------                                                                                 |

82: |  +---------------------------------------------------------------------------------------------------+ |

85: |  |   +-----------------+     +-----------------+                                                     | |

87: |  |   +-----------------+     +-----------------+                                                     | |

88: |  |   |  ETH            |----►|  ethShare       |  DGVE - Claims ETH + stETH proportionally           | |

89: |  |   |  stETH          |----►|  (combined)     |                                                     | |

90: |  |   +-----------------+     +-----------------+                                                     | |

91: |  |   |  BURNIE         |----►|  coinShare      |  DGVB - Claims BURNIE only                          | |

92: |  |   +-----------------+     +-----------------+                                                     | |

95: |  +---------------------------------------------------------------------------------------------------+ |

97: |  +---------------------------------------------------------------------------------------------------+ |

98: |  |                              DEPOSIT FLOW (Game-Only)                                             | |

100: |  |   DegenerusGame ----► deposit() ----► Pulls ETH/stETH, escrows BURNIE mint allowance              | |

102: |  |   Split: ETH+stETH deposits accrue to DGVE. BURNIE vault allowance is claimable by DGVB.          | |

104: |  |   Note: BURNIE uses a "virtual" deposit via vaultEscrow() - no token transfer,                    | |

106: |  +---------------------------------------------------------------------------------------------------+ |

108: |  +---------------------------------------------------------------------------------------------------+ |

111: |  |   User ----► burnCoin(amount) ----► Burns coinShare ----► Mints BURNIE to user                    | |

112: |  |   User ----► burnEth(amount) -----► Burns ethShare -----► Sends ETH + stETH to user               | |

115: |  |   Formula: claimAmount = (reserveBalance * sharesBurned) / totalShareSupply                       | |

118: |  |   This prevents division-by-zero and keeps the share token alive.                                 | |

119: |  +---------------------------------------------------------------------------------------------------+ |

122: |  --------------                                                                                        |

125: |  • Only this vault can mint/burn share tokens                                                          |

129: +========================================================================================================+*/

173:     uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

241:             uint256 newAllowance = allowed - amount;

261:             totalSupply += amount;

262:             balanceOf[to] += amount;

277:             balanceOf[from] = bal - amount;

278:             totalSupply -= amount;

295:             balanceOf[from] = bal - amount;

296:             balanceOf[to] += amount;

351:     uint256 private constant REFILL_SUPPLY = 1_000_000_000_000 * 1e18;

418:         return balance * 1000 > supply * 501;

458:             coinTracked += coinAmount;

576:         uint256 totalBet = uint256(amountPerTicket) * uint256(ticketCount);

771:             coinBal += vaultBal + claimable;

773:         coinOut = (coinBal * amount) / supplyBefore;

785:                 remaining -= payBal;

792:                     remaining -= claimed;

798:                 coinTracked -= remaining;

846:                 claimable -= 1;

850:         uint256 reserve = combined + claimable;

851:         uint256 claimValue = (reserve * amount) / supplyBefore;

863:             stEthOut = claimValue - ethBal;

891:         burnAmount = (coinOut * supply + reserve - 1) / reserve;

908:         burnAmount = (targetValue * supply + reserve - 1) / reserve;

910:         uint256 claimValue = (reserve * burnAmount) / supply;

915:             stEthOut = claimValue - ethBal;

931:         coinOut = (coinBal * amount) / supply;

943:         uint256 claimValue = (reserve * amount) / supply;

949:             stEthOut = claimValue - ethBal;

963:         totalValue = msg.value + extraValue;

975:             combined = ethBal + stBal;

994:                 mainReserve += vaultBal + claimable;

1007:             combined = ethBal + stBal;

1012:                 claimable -= 1;

1018:             mainReserve = combined + claimable;

```

```solidity
File: DeityBoonViewer.sol

103:             if (!deityPassAvailable) total -= W_DEITY_PASS_ALL;

105:             unchecked { ++i; }

115:         cursor += W_COINFLIP_5;

117:         cursor += W_COINFLIP_10;

119:         cursor += W_COINFLIP_25;

121:         cursor += W_LOOTBOX_5;

123:         cursor += W_LOOTBOX_15;

125:         cursor += W_LOOTBOX_25;

127:         cursor += W_PURCHASE_5;

129:         cursor += W_PURCHASE_15;

131:         cursor += W_PURCHASE_25;

134:             cursor += W_DECIMATOR_10;

136:             cursor += W_DECIMATOR_25;

138:             cursor += W_DECIMATOR_50;

141:         cursor += W_WHALE_10;

143:         cursor += W_WHALE_25;

145:         cursor += W_WHALE_50;

148:             cursor += W_DEITY_PASS_10;

150:             cursor += W_DEITY_PASS_25;

152:             cursor += W_DEITY_PASS_50;

155:         cursor += W_ACTIVITY_10;

157:         cursor += W_ACTIVITY_25;

159:         cursor += W_ACTIVITY_50;

161:         cursor += W_WHALE_PASS;

163:         cursor += W_LAZY_PASS_10;

165:         cursor += W_LAZY_PASS_25;

167:         cursor += W_LAZY_PASS_50;

```

```solidity
File: GNRUS.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {IStETH} from "./interfaces/IStETH.sol";

145:         address recipient;       // 20 bytes ┐

146:         uint48  approveWeight;   //  6 bytes ├─ slot 0 (32 bytes exact)

147:         uint48  rejectWeight;    //  6 bytes ┘

148:         address proposer;        // 20 bytes ── slot 1 (12 bytes free)

195:     uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

283:         if (burnerBal == amount || (supply - balanceOf[address(this)]) == amount) {

284:             amount = burnerBal; // sweep

291:         if (claimable > 1) { unchecked { claimable -= 1; } } else { claimable = 0; }

293:         uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;

296:         uint256 onHand = ethBal + stethBal;

304:         uint256 stethOut = owed - ethOut;

307:         balanceOf[burner] -= amount; // reverts on underflow via Solidity 0.8

308:         unchecked { totalSupply = supply - amount; }

339:             unchecked { totalSupply -= unallocated; }

363:             levelSdgnrsSnapshot[level] = uint48(sdgnrs.totalSupply() / 1e18);

373:             creatorProposalCount[level]++;

376:             if ((sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();

381:         proposalId = proposalCount++;

385:         levelProposalCount[level]++;

411:         if (count == 0 || proposalId < start || proposalId >= start + count) revert InvalidProposal();

417:         uint48 weight = uint48(sdgnrs.balanceOf(voter) / 1e18);

421:             weight += uint48((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / BPS_DENOM);

426:             proposals[proposalId].approveWeight += weight;

428:             proposals[proposalId].rejectWeight += weight;

450:         currentLevel = level + 1;

464:         int256 bestNet = 0; // must be > 0 to win

467:             Proposal storage p = proposals[start + i];

468:             int256 net = int256(uint256(p.approveWeight)) - int256(uint256(p.rejectWeight));

471:                 bestId = start + uint48(i);

473:             unchecked { ++i; }

484:         uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;

495:             balanceOf[address(this)] = unallocated - distribution;

496:             balanceOf[recipient] += distribution;

534:             totalSupply += amount;

535:             balanceOf[to] += amount;

```

```solidity
File: Icons32Data.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

7: +=======================================================================================================+

9: |                           On-Chain SVG Icon Path Storage for Degenerus                                |

10: +=======================================================================================================+

13: |  ---------------------                                                                                |

14: |  Icons32Data is an on-chain storage contract for SVG path data. It holds 33 icon                     |

18: |  +--------------------------------------------------------------------------------------------------+ |

21: |  |   _paths[0-7]   -► Quadrant 0 (Crypto):   Bitcoin, Ethereum, Litecoin, etc.                     | |

22: |  |   _paths[8-15]  -► Quadrant 1 (Zodiac):   Aries, Taurus, Gemini, etc.                           | |

23: |  |   _paths[16-23] -► Quadrant 2 (Cards):    Horseshoe, King, Cashsack, Club, Diamond, Heart       | |

25: |  |   _paths[24-31] -► Quadrant 3 (Dice):     1-8                                                   | |

26: |  |   _paths[32]    -► Affiliate Badge:       Special icon for affiliate trophies                   | |

28: |  |   _diamond      -► Flame icon:            Center glyph for all token renders                    | |

30: |  |   _symQ1[0-7]   -► Crypto symbol names:   "Bitcoin", "Ethereum", etc.                           | |

31: |  |   _symQ2[0-7]   -► Zodiac symbol names:   "Aries", "Taurus", etc.                               | |

32: |  |   _symQ3[0-7]   -► Cards symbol names:    "Club", "Diamond", "Heart", "Spade",                  | |

35: |  +--------------------------------------------------------------------------------------------------+ |

38: |  ----------------                                                                                     |

39: |  1. On-chain storage ensures token metadata remains available even if IPFS/centralized              |

46: +=======================================================================================================+

48: |  -----------------------                                                                              |

70: |     • View functions are free for off-chain calls                                                     |

73: +=======================================================================================================+

75: |  -----------------                                                                                    |

81: +=======================================================================================================+

157:         if (startIndex + paths.length > 33) revert IndexOutOfBounds();

159:         for (uint256 i = 0; i < paths.length; ++i) {

160:             _paths[startIndex + i] = paths[i];

176:             for (uint256 i = 0; i < 8; ++i) {

180:             for (uint256 i = 0; i < 8; ++i) {

184:             for (uint256 i = 0; i < 8; ++i) {

```

```solidity
File: StakedDegenerusStonk.sol

4: import {ContractAddresses} from "./ContractAddresses.sol";

5: import {IStETH} from "./interfaces/IStETH.sol";

183:         uint96  ethValueOwed;   // base (100%) ETH-equivalent owed (max ~79B ETH)

184:         uint96  burnieOwed;     // base (100%) BURNIE owed (max ~79B ETH-equiv)

185:         uint48  periodIndex;    // which daily period (dailyIdx at submission)

186:         uint16  activityScore;  // snapshotted activity score + 1 (0 = not yet set)

187:     } // 96 + 96 + 48 + 16 = 256 bits (1 slot)

190:         uint16  roll;           // 0 = unresolved, 25-175 = resolved

191:         uint48  flipDay;        // coinflip day for BURNIE gamble

197:     uint256 public pendingRedemptionEthValue;      // total segregated ETH across all periods

198:     uint256 internal pendingRedemptionBurnie;       // total reserved BURNIE

199:     uint256 internal pendingRedemptionEthBase;      // current unresolved period ETH base

200:     uint256 internal pendingRedemptionBurnieBase;   // current unresolved period BURNIE base

211:     uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

263:         uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;

264:         uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;

265:         uint256 earlybirdAmount = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;

266:         uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;

267:         uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;

268:         uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;

269:         uint256 totalAllocated = creatorAmount + whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;

273:                 dust = INITIAL_SUPPLY - totalAllocated;

275:             lootboxAmount += dust;

278:             whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;

316:             balanceOf[ContractAddresses.DGNRS] = bal - amount;

317:             balanceOf[to] += amount;

386:             poolBalances[idx] = available - amount;

387:             balanceOf[address(this)] -= amount;

388:             balanceOf[to] += amount;

411:             poolBalances[fromIdx] = available - amount;

413:         poolBalances[toIdx] += amount;

425:             totalSupply -= bal;

489:         uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;

490:         uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

493:             balanceOf[burnFrom] = bal - amount;

494:             totalSupply -= amount;

508:             stethOut = totalValueOwed - ethOut;

547:         uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;

548:         pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;

552:         burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;

555:         pendingRedemptionBurnie -= pendingRedemptionBurnieBase;

587:         uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

596:             ethDirect = totalRolledEth / 2;

597:             lootboxEth = totalRolledEth - ethDirect;

607:                 burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;

612:         pendingRedemptionEthValue -= totalRolledEth;

624:             uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;

660:         uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;

661:         uint256 totalValueOwed = (totalMoney * amount) / supply;

663:         uint256 ethAvailable = ethBal + claimableEth;

665:             ethAvailable -= pendingRedemptionEthValue;

673:             stethOut = totalValueOwed - ethOut;

680:             uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;

681:             burnieOut = (totalBurnie * amount) / supply;

691:         return burnieBal + claimableBurnie - pendingRedemptionBurnie;

718:         if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();

719:         redemptionPeriodBurned += amount;

727:         uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;

728:         uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

733:         uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;

734:         uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;

738:             balanceOf[burnFrom] = bal - amount;

739:             totalSupply -= amount;

744:         pendingRedemptionEthValue += ethValueOwed;

745:         pendingRedemptionEthBase += ethValueOwed;

746:         pendingRedemptionBurnie += burnieOwed;

747:         pendingRedemptionBurnieBase += burnieOwed;

756:         if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

758:         claim.ethValueOwed += uint96(ethValueOwed);

760:         claim.burnieOwed += uint96(burnieOwed);

765:             claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;

787:             uint256 stethOut = amount - ethOut;

800:         uint256 remaining = amount - payBal;

815:         return stored - 1;

832:             totalSupply += amount;

833:             balanceOf[to] += amount;

```

```solidity
File: WrappedWrappedXRP.sol

28: import {ContractAddresses} from "./ContractAddresses.sol";

43:       +======================================================================+

44:       |  Standard ERC20 events plus unwrap/donate tracking                  |

45:       +======================================================================+*/

80:       +======================================================================+

81:       |  Custom errors for gas-efficient reverts                            |

82:       +======================================================================+*/

113:       +======================================================================+

115:       +======================================================================+*/

143:       +======================================================================+

144:       |  All external dependencies are compile-time constants sourced from  |

146:       +======================================================================+*/

166:       +======================================================================+

168:       +======================================================================+*/

178:         return totalSupply + vaultAllowance;

188:       +======================================================================+

190:       +======================================================================+*/

230:             allowance[from][msg.sender] = allowed - amount;

231:             emit Approval(from, msg.sender, allowed - amount);

245:         balanceOf[from] -= amount;

246:         balanceOf[to] += amount;

257:         totalSupply += amount;

258:         balanceOf[to] += amount;

270:         balanceOf[from] -= amount;

271:         totalSupply -= amount;

277:       |                       WRAP / UNWRAP FUNCTIONS                        |

278:       +======================================================================+

279:       |  Wrap not implemented; unwrap/donate are enabled.                     |

280:       +======================================================================+*/

298:         wXRPReserves -= amount;

323:         wXRPReserves += amount;

329:       |                       PRIVILEGED MINT/BURN FUNCTIONS                 |

330:       +======================================================================+

331:       |  Allows authorized minters to create/destroy WWXRP                  |

332:       +======================================================================+*/

371:             vaultAllowance = allowanceVault - amount;

```

```solidity
File: libraries/BitPackingLib.sol

29:     uint256 internal constant MASK_16 = (uint256(1) << 16) - 1;

32:     uint256 internal constant MASK_24 = (uint256(1) << 24) - 1;

35:     uint256 internal constant MASK_32 = (uint256(1) << 32) - 1;

```

```solidity
File: libraries/GameTimeLib.sol

4: import {ContractAddresses} from "../ContractAddresses.sol";

32:         uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);

33:         return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;

```

```solidity
File: libraries/JackpotBucketLib.sol

38:         base[0] = 25; // Large bucket

39:         base[1] = 15; // Mid bucket

40:         base[2] = 8; // Small bucket

41:         base[3] = 1; // Solo bucket (receives the 60% share via rotation)

46:             counts[i] = base[(i + offset) & 3];

48:                 ++i;

68:             uint256 range = JACKPOT_SCALE_FIRST_WEI - JACKPOT_SCALE_MIN_WEI;

69:             uint256 progress = ethPool - JACKPOT_SCALE_MIN_WEI;

70:             scaleBps = JACKPOT_SCALE_BASE_BPS + (progress * (JACKPOT_SCALE_FIRST_BPS - JACKPOT_SCALE_BASE_BPS)) / range;

72:             uint256 range = JACKPOT_SCALE_SECOND_WEI - JACKPOT_SCALE_FIRST_WEI;

73:             uint256 progress = ethPool - JACKPOT_SCALE_FIRST_WEI;

74:             scaleBps = JACKPOT_SCALE_FIRST_BPS + (progress * (uint256(maxScaleBps) - JACKPOT_SCALE_FIRST_BPS)) / range;

83:                     uint256 scaled = (uint256(baseCount) * scaleBps) / 10_000;

89:                     ++i;

111:         total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];

147:         uint256 nonSoloCap = uint256(maxTotal) - 1;

148:         uint256 nonSoloTotal = total - 1;

154:                 uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;

157:                 scaledTotal += scaled;

160:                 ++i;

168:             uint256 excess = scaledTotal - nonSoloCap;

171:                 uint8 idx = uint8((uint256(trimOff) + 3 - i) & 3);

175:                         --excess;

179:                     ++i;

185:         uint256 remainder = nonSoloCap - scaledTotal;

189:                 uint8 idx = uint8((uint256(offset) + i) & 3);

191:                     capped[idx] += 1;

193:                         --remainder;

197:                     ++i;

222:                 uint256 share = (pool * shareBps[i]) / 10_000;

225:                         uint256 unitBucket = unit * count;

226:                         share = (share / unitBucket) * unitBucket;

230:                 distributed += share;

233:                 ++i;

236:         shares[remainderIdx] = pool - distributed;

241:         return uint8((uint256(3) - (entropy & 3)) & 3);

246:         uint8 baseIndex = uint8((uint256(traitIdx) + uint256(offset) + 1) & 3);

247:         return uint16(packed >> (baseIndex * 16));

253:             for (uint8 i; i < 4; ++i) {

279:         w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63

280:         w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127

281:         w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191

282:         w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255

293:         for (uint8 i = 1; i < 4; ++i) {

301:         for (uint8 i; i < 4; ++i) {

303:                 order[k++] = i;

```

```solidity
File: libraries/PriceLookupLib.sol

36:             return 0.24 ether; // Milestone levels: 100, 200, 300...

38:             return 0.04 ether; // Early cycle: x01-x29

40:             return 0.08 ether; // Mid cycle: x30-x59

42:             return 0.12 ether; // Late cycle: x60-x89

44:             return 0.16 ether; // Final cycle: x90-x99

```

### <a name="GAS-8"></a>[GAS-8] Avoid contract existence checks by using low level calls
Prior to 0.8.10 the compiler inserted extra code, including `EXTCODESIZE` (**100 gas**), to check for contract existence for external function calls. In more recent solidity versions, the compiler will not insert these checks if the external call has a return value. Similar behavior can be achieved in earlier versions by using low-level calls, since low level calls never check for contract existence

*Instances (58)*:
```solidity
File: DegenerusAdmin.sol

427:             if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)

470:         uint256 weight = sDGNRS.balanceOf(msg.sender);

522:             - sDGNRS.balanceOf(ContractAddresses.SDGNRS)

523:             - sDGNRS.balanceOf(ContractAddresses.DGNRS);

615:         uint256 bal = linkToken.balanceOf(address(this));

663:         uint256 bal = linkToken.balanceOf(address(this));

```

```solidity
File: DegenerusGame.sol

311:             .delegatecall(

339:             .delegatecall(

560:             .delegatecall(

587:             .delegatecall(

608:             .delegatecall(

643:             .delegatecall(

665:             .delegatecall(

685:             .delegatecall(

714:             .delegatecall(

730:             .delegatecall(

757:             .delegatecall(

782:             .delegatecall(

806:             .delegatecall(

827:             .delegatecall(

848:             .delegatecall(

903:             .delegatecall(

1040:             .delegatecall(

1072:             .delegatecall(

1101:             .delegatecall(

1127:             .delegatecall(

1148:             .delegatecall(

1184:             .delegatecall(

1209:             .delegatecall(

1226:             .delegatecall(

1704:             .delegatecall(

1760:                 .delegatecall(

1817:         uint256 stBal = steth.balanceOf(address(this));

1883:             .delegatecall(

1902:             .delegatecall(

1919:             .delegatecall(

1939:             .delegatecall(

1985:         uint256 stBal = steth.balanceOf(address(this));

2007:         uint256 stBal = steth.balanceOf(address(this));

2168:             steth.balanceOf(address(this));

```

```solidity
File: DegenerusStonk.sol

89:         uint256 deposited = stonk.balanceOf(address(this));

255:         uint256 remaining = stonk.balanceOf(address(this));

```

```solidity
File: DegenerusVault.sol

417:         uint256 balance = ethShare.balanceOf(account);

768:         uint256 vaultBal = coinToken.balanceOf(address(this));

990:         uint256 vaultBal = coinToken.balanceOf(address(this));

1025:         return steth.balanceOf(address(this));

```

```solidity
File: GNRUS.sol

289:         uint256 stethBal = steth.balanceOf(address(this));

300:             stethBal = steth.balanceOf(address(this));

376:             if ((sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();

417:         uint48 weight = uint48(sdgnrs.balanceOf(voter) / 1e18);

```

```solidity
File: StakedDegenerusStonk.sol

487:         uint256 stethBal = steth.balanceOf(address(this));

501:             stethBal = steth.balanceOf(address(this));

658:         uint256 stethBal = steth.balanceOf(address(this));

678:             uint256 burnieBal = coin.balanceOf(address(this));

689:         uint256 burnieBal = coin.balanceOf(address(this));

725:         uint256 stethBal = steth.balanceOf(address(this));

731:         uint256 burnieBal = coin.balanceOf(address(this));

798:         uint256 burnieBal = coin.balanceOf(address(this));

```

### <a name="GAS-9"></a>[GAS-9] Stack variable used as a cheaper cache for a state variable is only used once
If the variable is only accessed once, it's cheaper to use the state variable directly that one time, and save the **3 gas** the extra stack assignment would spend

*Instances (13)*:
```solidity
File: BurnieCoin.sol

729:         IDegenerusQuests module = questModule;

763:         IDegenerusQuests module = questModule;

788:         IDegenerusQuests module = questModule;

817:         IDegenerusQuests module = questModule;

844:         IDegenerusQuests module = questModule;

```

```solidity
File: BurnieCoinflip.sol

269:         IDegenerusQuests module = questModule;

646:                 address currentBountyOwner = bountyOwedTo;

647:                 uint128 bounty = currentBounty;

```

```solidity
File: DegenerusAdmin.sol

358:         address current = linkEthPriceFeed;

577:         address oldCoord = coordinator;

```

```solidity
File: DegenerusDeityPass.sol

91:         address prev = _contractOwner;

98:         address prev = renderer;

```

```solidity
File: StakedDegenerusStonk.sol

484:         uint256 supplyBefore = totalSupply;

```

### <a name="GAS-10"></a>[GAS-10] State variables only set in the constructor should be declared `immutable`
Variables only set in the constructor and never edited afterwards should be marked as immutable, as it would avoid the expensive storage-writing operation in the constructor (around **20 000 gas** per variable) and replace the expensive storage-reading operations (around **2100 gas** per reading) to a less expensive value reading (**3 gas**)

*Instances (10)*:
```solidity
File: BurnieCoinflip.sol

180:         burnie = IBurnieCoin(_burnie);

181:         degenerusGame = IDegenerusGame(_degenerusGame);

182:         jackpots = IDegenerusJackpots(_jackpots);

183:         wwxrp = IWrappedWrappedXRP(_wwxrp);

```

```solidity
File: DegenerusVault.sol

200:         symbol = symbol_;

200:         symbol = symbol_;

201:         totalSupply = INITIAL_SUPPLY;

201:         totalSupply = INITIAL_SUPPLY;

434:         coinShare = new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB");

435:         ethShare = new DegenerusVaultShare("Degenerus Vault Eth", "DGVE");

```

### <a name="GAS-11"></a>[GAS-11] Functions guaranteed to revert when called by normal users can be marked `payable`
If a function modifier such as `onlyOwner` is used, the function will revert if a normal user tries to pay the function. Marking the function as `payable` will lower the gas cost for legitimate callers because the compiler will not include checks for whether a payment was provided.

*Instances (39)*:
```solidity
File: BurnieCoin.sol

556:     function creditCoin(address player, uint256 amount) external onlyFlipCreditors {

566:     function creditFlip(address player, uint256 amount) external onlyFlipCreditors {

574:     function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors {

584:     function creditLinkReward(address player, uint256 amount) external onlyAdmin {

705:     function vaultMintTo(address to, uint256 amount) external onlyVault {

```

```solidity
File: BurnieCoinflip.sol

215:     function settleFlipModeChange(address player) external onlyDegenerusGameContract {

```

```solidity
File: DegenerusAdmin.sol

357:     function setLinkEthPriceFeed(address feed) external onlyOwner {

379:     function stakeGameEthToStEth(uint256 amount) external onlyOwner {

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {

```

```solidity
File: DegenerusDeityPass.sol

89:     function transferOwnership(address newOwner) external onlyOwner {

97:     function setRenderer(address newRenderer) external onlyOwner {

```

```solidity
File: DegenerusJackpots.sol

166:     function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin {

```

```solidity
File: DegenerusQuests.sol

331:     function awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay) external onlyGame {

```

```solidity
File: DegenerusVault.sol

258:     function vaultMint(address to, uint256 amount) external onlyVault {

273:     function vaultBurn(address from, uint256 amount) external onlyVault {

476:     function gameAdvance() external onlyVaultOwner {

510:     function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner {

519:     function gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner {

527:     function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner {

550:     function gameClaimWinnings() external onlyVaultOwner {

556:     function gameClaimWhalePass() external onlyVaultOwner {

636:     function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner {

643:     function gameSetAutoRebuy(bool enabled) external onlyVaultOwner {

650:     function gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {

657:     function gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner {

678:     function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner {

685:     function coinDepositCoinflip(uint256 amount) external onlyVaultOwner {

693:     function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {

700:     function coinDecimatorBurn(uint256 amount) external onlyVaultOwner {

708:     function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner {

715:     function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {

723:     function wwxrpMint(address to, uint256 amount) external onlyVaultOwner {

731:     function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner {

```

```solidity
File: GNRUS.sol

332:     function burnAtGameOver() external onlyGame {

444:     function pickCharity(uint24 level) external onlyGame {

```

```solidity
File: StakedDegenerusStonk.sol

352:     function depositSteth(uint256 amount) external onlyGame {

376:     function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {

401:     function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {

420:     function burnAtGameOver() external onlyGame {

```

### <a name="GAS-12"></a>[GAS-12] `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`)
Pre-increments and pre-decrements are cheaper.

For a `uint256 i` variable, the following is true with the Optimizer enabled at 10k:

**Increment:**

- `i += 1` is the most expensive form
- `i++` costs 6 gas less than `i += 1`
- `++i` costs 5 gas less than `i++` (11 gas less than `i += 1`)

**Decrement:**

- `i -= 1` is the most expensive form
- `i--` costs 11 gas less than `i -= 1`
- `--i` costs 5 gas less than `i--` (16 gas less than `i -= 1`)

Note that post-increments (or post-decrements) return the old value before incrementing or decrementing, hence the name *post-increment*:

```solidity
uint i = 1;  
uint j = 2;
require(j == i++, "This will be false as i is incremented after the comparison");
```
  
However, pre-increments (or pre-decrements) return the new value:
  
```solidity
uint i = 1;  
uint j = 2;
require(j == ++i, "This will be true as i is incremented before the comparison");
```

In the pre-increment case, the compiler has to create a temporary variable (when used) for returning `1` instead of `2`.

Consider using pre-increments and pre-decrements where they are relevant (meaning: not where post-increments/decrements logic are relevant).

*Saves 5 gas per instance*

*Instances (48)*:
```solidity
File: BurnieCoin.sol

158:       |  +-----------------------------------------------------------------+ |

160:       |  +------+-----------------------------+----------------------------+ |

164:       |  +-----------------------------------------------------------------+ |

353:       |  +-----------------------------------------------------------------+ |

355:       |  +------+------------------+----------+----------+-----------------+ |

359:       |  +-----------------------------------------------------------------+ |

623:       |  +-----------------------------------------------------------------+ |

625:       |  +------------------------+----------------------------------------+ |

631:       |  +-----------------------------------------------------------------+ |

```

```solidity
File: DegenerusAdmin.sol

634:         for (uint256 i = start; i <= count; i++) {

```

```solidity
File: DegenerusJackpots.sol

189:       |  +-----------------------------------------------------------------+ |

197:       |  +-----------------------------------------------------------------+ |

```

```solidity
File: DegenerusQuests.sol

1040:         newVersion = questVersionCounter++;

```

```solidity
File: DegenerusTraitUtils.sol

16:   |  +------------------------------------------------------------------------+  |

26:   |  +------------------------------------------------------------------------+  |

29:   |  +------------------------------------------------------------------------+  |

36:   |  +------------------------------------------------------------------------+  |

39:   |  +------------------------------------------------------------------------+  |

41:   |  |  -------+----------+-------+------------                               |  |

50:   |  |  -------+----------+-------+------------                               |  |

52:   |  +------------------------------------------------------------------------+  |

55:   |  +------------------------------------------------------------------------+  |

62:   |  +------------------------------------------------------------------------+  |

```

```solidity
File: DegenerusVault.sol

79: |  ---------------------                                                                                 |

82: |  +---------------------------------------------------------------------------------------------------+ |

85: |  |   +-----------------+     +-----------------+                                                     | |

87: |  |   +-----------------+     +-----------------+                                                     | |

88: |  |   |  ETH            |----►|  ethShare       |  DGVE - Claims ETH + stETH proportionally           | |

89: |  |   |  stETH          |----►|  (combined)     |                                                     | |

90: |  |   +-----------------+     +-----------------+                                                     | |

91: |  |   |  BURNIE         |----►|  coinShare      |  DGVB - Claims BURNIE only                          | |

92: |  |   +-----------------+     +-----------------+                                                     | |

95: |  +---------------------------------------------------------------------------------------------------+ |

97: |  +---------------------------------------------------------------------------------------------------+ |

100: |  |   DegenerusGame ----► deposit() ----► Pulls ETH/stETH, escrows BURNIE mint allowance              | |

106: |  +---------------------------------------------------------------------------------------------------+ |

108: |  +---------------------------------------------------------------------------------------------------+ |

111: |  |   User ----► burnCoin(amount) ----► Burns coinShare ----► Mints BURNIE to user                    | |

112: |  |   User ----► burnEth(amount) -----► Burns ethShare -----► Sends ETH + stETH to user               | |

119: |  +---------------------------------------------------------------------------------------------------+ |

122: |  --------------                                                                                        |

```

```solidity
File: GNRUS.sol

381:         proposalId = proposalCount++;

```

```solidity
File: Icons32Data.sol

13: |  ---------------------                                                                                |

18: |  +--------------------------------------------------------------------------------------------------+ |

35: |  +--------------------------------------------------------------------------------------------------+ |

38: |  ----------------                                                                                     |

48: |  -----------------------                                                                              |

75: |  -----------------                                                                                    |

```

### <a name="GAS-13"></a>[GAS-13] Using `private` rather than `public` for constants, saves gas
If needed, the values can be read from the verified contract source code, or if there are multiple values there can be a single getter function that [returns a tuple](https://github.com/code-423n4/2022-08-frax/blob/90f55a9ce4e25bceed3a74290b854341d8de6afa/src/contracts/FraxlendPair.sol#L156-L178) of the values of all currently-public constants. Saves **3406-3606 gas** in deployment gas due to the compiler not having to create non-payable getter functions for deployment calldata, not having to store the bytes of the value outside of where it's used, and not adding another entry to the method ID table

*Instances (21)*:
```solidity
File: BurnieCoin.sol

168:     string public constant name = "Burnies";

171:     string public constant symbol = "BURNIE";

379:     uint8 public constant decimals = 18;

```

```solidity
File: DegenerusStonk.sol

64:     string public constant name = "Degenerus Stonk";

65:     string public constant symbol = "DGNRS";

66:     uint8 public constant decimals = 18;

```

```solidity
File: DegenerusVault.sol

171:     uint8 public constant decimals = 18;

173:     uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

345:     string public constant name = "Degenerus Vault";

347:     string public constant symbol = "DGV";

349:     uint8 public constant decimals = 18;

```

```solidity
File: GNRUS.sol

121:     string public constant name = "GNRUS Donations";

124:     string public constant symbol = "GNRUS";

127:     uint8 public constant decimals = 18;

```

```solidity
File: StakedDegenerusStonk.sol

144:     string public constant name = "Staked Degenerus Stonk";

147:     string public constant symbol = "sDGNRS";

150:     uint8 public constant decimals = 18;

```

```solidity
File: WrappedWrappedXRP.sol

118:     string public constant name = "Wrapped Wrapped WWXRP (PARODY)";

121:     string public constant symbol = "WWXRP";

124:     uint8 public constant decimals = 18;

130:     uint256 public constant INITIAL_VAULT_ALLOWANCE = 1_000_000_000 ether;

```

### <a name="GAS-14"></a>[GAS-14] Use shift right/left instead of division/multiplication if possible
While the `DIV` / `MUL` opcode uses 5 gas, the `SHR` / `SHL` opcode only uses 3 gas. Furthermore, beware that Solidity's division operation also includes a division-by-0 prevention which is bypassed using shifting. Eventually, overflow checks are never performed for shift operations as they are done for arithmetic operations. Instead, the result is always truncated, so the calculation can be unchecked in Solidity version `0.8+`
- Use `>> 1` instead of `/ 2`
- Use `>> 2` instead of `/ 4`
- Use `<< 3` instead of `* 8`
- ...
- Use `>> 5` instead of `/ 2^5 == / 32`
- Use `<< 6` instead of `* 2^6 == * 64`

TL;DR:
- Shifting left by N is like multiplying by 2^N (Each bits to the left is an increased power of 2)
- Shifting right by N is like dividing by 2^N (Each bits to the right is a decreased power of 2)

*Saves around 2 gas + 20 for unchecked per instance*

*Instances (18)*:
```solidity
File: BurnieCoin.sol

1040:         uint256 reduction = (range * bonusBps + (DECIMATOR_ACTIVITY_CAP_BPS / 2)) / DECIMATOR_ACTIVITY_CAP_BPS;

```

```solidity
File: BurnieCoinflip.sol

1032:         uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;

1035:             return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1039:             / (uint256(BPS_DENOMINATOR) * 2);

```

```solidity
File: DegenerusAdmin.sol

763:             uint256 delta = (subBal * 2e18) / 200 ether;

```

```solidity
File: DegenerusDeityPass.sol

134:         uint8 quadrant = uint8(tokenId / 8);

272:         txm = -w1e6 / 2;

273:         tyn = -h1e6 / 2;

```

```solidity
File: DegenerusGame.sol

2772:         wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;

2790:                 uint256 amount = (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;

```

```solidity
File: DegenerusJackpots.sol

193:       |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)  | |

194:       |  |  5% | Far-future ticket holders 2nd draw (3% 1st / 2% 2nd)      | |

373:             uint256 scatterSecond = P / 4;

```

```solidity
File: DegenerusStonk.sol

261:         uint256 stethToGnrus = stethOut / 2;

263:         uint256 ethToGnrus = ethOut / 2;

```

```solidity
File: StakedDegenerusStonk.sol

596:             ethDirect = totalRolledEth / 2;

718:         if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();

```

```solidity
File: libraries/JackpotBucketLib.sol

247:         return uint16(packed >> (baseIndex * 16));

```

### <a name="GAS-15"></a>[GAS-15] Use of `this` instead of marking as `public` an `external` function
Using `this.` is like making an expensive external call. Consider marking the called function as public

*Saves around 2000 gas per instance*

*Instances (1)*:
```solidity
File: DegenerusAdmin.sol

712:         try this.linkAmountToEth(amount) returns (uint256 eth) {

```

### <a name="GAS-16"></a>[GAS-16] Increments/decrements can be unchecked in for-loops
In Solidity 0.8+, there's a default overflow check on unsigned integers. It's possible to uncheck this in for-loops and save some gas at each iteration, but at the cost of some code readability, as this uncheck cannot be made inline.

[ethereum/solidity#10695](https://github.com/ethereum/solidity/issues/10695)

The change would be:

```diff
- for (uint256 i; i < numIterations; i++) {
+ for (uint256 i; i < numIterations;) {
 // ...  
+   unchecked { ++i; }
}  
```

These save around **25 gas saved** per instance.

The same can be applied with decrements (which should use `break` when `i == 0`).

The risk of overflow is non-existent for `uint256`.

*Instances (12)*:
```solidity
File: DegenerusAdmin.sol

634:         for (uint256 i = start; i <= count; i++) {

```

```solidity
File: DegenerusDeityPass.sol

246:         for (uint256 i = 1; i < 7; ++i) {

312:         for (uint256 k; k < 6; ++k) {

```

```solidity
File: DegenerusGame.sol

2787:         for (uint8 q = 0; q < 4; ++q) {

2789:             for (uint8 s = 0; s < 8; ++s) {

```

```solidity
File: Icons32Data.sol

159:         for (uint256 i = 0; i < paths.length; ++i) {

176:             for (uint256 i = 0; i < 8; ++i) {

180:             for (uint256 i = 0; i < 8; ++i) {

184:             for (uint256 i = 0; i < 8; ++i) {

```

```solidity
File: libraries/JackpotBucketLib.sol

253:             for (uint8 i; i < 4; ++i) {

293:         for (uint8 i = 1; i < 4; ++i) {

301:         for (uint8 i; i < 4; ++i) {

```

### <a name="GAS-17"></a>[GAS-17] Use != 0 instead of > 0 for unsigned integer comparison

*Instances (12)*:
```solidity
File: BurnieCoin.sol

949:         if (boonBps > 0) {

```

```solidity
File: BurnieCoinflip.sol

620:             if (boonBps > 0) {

824:         if (bountyOwner != address(0) && currentBounty_ > 0) {

```

```solidity
File: DegenerusJackpots.sol

397:                         targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;

578:             while (idx > 0 && board[idx].score > board[idx - 1].score) {

592:             while (insert > 0 && score > board[insert - 1].score) {

606:         while (idx2 > 0 && score > board[idx2 - 1].score) {

```

```solidity
File: GNRUS.sol

464:         int256 bestNet = 0; // must be > 0 to win

```

```solidity
File: StakedDegenerusStonk.sol

512:         if (stethOut > 0) {

516:         if (ethOut > 0) {

624:             uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;

788:             if (ethOut > 0) {

```

### <a name="GAS-18"></a>[GAS-18] `internal` functions not called by the contract should be removed
If the functions are required by an interface, the contract should inherit from that interface and use the `override` keyword

*Instances (12)*:
```solidity
File: DegenerusTraitUtils.sol

172:     function packedTraitsFromSeed(uint256 rand) internal pure returns (uint32) {

```

```solidity
File: libraries/BitPackingLib.sol

79:     function setPacked(

```

```solidity
File: libraries/EntropyLib.sol

16:     function entropyStep(uint256 state) internal pure returns (uint256) {

```

```solidity
File: libraries/GameTimeLib.sol

21:     function currentDayIndex() internal view returns (uint48) {

```

```solidity
File: libraries/JackpotBucketLib.sol

98:     function bucketCountsForPoolCap(

211:     function bucketShares(

251:     function shareBpsByBucket(uint64 packed, uint8 offset) internal pure returns (uint16[4] memory shares) {

264:     function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed) {

269:     function unpackWinningTraits(uint32 packed) internal pure returns (uint8[4] memory traits) {

278:     function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {

290:     function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order) {

```

```solidity
File: libraries/PriceLookupLib.sol

21:     function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {

```


## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | Replace `abi.encodeWithSignature` and `abi.encodeWithSelector` with `abi.encodeCall` which keeps the code typo/type safe | 30 |
| [NC-2](#NC-2) | Missing checks for `address(0)` when assigning values to address state variables | 2 |
| [NC-3](#NC-3) | Array indices should be referenced via `enum`s rather than via numeric literals | 57 |
| [NC-4](#NC-4) | Use `string.concat()` or `bytes.concat()` instead of `abi.encodePacked` | 17 |
| [NC-5](#NC-5) | Constants should be in CONSTANT_CASE | 60 |
| [NC-6](#NC-6) | `constant`s should be defined rather than using magic numbers | 290 |
| [NC-7](#NC-7) | Control structures do not follow the Solidity Style Guide | 545 |
| [NC-8](#NC-8) | Default Visibility for constants | 4 |
| [NC-9](#NC-9) | Event is never emitted | 2 |
| [NC-10](#NC-10) | Event missing indexed field | 4 |
| [NC-11](#NC-11) | Events that mark critical parameter changes should contain both the old and the new value | 7 |
| [NC-12](#NC-12) | Function ordering does not follow the Solidity style guide | 11 |
| [NC-13](#NC-13) | Functions should not be longer than 50 lines | 377 |
| [NC-14](#NC-14) | Change int to int256 | 21 |
| [NC-15](#NC-15) | Interfaces should be defined in separate files from their usage | 31 |
| [NC-16](#NC-16) | Lack of checks in setters | 23 |
| [NC-17](#NC-17) | Missing Event for critical parameters change | 27 |
| [NC-18](#NC-18) | NatSpec is completely non-existent on functions that should have them | 83 |
| [NC-19](#NC-19) | Incomplete NatSpec: `@param` is missing on actually documented functions | 19 |
| [NC-20](#NC-20) | Incomplete NatSpec: `@return` is missing on actually documented functions | 6 |
| [NC-21](#NC-21) | Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor | 74 |
| [NC-22](#NC-22) | Constant state variables defined more than once | 57 |
| [NC-23](#NC-23) | Consider using named mappings | 47 |
| [NC-24](#NC-24) | `address`s shouldn't be hard-coded | 29 |
| [NC-25](#NC-25) | Numeric values having to do with time should use time units for readability | 1 |
| [NC-26](#NC-26) | Adding a `return` statement when the function defines a named return variable, is redundant | 167 |
| [NC-27](#NC-27) | Take advantage of Custom Error's return value property | 280 |
| [NC-28](#NC-28) | Deprecated library used for Solidity `>= 0.8` : SafeMath | 1 |
| [NC-29](#NC-29) | Strings should use double quotes rather than single quotes | 15 |
| [NC-30](#NC-30) | Contract does not follow the Solidity style guide's suggested layout ordering | 15 |
| [NC-31](#NC-31) | Use Underscores for Number Literals (add an underscore every 3 digits) | 29 |
| [NC-32](#NC-32) | Internal and private variables and functions names should begin with an underscore | 50 |
| [NC-33](#NC-33) | Event is missing `indexed` fields | 67 |
| [NC-34](#NC-34) | Constants should be defined rather than using magic numbers | 8 |
| [NC-35](#NC-35) | Variables need not be initialized to zero | 15 |
### <a name="NC-1"></a>[NC-1] Replace `abi.encodeWithSignature` and `abi.encodeWithSelector` with `abi.encodeCall` which keeps the code typo/type safe
When using `abi.encodeWithSignature`, it is possible to include a typo for the correct function signature.
When using `abi.encodeWithSignature` or `abi.encodeWithSelector`, it is also possible to provide parameters that are not of the correct type for the function.

To avoid these pitfalls, it would be best to use [`abi.encodeCall`](https://solidity-by-example.org/abi-encode/) instead.

*Instances (30)*:
```solidity
File: DegenerusGame.sol

312:                 abi.encodeWithSelector(

340:                 abi.encodeWithSelector(

561:                 abi.encodeWithSelector(

588:                 abi.encodeWithSelector(

609:                 abi.encodeWithSelector(

644:                 abi.encodeWithSelector(

666:                 abi.encodeWithSelector(

686:                 abi.encodeWithSelector(

715:                 abi.encodeWithSelector(

731:                 abi.encodeWithSelector(

758:                 abi.encodeWithSelector(

783:                 abi.encodeWithSelector(

807:                 abi.encodeWithSelector(

828:                 abi.encodeWithSelector(

849:                 abi.encodeWithSelector(

904:                 abi.encodeWithSelector(

1041:                 abi.encodeWithSelector(

1073:                 abi.encodeWithSelector(

1102:                 abi.encodeWithSelector(

1128:                 abi.encodeWithSelector(

1149:                 abi.encodeWithSelector(

1185:                 abi.encodeWithSelector(

1210:                 abi.encodeWithSelector(

1227:                 abi.encodeWithSelector(

1705:                 abi.encodeWithSelector(

1761:                     abi.encodeWithSelector(

1884:                 abi.encodeWithSelector(

1903:                 abi.encodeWithSelector(

1920:                 abi.encodeWithSelector(

1940:                 abi.encodeWithSelector(

```

### <a name="NC-2"></a>[NC-2] Missing checks for `address(0)` when assigning values to address state variables

*Instances (2)*:
```solidity
File: BurnieCoinflip.sol

662:                     bountyOwedTo = player;

```

```solidity
File: DegenerusDeityPass.sol

99:         renderer = newRenderer;

```

### <a name="NC-3"></a>[NC-3] Array indices should be referenced via `enum`s rather than via numeric literals

*Instances (57)*:
```solidity
File: DegenerusAffiliate.sol

603:             players[0] = affiliateAddr;

604:             amounts[0] = affiliateShareBase + questReward;

611:             amounts[1] = baseBonus + questRewardUpline;

618:             amounts[2] = bonus2 + questReward2;

622:             uint256 totalAmount = amounts[0] + amounts[1] + amounts[2];

623:             if (totalAmount != 0) {

881: 

```

```solidity
File: DegenerusDeityPass.sol

245:         if (b.length != 7 || b[0] != "#") return false;

```

```solidity
File: DegenerusGame.sol

244:         levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL;

```

```solidity
File: DegenerusJackpots.sol

604:         if (score <= board[3].score) return; // Not good enough

```

```solidity
File: DegenerusQuests.sol

383:         _seedQuestType(quests[0], day, primaryType);

384:         _seedQuestType(quests[1], day, bonusType);

389:             quests[0].questType,

391:             quests[0].version,

392:             quests[0].difficulty

397:             quests[1].questType,

399:             quests[1].version,

400:             quests[1].difficulty

403:         questTypes[0] = primaryType;

404:         questTypes[1] = bonusType;

453:             return (0, quests[0].questType, state.streak, false);

550:             return (0, quests[0].questType, state.streak, false);

605:             return (0, quests[0].questType, state.streak, false);

656:             return (0, quests[0].questType, state.streak, false);

709:             return (0, quests[0].questType, state.streak, false);

763:             return (0, quests[0].questType, state.streak, false);

1595:         if (day0 != 0) return day0;

1599: 

```

```solidity
File: libraries/JackpotBucketLib.sol

38:         base[0] = 25; // Large bucket

39:         base[1] = 15; // Mid bucket

40:         base[2] = 8; // Small bucket

41:         base[3] = 1; // Solo bucket (receives the 60% share via rotation)

111:         total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];

111:         total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];

122:             capped[0] = 0;

123:             capped[1] = 0;

124:             capped[2] = 0;

125:             capped[3] = 0;

131:             capped[0] = 0;

132:             capped[1] = 0;

133:             capped[2] = 0;

134:             capped[3] = 0;

138:             capped[0] = 0;

139:             capped[1] = 0;

140:             capped[2] = 0;

141:             capped[3] = 0;

265:         packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);

270:         traits[0] = uint8(packed);

271:         traits[1] = uint8(packed >> 8);

272:         traits[2] = uint8(packed >> 16);

273:         traits[3] = uint8(packed >> 24);

279:         w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63

280:         w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127

281:         w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191

282:         w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255

292:         uint16 largestCount = counts[0];

299:         order[0] = largestIdx;

```

### <a name="NC-4"></a>[NC-4] Use `string.concat()` or `bytes.concat()` instead of `abi.encodePacked`
Solidity version 0.8.4 introduces `bytes.concat()` (vs `abi.encodePacked(<bytes>,<bytes>)`)

Solidity version 0.8.12 introduces `string.concat()` (vs `abi.encodePacked(<str>,<str>), which catches concatenation errors (in the event of a `bytes` data mixed in the concatenation)`)

*Instances (17)*:
```solidity
File: BurnieCoinflip.sol

784:         uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

```

```solidity
File: DegenerusAffiliate.sol

581:                         abi.encodePacked(

859:                 abi.encodePacked(

```

```solidity
File: DegenerusDeityPass.sol

138:             symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));

162:         string memory json = string(abi.encodePacked(

170:         return string(abi.encodePacked(

187:             abi.encodePacked(

198:         return string(abi.encodePacked(

283:             abi.encodePacked(

300:         return string(abi.encodePacked(Strings.toString(i), ".", _pad6(uint32(f))));

305:             return string(abi.encodePacked("-", _dec6(uint256(-x))));

```

```solidity
File: DegenerusGame.sol

885:             rngWord = uint256(keccak256(abi.encodePacked(day, address(this))));

2679:             word = uint256(keccak256(abi.encodePacked(word, s)));

```

```solidity
File: DegenerusJackpots.sol

270:             entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));

287:             entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));

329:             entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));

385:                 entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));

```

### <a name="NC-5"></a>[NC-5] Constants should be in CONSTANT_CASE
For `constant` variable names, each word should use all capital letters, with underscores separating each word (CONSTANT_CASE)

*Instances (60)*:
```solidity
File: BurnieCoin.sol

168:     string public constant name = "Burnies";

171:     string public constant symbol = "BURNIE";

241:     IDegenerusGame internal constant degenerusGame =

245:     IDegenerusQuests internal constant questModule =

250:     address internal constant coinflipContract = ContractAddresses.COINFLIP;

379:     uint8 public constant decimals = 18;

```

```solidity
File: BurnieCoinflip.sol

135:     IDegenerusQuests internal constant questModule =

```

```solidity
File: DegenerusAdmin.sol

233:     IVRFCoordinatorV2_5Owner internal constant vrfCoordinator =

235:     IDegenerusGameAdmin internal constant gameAdmin =

237:     ILinkTokenLike internal constant linkToken =

239:     IDegenerusCoinLinkReward internal constant coinLinkReward =

241:     IsDGNRS internal constant sDGNRS =

319:     IDegenerusVaultOwner private constant vault =

```

```solidity
File: DegenerusAffiliate.sol

191:     IDegenerusCoinAffiliate internal constant coin = IDegenerusCoinAffiliate(ContractAddresses.COIN);

193:     IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);

```

```solidity
File: DegenerusGame.sol

142:     IDegenerusCoin internal constant coin =

147:     IBurnieCoinflip internal constant coinflip =

152:     IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

155:     IDegenerusAffiliate internal constant affiliate =

159:     IStakedDegenerusStonk internal constant dgnrs =

163:     IDegenerusQuestView internal constant questView =

```

```solidity
File: DegenerusJackpots.sol

93:     IDegenerusCoinJackpotView internal constant coin = IDegenerusCoinJackpotView(ContractAddresses.COINFLIP);

96:     IDegenerusGame internal constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);

```

```solidity
File: DegenerusQuests.sol

204:     IDegenerusGame internal constant questGame = IDegenerusGame(ContractAddresses.GAME);

```

```solidity
File: DegenerusStonk.sol

64:     string public constant name = "Degenerus Stonk";

65:     string public constant symbol = "DGNRS";

66:     uint8 public constant decimals = 18;

80:     IStakedDegenerusStonk private constant stonk = IStakedDegenerusStonk(ContractAddresses.SDGNRS);

81:     IERC20Minimal private constant burnie = IERC20Minimal(ContractAddresses.COIN);

82:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: DegenerusVault.sol

171:     uint8 public constant decimals = 18;

345:     string public constant name = "Degenerus Vault";

347:     string public constant symbol = "DGV";

349:     uint8 public constant decimals = 18;

365:     IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);

367:     IDegenerusGamePlayerActions internal constant gamePlayer =

370:     ICoinflipPlayerActions internal constant coinflipPlayer =

373:     ICoinPlayerActions internal constant coinPlayer =

376:     IVaultCoin internal constant coinToken = IVaultCoin(ContractAddresses.COIN);

378:     IWWXRPMint internal constant wwxrpToken = IWWXRPMint(ContractAddresses.WWXRP);

380:     IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: GNRUS.sol

121:     string public constant name = "GNRUS Donations";

124:     string public constant symbol = "GNRUS";

127:     uint8 public constant decimals = 18;

220:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

223:     ISDGNRSSnapshot private constant sdgnrs = ISDGNRSSnapshot(ContractAddresses.SDGNRS);

226:     IDegenerusGameDonations private constant game = IDegenerusGameDonations(ContractAddresses.GAME);

229:     IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);

```

```solidity
File: StakedDegenerusStonk.sol

144:     string public constant name = "Staked Degenerus Stonk";

147:     string public constant symbol = "sDGNRS";

150:     uint8 public constant decimals = 18;

230:     IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

233:     IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);

235:     IBurnieCoinflipPlayer private constant coinflip =

239:     IDegenerusStonkWrapper private constant dgnrsWrapper = IDegenerusStonkWrapper(ContractAddresses.DGNRS);

242:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: WrappedWrappedXRP.sol

118:     string public constant name = "Wrapped Wrapped WWXRP (PARODY)";

121:     string public constant symbol = "WWXRP";

124:     uint8 public constant decimals = 18;

150:     IERC20 internal constant wXRP = IERC20(ContractAddresses.WXRP);

```

### <a name="NC-6"></a>[NC-6] `constant`s should be defined rather than using magic numbers
Even [assembly](https://github.com/code-423n4/2022-05-opensea-seaport/blob/9d7ce4d08bf3c3010304a0476a785c70c0e90ae7/contracts/lib/TokenTransferrer.sol#L35-L39) can benefit from using readable constants instead of hex/numeric literals

*Instances (290)*:
```solidity
File: BurnieCoin.sol

163:       |  |  2   | allowance                   | mapping(addr => mapping)   | |

217:       |  a single 32-byte slot where possible.                               |

272:         _mint(ContractAddresses.SDGNRS, 2_000_000 ether);

347:       |  accumulates 1000 BURNIE per coinflip window. When a player sets     |

356:       |  |  17  | currentBounty    | uint128  | 16 bytes | Pool size       | |

357:       |  |      | biggestFlipEver  | uint128  | 16 bytes | All-time record | |

358:       |  |  18  | bountyOwedTo     | address  | 20 bytes | Armed recipient | |

767:             for (uint256 i; i < 2; ) {

939:         uint8 minBucket = (lvl % 100 == 0)

1040:         uint256 reduction = (range * bonusBps + (DECIMATOR_ACTIVITY_CAP_BPS / 2)) / DECIMATOR_ACTIVITY_CAP_BPS;

1049:         return BPS_DENOMINATOR + (bonusBps / 3);

```

```solidity
File: BurnieCoinflip.sol

504:                         100;

574:                 (purchaseLevel_ % 10 == 0)

621:                 uint256 maxDeposit = 100_000 ether; // Cap at 100k BURNIE for boost calc

625:                 uint256 boost = (cappedDeposit * boonBps) / 10_000;

657:                     uint256 onePercent = uint256(record) / 100;

789:         uint256 roll = seedWord % 20;

792:             rewardPercent = 50; // Unlucky: 50% bonus (1.5x total)

794:             rewardPercent = 150; // Lucky: 150% bonus (2.5x total)

805:                 rewardPercent += 6;

882:         for (uint256 i; i < 3; ) {

981:                         100;

1012:         locked = (!inJackpotPhase) && !degenerusGame.gameOver() && lastPurchaseDay_ && rngLocked_ && (purchaseLevel_ % 10 == 0);

1020:         bonus = amount / 100;

1021:         uint256 bonusCap = 1000 ether;

1032:         uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;

1035:             return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1039:             / (uint256(BPS_DENOMINATOR) * 2);

1107:         uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;

```

```solidity
File: DegenerusAdmin.sol

532:         if (elapsed >= 168 hours) return 0;

533:         if (elapsed >= 144 hours) return 500;   // 5%

534:         if (elapsed >= 120 hours) return 1000;  // 10%

535:         if (elapsed >= 96 hours)  return 2000;  // 20%

536:         if (elapsed >= 72 hours)  return 3000;  // 30%

537:         if (elapsed >= 48 hours)  return 4000;  // 40%

538:         return 5000; // 50%

761:         if (subBal >= 1000 ether) return 0;

762:         if (subBal <= 200 ether) {

763:             uint256 delta = (subBal * 2e18) / 200 ether;

765:                 return 3e18 - delta;

768:         uint256 excess = subBal - 200 ether;

769:         uint256 delta2 = (excess * 1e18) / 800 ether;

```

```solidity
File: DegenerusAffiliate.sol

506:             rewardScaleBps = lvl <= 3

564:             kickbackShare = (scaledAmount * uint256(kickbackPct)) / 100;

577:             uint256 totalAmount = scaledAmount + scaledAmount / 5 + scaledAmount / 25;

589:                 address winner = (entropy % 2 == 0)

608:             uint256 baseBonus = scaledAmount / 5;

615:             uint256 bonus2 = scaledAmount / 25;

627:                     3,

695:             for (uint8 offset = 1; offset <= 5; ) {

```

```solidity
File: DegenerusDeityPass.sol

134:         uint8 quadrant = uint8(tokenId / 8);

135:         uint8 symbolIdx = uint8(tokenId % 8);

245:         if (b.length != 7 || b[0] != "#") return false;

246:         for (uint256 i = 1; i < 7; ++i) {

257:         if (quadrant == 0 && (symbolIdx == 1 || symbolIdx == 5)) return 790_000;

258:         if (quadrant == 2 && (symbolIdx == 1 || symbolIdx == 5)) return 820_000;

259:         if (quadrant == 1 && symbolIdx == 6) return 820_000;

260:         if (quadrant == 3 && symbolIdx == 7) return 780_000;

261:         return 890_000;

272:         txm = -w1e6 / 2;

273:         tyn = -h1e6 / 2;

312:         for (uint256 k; k < 6; ++k) {

313:             b[5 - k] = bytes1(uint8(48 + (f % 10)));

314:             f /= 10;

383:         if (tokenId >= 32) revert InvalidToken();

```

```solidity
File: DegenerusGame.sol

222:       |  [154-159] (reserved)       - 6 unused bits                           |

224:       |  [184-227] (reserved)      - 44 unused bits                          |

249:         for (uint24 i = 1; i <= 100; ) {

250:             _queueTickets(ContractAddresses.SDGNRS, i, 16);

251:             _queueTickets(ContractAddresses.VAULT, i, 16);

266:       |  through its 2 active phases: PURCHASE (jackpotPhaseFlag=false), JACKPOT (jackpotPhaseFlag=true). |

276:       |  • Anyone — bypasses after 30+ min since level start                                   |

277:       |  • Pass holder (lazy/whale) — bypasses after 15+ min                                   |

282:       |  • Starts active: 62% bonus BURNIE from loot boxes, bonusFlip active                    |

394:                 10_000;

451:         uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;

881:         deityPassAvailable = deityPassOwners.length < 32; // DEITY_PASS_MAX_TOTAL (see LootboxModule)

1280:         if (denom < 2) return 0;

1281:         uint8 shift = (denom - 2) << 2;

1414:             uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;

1757:             uint256 box = remaining > 5 ether ? 5 ether : remaining;

1784:       |  • Daily jackpot - Paid each day to burn ticket holders (day 5 = full pool payout)             |

1785:       |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |

1858:       |  2. If no valid RNG word, _requestRng() is called                    |

1859:       |  3. Chainlink calls rawFulfillRandomWords() with random word         |

1860:       |  4. Next advanceGame() uses the fulfilled word                       |

1861:       |  5. After processing, _unlockRng() resets for next cycle             |

1865:       |  • 12-hour timeout allows recovery from stale requests               |

2065:         return uint32(ticketsOwedPacked[_tqWriteKey(lvl)][player] >> 8);

2079:         amount = packed & ((1 << 232) - 1);

2226:         if (day < 2 || rngWordByDay[day - 2] != 0) return false;

2283:                 uint256(ts) + 10 days >

2286:         return uint256(ts) + 5 days > uint256(lst) + 120 days;

2399:       |  • Mint streak: +1% per consecutive level minted (cap 50%)           |

2400:       |  • Mint count: +25% for 100% participation, scaled proportionally    |

2401:       |  • Quest streak: +1% per consecutive quest (cap 100%)                |

2402:       |  • Affiliate points: +1% per affiliate point (cap 50%)               |

2404:       |    - 10-level bundle: +10%                                           |

2405:       |    - 100-level bundle: +40%                                          |

2439:             (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3

2442:             (bundleType == 1 || bundleType == 3);

2448:                 bonusBps = 50 * 100;

2449:                 bonusBps += 25 * 100;

2452:                 uint256 streakPoints = streak > 50 ? 50 : uint256(streak);

2467:                 bonusBps = streakPoints * 100;

2468:                 bonusBps += mintCountPoints * 100;

2474:             uint256 questStreak = questStreakRaw > 100

2475:                 ? 100

2477:             bonusBps += questStreak * 100;

2483:                 100;

2490:                     bonusBps += 1000; // +10% for 10-level bundle

2491:                 } else if (bundleType == 3) {

2492:                     bonusBps += 4000; // +40% for 100-level bundle

2516:         if (mintCount >= currLevel) return 25;

2520:         return (uint256(mintCount) * 25) / uint256(currLevel);

2609:         if (maxOffset > 20) maxOffset = 20;

2618:         traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word

2625:         uint256 take = len > 4 ? 4 : len; // only need a small sample for scatter draws

2627:         uint256 start = (word >> 40) % len; // consume another slice for the start offset

2647:         traitSel = uint8(entropy >> 24);

2654:         uint256 take = len > 4 ? 4 : len;

2656:         uint256 start = (entropy >> 40) % len;

2678:         for (uint8 s; s < 10 && found < 4; ) {

2680:             uint24 candidate = currentLvl + 5 + uint24(word % 95);

2685:                 uint256 idx = (word >> 32) % len;

2753:         tickets = uint32(ticketsOwedPacked[_tqWriteKey(level)][player] >> 8);

2770:         if (quadrant >= 4 || symbol >= 8) return 0;

2772:         wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;

2787:         for (uint8 q = 0; q < 4; ++q) {

2789:             for (uint8 s = 0; s < 8; ++s) {

2790:                 uint256 amount = (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;

2820:         amountUnits = packed >> 160;

```

```solidity
File: DegenerusJackpots.sol

190:       |  | 10% | Top BAF bettor for this level                             | |

191:       |  |  5% | Top coinflip bettor from last 24h window                  | |

192:       |  |  5% | Random pick: 3rd or 4th BAF slot                          | |

193:       |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)  | |

194:       |  |  5% | Far-future ticket holders 2nd draw (3% 1st / 2% 2nd)      | |

195:       |  | 45% | Scatter 1st place (50 rounds x 4 multi-level trait tickets) | |

196:       |  | 25% | Scatter 2nd place (50 rounds x 4 multi-level trait tickets) | |

242:             uint256 topPrize = P / 10;

255:             uint256 topPrize = P / 20;

271:             uint256 prize = P / 20;

272:             uint8 pick = 2 + uint8(entropy & 1);

290:             uint256 farFirst = (P * 3) / 100;

291:             uint256 farSecond = P / 50;

332:             uint256 farFirst = (P * 3) / 100;

333:             uint256 farSecond = P / 50;

372:             uint256 scatterTop = (P * 45) / 100;

373:             uint256 scatterSecond = P / 4;

378:             bool isCentury = (lvl % 100 == 0);

392:                     if (round < 4) targetLvl = lvl;

393:                     else if (round < 8) targetLvl = lvl + 1 + uint24(entropy % 3);

394:                     else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);

396:                         uint24 maxBack = lvl > 99 ? 99 : lvl - 1;

400:                     if (round < 20) targetLvl = lvl;

401:                     else targetLvl = lvl + 1 + uint24(entropy % 4);

408:                 if (limit > 4) limit = 4;

561:         uint8 existing = 4; // sentinel: not found

573:         if (existing < 4) {

590:         if (len < 4) {

605:         uint8 idx2 = 3;

```

```solidity
File: DegenerusQuests.sol

374:         uint256 bonusEntropy = (entropy >> 128) | (entropy << 128);

1009:         if (lvl < 5) return false;

1010:         return (lvl % 10) == 5 && (lvl % 100) != 95;

1325:                 weight = 4;

1327:                 weight = 10;

1329:                 weight = 4;

1331:                 weight = 3;

```

```solidity
File: DegenerusStonk.sol

157:         if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 5 hours)

253:         if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

261:         uint256 stethToGnrus = stethOut / 2;

263:         uint256 ethToGnrus = ethOut / 2;

```

```solidity
File: DegenerusTraitUtils.sol

17:   |  |  Bits 7-6: Quadrant identifier (0-3)                                   |  |

18:   |  |  Bits 5-3: Category bucket (0-7)                                       |  |

19:   |  |  Bits 2-0: Sub-bucket (0-7)                                            |  |

21:   |  |  Format: [QQ][CCC][SSS] = 8 bits                                       |  |

23:   |  |  • Quadrant: Which of 4 trait slots (A=0, B=1, C=2, D=3)               |  |

30:   |  |  Bits 31-24: Trait D (quadrant 3)                                      |  |

31:   |  |  Bits 23-16: Trait C (quadrant 2)                                      |  |

32:   |  |  Bits 15-8:  Trait B (quadrant 1)                                      |  |

33:   |  |  Bits 7-0:   Trait A (quadrant 0)                                      |  |

35:   |  |  [DDDDDDDD][CCCCCCCC][BBBBBBBB][AAAAAAAA] = 32 bits                     |  |

42:   |  |    0    |  0-9     |  10   |  13.3%                                    |  |

43:   |  |    1    | 10-19    |  10   |  13.3%                                    |  |

44:   |  |    2    | 20-29    |  10   |  13.3%                                    |  |

45:   |  |    3    | 30-39    |  10   |  13.3%                                    |  |

46:   |  |    4    | 40-48    |   9   |  12.0%                                    |  |

47:   |  |    5    | 49-57    |   9   |  12.0%                                    |  |

48:   |  |    6    | 58-66    |   9   |  12.0%                                    |  |

49:   |  |    7    | 67-74    |   8   |  10.7%                                    |  |

51:   |  |  Total: 75 (scaled from uint32 range)                                  |  |

56:   |  |  256-bit seed divided into 4 × 64-bit words:                           |  |

58:   |  |  [bits 255-192] → Trait D (category from low 32, sub from high 32)     |  |

59:   |  |  [bits 191-128] → Trait C (category from low 32, sub from high 32)     |  |

60:   |  |  [bits 127-64]  → Trait B (category from low 32, sub from high 32)     |  |

61:   |  |  [bits 63-0]    → Trait A (category from low 32, sub from high 32)     |  |

73:   |  2. ARITHMETIC SAFETY:                                                       |

78:   |  3. DETERMINISM:                                                             |

116:             uint32 scaled = uint32((uint64(rnd) * 75) >> 32);

119:             if (scaled < 10) return 0;

120:             if (scaled < 20) return 1;

121:             if (scaled < 30) return 2;

122:             if (scaled < 40) return 3;

123:             if (scaled < 49) return 4;

124:             if (scaled < 58) return 5;

125:             if (scaled < 67) return 6;

126:             return 7;

133:       |  Derives 6-bit trait from 64-bit random word.                        |

147:         uint8 sub = weightedBucket(uint32(rnd >> 32));

149:         return (category << 3) | sub;

155:       |  Packs 4 traits into 32-bit value for efficient storage.             |

175:         uint8 traitB = traitFromWord(uint64(rand >> 64)) | 64; // Quadrant 1: bits 7-6 = 01

176:         uint8 traitC = traitFromWord(uint64(rand >> 128)) | 128; // Quadrant 2: bits 7-6 = 10

177:         uint8 traitD = traitFromWord(uint64(rand >> 192)) | 192; // Quadrant 3: bits 7-6 = 11

180:         return uint32(traitA) | (uint32(traitB) << 8) | (uint32(traitC) << 16) | (uint32(traitD) << 24);

```

```solidity
File: DegenerusVault.sol

418:         return balance * 1000 > supply * 501;

625:             3,

```

```solidity
File: Icons32Data.sol

14: |  Icons32Data is an on-chain storage contract for SVG path data. It holds 33 icon                     |

23: |  |   _paths[16-23] -► Quadrant 2 (Cards):    Horseshoe, King, Cashsack, Club, Diamond, Heart       | |

25: |  |   _paths[24-31] -► Quadrant 3 (Dice):     1-8                                                   | |

41: |  2. Batch initialization via setter functions allows data population within gas limits.              |

42: |  3. finalize() locks all data permanently, making it immutable after initialization.                 |

43: |  4. View functions allow efficient reading by renderers without state changes.                       |

44: |  5. SVG paths are stored as raw strings (not base64) to allow renderer flexibility.                  |

55: |  2. ACCESS CONTROL                                                                                    |

59: |  3. BOUNDS CHECKING                                                                                   |

61: |     • data(i) will revert if i >= 33 (array bounds)                                                   |

62: |     • symbol(q, idx) returns "" for quadrant 3 or invalid quadrant; reverts for invalid idx          |

64: |  4. NO EXTERNAL CALLS                                                                                 |

68: |  5. GAS OPTIMIZATION                                                                                  |

69: |     • Batch size limited to 10 paths per call to stay under gas limits                                |

78: |  2. Path data does not contain malicious SVG (script injection, etc.)                                 |

79: |  3. Symbol names are appropriate and accurate                                                         |

156:         if (paths.length > 10) revert MaxBatch();

157:         if (startIndex + paths.length > 33) revert IndexOutOfBounds();

176:             for (uint256 i = 0; i < 8; ++i) {

180:             for (uint256 i = 0; i < 8; ++i) {

183:         } else if (quadrant == 2) {

184:             for (uint256 i = 0; i < 8; ++i) {

224:         if (quadrant == 2) return _symQ3[idx];

```

```solidity
File: StakedDegenerusStonk.sol

293:             10 ether,

547:         uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;

552:         burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;

587:         uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

596:             ethDirect = totalRolledEth / 2;

607:                 burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;

718:         if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();

```

```solidity
File: libraries/EntropyLib.sol

18:             state ^= state << 7;

19:             state ^= state >> 9;

20:             state ^= state << 8;

```

```solidity
File: libraries/JackpotBucketLib.sol

38:         base[0] = 25; // Large bucket

39:         base[1] = 15; // Mid bucket

40:         base[2] = 8; // Small bucket

44:         uint8 offset = uint8(entropy & 3);

45:         for (uint8 i; i < 4; ) {

46:             counts[i] = base[(i + offset) & 3];

80:             for (uint8 i; i < 4; ) {

83:                     uint256 scaled = (uint256(baseCount) * scaleBps) / 10_000;

151:         for (uint8 i; i < 4; ) {

169:             uint8 trimOff = uint8((entropy >> 24) & 3);

170:             for (uint8 i; i < 4 && excess != 0; ) {

171:                 uint8 idx = uint8((uint256(trimOff) + 3 - i) & 3);

187:             uint8 offset = uint8((entropy >> 24) & 3);

188:             for (uint8 i; i < 4 && remainder != 0; ) {

189:                 uint8 idx = uint8((uint256(offset) + i) & 3);

219:         for (uint8 i; i < 4; ) {

222:                 uint256 share = (pool * shareBps[i]) / 10_000;

241:         return uint8((uint256(3) - (entropy & 3)) & 3);

246:         uint8 baseIndex = uint8((uint256(traitIdx) + uint256(offset) + 1) & 3);

247:         return uint16(packed >> (baseIndex * 16));

253:             for (uint8 i; i < 4; ++i) {

265:         packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);

271:         traits[1] = uint8(packed >> 8);

272:         traits[2] = uint8(packed >> 16);

273:         traits[3] = uint8(packed >> 24);

280:         w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127

281:         w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191

282:         w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255

293:         for (uint8 i = 1; i < 4; ++i) {

301:         for (uint8 i; i < 4; ++i) {

```

```solidity
File: libraries/PriceLookupLib.sol

23:         if (targetLevel < 5) return 0.01 ether;

24:         if (targetLevel < 10) return 0.02 ether;

27:         if (targetLevel < 30) return 0.04 ether;

28:         if (targetLevel < 60) return 0.08 ether;

29:         if (targetLevel < 90) return 0.12 ether;

30:         if (targetLevel < 100) return 0.16 ether;

32:         uint256 cycleOffset = targetLevel % 100;

37:         } else if (cycleOffset < 30) {

39:         } else if (cycleOffset < 60) {

41:         } else if (cycleOffset < 90) {

```

### <a name="NC-7"></a>[NC-7] Control structures do not follow the Solidity Style Guide
See the [control structures](https://docs.soliditylang.org/en/latest/style-guide.html#control-structures) section of the Solidity Style Guide

*Instances (545)*:
```solidity
File: BurnieCoin.sol

82:         bool highDifficulty

115:       |  to a specific access control or validation failure.                 |

349:       |  coinflip resolution, half the pool is removed; if they win, that    |

444:         if (value > type(uint128).max) revert SupplyOverflow();

454:         if (from == address(0) || to == address(0)) revert ZeroAddress();

480:         if (to == address(0)) revert ZeroAddress();

500:         if (from == address(0)) revert ZeroAddress();

504:             if (amount128 > allowanceVault) revert Insufficient();

529:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

538:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

547:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

548:         if (amount == 0) return;

557:         if (player == address(0) || amount == 0) return;

585:         if (player == address(0) || amount == 0) return;

591:         if (amount == 0) return;

592:         if (degenerusGame.rngLocked()) return;

594:         if (balance >= amount) return;

604:         if (amount == 0) return 0;

605:         if (degenerusGame.rngLocked()) return 0;

607:         if (balance >= amount) return 0;

617:       |                         MODIFIERS                                    |

619:       |  Access control modifiers for privileged operations. Each modifier   |

620:       |  gates access to a specific set of trusted contracts.                |

622:       |  MODIFIER HIERARCHY:                                                 |

624:       |  |  Modifier              | Allowed Callers                        | |

637:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

645:         if (

656:         if (

666:         if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();

673:         if (msg.sender != ContractAddresses.ADMIN) revert OnlyGame();

690:         if (

706:         if (to == address(0)) revert ZeroAddress();

709:         if (amount128 > allowanceVault) revert Insufficient();

728:         if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();

730:         if (player == address(0) || amount == 0) return 0;

750:       |  Daily quest lifecycle functions. The coin contract acts as a hub    |

764:         (bool rolled, uint8[2] memory questTypes, bool highDifficulty) = module

768:                 emit DailyQuestRolled(day, questTypes[i], highDifficulty);

782:     function notifyQuestMint(

787:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

816:         if (sender != ContractAddresses.GAME) revert OnlyGame();

843:         if (sender != ContractAddresses.GAME) revert OnlyGame();

901:         if (amount < DECIMATOR_MIN) revert AmountLTMin();

904:         if (!open) revert NotDecimatorWindow();

972:       |  early conviction. Total loss if level completes normally.           |

992:         if (amount < DECIMATOR_MIN) revert AmountLTMin();

995:         if (!open) revert NotDecimatorWindow();

1033:         if (bonusBps == 0) return adjustedBucket;

1042:         if (bucket < minBucket) bucket = minBucket;

1048:         if (bonusBps == 0) return BPS_DENOMINATOR;

1066:         if (!completed) return 0;

```

```solidity
File: BurnieCoinflip.sol

187:       |                         MODIFIERS                                    |

191:         if (msg.sender != address(degenerusGame)) revert OnlyDegenerusGame();

196:         if (

204:         if (msg.sender != address(burnie)) revert OnlyBurnieCoin();

249:             if (amount < MIN) revert AmountLTMin();

252:             if (_coinflipLockedDuringTransition()) revert CoinflipLocked();

349:         if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();

381:         if (stored == 0) return 0;

437:         if (start >= latest) return mintable;

569:             if (

649:                 if (recordAmount > type(uint128).max) revert Insufficient();

706:         if (degenerusGame.rngLocked()) revert RngLocked();

711:                 if (strict) revert AutoRebuyAlreadyEnabled();

756:         if (degenerusGame.rngLocked()) revert RngLocked();

758:         if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();

873:         if (player == address(0) || amount == 0) return;

936:         if (lastDay == 0) return (address(0), 0);

948:         if (startDay >= latestDay) return 0;

1019:         if (amount == 0) return 0;

1022:         if (bonus > bonusCap) bonus = bonusCap;

1031:         if (amount == 0) return 0;

1048:         if (activationLevel == 0) return 0;

1049:         if (currentLevel <= activationLevel) return 0;

1072:         if (!completed) return 0;

1108:         if (bracket > type(uint24).max) return MAX_BAF_BRACKET;

1114:         if (player == address(0)) return msg.sender;

```

```solidity
File: DegenerusAdmin.sol

310:     uint256 private constant PROPOSAL_LIFETIME = 168 hours;

323:         if (!vault.isVaultOwner(msg.sender)) revert NotOwner();

359:         if (_feedHealthy(current)) revert FeedHealthy();

360:         if (

375:         if (msg.value == 0) revert InvalidAmount();

402:         if (subscriptionId == 0) revert NotWired();

403:         if (gameAdmin.gameOver()) revert GameOver();

404:         if (newCoordinator == address(0) || newKeyHash == bytes32(0))

411:             if (ep.state == ProposalState.Active &&

422:             if (stall < ADMIN_STALL_THRESHOLD) revert NotStalled();

425:             if (stall < COMMUNITY_STALL_THRESHOLD) revert NotStalled();

427:             if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)

455:         if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD)

459:         if (p.state != ProposalState.Active || p.createdAt == 0)

471:         if (weight == 0) revert InsufficientStake();

501:         if (

510:         if (

532:         if (elapsed >= 168 hours) return 0;

533:         if (elapsed >= 144 hours) return 500;   // 5%

534:         if (elapsed >= 120 hours) return 1000;  // 10%

535:         if (elapsed >= 96 hours)  return 2000;  // 20%

536:         if (elapsed >= 72 hours)  return 3000;  // 30%

537:         if (elapsed >= 48 hours)  return 4000;  // 40%

546:         if (p.state != ProposalState.Active || p.createdAt == 0) return false;

547:         if (block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME) return false;

551:         if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD) return false;

635:             if (i == exceptId) continue;

652:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

654:         if (subId == 0) return;

688:         if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();

689:         if (amount == 0) revert InvalidAmount();

692:         if (subId == 0) revert NoSubscription();

693:         if (gameAdmin.gameOver()) revert GameOver();

705:             if (!ok) revert InvalidAmount();

709:         if (mult == 0) return;

717:         if (ethEquivalent == 0) return;

720:         if (priceWei == 0) return;

723:         if (credit == 0) return;

738:         if (feed == address(0) || amount == 0) return 0;

747:         if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)

749:         if (updatedAt > block.timestamp) return 0;

751:             if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE) return 0;

761:         if (subBal >= 1000 ether) return 0;

770:         if (delta2 >= 1e18) return 0;

778:         if (feed == address(0)) return false;

786:             if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)

788:             if (updatedAt > block.timestamp) return false;

790:                 if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE)

794:                 if (dec != LINK_ETH_FEED_DECIMALS) return false;

```

```solidity
File: DegenerusAffiliate.sol

242:         if (

329:         if (referrer == address(0) || referrer == msg.sender) revert Insufficient();

332:         if (existing != bytes32(0) && !_vaultReferralMutable(existing)) revert Insufficient();

408:         if (

692:         if (player == address(0) || currLevel == 0) return 0;

696:                 if (currLevel <= offset) break;

703:         if (sum == 0) return 0;

715:         if (code != REF_CODE_LOCKED && code != AFFILIATE_CODE_VAULT) return false;

736:         if (owner != address(0)) return owner;

752:         if (code == bytes32(0) || code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) return ContractAddresses.VAULT;

754:         if (owner == address(0)) return ContractAddresses.VAULT;

764:         if (owner == address(0)) revert Zero();

766:         if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();

768:         if (uint256(code_) <= type(uint160).max) revert Zero();

770:         if (kickbackPct > MAX_KICKBACK_PCT) revert InvalidKickback();

773:         if (info.owner != address(0)) revert Insufficient();

783:         if (player == address(0)) revert Zero();

786:         if (referrer == address(0) || referrer == player) revert Insufficient();

787:         if (playerReferralCode[player] != bytes32(0)) revert Insufficient();

798:         if (player == address(0) || amount == 0) return;

872:             if (roll < running) return players[i];

```

```solidity
File: DegenerusDeityPass.sol

72:         if (msg.sender != _contractOwner) revert NotAuthorized();

90:         if (newOwner == address(0)) revert ZeroAddress();

130:         if (_owners[tokenId] == address(0)) revert InvalidToken();

236:             if (bytes(out).length == 0) return (false, "");

245:         if (b.length != 7 || b[0] != "#") return false;

251:             if (!(digit || lower || upper)) return false;

257:         if (quadrant == 0 && (symbolIdx == 1 || symbolIdx == 5)) return 790_000;

258:         if (quadrant == 2 && (symbolIdx == 1 || symbolIdx == 5)) return 820_000;

259:         if (quadrant == 1 && symbolIdx == 6) return 820_000;

260:         if (quadrant == 3 && symbolIdx == 7) return 780_000;

334:         if (account == address(0)) revert ZeroAddress();

340:         if (ownerAddr == address(0)) revert InvalidToken();

344:         if (_owners[tokenId] == address(0)) revert InvalidToken();

382:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

383:         if (tokenId >= 32) revert InvalidToken();

384:         if (_owners[tokenId] != address(0)) revert InvalidToken();

385:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: DegenerusGame.sol

99:       |  specific failure condition in the game flow.                        |

170:       |  private to prevent external dependency on specific values.          |

259:       |                           MODIFIERS                                  |

316:         if (!ok) _revertDelegate(data);

347:         if (!ok) _revertDelegate(data);

385:         if (msg.sender != address(this)) revert E();

425:         if (msg.sender != ContractAddresses.COIN) revert E();

440:         if (

444:         if (player == address(0)) return;

445:         if (winningBet < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;

446:         if (bountyPool < COINFLIP_BOUNTY_DGNRS_MIN_POOL) return;

450:         if (poolBalance == 0) return;

452:         if (payout == 0) return;

469:         if (operator == address(0)) revert E();

494:         if (player == address(0)) return msg.sender;

495:         if (player != msg.sender) _requireApproved(player);

513:         if (msg.sender != ContractAddresses.ADMIN) revert E();

514:         if (newThreshold == 0) revert E();

570:         if (!ok) _revertDelegate(data);

595:         if (!ok) _revertDelegate(data);

615:         if (!ok) _revertDelegate(data);

650:         if (!ok) _revertDelegate(data);

671:         if (!ok) _revertDelegate(data);

692:         if (!ok) _revertDelegate(data);

721:         if (!ok) _revertDelegate(data);

737:         if (!ok) _revertDelegate(data);

770:         if (!ok) _revertDelegate(data);

789:         if (!ok) _revertDelegate(data);

800:         if (

812:         if (!ok) _revertDelegate(data);

824:         if (msg.sender != ContractAddresses.COIN) revert E();

833:         if (!ok) _revertDelegate(data);

845:         if (msg.sender != address(this)) revert E();

854:         if (!ok) _revertDelegate(data);

883:         if (rngWord == 0) rngWord = rngWordCurrent;

884:         if (rngWord == 0)

900:         if (recipient == deity) revert E();

911:         if (!ok) _revertDelegate(data);

937:             if (msg.value < amount) revert E();

942:             if (msg.value != 0) revert E();

945:             if (claimable <= amount) revert E();

954:             if (msg.value > amount) revert E();

972:             if (remaining != 0) revert E(); // Must fully cover cost

1022:         if (reason.length == 0) revert E();

1048:         if (!ok) _revertDelegate(data);

1082:         if (!ok) _revertDelegate(data);

1083:         if (data.length == 0) revert E();

1098:         if (msg.sender != address(this)) revert E();

1109:         if (!ok) _revertDelegate(data);

1110:         if (data.length == 0) revert E();

1135:         if (!ok) _revertDelegate(data);

1145:         if (msg.sender != address(this)) revert E();

1156:         if (!ok) _revertDelegate(data);

1157:         if (data.length == 0) revert E();

1181:         if (msg.sender != address(this)) revert E();

1192:         if (!ok) _revertDelegate(data);

1193:         if (data.length == 0) revert E();

1206:         if (msg.sender != address(this)) revert E();

1216:         if (!ok) _revertDelegate(data);

1217:         if (data.length == 0) revert E();

1234:         if (!ok) _revertDelegate(data);

1252:         if (totalBurn == 0) return (0, false);

1255:         if (e.claimed != 0) return (0, false);

1260:         if (denom == 0 || entryBurn == 0) return (0, false);

1264:         if (sub != winningSub) return (0, false);

1280:         if (denom < 2) return 0;

1281:         uint8 shift = (denom - 2) << 2;

1282:         return uint8((packed >> shift) & 0xF);

1294:       |  • Falls back to stETH if ETH balance insufficient                                     |

1353:         if (msg.sender != ContractAddresses.VAULT) revert E();

1358:         if (finalSwept) revert E();

1360:         if (amount <= 1) revert E();

1388:         if (currLevel == 0) revert E();

1390:         if (affiliateDgnrsClaimedBy[currLevel][player]) revert E();

1394:         if (!hasDeityPass && score < AFFILIATE_DGNRS_MIN_SCORE) revert E();

1397:         if (denominator == 0) revert E();

1400:         if (allocation == 0) revert E();

1402:         if (reward == 0) revert E();

1409:         if (paid == 0) revert E();

1467:         if (rngLockedFlag) revert RngLocked();

1488:         if (rngLockedFlag) revert RngLocked();

1503:         if (rngLockedFlag) revert RngLocked();

1568:         if (rngLockedFlag) revert RngLocked();

1573:         if (!_hasAnyLazyPass(player)) revert E();

1604:         if (deityPassCount[player] != 0) return true;

1607:             (mintPacked_[player] >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &

1617:         if (deityPassCount[player] != 0) return true;

1619:             (mintPacked_[player] >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &

1646:         if (

1661:         if (msg.sender != ContractAddresses.COINFLIP) revert E();

1663:         if (!state.afKingMode) return false;

1664:         if (_hasAnyLazyPass(player)) return true;

1676:         if (!state.afKingMode) return;

1680:             if (uint256(level) < unlockLevel) revert AfKingLockActive();

1710:         if (!ok) _revertDelegate(data);

1731:         if (msg.sender != ContractAddresses.SDGNRS) revert E();

1732:         if (amount == 0) return;

1771:             if (!ok) _revertDelegate(data);

1813:         if (msg.sender != ContractAddresses.ADMIN) revert E();

1814:         if (recipient == address(0)) revert E();

1815:         if (amount == 0 || msg.value != amount) revert E();

1818:         if (stBal < amount) revert E();

1819:         if (!steth.transfer(recipient, amount)) revert E();

1830:         if (msg.sender != ContractAddresses.ADMIN) revert E();

1831:         if (amount == 0) revert E();

1834:         if (ethBal < amount) revert E();

1841:         if (ethBal <= reserve) revert E();

1843:         if (amount > stakeable) revert E();

1856:       |  LIFECYCLE:                                                          |

1858:       |  2. If no valid RNG word, _requestRng() is called                    |

1893:         if (!ok) _revertDelegate(data);

1907:         if (!ok) _revertDelegate(data);

1924:         if (!ok) _revertDelegate(data);

1946:         if (!ok) _revertDelegate(data);

1957:         if (amount == 0) return;

1959:             if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();

1963:         if (!steth.transfer(to, amount)) revert E();

1972:         if (amount == 0) return;

1979:             if (!okEth) revert E();

1982:         if (remaining == 0) return;

1994:             if (ethRetry < leftover) revert E();

1996:             if (!ok) revert E();

2005:         if (amount == 0) return;

2012:         if (remaining == 0) return;

2015:         if (ethBal < remaining) revert E();

2017:         if (!ok) revert E();

2149:         if (finalSwept) return 0;

2174:         if (totalBalance <= obligations) return 0;

2224:         if (rngWordByDay[day] != 0) return false;

2225:         if (rngWordByDay[day - 1] != 0) return false;

2226:         if (day < 2 || rngWordByDay[day - 2] != 0) return false;

2277:         if (gameOver) return false;

2343:                 (mintPacked_[player] >> BitPackingLib.LAST_LEVEL_SHIFT) &

2357:                 (mintPacked_[player] >> BitPackingLib.LEVEL_COUNT_SHIFT) &

2388:             (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24

2425:         if (player == address(0)) return 0;

2430:             (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24

2435:             (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &

2439:             (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3

2513:         if (currLevel == 0) return 0;

2516:         if (mintCount >= currLevel) return 25;

2533:         if (finalSwept) return 0;

2535:         if (stored <= 1) return 0;

2547:         if (finalSwept) return 0;

2609:         if (maxOffset > 20) maxOffset = 20;

2733:         if (offset >= total) return (0, total, total);

2736:         if (end > total) end = total;

2739:             if (a[i] == player) count++;

2770:         if (quadrant >= 4 || symbol >= 8) return 0;

2840:         if (gameOver) revert E();

```

```solidity
File: DegenerusJackpots.sol

44:       |  specific failure condition in jackpot operations.                   |

134:       |                      MODIFIERS & ACCESS CONTROL                      |

142:         if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();

149:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

167:         if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS) return;

392:                     if (round < 4) targetLvl = lvl;

393:                     else if (round < 8) targetLvl = lvl + 1 + uint24(entropy % 3);

394:                     else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);

400:                     if (round < 20) targetLvl = lvl;

408:                 if (limit > 4) limit = 4;

514:         if (prize == 0) return false;

534:         if (bafPlayerEpoch[lvl][player] != bafEpoch[lvl]) return 0;

574:             if (score <= board[existing].score) return; // No improvement

604:         if (score <= board[3].score) return; // Not good enough

622:         if (idx >= len) return (address(0), 0);

```

```solidity
File: DegenerusQuests.sol

71:         uint16 difficulty

224:         uint48 day;       // Quest day identifier (derived by caller, not block timestamp)

226:         uint8 flags;      // Difficulty flags (HIGH/VERY_HIGH)

228:         uint16 difficulty;  // Unused (fixed to 0); retained for storage compatibility

286:         if (sender != ContractAddresses.COIN && sender != ContractAddresses.COINFLIP) revert OnlyCoin();

291:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

332:         if (player == address(0) || amount == 0 || currentDay == 0) return;

392:             quests[0].difficulty

400:             quests[1].difficulty

405:         highDifficulty = false;

406:         return (true, questTypes, highDifficulty);

476:             if (

923:             highDifficulty: false,

947:             if (

1004:         if (!game_.decWindowOpenFlag()) return false;

1007:         if (lvl != 0 && (lvl % DECIMATOR_SPECIAL_LEVEL) == 0) return true;

1009:         if (lvl < 5) return false;

1262:         if (

1549:         if (!_questProgressValidStorage(state, quest, slot, quest.day)) return false;

1552:         if (

1563:         if (target == 0) return false;

1595:         if (day0 != 0) return day0;

```

```solidity
File: DegenerusStonk.sol

90:         if (deposited == 0) revert Insufficient();

99:         if (msg.sender != address(stonk)) revert Unauthorized();

129:             if (amount > allowed) revert Insufficient();

154:         if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();

155:         if (recipient == address(0)) revert ZeroAddress();

157:         if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 5 hours)

174:         if (!IDegenerusGame(ContractAddresses.GAME).gameOver()) revert GameNotOver();

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

182:             if (!steth.transfer(msg.sender, stethOut)) revert TransferFailed();

186:             if (!success) revert TransferFailed();

211:         if (to == address(0)) revert ZeroAddress();

212:         if (to == address(this)) revert Unauthorized();

214:         if (amount > bal) revert Insufficient();

225:         if (amount == 0 || amount > bal) revert Insufficient();

251:         if (!gameContract.gameOver()) revert SweepNotReady();

253:         if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

256:         if (remaining == 0) revert NothingToSweep();

268:             if (!steth.transfer(ContractAddresses.GNRUS, stethToGnrus)) revert TransferFailed();

271:             if (!steth.transfer(ContractAddresses.VAULT, stethToVault)) revert TransferFailed();

276:             if (!ok) revert TransferFailed();

280:             if (!ok) revert TransferFailed();

296:         if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();

298:         if (amount == 0 || amount > bal) revert Insufficient();

```

```solidity
File: DegenerusTraitUtils.sol

17:   |  |  Bits 7-6: Quadrant identifier (0-3)                                   |  |

80:   |     • Critical for on-chain trait verification                               |

119:             if (scaled < 10) return 0;

120:             if (scaled < 20) return 1;

121:             if (scaled < 30) return 2;

122:             if (scaled < 40) return 3;

123:             if (scaled < 49) return 4;

124:             if (scaled < 58) return 5;

125:             if (scaled < 67) return 6;

```

```solidity
File: DegenerusVault.sol

117: |  |   REFILL MECHANISM: If user burns ALL shares, 1T new shares are minted to them.                   | |

187:         if (msg.sender != ContractAddresses.VAULT) revert Unauthorized();

240:             if (allowed < amount) revert Insufficient();

259:         if (to == address(0)) revert ZeroAddress();

275:         if (amount > bal) revert Insufficient();

291:         if (to == address(0)) revert ZeroAddress();

293:         if (amount > bal) revert Insufficient();

394:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

400:         if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();

511:         if (ticketQuantity == 0) revert Insufficient();

520:         if (burnieAmount == 0) revert Insufficient();

537:         if (priceWei == 0) revert Insufficient();

544:         if (address(this).balance < priceWei) revert Insufficient();

578:         if (totalValue > totalBet) revert Insufficient();

724:         if (amount == 0) return;

764:         if (amount == 0) revert Insufficient();

786:                 if (!coinToken.transfer(player, payBal)) revert TransferFailed();

793:                     if (!coinToken.transfer(player, claimed)) revert TransferFailed();

838:         if (amount == 0) revert Insufficient();

864:             if (stEthOut > stBal) revert Insufficient();

874:         if (stEthOut != 0) _paySteth(player, stEthOut);

875:         if (ethOut != 0) _payEth(player, ethOut);

889:         if (coinOut == 0 || coinOut > reserve) revert Insufficient();

906:         if (targetValue == 0 || targetValue > reserve) revert Insufficient();

929:         if (amount == 0 || amount > supply) revert Insufficient();

941:         if (amount == 0 || amount > supply) revert Insufficient();

964:         if (totalValue > address(this).balance) revert Insufficient();

1033:         if (!ok) revert TransferFailed();

1040:         if (!steth.transfer(to, amount)) revert TransferFailed();

1047:         if (amount == 0) return;

1048:         if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();

```

```solidity
File: DeityBoonViewer.sol

103:             if (!deityPassAvailable) total -= W_DEITY_PASS_ALL;

116:         if (roll < cursor) return DEITY_BOON_COINFLIP_5;

118:         if (roll < cursor) return DEITY_BOON_COINFLIP_10;

120:         if (roll < cursor) return DEITY_BOON_COINFLIP_25;

122:         if (roll < cursor) return DEITY_BOON_LOOTBOX_5;

124:         if (roll < cursor) return DEITY_BOON_LOOTBOX_15;

126:         if (roll < cursor) return DEITY_BOON_LOOTBOX_25;

128:         if (roll < cursor) return DEITY_BOON_PURCHASE_5;

130:         if (roll < cursor) return DEITY_BOON_PURCHASE_15;

132:         if (roll < cursor) return DEITY_BOON_PURCHASE_25;

135:             if (roll < cursor) return DEITY_BOON_DECIMATOR_10;

137:             if (roll < cursor) return DEITY_BOON_DECIMATOR_25;

139:             if (roll < cursor) return DEITY_BOON_DECIMATOR_50;

142:         if (roll < cursor) return DEITY_BOON_WHALE_10;

144:         if (roll < cursor) return DEITY_BOON_WHALE_25;

146:         if (roll < cursor) return DEITY_BOON_WHALE_50;

149:             if (roll < cursor) return DEITY_BOON_DEITY_PASS_10;

151:             if (roll < cursor) return DEITY_BOON_DEITY_PASS_25;

153:             if (roll < cursor) return DEITY_BOON_DEITY_PASS_50;

156:         if (roll < cursor) return DEITY_BOON_ACTIVITY_10;

158:         if (roll < cursor) return DEITY_BOON_ACTIVITY_25;

160:         if (roll < cursor) return DEITY_BOON_ACTIVITY_50;

162:         if (roll < cursor) return DEITY_BOON_WHALE_PASS;

164:         if (roll < cursor) return DEITY_BOON_LAZY_PASS_10;

166:         if (roll < cursor) return DEITY_BOON_LAZY_PASS_25;

168:         if (roll < cursor) return DEITY_BOON_LAZY_PASS_50;

```

```solidity
File: GNRUS.sol

237:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

275:         if (amount < MIN_BURN) revert InsufficientBurn();

315:             if (!steth.transfer(burner, stethOut)) revert TransferFailed();

319:             if (!ok) revert TransferFailed();

333:         if (finalized) revert AlreadyFinalized();

357:         if (recipient == address(0)) revert ZeroAddress();

358:         if (recipient.code.length != 0) revert RecipientIsContract();

371:             if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = proposer;

372:             if (creatorProposalCount[level] >= MAX_CREATOR_PROPOSALS) revert ProposalLimitReached();

376:             if ((sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();

377:             if (hasProposed[level][proposer]) revert AlreadyProposed();

411:         if (count == 0 || proposalId < start || proposalId >= start + count) revert InvalidProposal();

414:         if (hasVoted[level][voter][proposalId]) revert AlreadyVoted();

420:             if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = voter;

423:         if (weight == 0) revert InsufficientStake();

445:         if (level != currentLevel) revert LevelNotActive();

446:         if (levelResolved[level]) revert LevelAlreadyResolved();

532:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: Icons32Data.sol

39: |  1. On-chain storage ensures token metadata remains available even if IPFS/centralized              |

51: |     • Data can be modified by CREATOR until finalize() is called                                      |

60: |     • setPaths() reverts if batch would exceed array bounds                                           |

61: |     • data(i) will revert if i >= 33 (array bounds)                                                   |

154:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

155:         if (_finalized) revert AlreadyFinalized();

156:         if (paths.length > 10) revert MaxBatch();

157:         if (startIndex + paths.length > 33) revert IndexOutOfBounds();

172:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

173:         if (_finalized) revert AlreadyFinalized();

197:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

198:         if (_finalized) revert AlreadyFinalized();

222:         if (quadrant == 0) return _symQ1[idx];

223:         if (quadrant == 1) return _symQ2[idx];

224:         if (quadrant == 2) return _symQ3[idx];

```

```solidity
File: StakedDegenerusStonk.sol

250:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

311:         if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();

312:         if (to == address(0)) revert ZeroAddress();

314:         if (amount > bal) revert Insufficient();

353:         if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

377:         if (amount == 0) return 0;

378:         if (to == address(0)) revert ZeroAddress();

381:         if (available == 0) return 0;

402:         if (amount == 0) return 0;

406:         if (available == 0) return 0;

422:         if (bal == 0) return;

448:         if (game.rngLocked()) revert BurnsBlockedDuringRng();

467:         if (game.rngLocked()) revert BurnsBlockedDuringRng();

483:         if (amount == 0 || amount > bal) revert Insufficient();

509:             if (stethOut > stethBal) revert Insufficient();

513:             if (!steth.transfer(beneficiary, stethOut)) revert TransferFailed();

518:             if (!success) revert TransferFailed();

541:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

544:         if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0;

576:         if (claim.periodIndex == 0) revert NoClaim();

579:         if (period.roll == 0) revert NotResolved();

655:         if (amount == 0 || amount > supply) return (0, 0, 0);

709:         if (amount == 0 || amount > bal) revert Insufficient();

718:         if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();

756:         if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

773:         if (amount == 0) return;

784:             if (!success) revert TransferFailed();

790:                 if (!success) revert TransferFailed();

792:             if (!steth.transfer(player, stethOut)) revert TransferFailed();

802:             if (!coin.transfer(player, payBal)) revert TransferFailed();

806:             if (!coin.transfer(player, remaining)) revert TransferFailed();

814:         if (stored <= 1) return 0;

830:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: WrappedWrappedXRP.sol

229:             if (allowed < amount) revert InsufficientAllowance();

242:         if (from == address(0) || to == address(0)) revert ZeroAddress();

243:         if (balanceOf[from] < amount) revert InsufficientBalance();

255:         if (to == address(0)) revert ZeroAddress();

267:         if (from == address(0)) revert ZeroAddress();

268:         if (balanceOf[from] < amount) revert InsufficientBalance();

291:         if (amount == 0) revert ZeroAmount();

294:         if (wXRPReserves < amount) revert InsufficientReserves();

315:         if (amount == 0) revert ZeroAmount();

343:         if (

350:         if (amount == 0) revert ZeroAmount();

364:         if (msg.sender != MINTER_VAULT) revert OnlyVault();

365:         if (to == address(0)) revert ZeroAddress();

366:         if (amount == 0) return;

369:         if (amount > allowanceVault) revert InsufficientVaultAllowance();

385:         if (msg.sender != MINTER_GAME) revert OnlyMinter();

386:         if (amount == 0) return;

```

```solidity
File: libraries/BitPackingLib.sol

42:     uint256 internal constant LAST_LEVEL_SHIFT = 0;

45:     uint256 internal constant LEVEL_COUNT_SHIFT = 24;

48:     uint256 internal constant LEVEL_STREAK_SHIFT = 48;

51:     uint256 internal constant DAY_SHIFT = 72;

54:     uint256 internal constant LEVEL_UNITS_LEVEL_SHIFT = 104;

57:     uint256 internal constant FROZEN_UNTIL_LEVEL_SHIFT = 128;

60:     uint256 internal constant WHALE_BUNDLE_TYPE_SHIFT = 152;

63:     uint256 internal constant LEVEL_UNITS_SHIFT = 228;

81:         uint256 shift,

85:         return (data & ~(mask << shift)) | ((value & mask) << shift);

```

```solidity
File: libraries/JackpotBucketLib.sol

64:         if (ethPool < JACKPOT_SCALE_MIN_WEI) return counts;

84:                     if (scaled < baseCount) scaled = baseCount;

85:                     if (scaled > type(uint16).max) scaled = type(uint16).max;

104:         if (ethPool == 0) return bucketCounts;

145:         if (total <= maxTotal) return capped;

155:                 if (scaled == 0) scaled = 1;

```

```solidity
File: libraries/PriceLookupLib.sol

23:         if (targetLevel < 5) return 0.01 ether;

24:         if (targetLevel < 10) return 0.02 ether;

27:         if (targetLevel < 30) return 0.04 ether;

28:         if (targetLevel < 60) return 0.08 ether;

29:         if (targetLevel < 90) return 0.12 ether;

30:         if (targetLevel < 100) return 0.16 ether;

```

### <a name="NC-8"></a>[NC-8] Default Visibility for constants
Some constants are using the default visibility. For readability, consider explicitly declaring them as `internal`.

*Instances (4)*:
```solidity
File: BurnieCoin.sol

235:       |  CONSTANT REFERENCES:                                                |

```

```solidity
File: DegenerusGame.sol

1015:       |  context, with access to all storage. Modules are constant addresses.                                          |

```

```solidity
File: DegenerusJackpots.sol

87:       |                            CONSTANT STATE                            |

```

```solidity
File: DegenerusVault.sol

127: |  • All wiring is constant after construction                                                           |

```

### <a name="NC-9"></a>[NC-9] Event is never emitted
The following are defined but never emitted. They can be removed to make the code cleaner.

*Instances (2)*:
```solidity
File: DegenerusDeityPass.sol

48:     event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

49:     event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

```

### <a name="NC-10"></a>[NC-10] Event missing indexed field
Index event fields make the field more quickly accessible [to off-chain tools](https://ethereum.stackexchange.com/questions/40396/can-somebody-please-explain-the-concept-of-event-indexing) that parse events. This is especially useful when it comes to filtering based on an address. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Where applicable, each `event` should use three `indexed` fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three applicable fields, all of the applicable fields should be indexed.

*Instances (4)*:
```solidity
File: DegenerusDeityPass.sol

52:     event RenderColorsUpdated(string outlineColor, string backgroundColor, string nonCryptoSymbolColor);

```

```solidity
File: DegenerusGame.sol

122:     event LootboxRngThresholdUpdated(uint256 previous, uint256 current);

```

```solidity
File: DegenerusStonk.sol

244:     event YearSweep(uint256 ethToGnrus, uint256 stethToGnrus, uint256 ethToVault, uint256 stethToVault);

```

```solidity
File: GNRUS.sol

114:     event GameOverFinalized(uint256 gnrusBurned, uint256 ethClaimed, uint256 stethClaimed);

```

### <a name="NC-11"></a>[NC-11] Events that mark critical parameter changes should contain both the old and the new value
This should especially be done if the new value is not required to be different from the old value

*Instances (7)*:
```solidity
File: DegenerusAdmin.sol

357:     function setLinkEthPriceFeed(address feed) external onlyOwner {
             address current = linkEthPriceFeed;
             if (_feedHealthy(current)) revert FeedHealthy();
             if (
                 feed != address(0) &&
                 IAggregatorV3(feed).decimals() != LINK_ETH_FEED_DECIMALS
             ) {
                 revert InvalidFeedDecimals();
             }
             linkEthPriceFeed = feed;
             emit LinkEthFeedUpdated(feed);

```

```solidity
File: DegenerusDeityPass.sol

97:     function setRenderer(address newRenderer) external onlyOwner {
            address prev = renderer;
            renderer = newRenderer;
            emit RendererUpdated(prev, newRenderer);

107:     function setRenderColors(
             string calldata outlineColor,
             string calldata backgroundColor,
             string calldata nonCryptoSymbolColor
         ) external onlyOwner {
             if (!_isHexColor(outlineColor) || !_isHexColor(backgroundColor) || !_isHexColor(nonCryptoSymbolColor)) {
                 revert InvalidColor();
             }
             _outlineColor = outlineColor;
             _backgroundColor = backgroundColor;
             _nonCryptoSymbolColor = nonCryptoSymbolColor;
             emit RenderColorsUpdated(outlineColor, backgroundColor, nonCryptoSymbolColor);

```

```solidity
File: DegenerusGame.sol

468:     function setOperatorApproval(address operator, bool approved) external {
             if (operator == address(0)) revert E();
             operatorApprovals[msg.sender][operator] = approved;
             emit OperatorApproval(msg.sender, operator, approved);

512:     function setLootboxRngThreshold(uint256 newThreshold) external {
             if (msg.sender != ContractAddresses.ADMIN) revert E();
             if (newThreshold == 0) revert E();
             uint256 prev = lootboxRngThreshold;
             if (newThreshold == prev) {
                 emit LootboxRngThresholdUpdated(prev, newThreshold);
                 return;
             }
             lootboxRngThreshold = newThreshold;
             emit LootboxRngThresholdUpdated(prev, newThreshold);
         }

512:     function setLootboxRngThreshold(uint256 newThreshold) external {
             if (msg.sender != ContractAddresses.ADMIN) revert E();
             if (newThreshold == 0) revert E();
             uint256 prev = lootboxRngThreshold;
             if (newThreshold == prev) {
                 emit LootboxRngThresholdUpdated(prev, newThreshold);
                 return;

1466:         player = _resolvePlayer(player);
              if (rngLockedFlag) revert RngLocked();
              bool disabled = !enabled;
              if (decimatorAutoRebuyDisabled[player] != disabled) {
                  decimatorAutoRebuyDisabled[player] = disabled;
              }
              emit DecimatorAutoRebuyToggled(player, enabled);
          }
      
          /// @notice Set the auto-rebuy take profit (amount reserved for manual claim).

```

### <a name="NC-12"></a>[NC-12] Function ordering does not follow the Solidity style guide
According to the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.17/style-guide.html#order-of-functions), functions should be laid out in the following order :`constructor()`, `receive()`, `fallback()`, `external`, `public`, `internal`, `private`, but the cases below do not follow this pattern

*Instances (11)*:
```solidity
File: BurnieCoin.sol

1: 
   Current order:
   external previewClaimCoinflips
   external claimCoinflipsFromBurnie
   external consumeCoinflipsForBurn
   external coinflipAmount
   external coinflipAutoRebuyInfo
   external creditFlip
   external creditFlipBatch
   external claimableCoin
   external balanceOfWithClaimable
   external previewClaimCoinflips
   external coinflipAutoRebuyInfo
   external totalSupply
   external supplyIncUncirculated
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   private _toUint128
   internal _transfer
   internal _mint
   internal _burn
   external burnForCoinflip
   external mintForCoinflip
   external mintForGame
   external creditCoin
   external creditFlip
   external creditFlipBatch
   external creditLinkReward
   private _claimCoinflipShortfall
   private _consumeCoinflipShortfall
   external vaultEscrow
   external vaultMintTo
   external affiliateQuestReward
   external rollDailyQuest
   external notifyQuestMint
   external notifyQuestLootBox
   external notifyQuestDegenerette
   external burnCoin
   external decimatorBurn
   external terminalDecimatorBurn
   external coinflipAmount
   private _adjustDecimatorBucket
   private _decimatorBurnMultiplier
   private _questApplyReward
   
   Suggested order:
   external previewClaimCoinflips
   external claimCoinflipsFromBurnie
   external consumeCoinflipsForBurn
   external coinflipAmount
   external coinflipAutoRebuyInfo
   external creditFlip
   external creditFlipBatch
   external claimableCoin
   external balanceOfWithClaimable
   external previewClaimCoinflips
   external coinflipAutoRebuyInfo
   external totalSupply
   external supplyIncUncirculated
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   external burnForCoinflip
   external mintForCoinflip
   external mintForGame
   external creditCoin
   external creditFlip
   external creditFlipBatch
   external creditLinkReward
   external vaultEscrow
   external vaultMintTo
   external affiliateQuestReward
   external rollDailyQuest
   external notifyQuestMint
   external notifyQuestLootBox
   external notifyQuestDegenerette
   external burnCoin
   external decimatorBurn
   external terminalDecimatorBurn
   external coinflipAmount
   internal _transfer
   internal _mint
   internal _burn
   private _toUint128
   private _claimCoinflipShortfall
   private _consumeCoinflipShortfall
   private _adjustDecimatorBucket
   private _decimatorBurnMultiplier
   private _questApplyReward

```

```solidity
File: BurnieCoinflip.sol

1: 
   Current order:
   external burnForCoinflip
   external mintForCoinflip
   external mintPrize
   external settleFlipModeChange
   external depositCoinflip
   private _depositCoinflip
   external claimCoinflips
   external claimCoinflipsFromBurnie
   external claimCoinflipsForRedemption
   external getCoinflipDayResult
   external consumeCoinflipsForBurn
   private _claimCoinflipsAmount
   internal _claimCoinflipsInternal
   private _addDailyFlip
   external setCoinflipAutoRebuy
   external setCoinflipAutoRebuyTakeProfit
   private _setCoinflipAutoRebuy
   private _setCoinflipAutoRebuyTakeProfit
   external processCoinflipPayouts
   external creditFlip
   external creditFlipBatch
   external previewClaimCoinflips
   external coinflipAmount
   external coinflipAutoRebuyInfo
   external coinflipTopLastDay
   internal _viewClaimableCoin
   private _coinflipLockedDuringTransition
   private _recyclingBonus
   private _afKingRecyclingBonus
   private _afKingDeityBonusHalfBpsWithLevel
   internal _targetFlipDay
   private _questApplyReward
   private _score96
   private _updateTopDayBettor
   private _bafBracketLevel
   private _resolvePlayer
   private _requireApproved
   
   Suggested order:
   external burnForCoinflip
   external mintForCoinflip
   external mintPrize
   external settleFlipModeChange
   external depositCoinflip
   external claimCoinflips
   external claimCoinflipsFromBurnie
   external claimCoinflipsForRedemption
   external getCoinflipDayResult
   external consumeCoinflipsForBurn
   external setCoinflipAutoRebuy
   external setCoinflipAutoRebuyTakeProfit
   external processCoinflipPayouts
   external creditFlip
   external creditFlipBatch
   external previewClaimCoinflips
   external coinflipAmount
   external coinflipAutoRebuyInfo
   external coinflipTopLastDay
   internal _claimCoinflipsInternal
   internal _viewClaimableCoin
   internal _targetFlipDay
   private _depositCoinflip
   private _claimCoinflipsAmount
   private _addDailyFlip
   private _setCoinflipAutoRebuy
   private _setCoinflipAutoRebuyTakeProfit
   private _coinflipLockedDuringTransition
   private _recyclingBonus
   private _afKingRecyclingBonus
   private _afKingDeityBonusHalfBpsWithLevel
   private _questApplyReward
   private _score96
   private _updateTopDayBettor
   private _bafBracketLevel
   private _resolvePlayer
   private _requireApproved

```

```solidity
File: DegenerusAdmin.sol

1: 
   Current order:
   external addConsumer
   external cancelSubscription
   external createSubscription
   external getSubscription
   external lastVrfProcessed
   external jackpotPhase
   external gameOver
   external updateVrfCoordinatorAndSub
   external wireVrf
   external adminSwapEthForStEth
   external adminStakeEthForStEth
   external setLootboxRngThreshold
   external purchaseInfo
   external balanceOf
   external transfer
   external transferAndCall
   external creditLinkReward
   external latestRoundData
   external decimals
   external isVaultOwner
   external totalSupply
   external balanceOf
   external setLinkEthPriceFeed
   external swapGameEthForStEth
   external stakeGameEthToStEth
   external setLootboxRngThreshold
   external propose
   external vote
   public circulatingSupply
   public threshold
   external canExecute
   internal _executeSwap
   internal _voidAllActive
   external shutdownVrf
   external onTokenTransfer
   external linkAmountToEth
   private _linkRewardMultiplier
   private _feedHealthy
   
   Suggested order:
   external addConsumer
   external cancelSubscription
   external createSubscription
   external getSubscription
   external lastVrfProcessed
   external jackpotPhase
   external gameOver
   external updateVrfCoordinatorAndSub
   external wireVrf
   external adminSwapEthForStEth
   external adminStakeEthForStEth
   external setLootboxRngThreshold
   external purchaseInfo
   external balanceOf
   external transfer
   external transferAndCall
   external creditLinkReward
   external latestRoundData
   external decimals
   external isVaultOwner
   external totalSupply
   external balanceOf
   external setLinkEthPriceFeed
   external swapGameEthForStEth
   external stakeGameEthToStEth
   external setLootboxRngThreshold
   external propose
   external vote
   external canExecute
   external shutdownVrf
   external onTokenTransfer
   external linkAmountToEth
   public circulatingSupply
   public threshold
   internal _executeSwap
   internal _voidAllActive
   private _linkRewardMultiplier
   private _feedHealthy

```

```solidity
File: DegenerusDeityPass.sol

1: 
   Current order:
   external data
   external symbol
   external render
   external name
   external symbol
   external owner
   external transferOwnership
   external setRenderer
   external setRenderColors
   external renderColors
   external tokenURI
   private _renderSvgInternal
   private _tryRenderExternal
   private _isHexColor
   private _symbolFitScale
   private _symbolTranslate
   private _mat6
   private _dec6
   private _dec6s
   private _pad6
   external supportsInterface
   external balanceOf
   external ownerOf
   external getApproved
   external isApprovedForAll
   external approve
   external setApprovalForAll
   external transferFrom
   external safeTransferFrom
   external safeTransferFrom
   external mint
   
   Suggested order:
   external data
   external symbol
   external render
   external name
   external symbol
   external owner
   external transferOwnership
   external setRenderer
   external setRenderColors
   external renderColors
   external tokenURI
   external supportsInterface
   external balanceOf
   external ownerOf
   external getApproved
   external isApprovedForAll
   external approve
   external setApprovalForAll
   external transferFrom
   external safeTransferFrom
   external safeTransferFrom
   external mint
   private _renderSvgInternal
   private _tryRenderExternal
   private _isHexColor
   private _symbolFitScale
   private _symbolTranslate
   private _mat6
   private _dec6
   private _dec6s
   private _pad6

```

```solidity
File: DegenerusGame.sol

1: 
   Current order:
   external playerQuestStates
   external advanceGame
   external wireVrf
   external recordMint
   external recordMintQuestStreak
   external payCoinflipBountyDgnrs
   external setOperatorApproval
   external isOperatorApproved
   private _requireApproved
   private _resolvePlayer
   external currentDayView
   external setLootboxRngThreshold
   external purchase
   private _purchaseFor
   external purchaseCoin
   external purchaseBurnieLootbox
   external purchaseWhaleBundle
   private _purchaseWhaleBundleFor
   external purchaseLazyPass
   private _purchaseLazyPassFor
   external purchaseDeityPass
   private _purchaseDeityPassFor
   external openLootBox
   external openBurnieLootBox
   private _openLootBoxFor
   private _openBurnieLootBoxFor
   external placeFullTicketBets
   external resolveDegeneretteBets
   external consumeCoinflipBoon
   external consumeDecimatorBoon
   external consumePurchaseBoost
   external deityBoonData
   external issueDeityBoon
   private _processMintPayment
   private _revertDelegate
   private _recordMintDataModule
   external recordDecBurn
   external runDecimatorJackpot
   external recordTerminalDecBurn
   external runTerminalDecimatorJackpot
   external terminalDecWindow
   external runTerminalJackpot
   external consumeDecClaim
   external claimDecimatorJackpot
   external decClaimable
   private _unpackDecWinningSubbucket
   external claimWinnings
   external claimWinningsStethFirst
   private _claimWinningsInternal
   external claimAffiliateDgnrs
   external setAutoRebuy
   external setDecimatorAutoRebuy
   external setAutoRebuyTakeProfit
   private _setAutoRebuy
   private _setAutoRebuyTakeProfit
   external autoRebuyEnabledFor
   external decimatorAutoRebuyEnabledFor
   external autoRebuyTakeProfitFor
   external setAfKingMode
   private _setAfKingMode
   private _hasAnyLazyPass
   external hasActiveLazyPass
   external afKingModeFor
   external afKingActivatedLevelFor
   external deactivateAfKingFromCoin
   external syncAfKingLazyPassFromCoin
   private _deactivateAfKing
   external claimWhalePass
   private _claimWhalePassFor
   external resolveRedemptionLootbox
   external adminSwapEthForStEth
   external adminStakeEthForStEth
   external updateVrfCoordinatorAndSub
   external requestLootboxRng
   external reverseFlip
   external rawFulfillRandomWords
   private _transferSteth
   private _payoutWithStethFallback
   private _payoutWithEthFallback
   external prizePoolTargetView
   external nextPrizePoolView
   external futurePrizePoolView
   external futurePrizePoolTotalView
   external ticketsOwedView
   external lootboxStatus
   external degeneretteBetInfo
   external lootboxPresaleActiveFlag
   external lootboxRngIndexView
   external lootboxRngWord
   external lootboxRngThresholdView
   external lootboxRngMinLinkBalanceView
   external currentPrizePoolView
   external rewardPoolView
   external claimablePoolView
   external isFinalSwept
   external gameOverTimestamp
   external yieldPoolView
   external yieldAccumulatorView
   external mintPrice
   external rngWordForDay
   external lastRngWord
   external rngLocked
   external isRngFulfilled
   private _threeDayRngGap
   external rngStalledForThreeDays
   external lastVrfProcessed
   external decWindow
   external decWindowOpenFlag
   external jackpotCompressionTier
   private _isGameoverImminent
   private _activeTicketLevel
   external jackpotPhase
   external purchaseInfo
   external ethMintLastLevel
   external ethMintLevelCount
   external ethMintStreakCount
   external ethMintStats
   external playerActivityScore
   internal _playerActivityScore
   private _mintCountBonusPoints
   external getWinnings
   external claimableWinningsOf
   external whalePassClaimAmount
   external deityPassCountFor
   external deityPassPurchasedCountFor
   external deityPassTotalIssuedCount
   external sampleTraitTickets
   external sampleTraitTicketsAtLevel
   external sampleFarFutureTickets
   external getTickets
   external getPlayerPurchases
   external getDailyHeroWager
   external getDailyHeroWinner
   external getPlayerDegeneretteWager
   external getTopDegenerette
   
   Suggested order:
   external playerQuestStates
   external advanceGame
   external wireVrf
   external recordMint
   external recordMintQuestStreak
   external payCoinflipBountyDgnrs
   external setOperatorApproval
   external isOperatorApproved
   external currentDayView
   external setLootboxRngThreshold
   external purchase
   external purchaseCoin
   external purchaseBurnieLootbox
   external purchaseWhaleBundle
   external purchaseLazyPass
   external purchaseDeityPass
   external openLootBox
   external openBurnieLootBox
   external placeFullTicketBets
   external resolveDegeneretteBets
   external consumeCoinflipBoon
   external consumeDecimatorBoon
   external consumePurchaseBoost
   external deityBoonData
   external issueDeityBoon
   external recordDecBurn
   external runDecimatorJackpot
   external recordTerminalDecBurn
   external runTerminalDecimatorJackpot
   external terminalDecWindow
   external runTerminalJackpot
   external consumeDecClaim
   external claimDecimatorJackpot
   external decClaimable
   external claimWinnings
   external claimWinningsStethFirst
   external claimAffiliateDgnrs
   external setAutoRebuy
   external setDecimatorAutoRebuy
   external setAutoRebuyTakeProfit
   external autoRebuyEnabledFor
   external decimatorAutoRebuyEnabledFor
   external autoRebuyTakeProfitFor
   external setAfKingMode
   external hasActiveLazyPass
   external afKingModeFor
   external afKingActivatedLevelFor
   external deactivateAfKingFromCoin
   external syncAfKingLazyPassFromCoin
   external claimWhalePass
   external resolveRedemptionLootbox
   external adminSwapEthForStEth
   external adminStakeEthForStEth
   external updateVrfCoordinatorAndSub
   external requestLootboxRng
   external reverseFlip
   external rawFulfillRandomWords
   external prizePoolTargetView
   external nextPrizePoolView
   external futurePrizePoolView
   external futurePrizePoolTotalView
   external ticketsOwedView
   external lootboxStatus
   external degeneretteBetInfo
   external lootboxPresaleActiveFlag
   external lootboxRngIndexView
   external lootboxRngWord
   external lootboxRngThresholdView
   external lootboxRngMinLinkBalanceView
   external currentPrizePoolView
   external rewardPoolView
   external claimablePoolView
   external isFinalSwept
   external gameOverTimestamp
   external yieldPoolView
   external yieldAccumulatorView
   external mintPrice
   external rngWordForDay
   external lastRngWord
   external rngLocked
   external isRngFulfilled
   external rngStalledForThreeDays
   external lastVrfProcessed
   external decWindow
   external decWindowOpenFlag
   external jackpotCompressionTier
   external jackpotPhase
   external purchaseInfo
   external ethMintLastLevel
   external ethMintLevelCount
   external ethMintStreakCount
   external ethMintStats
   external playerActivityScore
   external getWinnings
   external claimableWinningsOf
   external whalePassClaimAmount
   external deityPassCountFor
   external deityPassPurchasedCountFor
   external deityPassTotalIssuedCount
   external sampleTraitTickets
   external sampleTraitTicketsAtLevel
   external sampleFarFutureTickets
   external getTickets
   external getPlayerPurchases
   external getDailyHeroWager
   external getDailyHeroWinner
   external getPlayerDegeneretteWager
   external getTopDegenerette
   internal _playerActivityScore
   private _requireApproved
   private _resolvePlayer
   private _purchaseFor
   private _purchaseWhaleBundleFor
   private _purchaseLazyPassFor
   private _purchaseDeityPassFor
   private _openLootBoxFor
   private _openBurnieLootBoxFor
   private _processMintPayment
   private _revertDelegate
   private _recordMintDataModule
   private _unpackDecWinningSubbucket
   private _claimWinningsInternal
   private _setAutoRebuy
   private _setAutoRebuyTakeProfit
   private _setAfKingMode
   private _hasAnyLazyPass
   private _deactivateAfKing
   private _claimWhalePassFor
   private _transferSteth
   private _payoutWithStethFallback
   private _payoutWithEthFallback
   private _threeDayRngGap
   private _isGameoverImminent
   private _activeTicketLevel
   private _mintCountBonusPoints

```

```solidity
File: DegenerusJackpots.sol

1: 
   Current order:
   external coinflipTopLastDay
   external recordBafFlip
   external runBafJackpot
   private _creditOrRefund
   private _bafScore
   private _score96
   private _updateBafTop
   private _bafTop
   private _clearBafTop
   external getLastBafResolvedDay
   
   Suggested order:
   external coinflipTopLastDay
   external recordBafFlip
   external runBafJackpot
   external getLastBafResolvedDay
   private _creditOrRefund
   private _bafScore
   private _score96
   private _updateBafTop
   private _bafTop
   private _clearBafTop

```

```solidity
File: DegenerusQuests.sol

1: 
   Current order:
   external rollDailyQuest
   external awardQuestStreakBonus
   private _rollDailyQuest
   external handleMint
   external handleFlip
   external handleDecimator
   external handleAffiliate
   external handleLootBox
   external handleDegenerette
   external getActiveQuests
   private _materializeActiveQuestsForView
   external playerQuestStates
   external getPlayerQuestView
   private _questViewData
   private _questRequirements
   private _currentDayQuestOfType
   private _canRollDecimatorQuest
   private _clampedAdd128
   private _nextQuestVersion
   private _questHandleProgressSlot
   private _questSyncState
   private _questSyncProgress
   private _questProgressValid
   private _questProgressValidStorage
   private _questCompleted
   private _questTargetValue
   private _bonusQuestType
   private _questComplete
   private _questCompleteWithPair
   private _maybeCompleteOther
   private _questReady
   private _seedQuestType
   private _currentQuestDay
   
   Suggested order:
   external rollDailyQuest
   external awardQuestStreakBonus
   external handleMint
   external handleFlip
   external handleDecimator
   external handleAffiliate
   external handleLootBox
   external handleDegenerette
   external getActiveQuests
   external playerQuestStates
   external getPlayerQuestView
   private _rollDailyQuest
   private _materializeActiveQuestsForView
   private _questViewData
   private _questRequirements
   private _currentDayQuestOfType
   private _canRollDecimatorQuest
   private _clampedAdd128
   private _nextQuestVersion
   private _questHandleProgressSlot
   private _questSyncState
   private _questSyncProgress
   private _questProgressValid
   private _questProgressValidStorage
   private _questCompleted
   private _questTargetValue
   private _bonusQuestType
   private _questComplete
   private _questCompleteWithPair
   private _maybeCompleteOther
   private _questReady
   private _seedQuestType
   private _currentQuestDay

```

```solidity
File: DegenerusStonk.sol

1: 
   Current order:
   external burn
   external balanceOf
   external wrapperTransferTo
   external previewBurn
   external transfer
   external lastVrfProcessed
   external gameOver
   external gameOverTimestamp
   external transfer
   external transferFrom
   external approve
   external unwrapTo
   external burn
   external previewBurn
   private _transfer
   private _burn
   external yearSweep
   external burnForSdgnrs
   
   Suggested order:
   external burn
   external balanceOf
   external wrapperTransferTo
   external previewBurn
   external transfer
   external lastVrfProcessed
   external gameOver
   external gameOverTimestamp
   external transfer
   external transferFrom
   external approve
   external unwrapTo
   external burn
   external previewBurn
   external yearSweep
   external burnForSdgnrs
   private _transfer
   private _burn

```

```solidity
File: DegenerusVault.sol

1: 
   Current order:
   external advanceGame
   external purchase
   external openLootBox
   external claimWinnings
   external claimWinningsStethFirst
   external claimWhalePass
   external claimDecimatorJackpot
   external setDecimatorAutoRebuy
   external purchaseBurnieLootbox
   external purchaseDeityPass
   external placeFullTicketBets
   external resolveDegeneretteBets
   external setAutoRebuy
   external setAutoRebuyTakeProfit
   external setAfKingMode
   external setOperatorApproval
   external claimableWinningsOf
   external purchaseCoin
   external depositCoinflip
   external claimCoinflips
   external previewClaimCoinflips
   external setCoinflipAutoRebuy
   external setCoinflipAutoRebuyTakeProfit
   external decimatorBurn
   external vaultMintTo
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   external vaultMint
   external vaultBurn
   private _transfer
   private _requireApproved
   private _isVaultOwner
   external isVaultOwner
   external deposit
   external gameAdvance
   external gamePurchase
   external gamePurchaseTicketsBurnie
   external gamePurchaseBurnieLootbox
   external gameOpenLootBox
   external gamePurchaseDeityPassFromBoon
   external gameClaimWinnings
   external gameClaimWhalePass
   external gameDegeneretteBetEth
   external gameDegeneretteBetBurnie
   external gameDegeneretteBetWwxrp
   external gameResolveDegeneretteBets
   external gameSetAutoRebuy
   external gameSetAutoRebuyTakeProfit
   external gameSetDecimatorAutoRebuy
   external gameSetAfKingMode
   external gameSetOperatorApproval
   external coinDepositCoinflip
   external coinClaimCoinflips
   external coinDecimatorBurn
   external coinSetAutoRebuy
   external coinSetAutoRebuyTakeProfit
   external wwxrpMint
   external jackpotsClaimDecimator
   external burnCoin
   private _burnCoinFor
   external burnEth
   private _burnEthFor
   external previewBurnForCoinOut
   external previewBurnForEthOut
   external previewCoin
   external previewEth
   private _combinedValue
   private _syncEthReserves
   private _syncCoinReserves
   private _coinReservesView
   private _ethReservesView
   private _stethBalance
   private _payEth
   private _paySteth
   private _pullSteth
   
   Suggested order:
   external advanceGame
   external purchase
   external openLootBox
   external claimWinnings
   external claimWinningsStethFirst
   external claimWhalePass
   external claimDecimatorJackpot
   external setDecimatorAutoRebuy
   external purchaseBurnieLootbox
   external purchaseDeityPass
   external placeFullTicketBets
   external resolveDegeneretteBets
   external setAutoRebuy
   external setAutoRebuyTakeProfit
   external setAfKingMode
   external setOperatorApproval
   external claimableWinningsOf
   external purchaseCoin
   external depositCoinflip
   external claimCoinflips
   external previewClaimCoinflips
   external setCoinflipAutoRebuy
   external setCoinflipAutoRebuyTakeProfit
   external decimatorBurn
   external vaultMintTo
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   external vaultMint
   external vaultBurn
   external isVaultOwner
   external deposit
   external gameAdvance
   external gamePurchase
   external gamePurchaseTicketsBurnie
   external gamePurchaseBurnieLootbox
   external gameOpenLootBox
   external gamePurchaseDeityPassFromBoon
   external gameClaimWinnings
   external gameClaimWhalePass
   external gameDegeneretteBetEth
   external gameDegeneretteBetBurnie
   external gameDegeneretteBetWwxrp
   external gameResolveDegeneretteBets
   external gameSetAutoRebuy
   external gameSetAutoRebuyTakeProfit
   external gameSetDecimatorAutoRebuy
   external gameSetAfKingMode
   external gameSetOperatorApproval
   external coinDepositCoinflip
   external coinClaimCoinflips
   external coinDecimatorBurn
   external coinSetAutoRebuy
   external coinSetAutoRebuyTakeProfit
   external wwxrpMint
   external jackpotsClaimDecimator
   external burnCoin
   external burnEth
   external previewBurnForCoinOut
   external previewBurnForEthOut
   external previewCoin
   external previewEth
   private _transfer
   private _requireApproved
   private _isVaultOwner
   private _burnCoinFor
   private _burnEthFor
   private _combinedValue
   private _syncEthReserves
   private _syncCoinReserves
   private _coinReservesView
   private _ethReservesView
   private _stethBalance
   private _payEth
   private _paySteth
   private _pullSteth

```

```solidity
File: StakedDegenerusStonk.sol

1: 
   Current order:
   external advanceGame
   external setAfKingMode
   external claimWinnings
   external claimWhalePass
   external claimableWinningsOf
   external rngLocked
   external gameOver
   external currentDayView
   external rngWordForDay
   external playerActivityScore
   external resolveRedemptionLootbox
   external balanceOf
   external transfer
   external claimCoinflips
   external previewClaimCoinflips
   external claimCoinflipsForRedemption
   external getCoinflipDayResult
   external burnForSdgnrs
   external wrapperTransferTo
   external gameAdvance
   external gameClaimWhalePass
   external depositSteth
   external poolBalance
   external transferFromPool
   external transferBetweenPools
   external burnAtGameOver
   external burn
   external burnWrapped
   private _deterministicBurn
   private _deterministicBurnFrom
   external hasPendingRedemptions
   external resolveRedemptionPeriod
   external claimRedemption
   external previewBurn
   external burnieReserve
   private _submitGamblingClaim
   private _submitGamblingClaimFrom
   private _payEth
   private _payBurnie
   private _claimableWinnings
   private _poolIndex
   private _mint
   
   Suggested order:
   external advanceGame
   external setAfKingMode
   external claimWinnings
   external claimWhalePass
   external claimableWinningsOf
   external rngLocked
   external gameOver
   external currentDayView
   external rngWordForDay
   external playerActivityScore
   external resolveRedemptionLootbox
   external balanceOf
   external transfer
   external claimCoinflips
   external previewClaimCoinflips
   external claimCoinflipsForRedemption
   external getCoinflipDayResult
   external burnForSdgnrs
   external wrapperTransferTo
   external gameAdvance
   external gameClaimWhalePass
   external depositSteth
   external poolBalance
   external transferFromPool
   external transferBetweenPools
   external burnAtGameOver
   external burn
   external burnWrapped
   external hasPendingRedemptions
   external resolveRedemptionPeriod
   external claimRedemption
   external previewBurn
   external burnieReserve
   private _deterministicBurn
   private _deterministicBurnFrom
   private _submitGamblingClaim
   private _submitGamblingClaimFrom
   private _payEth
   private _payBurnie
   private _claimableWinnings
   private _poolIndex
   private _mint

```

```solidity
File: WrappedWrappedXRP.sol

1: 
   Current order:
   external transfer
   external transferFrom
   external balanceOf
   external supplyIncUncirculated
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   internal _transfer
   internal _mint
   internal _burn
   external unwrap
   external donate
   external mintPrize
   external vaultMintTo
   external burnForGame
   
   Suggested order:
   external transfer
   external transferFrom
   external balanceOf
   external supplyIncUncirculated
   external vaultMintAllowance
   external approve
   external transfer
   external transferFrom
   external unwrap
   external donate
   external mintPrize
   external vaultMintTo
   external burnForGame
   internal _transfer
   internal _mint
   internal _burn

```

### <a name="NC-13"></a>[NC-13] Functions should not be longer than 50 lines
Overly complex code can make understanding functionality more difficult, try to further modularize your code to ensure readability 

*Instances (377)*:
```solidity
File: BurnieCoin.sol

30:     function previewClaimCoinflips(address player) external view returns (uint256 mintable);

31:     function claimCoinflipsFromBurnie(address player, uint256 amount) external returns (uint256 claimed);

32:     function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);

33:     function coinflipAmount(address player) external view returns (uint256);

34:     function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint48 startDay);

35:     function creditFlip(address player, uint256 amount) external;

36:     function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;

278:       |  Read-only functions for UIs and external contracts to query state.  |

284:     function claimableCoin() external view returns (uint256) {

295:     function balanceOfWithClaimable(address player) external view returns (uint256 spendable) {

309:     function previewClaimCoinflips(address player) external view returns (uint256 mintable) {

325:     function totalSupply() external view returns (uint256) {

332:     function supplyIncUncirculated() external view returns (uint256) {

339:     function vaultMintAllowance() external view returns (uint256) {

394:     function approve(address spender, uint256 amount) external returns (bool) {

408:     function transfer(address to, uint256 amount) external returns (bool) {

443:     function _toUint128(uint256 value) private pure returns (uint128) {

453:     function _transfer(address from, address to, uint256 amount) internal {

479:     function _mint(address to, uint256 amount) internal {

499:     function _burn(address from, uint256 amount) internal {

520:       |  Permission functions for BurnieCoinflip contract to burn/mint      |

528:     function burnForCoinflip(address from, uint256 amount) external {

537:     function mintForCoinflip(address to, uint256 amount) external {

546:     function mintForGame(address to, uint256 amount) external {

556:     function creditCoin(address player, uint256 amount) external onlyFlipCreditors {

566:     function creditFlip(address player, uint256 amount) external onlyFlipCreditors {

574:     function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors {

584:     function creditLinkReward(address player, uint256 amount) external onlyAdmin {

590:     function _claimCoinflipShortfall(address player, uint256 amount) private {

603:     function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {

705:     function vaultMintTo(address to, uint256 amount) external onlyVault {

814:     function notifyQuestLootBox(address player, uint256 amountWei) external {

841:     function notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth) external {

890:     function decimatorBurn(address player, uint256 amount) external {

981:     function terminalDecimatorBurn(address player, uint256 amount) external {

1012:       |  Read-only functions for querying coinflip stake amounts.            |

1018:     function coinflipAmount(address player) external view returns (uint256) {

1047:     function _decimatorBurnMultiplier(uint256 bonusBps) private pure returns (uint256 decMultBps) {

```

```solidity
File: BurnieCoinflip.sol

28:     function burnForCoinflip(address from, uint256 amount) external;

29:     function mintForCoinflip(address to, uint256 amount) external;

33:     function mintPrize(address to, uint256 amount) external;

215:     function settleFlipModeChange(address player) external onlyDegenerusGameContract {

225:     function depositCoinflip(address player, uint256 amount) external {

357:     function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win) {

899:     function previewClaimCoinflips(address player) external view returns (uint256 mintable) {

906:     function coinflipAmount(address player) external view returns (uint256) {

1060:     function _targetFlipDay() internal view returns (uint48) {

1083:     function _score96(uint256 s) private pure returns (uint96) {

1106:     function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {

1113:     function _resolvePlayer(address player) private view returns (address resolved) {

1124:     function _requireApproved(address player) private view {

```

```solidity
File: DegenerusAdmin.sol

49:     function addConsumer(uint256 subId, address consumer) external;

50:     function cancelSubscription(uint256 subId, address to) external;

51:     function createSubscription() external returns (uint256 subId);

68:     function lastVrfProcessed() external view returns (uint48);

69:     function jackpotPhase() external view returns (bool);

85:     function adminStakeEthForStEth(uint256 amount) external;

86:     function setLootboxRngThreshold(uint256 newThreshold) external;

101:     function balanceOf(address account) external view returns (uint256);

115:     function creditLinkReward(address player, uint256 amount) external;

130:     function decimals() external view returns (uint8);

135:     function isVaultOwner(address account) external view returns (bool);

140:     function totalSupply() external view returns (uint256);

141:     function balanceOf(address account) external view returns (uint256);

357:     function setLinkEthPriceFeed(address feed) external onlyOwner {

374:     function swapGameEthForStEth() external payable onlyOwner {

379:     function stakeGameEthToStEth(uint256 amount) external onlyOwner {

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {

452:     function vote(uint256 proposalId, bool approve) external {

520:     function circulatingSupply() public view returns (uint256) {

530:     function threshold(uint256 proposalId) public view returns (uint16) {

544:     function canExecute(uint256 proposalId) external view returns (bool) {

566:     function _executeSwap(uint256 proposalId) internal {

631:     function _voidAllActive(uint256 exceptId) internal {

777:     function _feedHealthy(address feed) private view returns (bool) {

```

```solidity
File: DegenerusAffiliate.sol

36:     function creditCoin(address player, uint256 amount) external;

41:     function creditFlip(address player, uint256 amount) external;

46:     function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;

52:     function affiliateQuestReward(address player, uint256 amount) external returns (uint256);

308:     function createAffiliateCode(bytes32 code_, uint8 kickbackPct) external {

343:     function getReferrer(address player) external view returns (address) {

349:     function defaultCode(address addr) external pure returns (bytes32) {

655:     function affiliateTop(uint24 lvl) external view returns (address player, uint96 score) {

667:     function affiliateScore(uint24 lvl, address player) external view returns (uint256 score) {

678:     function totalAffiliateScore(uint24 lvl) external view returns (uint256 total) {

691:     function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {

714:     function _vaultReferralMutable(bytes32 code) private view returns (bool) {

720:     function _setReferralCode(address player, bytes32 code) private {

734:     function _resolveCodeOwner(bytes32 code) private view returns (address) {

750:     function _referrerAddress(address player) private view returns (address) {

782:     function _bootstrapReferral(address player, bytes32 code_) private {

809:     function _score96(uint256 s) private pure returns (uint96) {

825:     function _updateTopAffiliate(address player, uint256 total, uint24 lvl) private {

836:     function _applyLootboxTaper(uint256 amt, uint16 score) private pure returns (uint256) {

```

```solidity
File: DegenerusDeityPass.sol

9:     function data(uint256 i) external view returns (string memory);

10:     function symbol(uint256 quadrant, uint8 idx) external view returns (string memory);

85:     function name() external pure returns (string memory) { return "Degenerus Deity Pass"; }

86:     function symbol() external pure returns (string memory) { return "DEITY"; }

87:     function owner() external view returns (address) { return _contractOwner; }

89:     function transferOwnership(address newOwner) external onlyOwner {

97:     function setRenderer(address newRenderer) external onlyOwner {

122:     function renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor) {

129:     function tokenURI(uint256 tokenId) external view returns (string memory) {

243:     function _isHexColor(string memory c) private pure returns (bool) {

256:     function _symbolFitScale(uint8 quadrant, uint8 symbolIdx) private pure returns (uint32) {

297:     function _dec6(uint256 x) private pure returns (string memory) {

303:     function _dec6s(int256 x) private pure returns (string memory) {

310:     function _pad6(uint32 f) private pure returns (string memory) {

323:     function supportsInterface(bytes4 id) external pure returns (bool) {

333:     function balanceOf(address account) external view returns (uint256) {

338:     function ownerOf(uint256 tokenId) external view returns (address ownerAddr) {

343:     function getApproved(uint256 tokenId) external view returns (address) {

348:     function isApprovedForAll(address, address) external pure returns (bool) {

356:     function approve(address, uint256) external pure {

360:     function setApprovalForAll(address, bool) external pure {

364:     function transferFrom(address, address, uint256) external pure {

368:     function safeTransferFrom(address, address, uint256) external pure {

372:     function safeTransferFrom(address, address, uint256, bytes calldata) external pure {

381:     function mint(address to, uint256 tokenId) external {

```

```solidity
File: DegenerusGame.sol

265:       |  The heart of the game. This function progresses the state machine                     |

320:       |                    ADMIN VRF FUNCTIONS                                                 |

322:       |  One-time VRF setup function called by ADMIN during deployment phase.                  |

353:       |  Functions called by the game contract to record mints and process         |

424:     function recordMintQuestStreak(address player) external {

468:     function setOperatorApproval(address operator, bool approved) external {

485:     function _requireApproved(address player) private view {

504:     function currentDayView() external view returns (uint48) {

512:     function setLootboxRngThreshold(uint256 newThreshold) external {

640:     function _purchaseWhaleBundleFor(address buyer, uint256 quantity) private {

657:     function purchaseLazyPass(address buyer) external payable {

662:     function _purchaseLazyPassFor(address buyer) private {

677:     function purchaseDeityPass(address buyer, uint8 symbolId) external payable {

682:     function _purchaseDeityPassFor(address buyer, uint8 symbolId) private {

698:     function openLootBox(address player, uint48 lootboxIndex) external {

706:     function openBurnieLootBox(address player, uint48 lootboxIndex) external {

711:     function _openLootBoxFor(address player, uint48 lootboxIndex) private {

1000:       |  Internal functions that delegatecall into specialized modules.                                                |

1021:     function _revertDelegate(bytes memory reason) private pure {

1164:     function terminalDecWindow() external view returns (bool open, uint24 lvl) {

1223:     function claimDecimatorJackpot(uint24 lvl) external {

1357:     function _claimWinningsInternal(address player, bool stethFirst) private {

1384:     function claimAffiliateDgnrs(address player) external {

1456:     function setAutoRebuy(address player, bool enabled) external {

1465:     function setDecimatorAutoRebuy(address player, bool enabled) external {

1487:     function _setAutoRebuy(address player, bool enabled) private {

1603:     function _hasAnyLazyPass(address player) private view returns (bool) {

1616:     function hasActiveLazyPass(address player) external view returns (bool) {

1628:     function afKingModeFor(address player) external view returns (bool active) {

1645:     function deactivateAfKingFromCoin(address player) external {

1674:     function _deactivateAfKing(address player) private {

1696:     function claimWhalePass(address player) external {

1701:     function _claimWhalePassFor(address player) private {

1778:       |                    JACKPOT PAYOUT FUNCTIONS                                                   |

1780:       |  Functions for distributing jackpot winnings. Most jackpot logic                              |

1792:       |  Admin-only functions for managing ETH/stETH liquidity.              |

1829:     function adminStakeEthForStEth(uint256 amount) external {

1952:       |  Internal functions for ETH/stETH payouts.                           |

1956:     function _transferSteth(address to, uint256 amount) private {

1971:     function _payoutWithStethFallback(address to, uint256 amount) private {

2004:     function _payoutWithEthFallback(address to, uint256 amount) private {

2023:       |  Lightweight view functions for UI/frontend consumption. These       |

2033:     function prizePoolTargetView() external view returns (uint256) {

2041:     function nextPrizePoolView() external view returns (uint256) {

2047:     function futurePrizePoolView() external view returns (uint256) {

2053:     function futurePrizePoolTotalView() external view returns (uint256) {

2095:     function lootboxPresaleActiveFlag() external view returns (bool active) {

2101:     function lootboxRngIndexView() external view returns (uint48 index) {

2136:     function currentPrizePoolView() external view returns (uint256) {

2142:     function rewardPoolView() external view returns (uint256) {

2148:     function claimablePoolView() external view returns (uint256) {

2154:     function isFinalSwept() external view returns (bool) {

2159:     function gameOverTimestamp() external view returns (uint48) {

2166:     function yieldPoolView() external view returns (uint256) {

2180:     function yieldAccumulatorView() external view returns (uint256) {

2187:     function mintPrice() external view returns (uint256) {

2195:     function rngWordForDay(uint48 day) external view returns (uint256) {

2202:     function lastRngWord() external view returns (uint256) {

2209:     function rngLocked() external view returns (bool) {

2215:     function isRngFulfilled() external view returns (bool) {

2223:     function _threeDayRngGap(uint48 day) private view returns (bool) {

2233:     function rngStalledForThreeDays() external view returns (bool) {

2239:     function lastVrfProcessed() external view returns (uint48) {

2256:     function decWindow() external view returns (bool on, uint24 lvl) {

2265:     function decWindowOpenFlag() external view returns (bool open) {

2270:     function jackpotCompressionTier() external view returns (uint8) {

2276:     function _isGameoverImminent() private view returns (bool) {

2292:     function _activeTicketLevel() private view returns (uint24) {

2297:     function jackpotPhase() external view returns (bool) {

2337:     function ethMintLastLevel(address player) external view returns (uint24) {

2351:     function ethMintLevelCount(address player) external view returns (uint24) {

2365:     function ethMintStreakCount(address player) external view returns (uint24) {

2532:     function getWinnings() external view returns (uint256) {

2563:     function deityPassCountFor(address player) external view returns (uint16) {

2578:     function deityPassTotalIssuedCount() external view returns (uint32 count) {

2585:       |  View function for sampling burn ticket holders from recent levels.  |

2711:       |  Read-only functions for querying trait state and game history.      |

2826:       |  Admin-only functions for testing and simulation purposes.           |

2827:       |  WARNING: These functions should NEVER be deployed to mainnet.       |

```

```solidity
File: DegenerusJackpots.sol

25:     function coinflipTopLastDay() external view returns (address player, uint96 score);

166:     function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin {

496:       |  Utility functions for bucket packing and scoring.                    |

533:     function _bafScore(address player, uint24 lvl) private view returns (uint256) {

541:     function _score96(uint256 s) private pure returns (uint96) {

555:     function _updateBafTop(uint24 lvl, address player, uint256 stake) private {

620:     function _bafTop(uint24 lvl, uint8 idx) private view returns (address player, uint96 score) {

647:     function getLastBafResolvedDay() external view returns (uint48) {

```

```solidity
File: DegenerusQuests.sol

331:     function awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay) external onlyGame {

801:     function getActiveQuests() external view returns (QuestInfo[2] memory quests) {

817:     function _materializeActiveQuestsForView() private view returns (DailyQuest[QUEST_SLOT_COUNT] memory local) {

861:     function getPlayerQuestView(address player) external view returns (PlayerQuestView memory viewData) {

941:     function _questRequirements(DailyQuest memory quest, uint8 slot) private view returns (QuestRequirements memory req) {

1002:     function _canRollDecimatorQuest() private view returns (bool) {

1024:     function _clampedAdd128(uint128 current, uint256 delta) private pure returns (uint128) {

1039:     function _nextQuestVersion() private returns (uint24 newVersion) {

1111:     function _questSyncState(PlayerQuestState storage state, address player, uint48 currentDay) private {

1593:     function _currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests) private pure returns (uint48) {

```

```solidity
File: DegenerusStonk.sol

8:     function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);

9:     function balanceOf(address account) external view returns (uint256);

10:     function wrapperTransferTo(address to, uint256 amount) external;

11:     function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);

15:     function transfer(address to, uint256 amount) external returns (bool);

20:     function lastVrfProcessed() external view returns (uint48);

22:     function gameOverTimestamp() external view returns (uint48);

113:     function transfer(address to, uint256 amount) external returns (bool) {

126:     function transferFrom(address from, address to, uint256 amount) external returns (bool) {

141:     function approve(address spender, uint256 amount) external returns (bool) {

153:     function unwrapTo(address recipient, uint256 amount) external {

172:     function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

202:     function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

210:     function _transfer(address from, address to, uint256 amount) private returns (bool) {

223:     function _burn(address from, uint256 amount) private {

295:     function burnForSdgnrs(address player, uint256 amount) external {

```

```solidity
File: DegenerusTraitUtils.sol

68:   |  1. PURE FUNCTIONS:                                                          |

113:     function weightedBucket(uint32 rnd) internal pure returns (uint8) {

143:     function traitFromWord(uint64 rnd) internal pure returns (uint8) {

172:     function packedTraitsFromSeed(uint256 rand) internal pure returns (uint32) {

```

```solidity
File: DegenerusVault.sol

19:     function openLootBox(address player, uint48 lootboxIndex) external;

23:     function claimDecimatorJackpot(uint24 lvl) external;

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

25:     function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;

26:     function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

35:     function resolveDegeneretteBets(address player, uint64[] calldata betIds) external;

36:     function setAutoRebuy(address player, bool enabled) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

44:     function setOperatorApproval(address operator, bool approved) external;

45:     function claimableWinningsOf(address player) external view returns (uint256);

55:     function depositCoinflip(address player, uint256 amount) external;

56:     function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

57:     function previewClaimCoinflips(address player) external view returns (uint256 mintable);

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

63:     function decimatorBurn(address player, uint256 amount) external;

68:     function vaultMintTo(address to, uint256 amount) external;

69:     function vaultMintAllowance() external view returns (uint256);

213:     function approve(address spender, uint256 amount) external returns (bool) {

225:     function transfer(address to, uint256 amount) external returns (bool) {

237:     function transferFrom(address from, address to, uint256 amount) external returns (bool) {

258:     function vaultMint(address to, uint256 amount) external onlyVault {

273:     function vaultBurn(address from, uint256 amount) external onlyVault {

290:     function _transfer(address from, address to, uint256 amount) private {

406:     function _requireApproved(address player) private view {

415:     function _isVaultOwner(address account) private view returns (bool) {

424:     function isVaultOwner(address account) external view returns (bool) {

454:     function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame {

510:     function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner {

519:     function gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner {

527:     function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner {

536:     function gamePurchaseDeityPassFromBoon(uint256 priceWei, uint8 symbolId) external payable onlyVaultOwner {

550:     function gameClaimWinnings() external onlyVaultOwner {

556:     function gameClaimWhalePass() external onlyVaultOwner {

636:     function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner {

643:     function gameSetAutoRebuy(bool enabled) external onlyVaultOwner {

650:     function gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {

657:     function gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner {

678:     function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner {

685:     function coinDepositCoinflip(uint256 amount) external onlyVaultOwner {

693:     function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {

700:     function coinDecimatorBurn(uint256 amount) external onlyVaultOwner {

708:     function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner {

715:     function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {

723:     function wwxrpMint(address to, uint256 amount) external onlyVaultOwner {

731:     function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner {

749:     function burnCoin(address player, uint256 amount) external returns (uint256 coinOut) {

762:     function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut) {

887:     function previewBurnForCoinOut(uint256 coinOut) external view returns (uint256 burnAmount) {

927:     function previewCoin(uint256 amount) external view returns (uint256 coinOut) {

939:     function previewEth(uint256 amount) external view returns (uint256 ethOut, uint256 stEthOut) {

959:     function _combinedValue(uint256 extraValue) private view returns (uint256 totalValue) {

971:     function _syncEthReserves() private view returns (uint256 ethBal, uint256 stBal, uint256 combined) {

980:     function _syncCoinReserves() private returns (uint256 synced) {

987:     function _coinReservesView() private view returns (uint256 mainReserve) {

1002:     function _ethReservesView() private view returns (uint256 mainReserve, uint256 ethBal) {

1024:     function _stethBalance() private view returns (uint256) {

1031:     function _payEth(address to, uint256 amount) private {

1039:     function _paySteth(address to, uint256 amount) private {

1046:     function _pullSteth(address from, uint256 amount) private {

```

```solidity
File: DeityBoonViewer.sol

5:     function deityBoonData(address deity) external view returns (

```

```solidity
File: GNRUS.sol

9:     function totalSupply() external view returns (uint256);

10:     function balanceOf(address account) external view returns (uint256);

16:     function claimableWinningsOf(address player) external view returns (uint256);

22:     function isVaultOwner(address account) external view returns (bool);

255:     function transfer(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

258:     function transferFrom(address, address, uint256) external pure returns (bool) { revert TransferDisabled(); }

261:     function approve(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

356:     function propose(address recipient) external returns (uint48 proposalId) {

407:     function vote(uint48 proposalId, bool approveVote) external {

444:     function pickCharity(uint24 level) external onlyGame {

514:     function getProposal(uint48 proposalId) external view returns (

522:     function getLevelProposals(uint24 level) external view returns (uint48 start, uint8 count) {

531:     function _mint(address to, uint256 amount) private {

```

```solidity
File: Icons32Data.sol

41: |  2. Batch initialization via setter functions allows data population within gas limits.              |

43: |  4. View functions allow efficient reading by renderers without state changes.                       |

56: |     • Only ContractAddresses.CREATOR can call setter functions                                        |

57: |     • View functions are publicly accessible                                                          |

70: |     • View functions are free for off-chain calls                                                     |

153:     function setPaths(uint256 startIndex, string[] calldata paths) external {

171:     function setSymbols(uint256 quadrant, string[8] memory symbols) external {

211:     function data(uint256 i) external view returns (string memory) {

221:     function symbol(uint256 quadrant, uint8 idx) external view returns (string memory) {

```

```solidity
File: StakedDegenerusStonk.sol

19:     function claimableWinningsOf(address player) external view returns (uint256);

20:     function rngLocked() external view returns (bool);

22:     function currentDayView() external view returns (uint48);

23:     function rngWordForDay(uint48 day) external view returns (uint256);

24:     function playerActivityScore(address player) external view returns (uint256);

25:     function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;

30:     function balanceOf(address account) external view returns (uint256);

31:     function transfer(address to, uint256 amount) external returns (bool);

35:     function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

36:     function previewClaimCoinflips(address player) external view returns (uint256 mintable);

37:     function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);

38:     function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win);

42:     function burnForSdgnrs(address player, uint256 amount) external;

310:     function wrapperTransferTo(address to, uint256 amount) external {

352:     function depositSteth(uint256 amount) external onlyGame {

364:     function poolBalance(Pool pool) external view returns (uint256) {

376:     function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {

401:     function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {

443:     function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

461:     function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

473:     function _deterministicBurn(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {

481:     function _deterministicBurnFrom(address beneficiary, address burnFrom, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {

531:     function hasPendingRedemptions() external view returns (bool) {

540:     function resolveRedemptionPeriod(uint16 roll, uint48 flipDay) external returns (uint256 burnieToCredit) {

653:     function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

688:     function burnieReserve() external view returns (uint256) {

699:     function _submitGamblingClaim(address player, uint256 amount) private {

707:     function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {

772:     function _payEth(address player, uint256 amount) private {

797:     function _payBurnie(address player, uint256 amount) private {

812:     function _claimableWinnings() private view returns (uint256 claimable) {

821:     function _poolIndex(Pool pool) private pure returns (uint8) {

829:     function _mint(address to, uint256 amount) private {

```

```solidity
File: WrappedWrappedXRP.sol

31:     function transfer(address to, uint256 amount) external returns (bool);

37:     function balanceOf(address account) external view returns (uint256);

177:     function supplyIncUncirculated() external view returns (uint256) {

182:     function vaultMintAllowance() external view returns (uint256) {

196:     function approve(address spender, uint256 amount) external returns (bool) {

208:     function transfer(address to, uint256 amount) external returns (bool) {

241:     function _transfer(address from, address to, uint256 amount) internal {

254:     function _mint(address to, uint256 amount) internal {

266:     function _burn(address from, uint256 amount) internal {

342:     function mintPrize(address to, uint256 amount) external {

363:     function vaultMintTo(address to, uint256 amount) external {

384:     function burnForGame(address from, uint256 amount) external {

```

```solidity
File: libraries/EntropyLib.sol

16:     function entropyStep(uint256 state) internal pure returns (uint256) {

```

```solidity
File: libraries/GameTimeLib.sol

21:     function currentDayIndex() internal view returns (uint48) {

31:     function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {

```

```solidity
File: libraries/JackpotBucketLib.sol

36:     function traitBucketCounts(uint256 entropy) internal pure returns (uint16[4] memory counts) {

110:     function sumBucketCounts(uint16[4] memory counts) internal pure returns (uint256 total) {

240:     function soloBucketIndex(uint256 entropy) internal pure returns (uint8) {

245:     function rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) internal pure returns (uint16) {

251:     function shareBpsByBucket(uint64 packed, uint8 offset) internal pure returns (uint16[4] memory shares) {

264:     function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed) {

269:     function unpackWinningTraits(uint32 packed) internal pure returns (uint8[4] memory traits) {

278:     function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {

290:     function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order) {

```

```solidity
File: libraries/PriceLookupLib.sol

21:     function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {

```

### <a name="NC-14"></a>[NC-14] Change int to int256
Throughout the code base, some variables are declared as `int`. To favor explicitness, consider changing all instances of `int` to `int256`

*Instances (21)*:
```solidity
File: BurnieCoin.sol

257:       |  Virtual mint allowance for the ContractAddresses.VAULT. This represents BURNIE that   |

259:       |  mint from this allowance when distributing to players.              |

520:       |  Permission functions for BurnieCoinflip contract to burn/mint      |

680:       |  Virtual mint allowance management for the VAULT. vaultEscrow()      |

```

```solidity
File: DegenerusGame.sol

210:       |                    MINT PACKED BIT LAYOUT                            |

212:       |  Player mint history is packed into a single uint256 for gas         |

218:       |  [72-103] lastEthDay       - Day index of last ETH mint              |

223:       |  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |

351:       |                       MINT RECORDING                                 |

1011:       |  • GAME_MINT_MODULE         - Mint data recording, airdrop multipliers                                          |

2328:       |                   VIEW: PLAYER MINT STATISTICS                       |

2330:       |  Unpack player mint history from the bit-packed mintPacked_ storage. |

2331:       |  See MINT PACKED BIT LAYOUT above for field positions.               |

2399:       |  • Mint streak: +1% per consecutive level minted (cap 50%)           |

2400:       |  • Mint count: +25% for 100% participation, scaled proportionally    |

2402:       |  • Affiliate points: +1% per affiliate point (cap 50%)               |

2618:         traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word

```

```solidity
File: DegenerusVault.sol

67: interface IWWXRPMint {

100: |  |   DegenerusGame ----► deposit() ----► Pulls ETH/stETH, escrows BURNIE mint allowance              | |

105: |  |         just increases the vault's mint allowance on the coin contract.                           | |

378:     IWWXRPMint internal constant wwxrpToken = IWWXRPMint(ContractAddresses.WWXRP);

```

### <a name="NC-15"></a>[NC-15] Interfaces should be defined in separate files from their usage
The interfaces below should be defined in separate files, so that it's easier for future projects to import them, and to avoid duplication later on if they need to be used elsewhere in the project

*Instances (31)*:
```solidity
File: BurnieCoin.sol

29: interface IBurnieCoinflip {

```

```solidity
File: BurnieCoinflip.sol

27: interface IBurnieCoin {

32: interface IWrappedWrappedXRP {

```

```solidity
File: DegenerusAdmin.sol

48: interface IVRFCoordinatorV2_5Owner {

67: interface IDegenerusGameAdmin {

100: interface ILinkTokenLike {

114: interface IDegenerusCoinLinkReward {

119: interface IAggregatorV3 {

134: interface IDegenerusVaultOwner {

139: interface IsDGNRS {

```

```solidity
File: DegenerusAffiliate.sol

32: interface IDegenerusCoinAffiliate {

```

```solidity
File: DegenerusDeityPass.sol

8: interface IIcons32 {

15: interface IDeityPassRendererV1 {

```

```solidity
File: DegenerusGame.sol

61: interface IDegenerusQuestView {

```

```solidity
File: DegenerusJackpots.sol

21: interface IDegenerusCoinJackpotView {

```

```solidity
File: DegenerusStonk.sol

7: interface IStakedDegenerusStonk {

14: interface IERC20Minimal {

19: interface IDegenerusGame {

```

```solidity
File: DegenerusVault.sol

10: interface IDegenerusGamePlayerActions {

54: interface ICoinflipPlayerActions {

62: interface ICoinPlayerActions {

67: interface IWWXRPMint {

```

```solidity
File: DeityBoonViewer.sol

4: interface IDeityBoonDataSource {

```

```solidity
File: GNRUS.sol

8: interface ISDGNRSSnapshot {

14: interface IDegenerusGameDonations {

21: interface IDegenerusVaultOwner {

```

```solidity
File: StakedDegenerusStonk.sol

9: interface IDegenerusGamePlayer {

29: interface IDegenerusCoinPlayer {

34: interface IBurnieCoinflipPlayer {

41: interface IDegenerusStonkWrapper {

```

```solidity
File: WrappedWrappedXRP.sol

30: interface IERC20 {

```

### <a name="NC-16"></a>[NC-16] Lack of checks in setters
Be it sanity checks (like checks against `0`-values) or initial setting checks: it's best for Setter functions to have them

*Instances (23)*:
```solidity
File: BurnieCoinflip.sol

689:     function setCoinflipAutoRebuyTakeProfit(
             address player,
             uint256 takeProfit
         ) external {
             _setCoinflipAutoRebuyTakeProfit(_resolvePlayer(player), takeProfit);

```

```solidity
File: DegenerusAdmin.sol

71:     function updateVrfCoordinatorAndSub(

86:     function setLootboxRngThreshold(uint256 newThreshold) external;

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {
             gameAdmin.setLootboxRngThreshold(newThreshold);

```

```solidity
File: DegenerusDeityPass.sol

97:     function setRenderer(address newRenderer) external onlyOwner {
            address prev = renderer;
            renderer = newRenderer;
            emit RendererUpdated(prev, newRenderer);

```

```solidity
File: DegenerusGame.sol

1457:         player = _resolvePlayer(player);
              _setAutoRebuy(player, enabled);
          }
      
          /// @notice Enable or disable auto-rebuy for decimator claims.

1482:     ) external {
              player = _resolvePlayer(player);
              _setAutoRebuyTakeProfit(player, takeProfit);
          }
      
          function _setAutoRebuy(address player, bool enabled) private {

1555:         uint256 ethTakeProfit,
              uint256 coinTakeProfit
          ) external {
              player = _resolvePlayer(player);
              _setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit);
          }
      
          function _setAfKingMode(

```

```solidity
File: DegenerusVault.sol

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

36:     function setAutoRebuy(address player, bool enabled) external;

36:     function setAutoRebuy(address player, bool enabled) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

38:     function setAfKingMode(

38:     function setAfKingMode(

44:     function setOperatorApproval(address operator, bool approved) external;

44:     function setOperatorApproval(address operator, bool approved) external;

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

```

```solidity
File: StakedDegenerusStonk.sol

11:     function setAfKingMode(

```

### <a name="NC-17"></a>[NC-17] Missing Event for critical parameters change
Events help non-contract tools to track changes, and events prevent users from being surprised by changes.

*Instances (27)*:
```solidity
File: BurnieCoinflip.sol

215:     function settleFlipModeChange(address player) external onlyDegenerusGameContract {
             // Process any pending claimable amounts before mode change
             uint256 mintable = _claimCoinflipsInternal(player, false);
             if (mintable != 0) {

674:     function setCoinflipAutoRebuy(
             address player,
             bool enabled,
             uint256 takeProfit
         ) external {
             bool fromGame = msg.sender == ContractAddresses.GAME;
             if (player == address(0)) {
                 player = msg.sender;
             } else if (!fromGame && player != msg.sender) {
                 _requireApproved(player);
             }
             _setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame);

689:     function setCoinflipAutoRebuyTakeProfit(
             address player,
             uint256 takeProfit
         ) external {
             _setCoinflipAutoRebuyTakeProfit(_resolvePlayer(player), takeProfit);

```

```solidity
File: DegenerusAdmin.sol

71:     function updateVrfCoordinatorAndSub(

86:     function setLootboxRngThreshold(uint256 newThreshold) external;

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {
             gameAdmin.setLootboxRngThreshold(newThreshold);

```

```solidity
File: DegenerusGame.sol

1457:         player = _resolvePlayer(player);
              _setAutoRebuy(player, enabled);
          }
      
          /// @notice Enable or disable auto-rebuy for decimator claims.

1482:     ) external {
              player = _resolvePlayer(player);
              _setAutoRebuyTakeProfit(player, takeProfit);
          }
      
          function _setAutoRebuy(address player, bool enabled) private {

1555:         uint256 ethTakeProfit,
              uint256 coinTakeProfit
          ) external {
              player = _resolvePlayer(player);
              _setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit);
          }
      
          function _setAfKingMode(

1879:         bytes32 newKeyHash
          ) external {
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_ADVANCE_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameAdvanceModule
                              .updateVrfCoordinatorAndSub
                              .selector,
                          newCoordinator,
                          newSubId,
                          newKeyHash
                      )
                  );
              if (!ok) _revertDelegate(data);
          }
      
          /// @notice Request lootbox RNG when activity threshold and LINK conditions are met.

```

```solidity
File: DegenerusVault.sol

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

36:     function setAutoRebuy(address player, bool enabled) external;

36:     function setAutoRebuy(address player, bool enabled) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

38:     function setAfKingMode(

38:     function setAfKingMode(

44:     function setOperatorApproval(address operator, bool approved) external;

44:     function setOperatorApproval(address operator, bool approved) external;

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

```

```solidity
File: Icons32Data.sol

153:     function setPaths(uint256 startIndex, string[] calldata paths) external {
             if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();
             if (_finalized) revert AlreadyFinalized();
             if (paths.length > 10) revert MaxBatch();
             if (startIndex + paths.length > 33) revert IndexOutOfBounds();
     
             for (uint256 i = 0; i < paths.length; ++i) {

171:     function setSymbols(uint256 quadrant, string[8] memory symbols) external {
             if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();
             if (_finalized) revert AlreadyFinalized();
     
             if (quadrant == 0) {
                 for (uint256 i = 0; i < 8; ++i) {

```

```solidity
File: StakedDegenerusStonk.sol

11:     function setAfKingMode(

```

### <a name="NC-18"></a>[NC-18] NatSpec is completely non-existent on functions that should have them
Public and external functions that aren't view or pure should have NatSpec comments

*Instances (83)*:
```solidity
File: BurnieCoin.sol

31:     function claimCoinflipsFromBurnie(address player, uint256 amount) external returns (uint256 claimed);

32:     function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);

35:     function creditFlip(address player, uint256 amount) external;

36:     function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;

```

```solidity
File: BurnieCoinflip.sol

28:     function burnForCoinflip(address from, uint256 amount) external;

29:     function mintForCoinflip(address to, uint256 amount) external;

33:     function mintPrize(address to, uint256 amount) external;

```

```solidity
File: DegenerusAdmin.sol

49:     function addConsumer(uint256 subId, address consumer) external;

50:     function cancelSubscription(uint256 subId, address to) external;

51:     function createSubscription() external returns (uint256 subId);

71:     function updateVrfCoordinatorAndSub(

76:     function wireVrf(

81:     function adminSwapEthForStEth(

85:     function adminStakeEthForStEth(uint256 amount) external;

86:     function setLootboxRngThreshold(uint256 newThreshold) external;

102:     function transfer(

106:     function transferAndCall(

115:     function creditLinkReward(address player, uint256 amount) external;

374:     function swapGameEthForStEth() external payable onlyOwner {

379:     function stakeGameEthToStEth(uint256 amount) external onlyOwner {

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {

```

```solidity
File: DegenerusDeityPass.sol

89:     function transferOwnership(address newOwner) external onlyOwner {

```

```solidity
File: DegenerusStonk.sol

8:     function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);

10:     function wrapperTransferTo(address to, uint256 amount) external;

15:     function transfer(address to, uint256 amount) external returns (bool);

```

```solidity
File: DegenerusVault.sol

11:     function advanceGame() external;

11:     function advanceGame() external;

12:     function purchase(

12:     function purchase(

19:     function openLootBox(address player, uint48 lootboxIndex) external;

19:     function openLootBox(address player, uint48 lootboxIndex) external;

20:     function claimWinnings(address player) external;

20:     function claimWinnings(address player) external;

21:     function claimWinningsStethFirst() external;

21:     function claimWinningsStethFirst() external;

22:     function claimWhalePass(address player) external;

22:     function claimWhalePass(address player) external;

23:     function claimDecimatorJackpot(uint24 lvl) external;

23:     function claimDecimatorJackpot(uint24 lvl) external;

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

24:     function setDecimatorAutoRebuy(address player, bool enabled) external;

25:     function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;

25:     function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;

26:     function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

26:     function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

27:     function placeFullTicketBets(

27:     function placeFullTicketBets(

35:     function resolveDegeneretteBets(address player, uint64[] calldata betIds) external;

35:     function resolveDegeneretteBets(address player, uint64[] calldata betIds) external;

36:     function setAutoRebuy(address player, bool enabled) external;

36:     function setAutoRebuy(address player, bool enabled) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

37:     function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

38:     function setAfKingMode(

38:     function setAfKingMode(

44:     function setOperatorApproval(address operator, bool approved) external;

44:     function setOperatorApproval(address operator, bool approved) external;

46:     function purchaseCoin(

46:     function purchaseCoin(

55:     function depositCoinflip(address player, uint256 amount) external;

55:     function depositCoinflip(address player, uint256 amount) external;

56:     function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

56:     function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

58:     function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

59:     function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;

63:     function decimatorBurn(address player, uint256 amount) external;

63:     function decimatorBurn(address player, uint256 amount) external;

68:     function vaultMintTo(address to, uint256 amount) external;

68:     function vaultMintTo(address to, uint256 amount) external;

```

```solidity
File: GNRUS.sol

15:     function claimWinnings(address player) external;

```

```solidity
File: StakedDegenerusStonk.sol

10:     function advanceGame() external;

11:     function setAfKingMode(

17:     function claimWinnings(address player) external;

18:     function claimWhalePass(address player) external;

25:     function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;

31:     function transfer(address to, uint256 amount) external returns (bool);

35:     function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

37:     function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);

42:     function burnForSdgnrs(address player, uint256 amount) external;

```

```solidity
File: WrappedWrappedXRP.sol

31:     function transfer(address to, uint256 amount) external returns (bool);

32:     function transferFrom(

```

### <a name="NC-19"></a>[NC-19] Incomplete NatSpec: `@param` is missing on actually documented functions
The following functions are missing `@param` NatSpec comments.

*Instances (19)*:
```solidity
File: BurnieCoinflip.sol

224:     /// @notice Deposit BURNIE into daily coinflip system.
         function depositCoinflip(address player, uint256 amount) external {

322:     /// @notice Claim coinflip winnings (exact amount).
         /// @dev Processes resolved days and claims from claimableStored (accumulated from
         ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
         function claimCoinflips(
             address player,
             uint256 amount

332:     /// @notice Claim coinflip winnings via BurnieCoin to cover token transfers/burns.
         /// @dev Access: BurnieCoin only. Processes resolved days and claims from claimableStored.
         ///      Auto-rebuy carry is never exposed to this path.
         function claimCoinflipsFromBurnie(
             address player,
             uint256 amount

342:     /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
         /// @dev Access: sDGNRS only. Used during claimRedemption() when wallet balance
         ///      is insufficient and coinflip winnings need to be sourced.
         function claimCoinflipsForRedemption(
             address player,
             uint256 amount

362:     /// @notice Consume coinflip winnings via BurnieCoin for burns (no mint).
         /// @dev Access: BurnieCoin only. Same safety as claimCoinflipsFromBurnie —
         ///      only claimableStored is consumable, carry stays in autoRebuyCarry.
         function consumeCoinflipsForBurn(
             address player,
             uint256 amount

673:     /// @notice Configure auto-rebuy mode for coinflips.
         function setCoinflipAutoRebuy(
             address player,
             bool enabled,
             uint256 takeProfit

688:     /// @notice Set auto-rebuy take profit.
         function setCoinflipAutoRebuyTakeProfit(
             address player,
             uint256 takeProfit

777:     /// @notice Process coinflip payout for a day (called by game contract).
         function processCoinflipPayouts(
             bool bonusFlip,
             uint256 rngWord,
             uint48 epoch

868:     /// @notice Credit flip to a player (called by authorized creditors).
         function creditFlip(
             address player,
             uint256 amount

877:     /// @notice Credit flips to multiple players (batch).
         function creditFlipBatch(
             address[3] calldata players,
             uint256[3] calldata amounts

```

```solidity
File: DegenerusAdmin.sol

680:     /// @notice ERC-677 callback: handles LINK donations to fund VRF subscription.
         /// @param from Address that sent the LINK.
         /// @param amount Amount of LINK received.
         function onTokenTransfer(
             address from,
             uint256 amount,
             bytes calldata

```

```solidity
File: DegenerusDeityPass.sol

96:     /// @notice Set optional external renderer. Set to address(0) to disable.
        function setRenderer(address newRenderer) external onlyOwner {

380:     /// @notice Mint a deity pass. Only callable by the game contract during purchase.
         function mint(address to, uint256 tokenId) external {

```

```solidity
File: DegenerusGame.sol

430:     /// @notice Pay DGNRS bounty for the biggest flip record holder.
         /// @dev Access: COIN or COINFLIP contract only.
         ///      Pays a share of the remaining DGNRS reward pool.
         /// @param player Recipient of the DGNRS bounty.
         /// @custom:reverts E If caller is not COIN or COINFLIP contract.
         function payCoinflipBountyDgnrs(
             address player,
             uint256 winningBet,
             uint256 bountyPool
         ) external {
             if (
                 msg.sender != ContractAddresses.COIN &&

1119:     /// @dev Delegatecalls to DecimatorModule. Access: coin contract only.
          function recordTerminalDecBurn(
              address player,
              uint24 lvl,
              uint256 baseAmount
          ) external {
              (bool ok, bytes memory data) = ContractAddresses

1139:     /// @dev Access: Game-only (self-call from handleGameOverDrain).
          function runTerminalDecimatorJackpot(
              uint256 poolWei,
              uint24 lvl,
              uint256 rngWord
          ) external returns (uint256 returnAmountWei) {
              if (msg.sender != address(this)) revert E();

```

```solidity
File: DegenerusStonk.sol

151:     /// @notice Burn DGNRS and send the underlying sDGNRS to a recipient as soulbound.
         /// @dev Blocked during VRF stall (>5h) to prevent creator vote-stacking via DGNRS→sDGNRS conversion.
         function unwrapTo(address recipient, uint256 amount) external {

168:     /// @notice Burn DGNRS to claim proportional ETH + stETH + BURNIE from sDGNRS backing
         /// @dev ETH sent last (checks-effects-interactions). Only available post-gameOver;
         ///      during active game, players must use burnWrapped() via sDGNRS gambling path.
         /// @custom:reverts GameNotOver If called during active game (Seam-1 fix).
         function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

```

```solidity
File: DegenerusVault.sol

531:     /// @notice Purchase a deity pass using an active boon for the vault
         /// @dev Uses vault ETH + claimable winnings; msg.value is retained in the vault.
         /// @param priceWei Expected deity pass price (24 + T(n) ETH where T(n) = n*(n+1)/2)
         /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
         /// @custom:reverts Insufficient If price is zero or vault cannot fund the purchase
         function gamePurchaseDeityPassFromBoon(uint256 priceWei, uint8 symbolId) external payable onlyVaultOwner {

```

### <a name="NC-20"></a>[NC-20] Incomplete NatSpec: `@return` is missing on actually documented functions
The following functions are missing `@return` NatSpec comments.

*Instances (6)*:
```solidity
File: BurnieCoinflip.sol

322:     /// @notice Claim coinflip winnings (exact amount).
         /// @dev Processes resolved days and claims from claimableStored (accumulated from
         ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
         function claimCoinflips(
             address player,
             uint256 amount
         ) external returns (uint256 claimed) {

332:     /// @notice Claim coinflip winnings via BurnieCoin to cover token transfers/burns.
         /// @dev Access: BurnieCoin only. Processes resolved days and claims from claimableStored.
         ///      Auto-rebuy carry is never exposed to this path.
         function claimCoinflipsFromBurnie(
             address player,
             uint256 amount
         ) external onlyBurnieCoin returns (uint256 claimed) {

342:     /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
         /// @dev Access: sDGNRS only. Used during claimRedemption() when wallet balance
         ///      is insufficient and coinflip winnings need to be sourced.
         function claimCoinflipsForRedemption(
             address player,
             uint256 amount
         ) external returns (uint256 claimed) {

362:     /// @notice Consume coinflip winnings via BurnieCoin for burns (no mint).
         /// @dev Access: BurnieCoin only. Same safety as claimCoinflipsFromBurnie —
         ///      only claimableStored is consumable, carry stays in autoRebuyCarry.
         function consumeCoinflipsForBurn(
             address player,
             uint256 amount
         ) external onlyBurnieCoin returns (uint256 consumed) {

```

```solidity
File: DegenerusGame.sol

1139:     /// @dev Access: Game-only (self-call from handleGameOverDrain).
          function runTerminalDecimatorJackpot(
              uint256 poolWei,
              uint24 lvl,
              uint256 rngWord
          ) external returns (uint256 returnAmountWei) {
              if (msg.sender != address(this)) revert E();

```

```solidity
File: DegenerusStonk.sol

168:     /// @notice Burn DGNRS to claim proportional ETH + stETH + BURNIE from sDGNRS backing
         /// @dev ETH sent last (checks-effects-interactions). Only available post-gameOver;
         ///      during active game, players must use burnWrapped() via sDGNRS gambling path.
         /// @custom:reverts GameNotOver If called during active game (Seam-1 fix).
         function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {

```

### <a name="NC-21"></a>[NC-21] Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor
If a function is supposed to be access-controlled, a `modifier` should be used instead of a `require/if` statement for more readability.

*Instances (74)*:
```solidity
File: BurnieCoin.sol

428:         if (msg.sender != ContractAddresses.GAME) {

529:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

538:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

547:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

637:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

666:         if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();

673:         if (msg.sender != ContractAddresses.ADMIN) revert OnlyGame();

728:         if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();

787:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

892:         if (player == address(0) || player == msg.sender) {

895:             if (!degenerusGame.isOperatorApproved(player, msg.sender)) {

983:         if (player == address(0) || player == msg.sender) {

986:             if (!degenerusGame.isOperatorApproved(player, msg.sender)) {

```

```solidity
File: BurnieCoinflip.sol

191:         if (msg.sender != address(degenerusGame)) revert OnlyDegenerusGame();

204:         if (msg.sender != address(burnie)) revert OnlyBurnieCoin();

228:         if (player == address(0) || player == msg.sender) {

232:             if (!degenerusGame.isOperatorApproved(player, msg.sender)) {

349:         if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();

682:         } else if (!fromGame && player != msg.sender) {

1114:         if (player == address(0)) return msg.sender;

1115:         if (player != msg.sender) {

1116:             if (!degenerusGame.isOperatorApproved(player, msg.sender)) {

1125:         if (msg.sender != player && !degenerusGame.isOperatorApproved(player, msg.sender)) {

```

```solidity
File: DegenerusAdmin.sol

323:         if (!vault.isVaultOwner(msg.sender)) revert NotOwner();

421:         if (vault.isVaultOwner(msg.sender)) {

427:             if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)

652:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

688:         if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();

```

```solidity
File: DegenerusAffiliate.sol

329:         if (referrer == address(0) || referrer == msg.sender) revert Insufficient();

```

```solidity
File: DegenerusDeityPass.sol

72:         if (msg.sender != _contractOwner) revert NotAuthorized();

382:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

```

```solidity
File: DegenerusGame.sol

385:         if (msg.sender != address(this)) revert E();

425:         if (msg.sender != ContractAddresses.COIN) revert E();

486:         if (msg.sender != player && !operatorApprovals[player][msg.sender]) {

494:         if (player == address(0)) return msg.sender;

495:         if (player != msg.sender) _requireApproved(player);

513:         if (msg.sender != ContractAddresses.ADMIN) revert E();

824:         if (msg.sender != ContractAddresses.COIN) revert E();

845:         if (msg.sender != address(this)) revert E();

1098:         if (msg.sender != address(this)) revert E();

1145:         if (msg.sender != address(this)) revert E();

1181:         if (msg.sender != address(this)) revert E();

1206:         if (msg.sender != address(this)) revert E();

1353:         if (msg.sender != ContractAddresses.VAULT) revert E();

1661:         if (msg.sender != ContractAddresses.COINFLIP) revert E();

1731:         if (msg.sender != ContractAddresses.SDGNRS) revert E();

1813:         if (msg.sender != ContractAddresses.ADMIN) revert E();

1830:         if (msg.sender != ContractAddresses.ADMIN) revert E();

```

```solidity
File: DegenerusJackpots.sol

142:         if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();

149:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

```

```solidity
File: DegenerusQuests.sol

291:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

```

```solidity
File: DegenerusStonk.sol

99:         if (msg.sender != address(stonk)) revert Unauthorized();

154:         if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

182:             if (!steth.transfer(msg.sender, stethOut)) revert TransferFailed();

296:         if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();

```

```solidity
File: DegenerusVault.sol

187:         if (msg.sender != ContractAddresses.VAULT) revert Unauthorized();

394:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

400:         if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();

407:         if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {

752:         } else if (player != msg.sender) {

822:         } else if (player != msg.sender) {

```

```solidity
File: GNRUS.sol

237:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

```

```solidity
File: Icons32Data.sol

154:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

172:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

197:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

```

```solidity
File: StakedDegenerusStonk.sol

250:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

311:         if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();

353:         if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

541:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

```

```solidity
File: WrappedWrappedXRP.sol

301:         if (!wXRP.transfer(msg.sender, amount)) {

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

364:         if (msg.sender != MINTER_VAULT) revert OnlyVault();

385:         if (msg.sender != MINTER_GAME) revert OnlyMinter();

```

### <a name="NC-22"></a>[NC-22] Constant state variables defined more than once
Rather than redefining state variable constant, consider using a library to store all constants as this will prevent data redundancy

*Instances (57)*:
```solidity
File: BurnieCoin.sol

168:     string public constant name = "Burnies";

171:     string public constant symbol = "BURNIE";

190:     uint8 private constant QUEST_TYPE_MINT_ETH = 1;

193:     uint16 private constant BPS_DENOMINATOR = 10_000;

241:     IDegenerusGame internal constant degenerusGame =

245:     IDegenerusQuests internal constant questModule =

379:     uint8 public constant decimals = 18;

```

```solidity
File: BurnieCoinflip.sol

123:     uint16 private constant BPS_DENOMINATOR = 10_000;

128:     uint48 private constant JACKPOT_RESET_TIME = 82620;

129:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

134:     uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;

135:     IDegenerusQuests internal constant questModule =

```

```solidity
File: DegenerusAdmin.sol

288:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

319:     IDegenerusVaultOwner private constant vault =

```

```solidity
File: DegenerusAffiliate.sol

174:     uint16 private constant BPS_DENOMINATOR = 10_000;

191:     IDegenerusCoinAffiliate internal constant coin = IDegenerusCoinAffiliate(ContractAddresses.COIN);

193:     IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);

```

```solidity
File: DegenerusGame.sol

142:     IDegenerusCoin internal constant coin =

147:     IBurnieCoinflip internal constant coinflip =

152:     IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

180:     uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;

```

```solidity
File: DegenerusJackpots.sol

93:     IDegenerusCoinJackpotView internal constant coin = IDegenerusCoinJackpotView(ContractAddresses.COINFLIP);

96:     IDegenerusGame internal constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);

```

```solidity
File: DegenerusQuests.sol

125:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

144:     uint8 private constant QUEST_TYPE_MINT_ETH = 1;

```

```solidity
File: DegenerusStonk.sol

64:     string public constant name = "Degenerus Stonk";

65:     string public constant symbol = "DGNRS";

66:     uint8 public constant decimals = 18;

82:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: DegenerusVault.sol

171:     uint8 public constant decimals = 18;

173:     uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

345:     string public constant name = "Degenerus Vault";

347:     string public constant symbol = "DGV";

349:     uint8 public constant decimals = 18;

365:     IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);

380:     IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: GNRUS.sol

121:     string public constant name = "GNRUS Donations";

124:     string public constant symbol = "GNRUS";

127:     uint8 public constant decimals = 18;

195:     uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

204:     uint16 private constant BPS_DENOM = 10_000;

220:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

226:     IDegenerusGameDonations private constant game = IDegenerusGameDonations(ContractAddresses.GAME);

229:     IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);

```

```solidity
File: StakedDegenerusStonk.sol

144:     string public constant name = "Staked Degenerus Stonk";

147:     string public constant symbol = "sDGNRS";

150:     uint8 public constant decimals = 18;

211:     uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

214:     uint16 private constant BPS_DENOM = 10_000;

230:     IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

233:     IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);

235:     IBurnieCoinflipPlayer private constant coinflip =

242:     IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

```

```solidity
File: WrappedWrappedXRP.sol

118:     string public constant name = "Wrapped Wrapped WWXRP (PARODY)";

121:     string public constant symbol = "WWXRP";

124:     uint8 public constant decimals = 18;

```

```solidity
File: libraries/GameTimeLib.sol

14:     uint48 internal constant JACKPOT_RESET_TIME = 82620;

```

### <a name="NC-23"></a>[NC-23] Consider using named mappings
Consider moving to solidity version 0.8.18 or later, and using [named mappings](https://ethereum.stackexchange.com/questions/51629/how-to-name-the-arguments-in-mapping/145555#145555) to make it easier to understand the purpose of each mapping

*Instances (47)*:
```solidity
File: BurnieCoin.sol

162:       |  |  1   | balanceOf                   | mapping(address => uint256)| |

163:       |  |  2   | allowance                   | mapping(addr => mapping)   | |

207:     mapping(address => uint256) public balanceOf;

211:     mapping(address => mapping(address => uint256)) public allowance;

```

```solidity
File: BurnieCoinflip.sol

155:     mapping(uint48 => mapping(address => uint256)) internal coinflipBalance;

156:     mapping(uint48 => CoinflipDayResult) internal coinflipDayResult;

157:     mapping(address => PlayerCoinflipState) internal playerState;

173:     mapping(uint48 => PlayerScore) internal coinflipTopByDay;

```

```solidity
File: DegenerusAdmin.sol

265:     mapping(uint256 => Proposal) public proposals;

268:     mapping(uint256 => mapping(address => Vote)) public votes;

271:     mapping(uint256 => mapping(address => uint256)) public voteWeight;

274:     mapping(address => uint256) public activeProposalId;

```

```solidity
File: DegenerusAffiliate.sol

202:     mapping(bytes32 => AffiliateCodeInfo) public affiliateCode;

209:     mapping(uint24 => mapping(address => uint256)) private affiliateCoinEarned;

214:     mapping(address => bytes32) private playerReferralCode;

219:     mapping(uint24 => PlayerScore) private affiliateTopByLevel;

224:     mapping(uint24 => uint256) private _totalAffiliateScore;

229:     mapping(uint24 => mapping(address => mapping(address => uint256))) private affiliateCommissionFromSender;

497:         mapping(address => uint256) storage earned = affiliateCoinEarned[lvl];

```

```solidity
File: DegenerusDeityPass.sol

58:     mapping(uint256 => address) private _owners;

59:     mapping(address => uint256) private _balances;

```

```solidity
File: DegenerusJackpots.sol

116:     mapping(uint24 => mapping(address => uint256)) internal bafTotals;

119:     mapping(uint24 => PlayerScore[4]) internal bafTop;

122:     mapping(uint24 => uint8) internal bafTopLen;

125:     mapping(uint24 => uint256) internal bafEpoch;

128:     mapping(uint24 => mapping(address => uint256)) internal bafPlayerEpoch;

```

```solidity
File: DegenerusQuests.sol

271:     mapping(address => PlayerQuestState) private questPlayerState;

274:     mapping(address => uint16) private questStreakShieldCount;

```

```solidity
File: DegenerusStonk.sol

73:     mapping(address => uint256) public balanceOf;

74:     mapping(address => mapping(address => uint256)) public allowance;

```

```solidity
File: DegenerusVault.sol

178:     mapping(address => uint256) public balanceOf;

180:     mapping(address => mapping(address => uint256)) public allowance;

```

```solidity
File: GNRUS.sol

137:     mapping(address => uint256) public balanceOf;

164:     mapping(uint48 => Proposal) public proposals;

167:     mapping(uint24 => uint48) public levelProposalStart;

170:     mapping(uint24 => uint8) public levelProposalCount;

173:     mapping(uint24 => bool) public levelResolved;

176:     mapping(uint24 => mapping(address => bool)) public hasProposed;

179:     mapping(uint24 => uint8) public creatorProposalCount;

182:     mapping(uint24 => mapping(address => mapping(uint48 => bool))) public hasVoted;

185:     mapping(uint24 => uint48) public levelSdgnrsSnapshot;

188:     mapping(uint24 => address) public levelVaultOwner;

```

```solidity
File: StakedDegenerusStonk.sol

160:     mapping(address => uint256) public balanceOf;

194:     mapping(address => PendingRedemption) public pendingRedemptions;

195:     mapping(uint48 => RedemptionPeriod) public redemptionPeriods;

```

```solidity
File: WrappedWrappedXRP.sol

136:     mapping(address => uint256) public balanceOf;

139:     mapping(address => mapping(address => uint256)) public allowance;

```

### <a name="NC-24"></a>[NC-24] `address`s shouldn't be hard-coded
It is often better to declare `address`es as `immutable`, and assign them via constructor arguments. This allows the code to remain the same across deployments on different networks, and avoids recompilation when addresses need to change.

*Instances (29)*:
```solidity
File: ContractAddresses.sol

10:     address internal constant ICONS_32 = address(0xa0Cb889707d426A7A386870A03bc70d1b0697598);

11:     address internal constant GAME_MINT_MODULE = address(0x1d1499e622D69689cdf9004d05Ec547d650Ff211);

12:     address internal constant GAME_ADVANCE_MODULE = address(0xA4AD4f68d0b91CFD19687c881e50f3A00242828c);

13:     address internal constant GAME_WHALE_MODULE = address(0x03A6a84cD762D9707A21605b548aaaB891562aAb);

14:     address internal constant GAME_JACKPOT_MODULE = address(0xD6BbDE9174b1CdAa358d2Cf4D57D1a9F7178FBfF);

15:     address internal constant GAME_DECIMATOR_MODULE = address(0x15cF58144EF33af1e14b5208015d11F9143E27b9);

16:     address internal constant GAME_ENDGAME_MODULE = address(0x212224D2F2d262cd093eE13240ca4873fcCBbA3C);

17:     address internal constant GAME_GAMEOVER_MODULE = address(0x2a07706473244BC757E10F2a9E86fB532828afe3);

18:     address internal constant GAME_LOOTBOX_MODULE = address(0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7);

19:     address internal constant GAME_BOON_MODULE = address(0xD16d567549A2a2a2005aEACf7fB193851603dd70);

20:     address internal constant GAME_DEGENERETTE_MODULE = address(0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758);

21:     address internal constant COIN = address(0x13aa49bAc059d709dd0a18D6bb63290076a702D7);

22:     address internal constant COINFLIP = address(0xDB25A7b768311dE128BBDa7B8426c3f9C74f3240);

23:     address internal constant VAULT = address(0x796f2974e3C1af763252512dd6d521E9E984726C);

24:     address internal constant AFFILIATE = address(0x1aF7f588A501EA2B5bB3feeFA744892aA2CF00e6);

25:     address internal constant JACKPOTS = address(0xe8dc788818033232EF9772CB2e6622F1Ec8bc840);

26:     address internal constant QUESTS = address(0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E);

27:     address internal constant GAME = address(0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f);

28:     address internal constant SDGNRS = address(0x92a6649Fdcc044DA968d94202465578a9371C7b1);

29:     address internal constant DGNRS = address(0xDA5A5ADC64C8013d334A0DA9e711B364Af7A4C2d);

30:     address internal constant ADMIN = address(0x886D6d1eB8D415b00052828CD6d5B321f072073d);

31:     address internal constant DEITY_PASS = address(0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da);

32:     address internal constant WWXRP = address(0x756e0562323ADcDA4430d6cb456d9151f605290B);

33:     address internal constant STETH_TOKEN = address(0x2e234DAe75C793f67A35089C9d99245E1C58470b);

34:     address internal constant LINK_TOKEN = address(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a);

35:     address internal constant GNRUS = address(0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC);

36:     address internal constant CREATOR = address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);

37:     address internal constant VRF_COORDINATOR = address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f);

38:     address internal constant WXRP = address(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9);

```

### <a name="NC-25"></a>[NC-25] Numeric values having to do with time should use time units for readability
There are [units](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#time-units) for seconds, minutes, hours, days, and weeks, and since they're defined, they should be used

*Instances (1)*:
```solidity
File: DegenerusGame.sol

174:     uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365; // 1 year

```

### <a name="NC-26"></a>[NC-26] Adding a `return` statement when the function defines a named return variable, is redundant

*Instances (167)*:
```solidity
File: BurnieCoin.sol

305:     /// @notice Preview the amount claimCoinflips(amount) would mint for a player.
         /// @dev Proxies to BurnieCoinflip contract.
         /// @param player The player to preview for.
         /// @return mintable Amount of BURNIE that would be minted on claim.
         function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
             return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);

603:     function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
             if (amount == 0) return 0;

603:     function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
             if (amount == 0) return 0;
             if (degenerusGame.rngLocked()) return 0;

603:     function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
             if (amount == 0) return 0;
             if (degenerusGame.rngLocked()) return 0;
             uint256 balance = balanceOf[player];
             if (balance >= amount) return 0;

603:     function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
             if (amount == 0) return 0;
             if (degenerusGame.rngLocked()) return 0;
             uint256 balance = balanceOf[player];
             if (balance >= amount) return 0;
             unchecked {
                 return IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(

719:     /// @notice Compute affiliate quest rewards while preserving quest module access control.
         /// @dev Access: affiliate contract only. Routes through coin contract to enforce access.
         /// @param player The player who triggered the affiliate action.
         /// @param amount The base amount for quest calculation.
         /// @return questReward The bonus reward earned (if any quest completed).
         function affiliateQuestReward(
             address player,
             uint256 amount
         ) external returns (uint256 questReward) {
             if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();
             IDegenerusQuests module = questModule;
             if (player == address(0) || amount == 0) return 0;
             (
                 uint256 reward,
                 uint8 questType,
                 uint32 streak,
                 bool completed
             ) = module.handleAffiliate(player, amount);
             questReward = _questApplyReward(
                 player,
                 reward,
                 questType,
                 streak,
                 completed
             );
             return questReward;

719:     /// @notice Compute affiliate quest rewards while preserving quest module access control.
         /// @dev Access: affiliate contract only. Routes through coin contract to enforce access.
         /// @param player The player who triggered the affiliate action.
         /// @param amount The base amount for quest calculation.
         /// @return questReward The bonus reward earned (if any quest completed).
         function affiliateQuestReward(
             address player,
             uint256 amount
         ) external returns (uint256 questReward) {
             if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();
             IDegenerusQuests module = questModule;
             if (player == address(0) || amount == 0) return 0;

1026:     /// @dev Adjust decimator bucket based on activity score bonus.
          ///      Higher bonus yields lower bucket (better odds), capped at DECIMATOR_ACTIVITY_CAP_BPS.
          function _adjustDecimatorBucket(
              uint256 bonusBps,
              uint8 minBucket
          ) private pure returns (uint8 adjustedBucket) {
              adjustedBucket = DECIMATOR_BUCKET_BASE;
              if (bonusBps == 0) return adjustedBucket;

1046:     /// @dev Decimator burn multiplier: 1x base plus one-third of activity bonus.
          function _decimatorBurnMultiplier(uint256 bonusBps) private pure returns (uint256 decMultBps) {
              if (bonusBps == 0) return BPS_DENOMINATOR;
              return BPS_DENOMINATOR + (bonusBps / 3);

1046:     /// @dev Decimator burn multiplier: 1x base plus one-third of activity bonus.
          function _decimatorBurnMultiplier(uint256 bonusBps) private pure returns (uint256 decMultBps) {
              if (bonusBps == 0) return BPS_DENOMINATOR;

```

```solidity
File: BurnieCoinflip.sol

322:     /// @notice Claim coinflip winnings (exact amount).
         /// @dev Processes resolved days and claims from claimableStored (accumulated from
         ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
         function claimCoinflips(
             address player,
             uint256 amount
         ) external returns (uint256 claimed) {
             return _claimCoinflipsAmount(_resolvePlayer(player), amount, true);

332:     /// @notice Claim coinflip winnings via BurnieCoin to cover token transfers/burns.
         /// @dev Access: BurnieCoin only. Processes resolved days and claims from claimableStored.
         ///      Auto-rebuy carry is never exposed to this path.
         function claimCoinflipsFromBurnie(
             address player,
             uint256 amount
         ) external onlyBurnieCoin returns (uint256 claimed) {
             return _claimCoinflipsAmount(player, amount, true);

342:     /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
         /// @dev Access: sDGNRS only. Used during claimRedemption() when wallet balance
         ///      is insufficient and coinflip winnings need to be sourced.
         function claimCoinflipsForRedemption(
             address player,
             uint256 amount
         ) external returns (uint256 claimed) {
             if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();
             return _claimCoinflipsAmount(player, amount, true);

353:     /// @notice Get the result of a coinflip day.
         /// @param day The day to query.
         /// @return rewardPercent The reward percentage for that day.
         /// @return win Whether the flip was a win.
         function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win) {
             CoinflipDayResult memory result = coinflipDayResult[day];
             return (result.rewardPercent, result.win);

362:     /// @notice Consume coinflip winnings via BurnieCoin for burns (no mint).
         /// @dev Access: BurnieCoin only. Same safety as claimCoinflipsFromBurnie —
         ///      only claimableStored is consumable, carry stays in autoRebuyCarry.
         function consumeCoinflipsForBurn(
             address player,
             uint256 amount
         ) external onlyBurnieCoin returns (uint256 consumed) {
             return _claimCoinflipsAmount(player, amount, false);

372:     /// @dev Internal claim exact amount.
         function _claimCoinflipsAmount(
             address player,
             uint256 amount,
             bool mintTokens
         ) private returns (uint256 claimed) {
             PlayerCoinflipState storage state = playerState[player];
             uint256 mintable = _claimCoinflipsInternal(player, false);
             uint256 stored = state.claimableStored + mintable;
             if (stored == 0) return 0;

399:     /// @dev Process daily coinflip claims and calculate winnings.
         function _claimCoinflipsInternal(
             address player,
             bool deepAutoRebuy
         ) internal returns (uint256 mintable) {
             IDegenerusGame game = degenerusGame;
             PlayerCoinflipState storage state = playerState[player];
             bool afKingMode = game.syncAfKingLazyPassFromCoin(player);
             uint48 latest = flipsClaimableDay;
             uint48 start = state.lastClaim;
     
             bool rebuyActive = state.autoRebuyEnabled;
             bool deep = deepAutoRebuy && rebuyActive;
             uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;
             uint256 carry;
             uint256 winningBafCredit;
             uint48 bafResolvedDay;
             bool bafResolvedDayCached;
             uint256 lossCount;
             bool afKingActive = rebuyActive && afKingMode;
             bool hasDeityPass = afKingActive && game.deityPassCountFor(player) != 0;
             uint16 deityBonusHalfBps;
             bool levelCached;
             uint24 cachedLevel;
             if (hasDeityPass) {
                 cachedLevel = game.level();
                 levelCached = true;
                 deityBonusHalfBps = _afKingDeityBonusHalfBpsWithLevel(player, cachedLevel);
             }
     
             uint256 oldCarry = state.autoRebuyCarry;
             if (rebuyActive) {
                 carry = oldCarry;
             } else if (oldCarry != 0) {
                 mintable += oldCarry;
                 state.autoRebuyCarry = 0;
             }
     
             if (start >= latest) return mintable;
     
             // Enforce claim window unless auto-rebuy is enabled (settles back to enable day).
             uint8 windowDays = start == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
             uint48 minClaimableDay;
             if (rebuyActive) {
                 minClaimableDay = state.autoRebuyStartDay;
                 if (minClaimableDay > latest) {
                     minClaimableDay = latest;
                 }
             } else {
                 unchecked {
                     minClaimableDay = latest > windowDays ? latest - windowDays : 0;
                 }
             }
             if (start < minClaimableDay) {
                 start = minClaimableDay;
                 if (rebuyActive && carry != 0) {
                     carry = 0;
                 }
             }
     
             uint48 cursor;
             unchecked {
                 cursor = start + 1;
             }
             uint48 processed = start;
     
             uint32 remaining;
             if (deep) {
                 uint48 available = latest - start;
                 uint48 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                     ? AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                     : available;
                 remaining = uint32(cap);
             } else {
                 remaining = windowDays;
             }
     
             // Auto-rebuy-off processes a larger fixed window while keeping tx cost bounded.
             while (remaining != 0 && cursor <= latest) {
                 CoinflipDayResult memory result = coinflipDayResult[cursor];
                 uint16 rewardPercent = result.rewardPercent;
                 bool win = result.win;
     
                 // Skip unresolved days (gaps from testnet day-advance or missed resolution)
                 if (rewardPercent == 0 && !win) {
                     unchecked { ++cursor; --remaining; }
                     continue;
                 }
     
                 uint256 storedStake = coinflipBalance[cursor][player];
                 uint256 stake = storedStake;
                 if (rebuyActive && carry != 0) {
                     stake += carry;
                 }
     
                 if (storedStake != 0) {
                     // Clear stake whether win or loss (loss = forfeit principal)
                     coinflipBalance[cursor][player] = 0;
                 }
     
                 if (stake != 0) {
                     if (win) {
                         // Winnings = principal + (principal * rewardPercent%) where rewardPercent already in percent (not bps).
                         uint256 payout = stake +
                             (stake * uint256(rewardPercent)) /
                             100;
                         if (!bafResolvedDayCached) {
                             bafResolvedDay = jackpots.getLastBafResolvedDay();
                             bafResolvedDayCached = true;
                         }
                         if (cursor > bafResolvedDay) {
                             winningBafCredit += payout;
                         }
                         if (rebuyActive) {
                             if (takeProfit != 0) {
                                 uint256 reserved = (payout / takeProfit) *
                                     takeProfit;
                                 if (reserved != 0) {
                                     mintable += reserved;
                                 }
                                 carry = payout - reserved;
                             } else {
                                 carry = payout;
                             }
                             if (carry != 0) {
                                 if (afKingActive) {
                                     carry += _afKingRecyclingBonus(
                                         carry,
                                         deityBonusHalfBps
                                     );
                                 } else {
                                     carry += _recyclingBonus(carry);
                                 }
                             }
                         } else {
                             mintable += payout;
                         }
                     } else {
                         unchecked {
                             ++lossCount;
                         }
                         if (rebuyActive) {
                             carry = 0;
                         }
                     }
                 }
     
                 processed = cursor;
                 unchecked {
                     ++cursor;
                     --remaining;
                 }
             }
     
             // sDGNRS is excluded from BAF in jackpots (recordBafFlip returns early).
             // Skip the BAF section entirely so this path doesn't hit the rngLocked guard
             // when called from processCoinflipPayouts during advanceGame.
             if (winningBafCredit != 0 && player != ContractAddresses.SDGNRS) {
                 if (!levelCached) {
                     cachedLevel = game.level();
                     levelCached = true;
                 }
                 (
                     uint24 purchaseLevel_,
                     bool inJackpotPhase,
                     bool lastPurchaseDay_,
                     bool rngLocked_,
     
                 ) = game.purchaseInfo();
                 bool over = game.gameOver();
                 if (
                     !inJackpotPhase &&
                     !over &&
                     lastPurchaseDay_ &&
                     rngLocked_ &&
                     (purchaseLevel_ % 10 == 0)
                 ) {
                     revert RngLocked();
                 }
                 uint24 bafLevel = cachedLevel;
                 if (!inJackpotPhase && !over) {
                     bafLevel = purchaseLevel_;
                 }
                 uint24 bafLvl = _bafBracketLevel(bafLevel);
                 jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
             }
     
             // Update last claim pointer if we processed any days
             if (processed != start) {
                 state.lastClaim = processed;
             }
     
             if (rebuyActive && oldCarry != carry) {
                 // Safe truncation: carry is bounded by a single day's coinflip payout; uint128 max is unreachable.
                 state.autoRebuyCarry = uint128(carry);
             }
     
             if (lossCount != 0) {
                 wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
             }
     
             return mintable;

399:     /// @dev Process daily coinflip claims and calculate winnings.
         function _claimCoinflipsInternal(
             address player,
             bool deepAutoRebuy
         ) internal returns (uint256 mintable) {
             IDegenerusGame game = degenerusGame;
             PlayerCoinflipState storage state = playerState[player];
             bool afKingMode = game.syncAfKingLazyPassFromCoin(player);
             uint48 latest = flipsClaimableDay;
             uint48 start = state.lastClaim;
     
             bool rebuyActive = state.autoRebuyEnabled;
             bool deep = deepAutoRebuy && rebuyActive;
             uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;
             uint256 carry;
             uint256 winningBafCredit;
             uint48 bafResolvedDay;
             bool bafResolvedDayCached;
             uint256 lossCount;
             bool afKingActive = rebuyActive && afKingMode;
             bool hasDeityPass = afKingActive && game.deityPassCountFor(player) != 0;
             uint16 deityBonusHalfBps;
             bool levelCached;
             uint24 cachedLevel;
             if (hasDeityPass) {
                 cachedLevel = game.level();
                 levelCached = true;
                 deityBonusHalfBps = _afKingDeityBonusHalfBpsWithLevel(player, cachedLevel);
             }
     
             uint256 oldCarry = state.autoRebuyCarry;
             if (rebuyActive) {
                 carry = oldCarry;
             } else if (oldCarry != 0) {
                 mintable += oldCarry;
                 state.autoRebuyCarry = 0;
             }
     
             if (start >= latest) return mintable;

898:     /// @notice Preview claimable coinflip winnings.
         function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
             uint256 daily = _viewClaimableCoin(player);
             uint256 stored = playerState[player].claimableStored;
             return daily + stored;

929:     /// @notice Get last day's coinflip leaderboard winner.
         function coinflipTopLastDay()
             external
             view
             returns (address player, uint128 score)
         {
             uint48 lastDay = flipsClaimableDay;
             if (lastDay == 0) return (address(0), 0);
             PlayerScore memory top = coinflipTopByDay[lastDay];
             return (top.player, uint128(top.score));

929:     /// @notice Get last day's coinflip leaderboard winner.
         function coinflipTopLastDay()
             external
             view
             returns (address player, uint128 score)
         {
             uint48 lastDay = flipsClaimableDay;
             if (lastDay == 0) return (address(0), 0);

941:     /// @dev View helper for daily coinflip claimable winnings.
         function _viewClaimableCoin(
             address player
         ) internal view returns (uint256 total) {
             // Pending flip winnings within the claim window; staking removed.
             uint48 latestDay = flipsClaimableDay;
             uint48 startDay = playerState[player].lastClaim;
             if (startDay >= latestDay) return 0;

1015:     /// @dev Calculate recycling bonus for daily flip deposits (1% bonus, capped at 1000 BURNIE).
          function _recyclingBonus(
              uint256 amount
          ) private pure returns (uint256 bonus) {
              if (amount == 0) return 0;
              bonus = amount / 100;

1025:     /// @dev Calculate recycling bonus for afKing flip deposits.
          /// Deity bonus portion is capped at DEITY_RECYCLE_CAP; remainder gets base only.
          function _afKingRecyclingBonus(
              uint256 amount,
              uint16 deityBonusHalfBps
          ) private pure returns (uint256 bonus) {
              if (amount == 0) return 0;
              uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;
              if (deityBonusHalfBps == 0 || amount <= DEITY_RECYCLE_CAP) {
                  uint256 totalHalfBps = baseHalfBps + uint256(deityBonusHalfBps);
                  return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);
              }
              uint256 fullHalfBps = baseHalfBps + uint256(deityBonusHalfBps);
              return (DEITY_RECYCLE_CAP * fullHalfBps + (amount - DEITY_RECYCLE_CAP) * baseHalfBps)

1025:     /// @dev Calculate recycling bonus for afKing flip deposits.
          /// Deity bonus portion is capped at DEITY_RECYCLE_CAP; remainder gets base only.
          function _afKingRecyclingBonus(
              uint256 amount,
              uint16 deityBonusHalfBps
          ) private pure returns (uint256 bonus) {
              if (amount == 0) return 0;
              uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;

1025:     /// @dev Calculate recycling bonus for afKing flip deposits.
          /// Deity bonus portion is capped at DEITY_RECYCLE_CAP; remainder gets base only.
          function _afKingRecyclingBonus(
              uint256 amount,
              uint16 deityBonusHalfBps
          ) private pure returns (uint256 bonus) {
              if (amount == 0) return 0;
              uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;
              if (deityBonusHalfBps == 0 || amount <= DEITY_RECYCLE_CAP) {
                  uint256 totalHalfBps = baseHalfBps + uint256(deityBonusHalfBps);
                  return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1112:     /// @dev Resolve player address (address(0) -> msg.sender, else validate approval).
          function _resolvePlayer(address player) private view returns (address resolved) {
              if (player == address(0)) return msg.sender;
              if (player != msg.sender) {
                  if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
                      revert NotApproved();
                  }
              }
              return player;

1112:     /// @dev Resolve player address (address(0) -> msg.sender, else validate approval).
          function _resolvePlayer(address player) private view returns (address resolved) {
              if (player == address(0)) return msg.sender;

```

```solidity
File: DegenerusAdmin.sol

733:     /// @dev Convert LINK amount to ETH-equivalent using price feed.
         function linkAmountToEth(
             uint256 amount
         ) external view returns (uint256 ethAmount) {
             address feed = linkEthPriceFeed;
             if (feed == address(0) || amount == 0) return 0;

733:     /// @dev Convert LINK amount to ETH-equivalent using price feed.
         function linkAmountToEth(
             uint256 amount
         ) external view returns (uint256 ethAmount) {
             address feed = linkEthPriceFeed;
             if (feed == address(0) || amount == 0) return 0;
     
             (
                 uint80 roundId,
                 int256 answer,
                 ,
                 uint256 updatedAt,
                 uint80 answeredInRound
             ) = IAggregatorV3(feed).latestRoundData();
             if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                 return 0;

733:     /// @dev Convert LINK amount to ETH-equivalent using price feed.
         function linkAmountToEth(
             uint256 amount
         ) external view returns (uint256 ethAmount) {
             address feed = linkEthPriceFeed;
             if (feed == address(0) || amount == 0) return 0;
     
             (
                 uint80 roundId,
                 int256 answer,
                 ,
                 uint256 updatedAt,
                 uint80 answeredInRound
             ) = IAggregatorV3(feed).latestRoundData();
             if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                 return 0;
             if (updatedAt > block.timestamp) return 0;

733:     /// @dev Convert LINK amount to ETH-equivalent using price feed.
         function linkAmountToEth(
             uint256 amount
         ) external view returns (uint256 ethAmount) {
             address feed = linkEthPriceFeed;
             if (feed == address(0) || amount == 0) return 0;
     
             (
                 uint80 roundId,
                 int256 answer,
                 ,
                 uint256 updatedAt,
                 uint80 answeredInRound
             ) = IAggregatorV3(feed).latestRoundData();
             if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                 return 0;
             if (updatedAt > block.timestamp) return 0;
             unchecked {
                 if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE) return 0;

757:     /// @dev Calculate reward multiplier based on subscription LINK balance.
         function _linkRewardMultiplier(
             uint256 subBal
         ) private pure returns (uint256 mult) {
             if (subBal >= 1000 ether) return 0;

757:     /// @dev Calculate reward multiplier based on subscription LINK balance.
         function _linkRewardMultiplier(
             uint256 subBal
         ) private pure returns (uint256 mult) {
             if (subBal >= 1000 ether) return 0;
             if (subBal <= 200 ether) {
                 uint256 delta = (subBal * 2e18) / 200 ether;
                 unchecked {
                     return 3e18 - delta;
                 }
             }
             uint256 excess = subBal - 200 ether;
             uint256 delta2 = (excess * 1e18) / 800 ether;
             if (delta2 >= 1e18) return 0;

757:     /// @dev Calculate reward multiplier based on subscription LINK balance.
         function _linkRewardMultiplier(
             uint256 subBal
         ) private pure returns (uint256 mult) {
             if (subBal >= 1000 ether) return 0;
             if (subBal <= 200 ether) {
                 uint256 delta = (subBal * 2e18) / 200 ether;
                 unchecked {
                     return 3e18 - delta;
                 }
             }
             uint256 excess = subBal - 200 ether;
             uint256 delta2 = (excess * 1e18) / 800 ether;
             if (delta2 >= 1e18) return 0;
             unchecked {
                 return 1e18 - delta2;

757:     /// @dev Calculate reward multiplier based on subscription LINK balance.
         function _linkRewardMultiplier(
             uint256 subBal
         ) private pure returns (uint256 mult) {
             if (subBal >= 1000 ether) return 0;
             if (subBal <= 200 ether) {
                 uint256 delta = (subBal * 2e18) / 200 ether;
                 unchecked {
                     return 3e18 - delta;

```

```solidity
File: DegenerusAffiliate.sol

358:      * @notice Process affiliate rewards for a purchase or gameplay action.
          * @dev Core payout logic. Handles referral resolution, reward scaling,
          *      and multi-tier distribution.
          *
      * ACCESS: coin or game only.
          *
          * REWARD FLOW:
          * +--------------------------------------------------------------------+
          * | 1. Resolve referral code (stored or provided)                      |
          * | 2. Apply reward percentage based on ETH type and level             |
          * | 3. Update leaderboard (full untapered amount)                      |
          * | 4. Apply lootbox activity taper if applicable                      |
          * | 5. Calculate kickback (returned to caller for player credit)       |
          * | 6. Pay direct affiliate (base - kickback)                          |
          * | 7. Pay upline1 (20% of scaled amount)                              |
          * | 8. Pay upline2 (20% of upline1 share = 4%)                         |
          * | 9. Quest rewards added on top                                     |
          * +--------------------------------------------------------------------+
          *
          * REWARD RATES:
          * - Fresh ETH (levels 0-3): 25% (REWARD_SCALE_FRESH_L1_3_BPS = 2500)
          * - Fresh ETH (levels 4+): 20% (REWARD_SCALE_FRESH_L4P_BPS = 2000)
          * - Recycled ETH (all levels): 5% (REWARD_SCALE_RECYCLED_BPS = 500)
          *
          * LOOTBOX TAPER (fresh ETH only):
          * - Activity score < 10,000: no taper (100% payout)
          * - Activity score 10,000-25,500: linear taper from 100% to 25%
          * - Activity score >= 25,500: 25% payout floor (LOOTBOX_TAPER_MIN_BPS = 2500)
          * - Leaderboard tracking always uses full untapered amount.
          *
          * @param amount Base reward amount (18 decimals).
          * @param code Affiliate code provided with the transaction (may be bytes32(0)).
          * @param sender The player making the purchase.
          * @param lvl Current game level (for join tracking and leaderboard).
          * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
          * @param lootboxActivityScore Buyer's activity score for lootbox taper (0 = no taper; 10000+ triggers linear taper to 25% floor at 25500).
          * @return playerKickback Amount of kickback to credit to the player (caller handles minting and batching).
          */
         function payAffiliate(
             uint256 amount,
             bytes32 code,
             address sender,
             uint24 lvl,
             bool isFreshEth,
             uint16 lootboxActivityScore
         ) external returns (uint256 playerKickback) {
             // -----------------------------------------------------------------
             // ACCESS CONTROL
             // -----------------------------------------------------------------
             // SECURITY: Only trusted contracts can distribute affiliate rewards.
             if (
                 msg.sender != ContractAddresses.COIN &&
                 msg.sender != ContractAddresses.GAME
             ) revert OnlyAuthorized();
     
             // -----------------------------------------------------------------
             // REFERRAL RESOLUTION
             // -----------------------------------------------------------------
             bytes32 storedCode = playerReferralCode[sender];
             AffiliateCodeInfo memory info;
             bool infoSet;
             bool noReferrer;
             AffiliateCodeInfo memory vaultInfo = AffiliateCodeInfo({
                 owner: ContractAddresses.VAULT,
                 kickback: 0
             });
     
             if (storedCode == bytes32(0)) {
                 // No stored code - resolve provided code or default to VAULT.
                 if (code == bytes32(0)) {
                     // Blank referral: lock to VAULT as default.
                     _setReferralCode(sender, REF_CODE_LOCKED);
                     storedCode = AFFILIATE_CODE_VAULT;
                     info = vaultInfo;
                     noReferrer = true;
                 } else {
                     // Try custom code first, then default (address-derived) code.
                     address resolved = _resolveCodeOwner(code);
                     if (resolved == address(0) || resolved == sender) {
                         // Invalid/self-referral: lock to VAULT as default.
                         _setReferralCode(sender, REF_CODE_LOCKED);
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Valid code (custom or default): store it permanently.
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             // Default code: 0% kickback.
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                     }
                 }
                 infoSet = true;
             } else {
                 if (code != bytes32(0) && code != storedCode && _vaultReferralMutable(storedCode)) {
                     address resolved = _resolveCodeOwner(code);
                     if (resolved != address(0) && resolved != sender) {
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                         infoSet = true;
                     }
                 }
                 if (!infoSet) {
                     if (storedCode == REF_CODE_LOCKED) {
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Use the stored code (custom or default).
                         AffiliateCodeInfo storage customInfo = affiliateCode[storedCode];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: _resolveCodeOwner(storedCode), kickback: 0 });
                         }
                     }
                 }
             }
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION SETUP
             // -----------------------------------------------------------------
             address affiliateAddr = info.owner;
             uint8 kickbackPct = info.kickback;
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION
             // -----------------------------------------------------------------
             mapping(address => uint256) storage earned = affiliateCoinEarned[lvl];
     
             // Apply reward percentage based on ETH type and level.
             // - Fresh ETH (levels 0-3): 25%
             // - Fresh ETH (levels 4+): 20%
             // - Recycled ETH: 5%
             uint256 rewardScaleBps;
             if (isFreshEth) {
                 // Fresh ETH: 25% for first 4 levels (0-3), 20% for levels 4+
                 rewardScaleBps = lvl <= 3
                     ? REWARD_SCALE_FRESH_L1_3_BPS
                     : REWARD_SCALE_FRESH_L4P_BPS;
             } else {
                 // Recycled ETH: 5%
                 rewardScaleBps = REWARD_SCALE_RECYCLED_BPS;
             }
             uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
             if (scaledAmount == 0) {
                 emit Affiliate(amount, storedCode, sender);
                 return 0;
             }
     
             // -----------------------------------------------------------------
             // PER-REFERRER COMMISSION CAP
             // -----------------------------------------------------------------
             // Cap commission from any single sender to 0.5 ETH BURNIE per level.
             // This prevents a single whale from dominating an affiliate's earnings.
             {
                 uint256 alreadyEarned = affiliateCommissionFromSender[lvl][affiliateAddr][sender];
                 if (alreadyEarned >= MAX_COMMISSION_PER_REFERRER_PER_LEVEL) {
                     // Cap fully reached - no more commission from this sender this level.
                     emit Affiliate(amount, storedCode, sender);
                     return 0;
                 }
                 uint256 remainingCap = MAX_COMMISSION_PER_REFERRER_PER_LEVEL - alreadyEarned;
                 if (scaledAmount > remainingCap) {
                     scaledAmount = remainingCap;
                 }
                 affiliateCommissionFromSender[lvl][affiliateAddr][sender] = alreadyEarned + scaledAmount;
             }
     
             // Update leaderboard tracking (full amount, before any lootbox taper).
             uint256 newTotal = earned[affiliateAddr] + scaledAmount;
             earned[affiliateAddr] = newTotal;
             _totalAffiliateScore[lvl] += scaledAmount;
             emit AffiliateEarningsRecorded(
                 lvl,
                 affiliateAddr,
                 scaledAmount,
                 newTotal,
                 sender,
                 storedCode,
                 isFreshEth
             );
             _updateTopAffiliate(affiliateAddr, newTotal, lvl);
     
             // Taper payout for high-activity lootbox buyers (leaderboard already recorded full amount).
             if (lootboxActivityScore >= LOOTBOX_TAPER_START_SCORE) {
                 scaledAmount = _applyLootboxTaper(scaledAmount, lootboxActivityScore);
             }
     
             // Calculate kickback (returned to player) and affiliate share.
             uint256 affiliateShareBase;
             uint256 kickbackShare;
             if (kickbackPct == 0) {
                 affiliateShareBase = scaledAmount;
             } else {
                 kickbackShare = (scaledAmount * uint256(kickbackPct)) / 100;
                 affiliateShareBase = scaledAmount - kickbackShare;
             }
     
             playerKickback = kickbackShare;
             // Upline rewards are paid out but not tracked for leaderboard scores (gas).
     
             // -----------------------------------------------------------------
             // DISTRIBUTION
             // -----------------------------------------------------------------
             if (noReferrer) {
                 // No real referrer — 50/50 flip between VAULT and DGNRS.
                 // Skip quest reward calls (VAULT has no quest state).
                 uint256 totalAmount = scaledAmount + scaledAmount / 5 + scaledAmount / 25;
                 if (totalAmount != 0) {
                     uint256 entropy = uint256(
                         keccak256(
                             abi.encodePacked(
                                 AFFILIATE_ROLL_TAG,
                                 GameTimeLib.currentDayIndex(),
                                 sender,
                                 storedCode
                             )
                         )
                     );
                     address winner = (entropy % 2 == 0)
                         ? ContractAddresses.VAULT
                         : ContractAddresses.DGNRS;
                     _routeAffiliateReward(winner, totalAmount);
                 }
             } else {
                 // Real affiliate — normal 3-recipient weighted roll.
                 // PRNG is known — accepted design tradeoff (EV-neutral, manipulation only redistributive between affiliates).
                 // Always 3 recipients: affiliate + upline tier 1 (VAULT fallback) + upline tier 2 (VAULT fallback).
                 address[3] memory players;
                 uint256[3] memory amounts;
     
                 // Affiliate share + quest bonus
                 uint256 questReward = coin.affiliateQuestReward(affiliateAddr, affiliateShareBase);
                 players[0] = affiliateAddr;
                 amounts[0] = affiliateShareBase + questReward;
     
                 // Upline tier 1 (20% of scaled amount)
                 address upline = _referrerAddress(affiliateAddr);
                 uint256 baseBonus = scaledAmount / 5;
                 uint256 questRewardUpline = coin.affiliateQuestReward(upline, baseBonus);
                 players[1] = upline;
                 amounts[1] = baseBonus + questRewardUpline;
     
                 // Upline tier 2 (20% of tier 1 = 4% of original)
                 address upline2 = _referrerAddress(upline);
                 uint256 bonus2 = scaledAmount / 25;
                 uint256 questReward2 = coin.affiliateQuestReward(upline2, bonus2);
                 players[2] = upline2;
                 amounts[2] = bonus2 + questReward2;
     
                 // Roll weighted winner and pay combined amount.
                 // Preserves each recipient's EV: P(win_i) = amount_i / totalAmount.
                 uint256 totalAmount = amounts[0] + amounts[1] + amounts[2];
                 if (totalAmount != 0) {
                     address winner = _rollWeightedAffiliateWinner(
                         players,
                         amounts,
                         3,
                         totalAmount,
                         sender,
                         storedCode
                     );
                     // Don't pay the buyer from their own purchase
                     if (winner != sender) {
                         _routeAffiliateReward(winner, totalAmount);
                     }
                 }
             }
     
             emit Affiliate(amount, storedCode, sender);
             return playerKickback;

358:      * @notice Process affiliate rewards for a purchase or gameplay action.
          * @dev Core payout logic. Handles referral resolution, reward scaling,
          *      and multi-tier distribution.
          *
      * ACCESS: coin or game only.
          *
          * REWARD FLOW:
          * +--------------------------------------------------------------------+
          * | 1. Resolve referral code (stored or provided)                      |
          * | 2. Apply reward percentage based on ETH type and level             |
          * | 3. Update leaderboard (full untapered amount)                      |
          * | 4. Apply lootbox activity taper if applicable                      |
          * | 5. Calculate kickback (returned to caller for player credit)       |
          * | 6. Pay direct affiliate (base - kickback)                          |
          * | 7. Pay upline1 (20% of scaled amount)                              |
          * | 8. Pay upline2 (20% of upline1 share = 4%)                         |
          * | 9. Quest rewards added on top                                     |
          * +--------------------------------------------------------------------+
          *
          * REWARD RATES:
          * - Fresh ETH (levels 0-3): 25% (REWARD_SCALE_FRESH_L1_3_BPS = 2500)
          * - Fresh ETH (levels 4+): 20% (REWARD_SCALE_FRESH_L4P_BPS = 2000)
          * - Recycled ETH (all levels): 5% (REWARD_SCALE_RECYCLED_BPS = 500)
          *
          * LOOTBOX TAPER (fresh ETH only):
          * - Activity score < 10,000: no taper (100% payout)
          * - Activity score 10,000-25,500: linear taper from 100% to 25%
          * - Activity score >= 25,500: 25% payout floor (LOOTBOX_TAPER_MIN_BPS = 2500)
          * - Leaderboard tracking always uses full untapered amount.
          *
          * @param amount Base reward amount (18 decimals).
          * @param code Affiliate code provided with the transaction (may be bytes32(0)).
          * @param sender The player making the purchase.
          * @param lvl Current game level (for join tracking and leaderboard).
          * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
          * @param lootboxActivityScore Buyer's activity score for lootbox taper (0 = no taper; 10000+ triggers linear taper to 25% floor at 25500).
          * @return playerKickback Amount of kickback to credit to the player (caller handles minting and batching).
          */
         function payAffiliate(
             uint256 amount,
             bytes32 code,
             address sender,
             uint24 lvl,
             bool isFreshEth,
             uint16 lootboxActivityScore
         ) external returns (uint256 playerKickback) {
             // -----------------------------------------------------------------
             // ACCESS CONTROL
             // -----------------------------------------------------------------
             // SECURITY: Only trusted contracts can distribute affiliate rewards.
             if (
                 msg.sender != ContractAddresses.COIN &&
                 msg.sender != ContractAddresses.GAME
             ) revert OnlyAuthorized();
     
             // -----------------------------------------------------------------
             // REFERRAL RESOLUTION
             // -----------------------------------------------------------------
             bytes32 storedCode = playerReferralCode[sender];
             AffiliateCodeInfo memory info;
             bool infoSet;
             bool noReferrer;
             AffiliateCodeInfo memory vaultInfo = AffiliateCodeInfo({
                 owner: ContractAddresses.VAULT,
                 kickback: 0
             });
     
             if (storedCode == bytes32(0)) {
                 // No stored code - resolve provided code or default to VAULT.
                 if (code == bytes32(0)) {
                     // Blank referral: lock to VAULT as default.
                     _setReferralCode(sender, REF_CODE_LOCKED);
                     storedCode = AFFILIATE_CODE_VAULT;
                     info = vaultInfo;
                     noReferrer = true;
                 } else {
                     // Try custom code first, then default (address-derived) code.
                     address resolved = _resolveCodeOwner(code);
                     if (resolved == address(0) || resolved == sender) {
                         // Invalid/self-referral: lock to VAULT as default.
                         _setReferralCode(sender, REF_CODE_LOCKED);
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Valid code (custom or default): store it permanently.
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             // Default code: 0% kickback.
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                     }
                 }
                 infoSet = true;
             } else {
                 if (code != bytes32(0) && code != storedCode && _vaultReferralMutable(storedCode)) {
                     address resolved = _resolveCodeOwner(code);
                     if (resolved != address(0) && resolved != sender) {
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                         infoSet = true;
                     }
                 }
                 if (!infoSet) {
                     if (storedCode == REF_CODE_LOCKED) {
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Use the stored code (custom or default).
                         AffiliateCodeInfo storage customInfo = affiliateCode[storedCode];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: _resolveCodeOwner(storedCode), kickback: 0 });
                         }
                     }
                 }
             }
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION SETUP
             // -----------------------------------------------------------------
             address affiliateAddr = info.owner;
             uint8 kickbackPct = info.kickback;
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION
             // -----------------------------------------------------------------
             mapping(address => uint256) storage earned = affiliateCoinEarned[lvl];
     
             // Apply reward percentage based on ETH type and level.
             // - Fresh ETH (levels 0-3): 25%
             // - Fresh ETH (levels 4+): 20%
             // - Recycled ETH: 5%
             uint256 rewardScaleBps;
             if (isFreshEth) {
                 // Fresh ETH: 25% for first 4 levels (0-3), 20% for levels 4+
                 rewardScaleBps = lvl <= 3
                     ? REWARD_SCALE_FRESH_L1_3_BPS
                     : REWARD_SCALE_FRESH_L4P_BPS;
             } else {
                 // Recycled ETH: 5%
                 rewardScaleBps = REWARD_SCALE_RECYCLED_BPS;
             }
             uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
             if (scaledAmount == 0) {
                 emit Affiliate(amount, storedCode, sender);
                 return 0;
             }

358:      * @notice Process affiliate rewards for a purchase or gameplay action.
          * @dev Core payout logic. Handles referral resolution, reward scaling,
          *      and multi-tier distribution.
          *
      * ACCESS: coin or game only.
          *
          * REWARD FLOW:
          * +--------------------------------------------------------------------+
          * | 1. Resolve referral code (stored or provided)                      |
          * | 2. Apply reward percentage based on ETH type and level             |
          * | 3. Update leaderboard (full untapered amount)                      |
          * | 4. Apply lootbox activity taper if applicable                      |
          * | 5. Calculate kickback (returned to caller for player credit)       |
          * | 6. Pay direct affiliate (base - kickback)                          |
          * | 7. Pay upline1 (20% of scaled amount)                              |
          * | 8. Pay upline2 (20% of upline1 share = 4%)                         |
          * | 9. Quest rewards added on top                                     |
          * +--------------------------------------------------------------------+
          *
          * REWARD RATES:
          * - Fresh ETH (levels 0-3): 25% (REWARD_SCALE_FRESH_L1_3_BPS = 2500)
          * - Fresh ETH (levels 4+): 20% (REWARD_SCALE_FRESH_L4P_BPS = 2000)
          * - Recycled ETH (all levels): 5% (REWARD_SCALE_RECYCLED_BPS = 500)
          *
          * LOOTBOX TAPER (fresh ETH only):
          * - Activity score < 10,000: no taper (100% payout)
          * - Activity score 10,000-25,500: linear taper from 100% to 25%
          * - Activity score >= 25,500: 25% payout floor (LOOTBOX_TAPER_MIN_BPS = 2500)
          * - Leaderboard tracking always uses full untapered amount.
          *
          * @param amount Base reward amount (18 decimals).
          * @param code Affiliate code provided with the transaction (may be bytes32(0)).
          * @param sender The player making the purchase.
          * @param lvl Current game level (for join tracking and leaderboard).
          * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
          * @param lootboxActivityScore Buyer's activity score for lootbox taper (0 = no taper; 10000+ triggers linear taper to 25% floor at 25500).
          * @return playerKickback Amount of kickback to credit to the player (caller handles minting and batching).
          */
         function payAffiliate(
             uint256 amount,
             bytes32 code,
             address sender,
             uint24 lvl,
             bool isFreshEth,
             uint16 lootboxActivityScore
         ) external returns (uint256 playerKickback) {
             // -----------------------------------------------------------------
             // ACCESS CONTROL
             // -----------------------------------------------------------------
             // SECURITY: Only trusted contracts can distribute affiliate rewards.
             if (
                 msg.sender != ContractAddresses.COIN &&
                 msg.sender != ContractAddresses.GAME
             ) revert OnlyAuthorized();
     
             // -----------------------------------------------------------------
             // REFERRAL RESOLUTION
             // -----------------------------------------------------------------
             bytes32 storedCode = playerReferralCode[sender];
             AffiliateCodeInfo memory info;
             bool infoSet;
             bool noReferrer;
             AffiliateCodeInfo memory vaultInfo = AffiliateCodeInfo({
                 owner: ContractAddresses.VAULT,
                 kickback: 0
             });
     
             if (storedCode == bytes32(0)) {
                 // No stored code - resolve provided code or default to VAULT.
                 if (code == bytes32(0)) {
                     // Blank referral: lock to VAULT as default.
                     _setReferralCode(sender, REF_CODE_LOCKED);
                     storedCode = AFFILIATE_CODE_VAULT;
                     info = vaultInfo;
                     noReferrer = true;
                 } else {
                     // Try custom code first, then default (address-derived) code.
                     address resolved = _resolveCodeOwner(code);
                     if (resolved == address(0) || resolved == sender) {
                         // Invalid/self-referral: lock to VAULT as default.
                         _setReferralCode(sender, REF_CODE_LOCKED);
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Valid code (custom or default): store it permanently.
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             // Default code: 0% kickback.
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                     }
                 }
                 infoSet = true;
             } else {
                 if (code != bytes32(0) && code != storedCode && _vaultReferralMutable(storedCode)) {
                     address resolved = _resolveCodeOwner(code);
                     if (resolved != address(0) && resolved != sender) {
                         _setReferralCode(sender, code);
                         AffiliateCodeInfo storage customInfo = affiliateCode[code];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: resolved, kickback: 0 });
                         }
                         storedCode = code;
                         infoSet = true;
                     }
                 }
                 if (!infoSet) {
                     if (storedCode == REF_CODE_LOCKED) {
                         storedCode = AFFILIATE_CODE_VAULT;
                         info = vaultInfo;
                         noReferrer = true;
                     } else {
                         // Use the stored code (custom or default).
                         AffiliateCodeInfo storage customInfo = affiliateCode[storedCode];
                         if (customInfo.owner != address(0)) {
                             info = customInfo;
                         } else {
                             info = AffiliateCodeInfo({ owner: _resolveCodeOwner(storedCode), kickback: 0 });
                         }
                     }
                 }
             }
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION SETUP
             // -----------------------------------------------------------------
             address affiliateAddr = info.owner;
             uint8 kickbackPct = info.kickback;
     
             // -----------------------------------------------------------------
             // REWARD CALCULATION
             // -----------------------------------------------------------------
             mapping(address => uint256) storage earned = affiliateCoinEarned[lvl];
     
             // Apply reward percentage based on ETH type and level.
             // - Fresh ETH (levels 0-3): 25%
             // - Fresh ETH (levels 4+): 20%
             // - Recycled ETH: 5%
             uint256 rewardScaleBps;
             if (isFreshEth) {
                 // Fresh ETH: 25% for first 4 levels (0-3), 20% for levels 4+
                 rewardScaleBps = lvl <= 3
                     ? REWARD_SCALE_FRESH_L1_3_BPS
                     : REWARD_SCALE_FRESH_L4P_BPS;
             } else {
                 // Recycled ETH: 5%
                 rewardScaleBps = REWARD_SCALE_RECYCLED_BPS;
             }
             uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
             if (scaledAmount == 0) {
                 emit Affiliate(amount, storedCode, sender);
                 return 0;
             }
     
             // -----------------------------------------------------------------
             // PER-REFERRER COMMISSION CAP
             // -----------------------------------------------------------------
             // Cap commission from any single sender to 0.5 ETH BURNIE per level.
             // This prevents a single whale from dominating an affiliate's earnings.
             {
                 uint256 alreadyEarned = affiliateCommissionFromSender[lvl][affiliateAddr][sender];
                 if (alreadyEarned >= MAX_COMMISSION_PER_REFERRER_PER_LEVEL) {
                     // Cap fully reached - no more commission from this sender this level.
                     emit Affiliate(amount, storedCode, sender);
                     return 0;
                 }

648:      * @notice Get the top affiliate for a given game level.
          * @dev Returns the affiliate with the highest earnings for that level.
          *      Used for trophies and jackpot affiliate selection.
          * @param lvl The game level to query.
          * @return player Address of the top affiliate.
          * @return score Their score in BURNIE base units (18 decimals).
          */
         function affiliateTop(uint24 lvl) external view returns (address player, uint96 score) {
             PlayerScore memory stored = affiliateTopByLevel[lvl];
             return (stored.player, stored.score);

661:      * @notice Get an affiliate's base earnings score for a level.
          * @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
          * @param lvl The game level to query.
          * @param player The affiliate address to query.
          * @return score The base affiliate score (18 decimals).
          */
         function affiliateScore(uint24 lvl, address player) external view returns (uint256 score) {
             return affiliateCoinEarned[lvl][player];

672:      * @notice Get the total affiliate score across all affiliates for a level.
          * @dev Sum of all affiliateCoinEarned for this level. Used as the exact
          *      denominator for score-proportional DGNRS claim distribution.
          * @param lvl The game level to query.
          * @return total The total affiliate score (18 decimals).
          */
         function totalAffiliateScore(uint24 lvl) external view returns (uint256 total) {
             return _totalAffiliateScore[lvl];

683:      * @notice Calculate the affiliate bonus points for a player.
          * @dev Sums the player's affiliate scores for the previous 5 levels.
          *      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
          *
          * @param currLevel The current game level.
          * @param player The player to calculate bonus for.
          * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
          */
         function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
             if (player == address(0) || currLevel == 0) return 0;
             uint256 sum;
             unchecked {
                 for (uint8 offset = 1; offset <= 5; ) {
                     if (currLevel <= offset) break;
                     uint24 lvl = currLevel - offset;
                     sum += affiliateCoinEarned[lvl][player];
                     ++offset;
                 }
             }
     
             if (sum == 0) return 0;
             uint256 ethUnit = 1 ether;
             points = sum / ethUnit;
             return points > AFFILIATE_BONUS_MAX ? AFFILIATE_BONUS_MAX : points;

683:      * @notice Calculate the affiliate bonus points for a player.
          * @dev Sums the player's affiliate scores for the previous 5 levels.
          *      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
          *
          * @param currLevel The current game level.
          * @param player The player to calculate bonus for.
          * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
          */
         function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
             if (player == address(0) || currLevel == 0) return 0;
             uint256 sum;

683:      * @notice Calculate the affiliate bonus points for a player.
          * @dev Sums the player's affiliate scores for the previous 5 levels.
          *      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
          *
          * @param currLevel The current game level.
          * @param player The player to calculate bonus for.
          * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
          */
         function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
             if (player == address(0) || currLevel == 0) return 0;
             uint256 sum;
             unchecked {
                 for (uint8 offset = 1; offset <= 5; ) {
                     if (currLevel <= offset) break;
                     uint24 lvl = currLevel - offset;
                     sum += affiliateCoinEarned[lvl][player];
                     ++offset;
                 }
             }
     
             if (sum == 0) return 0;
             uint256 ethUnit = 1 ether;

846:     /// @dev Select one recipient with probability proportional to their amount.
         function _rollWeightedAffiliateWinner(
             address[3] memory players,
             uint256[3] memory amounts,
             uint256 count,
             uint256 totalAmount,
             address sender,
             bytes32 storedCode
         ) private view returns (address winner) {
             uint48 currentDay = GameTimeLib.currentDayIndex();
     
             uint256 entropy = uint256(
                 keccak256(
                     abi.encodePacked(
                         AFFILIATE_ROLL_TAG,
                         currentDay,
                         sender,
                         storedCode
                     )
                 )
             );
             uint256 roll = entropy % totalAmount;
     
             uint256 running;
             for (uint256 i; i < count; ) {
                 running += amounts[i];
                 if (roll < running) return players[i];
                 unchecked {
                     ++i;
                 }
             }
             // Should be unreachable for totalAmount > 0, but keep deterministic fallback.
             return players[0];
         }
     }

846:     /// @dev Select one recipient with probability proportional to their amount.
         function _rollWeightedAffiliateWinner(
             address[3] memory players,
             uint256[3] memory amounts,
             uint256 count,
             uint256 totalAmount,
             address sender,
             bytes32 storedCode
         ) private view returns (address winner) {
             uint48 currentDay = GameTimeLib.currentDayIndex();
     
             uint256 entropy = uint256(
                 keccak256(
                     abi.encodePacked(
                         AFFILIATE_ROLL_TAG,
                         currentDay,
                         sender,
                         storedCode
                     )
                 )
             );
             uint256 roll = entropy % totalAmount;
     
             uint256 running;
             for (uint256 i; i < count; ) {
                 running += amounts[i];
                 if (roll < running) return players[i];
                 unchecked {

```

```solidity
File: DegenerusDeityPass.sol

121:     /// @notice Read active render colors.
         function renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor) {
             return (_outlineColor, _backgroundColor, _nonCryptoSymbolColor);

217:     function _tryRenderExternal(
             uint256 tokenId,
             uint8 quadrant,
             uint8 symbolIdx,
             string memory symbolName,
             string memory iconPath,
             bool isCrypto
         ) private view returns (bool ok, string memory svg) {
             try IDeityPassRendererV1(renderer).render(
                 tokenId,
                 quadrant,
                 symbolIdx,
                 symbolName,
                 iconPath,
                 isCrypto,
                 _outlineColor,
                 _backgroundColor,
                 _nonCryptoSymbolColor
             ) returns (string memory out) {
                 if (bytes(out).length == 0) return (false, "");
                 return (true, out);

217:     function _tryRenderExternal(
             uint256 tokenId,
             uint8 quadrant,
             uint8 symbolIdx,
             string memory symbolName,
             string memory iconPath,
             bool isCrypto
         ) private view returns (bool ok, string memory svg) {
             try IDeityPassRendererV1(renderer).render(
                 tokenId,
                 quadrant,
                 symbolIdx,
                 symbolName,
                 iconPath,
                 isCrypto,
                 _outlineColor,
                 _backgroundColor,
                 _nonCryptoSymbolColor
             ) returns (string memory out) {
                 if (bytes(out).length == 0) return (false, "");
                 return (true, out);
             } catch {
                 return (false, "");

217:     function _tryRenderExternal(
             uint256 tokenId,
             uint8 quadrant,
             uint8 symbolIdx,
             string memory symbolName,
             string memory iconPath,
             bool isCrypto
         ) private view returns (bool ok, string memory svg) {
             try IDeityPassRendererV1(renderer).render(
                 tokenId,
                 quadrant,
                 symbolIdx,
                 symbolName,
                 iconPath,
                 isCrypto,
                 _outlineColor,
                 _backgroundColor,
                 _nonCryptoSymbolColor
             ) returns (string memory out) {
                 if (bytes(out).length == 0) return (false, "");

```

```solidity
File: DegenerusGame.sol

474:     /// @notice Check if an operator is approved to act for a player.
         /// @param owner The player who granted approval.
         /// @param operator The operator address.
         /// @return approved True if operator is approved.
         function isOperatorApproved(
             address owner,
             address operator
         ) external view returns (bool approved) {
             return operatorApprovals[owner][operator];
         }
     
         function _requireApproved(address player) private view {

493:     ) private view returns (address resolved) {
             if (player == address(0)) return msg.sender;
             if (player != msg.sender) _requireApproved(player);
             return player;
         }
     
         /*+======================================================================+

493:     ) private view returns (address resolved) {
             if (player == address(0)) return msg.sender;
             if (player != msg.sender) _requireApproved(player);

792:     /// @notice Consume coinflip boon for next coinflip stake bonus.
         /// @dev Access: COIN or COINFLIP contract only.
         /// @param player The player whose boon to consume.
         /// @return boostBps The boost in basis points to apply.
         /// @custom:reverts E If caller is not COIN or COINFLIP contract.
         function consumeCoinflipBoon(
             address player
         ) external returns (uint16 boostBps) {
             if (
                 msg.sender != ContractAddresses.COIN &&
                 msg.sender != ContractAddresses.COINFLIP
             ) revert E();
             (bool ok, bytes memory data) = ContractAddresses
                 .GAME_BOON_MODULE
                 .delegatecall(
                     abi.encodeWithSelector(
                         IDegenerusGameBoonModule.consumeCoinflipBoon.selector,
                         player
                     )
                 );
             if (!ok) _revertDelegate(data);
             return abi.decode(data, (uint16));
         }
     
         /// @notice Consume decimator boon for burn bonus.

817:     /// @dev Access: COIN contract only.
         /// @param player The player whose boon to consume.
         /// @return boostBps The boost in basis points to apply.
         /// @custom:reverts E If caller is not COIN contract.
         function consumeDecimatorBoon(
             address player
         ) external returns (uint16 boostBps) {
             if (msg.sender != ContractAddresses.COIN) revert E();
             (bool ok, bytes memory data) = ContractAddresses
                 .GAME_BOON_MODULE
                 .delegatecall(
                     abi.encodeWithSelector(
                         IDegenerusGameBoonModule.consumeDecimatorBoost.selector,
                         player
                     )
                 );
             if (!ok) _revertDelegate(data);
             return abi.decode(data, (uint16));
         }
     
         /// @notice Consume purchase boost for purchase bonus.

837:     /// @notice Consume purchase boost for purchase bonus.
         /// @dev Access: self-call only (from delegate modules).
         /// @param player The player whose boost to consume.
         /// @return boostBps The boost in basis points to apply.
         /// @custom:reverts E If caller is not self-call context.
         function consumePurchaseBoost(
             address player
         ) external returns (uint16 boostBps) {
             if (msg.sender != address(this)) revert E();
             (bool ok, bytes memory data) = ContractAddresses
                 .GAME_BOON_MODULE
                 .delegatecall(
                     abi.encodeWithSelector(
                         IDegenerusGameBoonModule.consumePurchaseBoost.selector,
                         player
                     )
                 );
             if (!ok) _revertDelegate(data);
             return abi.decode(data, (uint16));
         }
     
         /// @notice Get raw deity boon state for off-chain or viewer contract computation.

1056:     /// @dev Access: COIN contract only (enforced in module).
          /// @param player Address of the player.
          /// @param lvl Current game level.
          /// @param bucket Player's chosen denominator (2-12).
          /// @param baseAmount Burn amount before multiplier.
          /// @param multBps Multiplier in basis points (10000 = 1x).
          /// @return bucketUsed The bucket actually used (may differ from requested if not an improvement).
          function recordDecBurn(
              address player,
              uint24 lvl,
              uint8 bucket,
              uint256 baseAmount,
              uint256 multBps
          ) external returns (uint8 bucketUsed) {
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_DECIMATOR_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameDecimatorModule.recordDecBurn.selector,
                          player,
                          lvl,
                          bucket,
                          baseAmount,
                          multBps
                      )
                  );
              if (!ok) _revertDelegate(data);
              if (data.length == 0) revert E();
              return abi.decode(data, (uint8));
          }
      
          /// @notice Snapshot Decimator jackpot winners for deferred claims.

1088:     /// @dev Access: Game-only (self-call).
          /// @param poolWei Total ETH prize pool for this level.
          /// @param lvl Level number being resolved.
          /// @param rngWord VRF-derived randomness seed.
          /// @return returnAmountWei Amount to return (non-zero if no winners or already snapshotted).
          function runDecimatorJackpot(
              uint256 poolWei,
              uint24 lvl,
              uint256 rngWord
          ) external returns (uint256 returnAmountWei) {
              if (msg.sender != address(this)) revert E();
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_DECIMATOR_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameDecimatorModule.runDecimatorJackpot.selector,
                          poolWei,
                          lvl,
                          rngWord
                      )
                  );
              if (!ok) _revertDelegate(data);
              if (data.length == 0) revert E();
              return abi.decode(data, (uint256));
          }
      
          // -------------------------------------------------------------------------

1139:     /// @dev Access: Game-only (self-call from handleGameOverDrain).
          function runTerminalDecimatorJackpot(
              uint256 poolWei,
              uint24 lvl,
              uint256 rngWord
          ) external returns (uint256 returnAmountWei) {
              if (msg.sender != address(this)) revert E();
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_DECIMATOR_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameDecimatorModule.runTerminalDecimatorJackpot.selector,
                          poolWei,
                          lvl,
                          rngWord
                      )
                  );
              if (!ok) _revertDelegate(data);
              if (data.length == 0) revert E();
              return abi.decode(data, (uint256));
          }
      
          /// @notice Terminal decimator window. Always open except lastPurchaseDay and gameOver.

1169:     /// @notice Terminal jackpot for x00 levels: Day-5-style bucket distribution.
          /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule.
          ///      Updates claimablePool internally — callers must NOT double-count.
          /// @param poolWei Total ETH to distribute.
          /// @param targetLvl Level to sample winners from.
          /// @param rngWord VRF entropy seed.
          /// @return paidWei Total ETH distributed.
          function runTerminalJackpot(
              uint256 poolWei,
              uint24 targetLvl,
              uint256 rngWord
          ) external returns (uint256 paidWei) {
              if (msg.sender != address(this)) revert E();
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_JACKPOT_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameJackpotModule.runTerminalJackpot.selector,
                          poolWei,
                          targetLvl,
                          rngWord
                      )
                  );
              if (!ok) _revertDelegate(data);
              if (data.length == 0) revert E();
              return abi.decode(data, (uint256));
          }
      
          /// @notice Consume Decimator claim on behalf of player.

1198:     /// @dev Access: Game-only (self-call).
          /// @param player Address to claim for.
          /// @param lvl Level to claim from.
          /// @return amountWei Pro-rata payout amount.
          function consumeDecClaim(
              address player,
              uint24 lvl
          ) external returns (uint256 amountWei) {
              if (msg.sender != address(this)) revert E();
              (bool ok, bytes memory data) = ContractAddresses
                  .GAME_DECIMATOR_MODULE
                  .delegatecall(
                      abi.encodeWithSelector(
                          IDegenerusGameDecimatorModule.consumeDecClaim.selector,
                          player,
                          lvl
                      )
                  );
              if (!ok) _revertDelegate(data);
              if (data.length == 0) revert E();
              return abi.decode(data, (uint256));
          }
      
          /// @notice Claim Decimator jackpot for caller.

1238:     /// @param player Address to check.
          /// @param lvl Level to check.
          /// @return amountWei Claimable amount (0 if not winner or already claimed).
          /// @return winner True if player is a winner for this level.
          function decClaimable(
              address player,
              uint24 lvl
          ) external view returns (uint256 amountWei, bool winner) {
              DecClaimRound storage round = decClaimRounds[lvl];
              if (round.poolWei == 0) {
                  return (0, false);
              }
      
              uint256 totalBurn = uint256(round.totalBurn);
              if (totalBurn == 0) return (0, false);
      
              DecEntry storage e = decBurn[lvl][player];
              if (e.claimed != 0) return (0, false);

1238:     /// @param player Address to check.
          /// @param lvl Level to check.
          /// @return amountWei Claimable amount (0 if not winner or already claimed).
          /// @return winner True if player is a winner for this level.
          function decClaimable(
              address player,
              uint24 lvl
          ) external view returns (uint256 amountWei, bool winner) {
              DecClaimRound storage round = decClaimRounds[lvl];
              if (round.poolWei == 0) {
                  return (0, false);
              }
      
              uint256 totalBurn = uint256(round.totalBurn);
              if (totalBurn == 0) return (0, false);
      
              DecEntry storage e = decBurn[lvl][player];
              if (e.claimed != 0) return (0, false);
      
              uint8 denom = e.bucket;
              uint8 sub = e.subBucket;

1238:     /// @param player Address to check.
          /// @param lvl Level to check.
          /// @return amountWei Claimable amount (0 if not winner or already claimed).
          /// @return winner True if player is a winner for this level.
          function decClaimable(
              address player,
              uint24 lvl
          ) external view returns (uint256 amountWei, bool winner) {
              DecClaimRound storage round = decClaimRounds[lvl];
              if (round.poolWei == 0) {
                  return (0, false);
              }
      
              uint256 totalBurn = uint256(round.totalBurn);
              if (totalBurn == 0) return (0, false);
      
              DecEntry storage e = decBurn[lvl][player];
              if (e.claimed != 0) return (0, false);
      
              uint8 denom = e.bucket;
              uint8 sub = e.subBucket;
              uint192 entryBurn = e.burn;
              if (denom == 0 || entryBurn == 0) return (0, false);
      
              uint64 packedOffsets = decBucketOffsetPacked[lvl];

1238:     /// @param player Address to check.
          /// @param lvl Level to check.
          /// @return amountWei Claimable amount (0 if not winner or already claimed).
          /// @return winner True if player is a winner for this level.
          function decClaimable(
              address player,
              uint24 lvl
          ) external view returns (uint256 amountWei, bool winner) {
              DecClaimRound storage round = decClaimRounds[lvl];
              if (round.poolWei == 0) {
                  return (0, false);
              }
      
              uint256 totalBurn = uint256(round.totalBurn);
              if (totalBurn == 0) return (0, false);
      
              DecEntry storage e = decBurn[lvl][player];
              if (e.claimed != 0) return (0, false);
      
              uint8 denom = e.bucket;
              uint8 sub = e.subBucket;
              uint192 entryBurn = e.burn;
              if (denom == 0 || entryBurn == 0) return (0, false);
      
              uint64 packedOffsets = decBucketOffsetPacked[lvl];
              uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, denom);
              if (sub != winningSub) return (0, false);
      
              amountWei =
                  (round.poolWei * uint256(entryBurn)) /

1238:     /// @param player Address to check.
          /// @param lvl Level to check.
          /// @return amountWei Claimable amount (0 if not winner or already claimed).
          /// @return winner True if player is a winner for this level.
          function decClaimable(
              address player,
              uint24 lvl
          ) external view returns (uint256 amountWei, bool winner) {
              DecClaimRound storage round = decClaimRounds[lvl];
              if (round.poolWei == 0) {
                  return (0, false);
              }
      
              uint256 totalBurn = uint256(round.totalBurn);

1516:     /// @param player Player address to check.
          /// @return enabled True if auto-rebuy is enabled for this player.
          function autoRebuyEnabledFor(
              address player
          ) external view returns (bool enabled) {
              return autoRebuyState[player].autoRebuyEnabled;
          }
      
          /// @notice Check if decimator auto-rebuy is enabled for a player.

1525:     /// @param player Player address to check.
          /// @return enabled True if decimator auto-rebuy is enabled for this player.
          function decimatorAutoRebuyEnabledFor(
              address player
          ) external view returns (bool enabled) {
              return !decimatorAutoRebuyDisabled[player];
          }
      
          /// @notice Check the auto-rebuy take profit for a player.

1534:     /// @param player Player address to check.
          /// @return takeProfit Amount reserved as complete multiples (wei).
          function autoRebuyTakeProfitFor(
              address player
          ) external view returns (uint256 takeProfit) {
              return autoRebuyState[player].takeProfit;
          }
      
          /// @notice Enable or disable afKing mode.
          /// @dev Enabling afKing forces auto-rebuy on for ETH and coin and clamps take profit

1626:     /// @param player Player address to check.
          /// @return active True if afKing mode is active.
          function afKingModeFor(address player) external view returns (bool active) {
              return autoRebuyState[player].afKingMode;
          }
      
          /// @notice Get the level when afKing mode was activated for a player.

1633:     /// @param player Player address to check.
          /// @return activationLevel Level at which afKing mode was enabled (0 if inactive).
          function afKingActivatedLevelFor(
              address player
          ) external view returns (uint24 activationLevel) {
              return autoRebuyState[player].afKingActivatedLevel;
          }
      
          /// @notice Deactivate afKing mode for a player (coin/coinflip hook).

1654:     /// @dev Access: COINFLIP contract only.
          /// @param player Player to sync.
          /// @return active True if afKing remains active after sync.
          /// @custom:reverts E If caller is not COINFLIP contract.
          function syncAfKingLazyPassFromCoin(
              address player
          ) external returns (bool active) {
              if (msg.sender != ContractAddresses.COINFLIP) revert E();
              AutoRebuyState storage state = autoRebuyState[player];
              if (!state.afKingMode) return false;
              if (_hasAnyLazyPass(player)) return true;
      
              // Note: settle not called here - it's already being called by the coinflip
              // operation that triggered this sync (deposit/claim calls _syncAfKingLazyPass)
              state.afKingMode = false;
              state.afKingActivatedLevel = 0;
              emit AfKingModeToggled(player, false);
              return false;
          }
      
          function _deactivateAfKing(address player) private {
              AutoRebuyState storage state = autoRebuyState[player];

1654:     /// @dev Access: COINFLIP contract only.
          /// @param player Player to sync.
          /// @return active True if afKing remains active after sync.
          /// @custom:reverts E If caller is not COINFLIP contract.
          function syncAfKingLazyPassFromCoin(
              address player
          ) external returns (bool active) {
              if (msg.sender != ContractAddresses.COINFLIP) revert E();
              AutoRebuyState storage state = autoRebuyState[player];
              if (!state.afKingMode) return false;
              if (_hasAnyLazyPass(player)) return true;
      
              // Note: settle not called here - it's already being called by the coinflip

2085:     /// @param betId Bet identifier for the player.
          function degeneretteBetInfo(
              address player,
              uint64 betId
          ) external view returns (uint256 packed) {
              return degeneretteBets[player][betId];
          }
      
          /// @notice Check whether lootbox presale mode is currently active.
          /// @return active True if presale is active.

2095:     function lootboxPresaleActiveFlag() external view returns (bool active) {
              return lootboxPresaleActive;
          }
      
          /// @notice Get the current lootbox RNG index for new purchases.
          /// @return index The current lootbox RNG index (1-based).

2100:     /// @return index The current lootbox RNG index (1-based).
          function lootboxRngIndexView() external view returns (uint48 index) {
              return lootboxRngIndex;
          }
      
          /// @notice Get the VRF random word for a lootbox RNG index.
          /// @param lootboxIndex Lootbox RNG index to query.

2107:     /// @return word VRF word (0 if not ready).
          function lootboxRngWord(
              uint48 lootboxIndex
          ) external view returns (uint256 word) {
              return lootboxRngWordByIndex[lootboxIndex];
          }
      
          /// @notice Get the lootbox RNG request threshold (wei).
          /// @return threshold The ETH threshold that triggers a lootbox RNG request.

2115:     /// @return threshold The ETH threshold that triggers a lootbox RNG request.
          function lootboxRngThresholdView()
              external
              view
              returns (uint256 threshold)
          {
              return lootboxRngThreshold;
          }
      
          /// @notice Get minimum LINK balance required for manual lootbox RNG rolls.
          /// @return minBalance The minimum LINK balance required.

2125:     /// @return minBalance The minimum LINK balance required.
          function lootboxRngMinLinkBalanceView()
              external
              view
              returns (uint256 minBalance)
          {
              return lootboxRngMinLinkBalance;
          }
      
          /// @notice Get the current prize pool (jackpots are paid from this).
          /// @return The currentPrizePool value (ETH wei).

2264:     /// @return open True if decimator window flag is set or gameover is imminent.
          function decWindowOpenFlag() external view returns (bool open) {
              return decWindowOpen || _isGameoverImminent();
          }
      
          /// @notice Jackpot compression tier: 0=normal, 1=compressed (3d), 2=turbo (1d).

2373:     /// @dev Batches multiple stats into single call for gas efficiency.
          /// @param player The player address to query.
          /// @return lvl Current game level.
          /// @return levelCount Total levels with ETH mints.
          /// @return streak Consecutive level mint streak.
          function ethMintStats(
              address player
          ) external view returns (uint24 lvl, uint24 levelCount, uint24 streak) {
              if (deityPassCount[player] != 0) {
                  uint24 currLevel = level;
                  return (currLevel, currLevel, currLevel);
              }
              uint256 packed = mintPacked_[player];
              lvl = level;
              levelCount = uint24(

2411:     /// @dev Activity Score: 50% (streak) + 25% (count) + 100% (quest) + 50% (affiliate) + 40% (whale) = 265% max
          ///      Deity pass adds +80% in place of whale bundle bonus (305% max base).
          ///      Consumers apply their own caps (lootbox EV: 255%, degenerette ROI: 305%, decimator: 235%).
          /// @param player The player address to calculate for.
          /// @return scoreBps Total activity score in basis points.
          function playerActivityScore(
              address player
          ) external view returns (uint256 scoreBps) {
              return _playerActivityScore(player);
          }
      
          function _playerActivityScore(
              address player
          ) internal view returns (uint256 scoreBps) {

2425:         if (player == address(0)) return 0;
      
              bool hasDeityPass = deityPassCount[player] != 0;
              uint256 packed = mintPacked_[player];
              uint24 levelCount = uint24(

2578:     function deityPassTotalIssuedCount() external view returns (uint32 count) {
              return uint32(deityPassOwners.length);
          }
      
          /*+======================================================================+
            |                    TRAIT TICKET SAMPLING                             |

2590:     /// @dev Samples from last 20 levels. Uses entropy to select level, trait, and offset.
          ///      Returns empty array if no tickets exist for selected level/trait.
          /// @param entropy Random seed (typically VRF word) for selection.
          /// @return lvlSel Selected level.
          /// @return traitSel Selected trait ID.
          /// @return tickets Array of up to 4 ticket holder addresses.
          function sampleTraitTickets(
              uint256 entropy
          )
              external
              view
              returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)
          {
              uint24 currentLvl = level;
              if (currentLvl <= 1) {
                  return (0, 0, new address[](0));
              }
      
              uint24 maxOffset = currentLvl - 1;
              if (maxOffset > 20) maxOffset = 20;
      
              uint256 word = entropy;

2590:     /// @dev Samples from last 20 levels. Uses entropy to select level, trait, and offset.
          ///      Returns empty array if no tickets exist for selected level/trait.
          /// @param entropy Random seed (typically VRF word) for selection.
          /// @return lvlSel Selected level.
          /// @return traitSel Selected trait ID.
          /// @return tickets Array of up to 4 ticket holder addresses.
          function sampleTraitTickets(
              uint256 entropy
          )
              external
              view
              returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)
          {
              uint24 currentLvl = level;
              if (currentLvl <= 1) {
                  return (0, 0, new address[](0));
              }
      
              uint24 maxOffset = currentLvl - 1;
              if (maxOffset > 20) maxOffset = 20;
      
              uint256 word = entropy;
              uint24 offset;
              unchecked {
                  offset = uint24(word % maxOffset) + 1; // 1..maxOffset
                  lvlSel = currentLvl - offset;
              }
      
              traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word
              address[] storage arr = traitBurnTicket[lvlSel][traitSel];
              uint256 len = arr.length;
              if (len == 0) {
                  return (lvlSel, traitSel, new address[](0));
              }
      
              uint256 take = len > 4 ? 4 : len; // only need a small sample for scatter draws

2637:     /// @dev Simplified variant of sampleTraitTickets for targeted level sampling.
          ///      Used by BAF scatter to sample the next level's ticket holders.
          /// @param targetLvl The level to sample from.
          /// @param entropy Random seed (typically VRF word) for trait and offset selection.
          /// @return traitSel Selected trait ID.
          /// @return tickets Array of up to 4 ticket holder addresses.
          function sampleTraitTicketsAtLevel(
              uint24 targetLvl,
              uint256 entropy
          ) external view returns (uint8 traitSel, address[] memory tickets) {
              traitSel = uint8(entropy >> 24);
              address[] storage arr = traitBurnTicket[targetLvl][traitSel];
              uint256 len = arr.length;
              if (len == 0) {
                  return (traitSel, new address[](0));
              }
      
              uint256 take = len > 4 ? 4 : len;
              tickets = new address[](take);
              uint256 start = (entropy >> 40) % len;

2716:     /// @param trait The trait ID.
          /// @param lvl The level to query.
          /// @param offset Starting index for pagination.
          /// @param limit Maximum entries to scan.
          /// @param player The player address to count.
          /// @return count Number of tickets found in this page.
          /// @return nextOffset Next offset for pagination.
          /// @return total Total tickets in the array.
          function getTickets(
              uint8 trait,
              uint24 lvl,
              uint32 offset,
              uint32 limit,
              address player
          ) external view returns (uint24 count, uint32 nextOffset, uint32 total) {
              address[] storage a = traitBurnTicket[lvl][trait];
              total = uint32(a.length);
              if (offset >= total) return (0, total, total);
      
              uint256 end = offset + limit;
              if (end > total) end = total;
      
              for (uint256 i = offset; i < end; ) {

2762:     /// @param quadrant Quadrant (0-3).
          /// @param symbol Symbol index within quadrant (0-7).
          /// @return wagerUnits Amount wagered in 1e12 wei units.
          function getDailyHeroWager(
              uint48 day,
              uint8 quadrant,
              uint8 symbol
          ) external view returns (uint256 wagerUnits) {
              if (quadrant >= 4 || symbol >= 8) return 0;
              uint256 packed = dailyHeroWagers[day][quadrant];
              wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;

```

```solidity
File: DegenerusJackpots.sol

209:     /// @notice Resolve the BAF jackpot for a level.
         /// @dev Distributes poolWei across multiple winner categories with eligibility checks.
         ///      Returns arrays of winners/amounts plus unawarded amount for recycling.
         ///      Clears leaderboard state after resolution.
         /// @param poolWei Total ETH prize pool for distribution.
         /// @param lvl Level number being resolved.
         /// @param rngWord VRF-derived randomness seed.
         /// @return winners Array of winner addresses.
         /// @return amounts Array of prize amounts corresponding to winners.
         /// @return returnAmountWei Unawarded prize amount to return to caller.
         /// @custom:access Restricted to game contract via onlyGame modifier.
         function runBafJackpot(
             uint256 poolWei,
             uint24 lvl,
             uint256 rngWord
         )
             external
             override
             onlyGame
             returns (address[] memory winners, uint256[] memory amounts, uint256 returnAmountWei)
         {
             uint256 P = poolWei;
             // Max distinct winners: 1 (top BAF) + 1 (top flip) + 1 (pick) + 4 (far-future x2) + 50 + 50 (scatter) = 107.
             address[] memory tmpW = new address[](107);
             uint256[] memory tmpA = new uint256[](107);
             uint256 n;
             uint256 toReturn;
     
             uint256 entropy = rngWord;
             uint256 salt;
     
             {
                 // Slice A: 10% to the top BAF bettor for the level.
                 uint256 topPrize = P / 10;
                 (address w, ) = _bafTop(lvl, 0);
                 if (_creditOrRefund(w, topPrize, tmpW, tmpA, n)) {
                     unchecked {
                         ++n;
                     }
                 } else {
                     toReturn += topPrize;
                 }
             }
     
             {
                 // Slice A2: 5% to the top coinflip bettor from the last day window.
                 uint256 topPrize = P / 20;
                 (address w, ) = coin.coinflipTopLastDay();
                 if (_creditOrRefund(w, topPrize, tmpW, tmpA, n)) {
                     unchecked {
                         ++n;
                     }
                 } else {
                     toReturn += topPrize;
                 }
             }
     
             {
                 unchecked {
                     ++salt;
                 }
                 entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
                 uint256 prize = P / 20;
                 uint8 pick = 2 + uint8(entropy & 1);
                 (address w, ) = _bafTop(lvl, pick);
                 // Slice B: 5% to either the 3rd or 4th BAF leaderboard slot (pseudo-random tie-break).
                 if (_creditOrRefund(w, prize, tmpW, tmpA, n)) {
                     unchecked {
                         ++n;
                     }
                 } else {
                     toReturn += prize;
                 }
             }
     
             // Slice D: 5% to far-future ticket holders (3% 1st / 2% 2nd by BAF score).
             {
                 unchecked { ++salt; }
                 entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
                 address[] memory farTickets = degenerusGame.sampleFarFutureTickets(entropy);
     
                 uint256 farFirst = (P * 3) / 100;
                 uint256 farSecond = P / 50;
     
                 address best;
                 uint256 bestScore;
                 address second;
                 uint256 secondScore;
     
                 uint256 fLen = farTickets.length;
                 for (uint256 i; i < fLen; ) {
                     address cand = farTickets[i];
                     uint256 score = _bafScore(cand, lvl);
                     if (score > bestScore || best == address(0)) {
                         second = best;
                         secondScore = bestScore;
                         best = cand;
                         bestScore = score;
                     } else if ((score > secondScore || second == address(0)) && cand != best) {
                         second = cand;
                         secondScore = score;
                     }
                     unchecked { ++i; }
                 }
     
                 if (_creditOrRefund(best, farFirst, tmpW, tmpA, n)) {
                     unchecked { ++n; }
                 } else {
                     toReturn += farFirst;
                 }
                 if (_creditOrRefund(second, farSecond, tmpW, tmpA, n)) {
                     unchecked { ++n; }
                 } else {
                     toReturn += farSecond;
                 }
             }
     
             // Slice D2: 5% to far-future ticket holders, 2nd independent draw (3% 1st / 2% 2nd by BAF score).
             {
                 unchecked { ++salt; }
                 entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
                 address[] memory farTickets = degenerusGame.sampleFarFutureTickets(entropy);
     
                 uint256 farFirst = (P * 3) / 100;
                 uint256 farSecond = P / 50;
     
                 address best;
                 uint256 bestScore;
                 address second;
                 uint256 secondScore;
     
                 uint256 fLen = farTickets.length;
                 for (uint256 i; i < fLen; ) {
                     address cand = farTickets[i];
                     uint256 score = _bafScore(cand, lvl);
                     if (score > bestScore || best == address(0)) {
                         second = best;
                         secondScore = bestScore;
                         best = cand;
                         bestScore = score;
                     } else if ((score > secondScore || second == address(0)) && cand != best) {
                         second = cand;
                         secondScore = score;
                     }
                     unchecked { ++i; }
                 }
     
                 if (_creditOrRefund(best, farFirst, tmpW, tmpA, n)) {
                     unchecked { ++n; }
                 } else {
                     toReturn += farFirst;
                 }
                 if (_creditOrRefund(second, farSecond, tmpW, tmpA, n)) {
                     unchecked { ++n; }
                 } else {
                     toReturn += farSecond;
                 }
             }
     
             // Scatter slice: 200 total draws (4 tickets * 50 rounds). Per round, take top-2 by BAF score.
             // Unfilled rounds return their per-round share to future pool.
             {
                 // Slice E: scatter tickets from trait sampler so casual participants can land smaller cuts.
                 uint256 scatterTop = (P * 45) / 100;
                 uint256 scatterSecond = P / 4;
                 address[50] memory firstWinners;
                 address[50] memory secondWinners;
                 uint256 firstCount;
                 uint256 secondCount;
                 bool isCentury = (lvl % 100 == 0);
     
                 // Fixed rounds of 4-ticket sampling to keep gas bounded per call.
                 for (uint8 round = 0; round < BAF_SCATTER_ROUNDS; ) {
                     unchecked {
                         ++salt;
                     }
                     entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
     
                     // Level targeting varies by BAF type:
                     // Non-x00: 20 rounds from lvl, 30 rounds random from lvl+1..lvl+4
                     // x00:     4 rounds lvl, 8 rounds lvl+1..lvl+3, 38 random from past 99
                     uint24 targetLvl;
                     if (isCentury) {
                         if (round < 4) targetLvl = lvl;
                         else if (round < 8) targetLvl = lvl + 1 + uint24(entropy % 3);
                         else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);
                         else {
                             uint24 maxBack = lvl > 99 ? 99 : lvl - 1;
                             targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;
                         }
                     } else {
                         if (round < 20) targetLvl = lvl;
                         else targetLvl = lvl + 1 + uint24(entropy % 4);
                     }
     
                     (, address[] memory tickets) = degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy);
     
                     // Pick up to 4 tickets from the sampled set.
                     uint256 limit = tickets.length;
                     if (limit > 4) limit = 4;
     
                     address best;
                     uint256 bestScore;
                     address second;
                     uint256 secondScore;
     
                     for (uint256 i; i < limit; ) {
                         address cand = tickets[i];
                         uint256 score = _bafScore(cand, lvl);
                         if (score > bestScore) {
                             second = best;
                             secondScore = bestScore;
                             best = cand;
                             bestScore = score;
                         } else if (score > secondScore && cand != best) {
                             second = cand;
                             secondScore = score;
                         }
                         unchecked {
                             ++i;
                         }
                     }
     
                     // Bucket winners if eligible and capacity not exceeded; otherwise refund their would-be share later.
                     if (best != address(0)) {
                         firstWinners[firstCount] = best;
                         unchecked {
                             ++firstCount;
                         }
                     }
                     if (second != address(0)) {
                         secondWinners[secondCount] = second;
                         unchecked {
                             ++secondCount;
                         }
                     }
     
                     unchecked {
                         ++round;
                     }
                 }
     
                 // Per-round fixed share: empty rounds return to future pool.
                 uint256 perRoundFirst = scatterTop / BAF_SCATTER_ROUNDS;
                 uint256 perRoundSecond = scatterSecond / BAF_SCATTER_ROUNDS;
     
                 // Return unfilled rounds + integer division dust.
                 toReturn += scatterTop - perRoundFirst * firstCount;
                 toReturn += scatterSecond - perRoundSecond * secondCount;
     
                 for (uint256 i; i < firstCount; ) {
                     tmpW[n] = firstWinners[i];
                     tmpA[n] = perRoundFirst;
                     unchecked {
                         ++n;
                         ++i;
                     }
                 }
     
                 for (uint256 i; i < secondCount; ) {
                     tmpW[n] = secondWinners[i];
                     tmpA[n] = perRoundSecond;
                     unchecked {
                         ++n;
                         ++i;
                     }
                 }
     
             }
     
             winners = tmpW;
             amounts = tmpA;
             assembly ("memory-safe") {
                 mstore(winners, n)
                 mstore(amounts, n)
             }
     
             // Clean up leaderboard state for this level
             _clearBafTop(lvl);
             unchecked { ++bafEpoch[lvl]; }
             lastBafResolvedDay = degenerusGame.currentDayView();
             return (winners, amounts, toReturn);

499:     /// @dev Credit prize to non-zero winner or return false for refund.
         ///      Writes to preallocated buffers if winner is valid.
         /// @param candidate Potential winner address.
         /// @param prize Prize amount in wei.
         /// @param winnersBuf Pre-allocated winners array.
         /// @param amountsBuf Pre-allocated amounts array.
         /// @param idx Current write index.
         /// @return credited True if winner was credited (eligible and non-zero prize).
         function _creditOrRefund(
             address candidate,
             uint256 prize,
             address[] memory winnersBuf,
             uint256[] memory amountsBuf,
             uint256 idx
         ) private pure returns (bool credited) {
             if (prize == 0) return false;
             if (candidate != address(0)) {
                 winnersBuf[idx] = candidate;
                 amountsBuf[idx] = prize;
                 return true;
             }
             return false;

499:     /// @dev Credit prize to non-zero winner or return false for refund.
         ///      Writes to preallocated buffers if winner is valid.
         /// @param candidate Potential winner address.
         /// @param prize Prize amount in wei.
         /// @param winnersBuf Pre-allocated winners array.
         /// @param amountsBuf Pre-allocated amounts array.
         /// @param idx Current write index.
         /// @return credited True if winner was credited (eligible and non-zero prize).
         function _creditOrRefund(
             address candidate,
             uint256 prize,
             address[] memory winnersBuf,
             uint256[] memory amountsBuf,
             uint256 idx
         ) private pure returns (bool credited) {
             if (prize == 0) return false;

499:     /// @dev Credit prize to non-zero winner or return false for refund.
         ///      Writes to preallocated buffers if winner is valid.
         /// @param candidate Potential winner address.
         /// @param prize Prize amount in wei.
         /// @param winnersBuf Pre-allocated winners array.
         /// @param amountsBuf Pre-allocated amounts array.
         /// @param idx Current write index.
         /// @return credited True if winner was credited (eligible and non-zero prize).
         function _creditOrRefund(
             address candidate,
             uint256 prize,
             address[] memory winnersBuf,
             uint256[] memory amountsBuf,
             uint256 idx
         ) private pure returns (bool credited) {
             if (prize == 0) return false;
             if (candidate != address(0)) {
                 winnersBuf[idx] = candidate;
                 amountsBuf[idx] = prize;
                 return true;

615:     /// @dev Get player at leaderboard position.
         /// @param lvl Level number.
         /// @param idx Position (0 = top).
         /// @return player Address at position (address(0) if empty).
         /// @return score Player's score.
         function _bafTop(uint24 lvl, uint8 idx) private view returns (address player, uint96 score) {
             uint8 len = bafTopLen[lvl];
             if (idx >= len) return (address(0), 0);
             PlayerScore memory entry = bafTop[lvl][idx];
             return (entry.player, entry.score);

615:     /// @dev Get player at leaderboard position.
         /// @param lvl Level number.
         /// @param idx Position (0 = top).
         /// @return player Address at position (address(0) if empty).
         /// @return score Player's score.
         function _bafTop(uint24 lvl, uint8 idx) private view returns (address player, uint96 score) {
             uint8 len = bafTopLen[lvl];
             if (idx >= len) return (address(0), 0);

```

```solidity
File: DegenerusQuests.sol

300:      * @notice Roll the daily quest set using VRF entropy.
          * @dev Access: COIN or COINFLIP contract only.
          *      Entropy Usage:
          *      - Slot 0 uses `entropy` directly for type selection
          *      - Slot 1 uses `(entropy >> 128) | (entropy << 128)` (swapped halves)
          *      - Difficulty is fixed (no variance)
          * @param day Quest day identifier (monotonicity enforced by caller).
          * @param entropy VRF entropy word; second slot reuses swapped halves.
          * @return rolled Always true on success.
          * @return questTypes The two quest types rolled [slot0, slot1].
          * @return highDifficulty Always false (difficulty removed).
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function rollDailyQuest(
             uint48 day,
             uint256 entropy
         ) external onlyCoin returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty) {
             return _rollDailyQuest(day, entropy);

353:      * @dev Internal quest rolling logic shared by public entry points.
          *
          * Flow:
          * 1. Check game state for decimator quest eligibility
          * 2. Slot 0 is fixed to MINT_ETH ("deposit new ETH")
          * 3. Slot 1 is a weighted-random quest distinct from slot 0
          * 4. Seed both quest slots with fixed difficulty and versioning
          * @param day Quest day identifier.
          * @param entropy VRF entropy word.
          * @return rolled Always true on success.
          * @return questTypes The two quest types rolled [slot0, slot1].
          * @return highDifficulty Always false (difficulty removed).
          */
         function _rollDailyQuest(
             uint48 day,
             uint256 entropy
         ) private returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty) {
             DailyQuest[QUEST_SLOT_COUNT] storage quests = activeQuests;
             bool decAllowed = _canRollDecimatorQuest();
     
             // Swap 128-bit halves to derive independent entropy for slot 1
             uint256 bonusEntropy = (entropy >> 128) | (entropy << 128);
     
             uint8 primaryType = QUEST_TYPE_MINT_ETH;
             uint8 bonusType = _bonusQuestType(
                 bonusEntropy,
                 primaryType,
                 decAllowed
             );
     
             _seedQuestType(quests[0], day, primaryType);
             _seedQuestType(quests[1], day, bonusType);
     
             emit QuestSlotRolled(
                 day,
                 0,
                 quests[0].questType,
                 quests[0].flags,
                 quests[0].version,
                 quests[0].difficulty
             );
             emit QuestSlotRolled(
                 day,
                 1,
                 quests[1].questType,
                 quests[1].flags,
                 quests[1].version,
                 quests[1].difficulty
             );
     
             questTypes[0] = primaryType;
             questTypes[1] = bonusType;
             highDifficulty = false;
             return (true, questTypes, highDifficulty);

427:      * @notice Handle mint progress for a player; covers both BURNIE and ETH paid mints.
          * @dev Access: COIN or COINFLIP contract only.
          *      Iterates both slots since both could theoretically match (though in practice
          *      the rolling logic ensures only one slot has each mint type).
          * @param player The player who performed the mint.
          * @param quantity Number of tickets minted.
          * @param paidWithEth True if ETH was used (MINT_ETH quest), false for BURNIE (MINT_BURNIE).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleMint(
             address player,
             uint32 quantity,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || quantity == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
     
             _questSyncState(state, player, currentDay);
     
             uint256 totalReward;
             bool anyCompleted;
             uint8 outQuestType = paidWithEth ? QUEST_TYPE_MINT_ETH : QUEST_TYPE_MINT_BURNIE;
             uint32 outStreak = state.streak;
             uint256 mintPrice;
             if (paidWithEth) {
                 mintPrice = questGame.mintPrice();
             }
     
             // Check both slots for matching mint quest type
             for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
                 DailyQuest memory quest = quests[slot];
                 if (quest.day != currentDay) {
                     unchecked {
                         ++slot;
                     }
                     continue;
                 }
                 if (
                     (!paidWithEth && quest.questType == QUEST_TYPE_MINT_BURNIE) ||
                     (paidWithEth && quest.questType == QUEST_TYPE_MINT_ETH)
                 ) {
                     outQuestType = quest.questType;
                     if (paidWithEth) {
                         uint256 delta = uint256(quantity) * mintPrice;
                         uint256 target = _questTargetValue(quest, slot, mintPrice);
                         (reward, questType, streak, completed) = _questHandleProgressSlot(
                             player,
                             state,
                             quests,
                             quest,
                             slot,
                             delta,
                             target,
                             currentDay,
                             mintPrice
                         );
                     } else {
                         uint256 target = _questTargetValue(quest, slot, mintPrice);
                         (reward, questType, streak, completed) = _questHandleProgressSlot(
                             player,
                             state,
                             quests,
                             quest,
                             slot,
                             quantity,
                             target,
                             currentDay,
                             mintPrice
                         );
                     }
                     if (completed) {
                         totalReward += reward;
                         outQuestType = questType;
                         outStreak = streak;
                         anyCompleted = true;
                     }
                 }
                 unchecked {
                     ++slot;
                 }
             }
             if (anyCompleted) {
                 return (totalReward, outQuestType, outStreak, true);
             }
             return (0, outQuestType, state.streak, false);

427:      * @notice Handle mint progress for a player; covers both BURNIE and ETH paid mints.
          * @dev Access: COIN or COINFLIP contract only.
          *      Iterates both slots since both could theoretically match (though in practice
          *      the rolling logic ensures only one slot has each mint type).
          * @param player The player who performed the mint.
          * @param quantity Number of tickets minted.
          * @param paidWithEth True if ETH was used (MINT_ETH quest), false for BURNIE (MINT_BURNIE).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleMint(
             address player,
             uint32 quantity,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || quantity == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

427:      * @notice Handle mint progress for a player; covers both BURNIE and ETH paid mints.
          * @dev Access: COIN or COINFLIP contract only.
          *      Iterates both slots since both could theoretically match (though in practice
          *      the rolling logic ensures only one slot has each mint type).
          * @param player The player who performed the mint.
          * @param quantity Number of tickets minted.
          * @param paidWithEth True if ETH was used (MINT_ETH quest), false for BURNIE (MINT_BURNIE).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleMint(
             address player,
             uint32 quantity,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || quantity == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
     
             _questSyncState(state, player, currentDay);
     
             uint256 totalReward;
             bool anyCompleted;
             uint8 outQuestType = paidWithEth ? QUEST_TYPE_MINT_ETH : QUEST_TYPE_MINT_BURNIE;
             uint32 outStreak = state.streak;
             uint256 mintPrice;
             if (paidWithEth) {
                 mintPrice = questGame.mintPrice();
             }
     
             // Check both slots for matching mint quest type
             for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
                 DailyQuest memory quest = quests[slot];
                 if (quest.day != currentDay) {
                     unchecked {
                         ++slot;
                     }
                     continue;
                 }
                 if (
                     (!paidWithEth && quest.questType == QUEST_TYPE_MINT_BURNIE) ||
                     (paidWithEth && quest.questType == QUEST_TYPE_MINT_ETH)
                 ) {
                     outQuestType = quest.questType;
                     if (paidWithEth) {
                         uint256 delta = uint256(quantity) * mintPrice;
                         uint256 target = _questTargetValue(quest, slot, mintPrice);
                         (reward, questType, streak, completed) = _questHandleProgressSlot(
                             player,
                             state,
                             quests,
                             quest,
                             slot,
                             delta,
                             target,
                             currentDay,
                             mintPrice
                         );
                     } else {
                         uint256 target = _questTargetValue(quest, slot, mintPrice);
                         (reward, questType, streak, completed) = _questHandleProgressSlot(
                             player,
                             state,
                             quests,
                             quest,
                             slot,
                             quantity,
                             target,
                             currentDay,
                             mintPrice
                         );
                     }
                     if (completed) {
                         totalReward += reward;
                         outQuestType = questType;
                         outStreak = streak;
                         anyCompleted = true;
                     }
                 }
                 unchecked {
                     ++slot;
                 }
             }
             if (anyCompleted) {
                 return (totalReward, outQuestType, outStreak, true);

527:      * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Progress tracks cumulative flip volume for the day.
          * @param player The player who staked/unstaked.
          * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleFlip(
             address player,
             uint256 flipCredit
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || flipCredit == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_FLIP);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_FLIP, state.streak, false);
             }
     
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             uint128 progressAfter = _clampedAdd128(state.progress[slotIndex], flipCredit);
             state.progress[slotIndex] = progressAfter;
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 progressAfter,
                 target
             );
             if (progressAfter < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);
             }
     
             return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);

527:      * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Progress tracks cumulative flip volume for the day.
          * @param player The player who staked/unstaked.
          * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleFlip(
             address player,
             uint256 flipCredit
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || flipCredit == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

527:      * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Progress tracks cumulative flip volume for the day.
          * @param player The player who staked/unstaked.
          * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleFlip(
             address player,
             uint256 flipCredit
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || flipCredit == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_FLIP);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_FLIP, state.streak, false);

527:      * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Progress tracks cumulative flip volume for the day.
          * @param player The player who staked/unstaked.
          * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleFlip(
             address player,
             uint256 flipCredit
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || flipCredit == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_FLIP);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_FLIP, state.streak, false);
             }
     
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             uint128 progressAfter = _clampedAdd128(state.progress[slotIndex], flipCredit);
             state.progress[slotIndex] = progressAfter;
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 progressAfter,
                 target
             );
             if (progressAfter < target) {
                 return (0, quest.questType, state.streak, false);

527:      * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Progress tracks cumulative flip volume for the day.
          * @param player The player who staked/unstaked.
          * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleFlip(
             address player,
             uint256 flipCredit
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || flipCredit == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_FLIP);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_FLIP, state.streak, false);
             }
     
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             uint128 progressAfter = _clampedAdd128(state.progress[slotIndex], flipCredit);
             state.progress[slotIndex] = progressAfter;
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 progressAfter,
                 target
             );
             if (progressAfter < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);

582:      * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
          * @param player The player who performed the decimator burn.
          * @param burnAmount Amount of BURNIE burned (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDecimator(
             address player,
             uint256 burnAmount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || burnAmount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_DECIMATOR);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_DECIMATOR, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], burnAmount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);
             }
             return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);

582:      * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
          * @param player The player who performed the decimator burn.
          * @param burnAmount Amount of BURNIE burned (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDecimator(
             address player,
             uint256 burnAmount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || burnAmount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

582:      * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
          * @param player The player who performed the decimator burn.
          * @param burnAmount Amount of BURNIE burned (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDecimator(
             address player,
             uint256 burnAmount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || burnAmount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_DECIMATOR);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_DECIMATOR, state.streak, false);

582:      * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
          * @param player The player who performed the decimator burn.
          * @param burnAmount Amount of BURNIE burned (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDecimator(
             address player,
             uint256 burnAmount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || burnAmount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_DECIMATOR);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_DECIMATOR, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], burnAmount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);

582:      * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
          * @param player The player who performed the decimator burn.
          * @param burnAmount Amount of BURNIE burned (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDecimator(
             address player,
             uint256 burnAmount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || burnAmount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_DECIMATOR);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_DECIMATOR, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], burnAmount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);

634:      * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The affiliate who earned commission.
          * @param amount BURNIE earned from affiliate referrals (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleAffiliate(
             address player,
             uint256 amount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_AFFILIATE);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_AFFILIATE, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);
             }
             return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);

634:      * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The affiliate who earned commission.
          * @param amount BURNIE earned from affiliate referrals (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleAffiliate(
             address player,
             uint256 amount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

634:      * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The affiliate who earned commission.
          * @param amount BURNIE earned from affiliate referrals (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleAffiliate(
             address player,
             uint256 amount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_AFFILIATE);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_AFFILIATE, state.streak, false);

634:      * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The affiliate who earned commission.
          * @param amount BURNIE earned from affiliate referrals (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleAffiliate(
             address player,
             uint256 amount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_AFFILIATE);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_AFFILIATE, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);

634:      * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The affiliate who earned commission.
          * @param amount BURNIE earned from affiliate referrals (in base units).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleAffiliate(
             address player,
             uint256 amount
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_AFFILIATE);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_AFFILIATE, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amount);
             uint256 target = _questTargetValue(quest, slotIndex, 0);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);

685:      * @notice Handle loot box purchase progress in ETH value (wei).
          * @dev Access: COIN or COINFLIP contract only.
          *      Loot box quests track cumulative ETH spent on loot boxes.
          *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
          * @param player The player who purchased the loot box.
          * @param amountWei ETH amount spent on the loot box (in wei).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleLootBox(
             address player,
             uint256 amountWei
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amountWei == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_LOOTBOX, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amountWei);
             uint256 currentPrice = questGame.mintPrice();
             uint256 target = _questTargetValue(quest, slotIndex, currentPrice);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);
             }
             return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, currentPrice);

685:      * @notice Handle loot box purchase progress in ETH value (wei).
          * @dev Access: COIN or COINFLIP contract only.
          *      Loot box quests track cumulative ETH spent on loot boxes.
          *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
          * @param player The player who purchased the loot box.
          * @param amountWei ETH amount spent on the loot box (in wei).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleLootBox(
             address player,
             uint256 amountWei
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amountWei == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

685:      * @notice Handle loot box purchase progress in ETH value (wei).
          * @dev Access: COIN or COINFLIP contract only.
          *      Loot box quests track cumulative ETH spent on loot boxes.
          *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
          * @param player The player who purchased the loot box.
          * @param amountWei ETH amount spent on the loot box (in wei).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleLootBox(
             address player,
             uint256 amountWei
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amountWei == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_LOOTBOX, state.streak, false);

685:      * @notice Handle loot box purchase progress in ETH value (wei).
          * @dev Access: COIN or COINFLIP contract only.
          *      Loot box quests track cumulative ETH spent on loot boxes.
          *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
          * @param player The player who purchased the loot box.
          * @param amountWei ETH amount spent on the loot box (in wei).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleLootBox(
             address player,
             uint256 amountWei
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amountWei == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_LOOTBOX, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amountWei);
             uint256 currentPrice = questGame.mintPrice();
             uint256 target = _questTargetValue(quest, slotIndex, currentPrice);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);

685:      * @notice Handle loot box purchase progress in ETH value (wei).
          * @dev Access: COIN or COINFLIP contract only.
          *      Loot box quests track cumulative ETH spent on loot boxes.
          *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
          * @param player The player who purchased the loot box.
          * @param amountWei ETH amount spent on the loot box (in wei).
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleLootBox(
             address player,
             uint256 amountWei
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amountWei == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
             if (slotIndex == type(uint8).max) {
                 return (0, QUEST_TYPE_LOOTBOX, state.streak, false);
             }
             _questSyncProgress(state, slotIndex, currentDay, quest.version);
             state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amountWei);
             uint256 currentPrice = questGame.mintPrice();
             uint256 target = _questTargetValue(quest, slotIndex, currentPrice);
             emit QuestProgressUpdated(
                 player,
                 currentDay,
                 slotIndex,
                 quest.questType,
                 state.progress[slotIndex],
                 target
             );
             if (state.progress[slotIndex] < target) {
                 return (0, quest.questType, state.streak, false);
             }
             if (slotIndex == 1 && (state.completionMask & 1) == 0) {
                 return (0, quest.questType, state.streak, false);

739:      * @notice Handle Degenerette bet progress for a player.
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The player who placed the Degenerette bet.
          * @param amount The bet amount (wei for ETH, base units for BURNIE).
          * @param paidWithEth True if bet was paid with ETH, false for BURNIE.
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDegenerette(
             address player,
             uint256 amount,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             uint8 targetType = paidWithEth ? QUEST_TYPE_DEGENERETTE_ETH : QUEST_TYPE_DEGENERETTE_BURNIE;
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, targetType);
             if (slotIndex == type(uint8).max) {
                 return (0, targetType, state.streak, false);
             }
     
             uint256 mintPrice = 0;
             if (paidWithEth) {
                 mintPrice = questGame.mintPrice();
             }
             uint256 target = _questTargetValue(quest, slotIndex, mintPrice);
             return _questHandleProgressSlot(

739:      * @notice Handle Degenerette bet progress for a player.
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The player who placed the Degenerette bet.
          * @param amount The bet amount (wei for ETH, base units for BURNIE).
          * @param paidWithEth True if bet was paid with ETH, false for BURNIE.
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDegenerette(
             address player,
             uint256 amount,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);

739:      * @notice Handle Degenerette bet progress for a player.
          * @dev Access: COIN or COINFLIP contract only.
          * @param player The player who placed the Degenerette bet.
          * @param amount The bet amount (wei for ETH, base units for BURNIE).
          * @param paidWithEth True if bet was paid with ETH, false for BURNIE.
          * @return reward BURNIE tokens earned (in base units, 18 decimals).
          * @return questType The type of quest that was processed.
          * @return streak Player's current streak after this action.
          * @return completed True if a quest was completed by this action.
          * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
          */
         function handleDegenerette(
             address player,
             uint256 amount,
             bool paidWithEth
         )
             external
             onlyCoin
             returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
         {
             DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
             uint48 currentDay = _currentQuestDay(quests);
             PlayerQuestState storage state = questPlayerState[player];
             if (player == address(0) || amount == 0 || currentDay == 0) {
                 return (0, quests[0].questType, state.streak, false);
             }
             _questSyncState(state, player, currentDay);
     
             uint8 targetType = paidWithEth ? QUEST_TYPE_DEGENERETTE_ETH : QUEST_TYPE_DEGENERETTE_BURNIE;
             (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, targetType);
             if (slotIndex == type(uint8).max) {
                 return (0, targetType, state.streak, false);

963:      * @dev Returns the active quest of a given type for the current day, if present.
          * @param quests Memory array of active quests.
          * @param currentDay The current quest day.
          * @param questType The type to search for.
          * @return quest The matching quest (empty if not found).
          * @return slotIndex The slot index (type(uint8).max if not found).
          */
         function _currentDayQuestOfType(
             DailyQuest[QUEST_SLOT_COUNT] memory quests,
             uint48 currentDay,
             uint8 questType
         ) private pure returns (DailyQuest memory quest, uint8 slotIndex) {
             slotIndex = type(uint8).max; // Sentinel for "not found"
             for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
                 DailyQuest memory candidate = quests[slot];
                 if (candidate.day == currentDay && candidate.questType == questType) {
                     quest = candidate;
                     slotIndex = slot;
                     return (quest, slotIndex);

1048:      * @dev Processes progress against a given quest slot, updating progress and returning rewards.
           * @param player Player address for event emission.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests (for pair completion check).
           * @param quest The specific quest being processed.
           * @param slot The slot index (0 or 1).
           * @param delta Progress delta to add (units depend on quest type).
           * @param target Target to complete the quest (units depend on quest type).
           * @param currentDay Current quest day (for paired completion checks).
           * @param mintPrice Cached mint price (wei) for ETH-based quests, 0 if unused.
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questHandleProgressSlot(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              DailyQuest memory quest,
              uint8 slot,
              uint256 delta,
              uint256 target,
              uint48 currentDay,
              uint256 mintPrice
          ) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed) {
              _questSyncProgress(state, slot, quest.day, quest.version);
              state.progress[slot] = _clampedAdd128(state.progress[slot], delta);
              emit QuestProgressUpdated(
                  player,
                  quest.day,
                  slot,
                  quest.questType,
                  state.progress[slot],
                  target
              );
              if (state.progress[slot] >= target) {
                  if (slot == 1 && (state.completionMask & 1) == 0) {
                      return (0, quest.questType, state.streak, false);
                  }
                  return _questCompleteWithPair(player, state, quests, slot, quest, currentDay, mintPrice);
              }
              return (0, quest.questType, state.streak, false);

1048:      * @dev Processes progress against a given quest slot, updating progress and returning rewards.
           * @param player Player address for event emission.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests (for pair completion check).
           * @param quest The specific quest being processed.
           * @param slot The slot index (0 or 1).
           * @param delta Progress delta to add (units depend on quest type).
           * @param target Target to complete the quest (units depend on quest type).
           * @param currentDay Current quest day (for paired completion checks).
           * @param mintPrice Cached mint price (wei) for ETH-based quests, 0 if unused.
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questHandleProgressSlot(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              DailyQuest memory quest,
              uint8 slot,
              uint256 delta,
              uint256 target,
              uint48 currentDay,
              uint256 mintPrice
          ) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed) {
              _questSyncProgress(state, slot, quest.day, quest.version);
              state.progress[slot] = _clampedAdd128(state.progress[slot], delta);
              emit QuestProgressUpdated(
                  player,
                  quest.day,
                  slot,
                  quest.questType,
                  state.progress[slot],
                  target
              );
              if (state.progress[slot] >= target) {
                  if (slot == 1 && (state.completionMask & 1) == 0) {
                      return (0, quest.questType, state.streak, false);
                  }
                  return _questCompleteWithPair(player, state, quests, slot, quest, currentDay, mintPrice);

1048:      * @dev Processes progress against a given quest slot, updating progress and returning rewards.
           * @param player Player address for event emission.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests (for pair completion check).
           * @param quest The specific quest being processed.
           * @param slot The slot index (0 or 1).
           * @param delta Progress delta to add (units depend on quest type).
           * @param target Target to complete the quest (units depend on quest type).
           * @param currentDay Current quest day (for paired completion checks).
           * @param mintPrice Cached mint price (wei) for ETH-based quests, 0 if unused.
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questHandleProgressSlot(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              DailyQuest memory quest,
              uint8 slot,
              uint256 delta,
              uint256 target,
              uint48 currentDay,
              uint256 mintPrice
          ) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed) {
              _questSyncProgress(state, slot, quest.day, quest.version);
              state.progress[slot] = _clampedAdd128(state.progress[slot], delta);
              emit QuestProgressUpdated(
                  player,
                  quest.day,
                  slot,
                  quest.questType,
                  state.progress[slot],
                  target
              );
              if (state.progress[slot] >= target) {
                  if (slot == 1 && (state.completionMask & 1) == 0) {
                      return (0, quest.questType, state.streak, false);

1370:      * @dev Completes a quest slot, credits streak when all slots finish, and returns rewards.
           *
           *      Streak Logic:
           *      - Streak increments on the first quest completion of the day
           *      - QUEST_STATE_STREAK_CREDITED bit prevents double-crediting
           *      - lastCompletedDay updates on that first completion
           *
           *      Reward Calculation:
           *      - Slot 0 (deposit ETH) pays a fixed 100 BURNIE
           *      - Slot 1 (random quest) pays a fixed 200 BURNIE
           * @param state Storage reference to player's quest state.
           * @param slot The slot index being completed.
           * @param quest The quest being completed.
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questComplete(
              address player,
              PlayerQuestState storage state,
              uint8 slot,
              DailyQuest memory quest
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              uint8 mask = state.completionMask;
              uint8 slotMask = uint8(1 << slot);
      
              // Already completed this slot today
              if ((mask & slotMask) != 0) {
                  return (0, quest.questType, state.streak, false);
              }
      
              // Mark slot as complete
              mask |= slotMask;
              uint24 questDay24 = uint24(quest.day);
              if (questDay24 > state.lastActiveDay) {
                  state.lastActiveDay = questDay24;
              }
      
              uint32 newStreak = uint32(state.streak);
      
              // Streak is credited on the first quest completion of the day.
              if ((mask & QUEST_STATE_STREAK_CREDITED) == 0) {
                  mask |= QUEST_STATE_STREAK_CREDITED;
                  if (newStreak < type(uint24).max) {
                      newStreak += 1;
                  }
                  state.streak = uint24(newStreak);
                  state.lastCompletedDay = questDay24;
              }
              state.completionMask = mask;
      
              uint256 rewardShare = slot == 1 ? QUEST_RANDOM_REWARD : QUEST_SLOT0_REWARD;
              emit QuestCompleted(
                  player,
                  quest.day,
                  slot,
                  quest.questType,
                  newStreak,
                  rewardShare
              );
              return (rewardShare, quest.questType, newStreak, true);

1370:      * @dev Completes a quest slot, credits streak when all slots finish, and returns rewards.
           *
           *      Streak Logic:
           *      - Streak increments on the first quest completion of the day
           *      - QUEST_STATE_STREAK_CREDITED bit prevents double-crediting
           *      - lastCompletedDay updates on that first completion
           *
           *      Reward Calculation:
           *      - Slot 0 (deposit ETH) pays a fixed 100 BURNIE
           *      - Slot 1 (random quest) pays a fixed 200 BURNIE
           * @param state Storage reference to player's quest state.
           * @param slot The slot index being completed.
           * @param quest The quest being completed.
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questComplete(
              address player,
              PlayerQuestState storage state,
              uint8 slot,
              DailyQuest memory quest
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              uint8 mask = state.completionMask;
              uint8 slotMask = uint8(1 << slot);
      
              // Already completed this slot today
              if ((mask & slotMask) != 0) {
                  return (0, quest.questType, state.streak, false);

1438:      * @dev Completes a quest and checks if the paired quest can also complete.
           *      This function enables "combo completion" where completing one quest
           *      can automatically complete the other if its progress already meets target.
           *      This is a UX optimization to avoid requiring separate transactions.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot being completed.
           * @param quest The quest being completed.
           * @param currentDay Current quest day for pair checks.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questCompleteWithPair(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              DailyQuest memory quest,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              (reward, questType, streak, completed) = _questComplete(
                  player,
                  state,
                  slot,
                  quest
              );
              if (!completed) {
                  return (reward, questType, streak, false);
              }
      
              // Check the other slot; if it already meets the target, complete it now
              uint8 otherSlot = slot ^ 1; // XOR to flip 0↔1
              (
                  uint256 extraReward,
                  uint8 extraType,
                  uint32 extraStreak,
                  bool extraCompleted
              ) = _maybeCompleteOther(player, state, quests, otherSlot, currentDay, mintPrice);
      
              // Aggregate rewards from paired completion
              if (extraCompleted) {
                  reward += extraReward;
                  questType = extraType;
                  streak = extraStreak;
              }
              // completed is already true if we reached here
              return (reward, questType, streak, true);

1438:      * @dev Completes a quest and checks if the paired quest can also complete.
           *      This function enables "combo completion" where completing one quest
           *      can automatically complete the other if its progress already meets target.
           *      This is a UX optimization to avoid requiring separate transactions.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot being completed.
           * @param quest The quest being completed.
           * @param currentDay Current quest day for pair checks.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _questCompleteWithPair(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              DailyQuest memory quest,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              (reward, questType, streak, completed) = _questComplete(
                  player,
                  state,
                  slot,
                  quest
              );
              if (!completed) {
                  return (reward, questType, streak, false);

1495:      * @dev Attempts to complete the other slot if its progress meets the target.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot to check for completion.
           * @param currentDay Current quest day for validation.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _maybeCompleteOther(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              DailyQuest memory quest = quests[slot];
      
              // Skip if quest is not for today
              if (quest.day == 0 || quest.day != currentDay) {
                  return (0, quest.questType, state.streak, false);
              }
              // Skip if already completed
              if ((state.completionMask & uint8(1 << slot)) != 0) {
                  return (0, quest.questType, state.streak, false);
              }
      
              if (!_questReady(state, quest, slot, mintPrice)) {
                  return (0, quest.questType, state.streak, false);
              }
      
              return _questComplete(player, state, slot, quest);

1495:      * @dev Attempts to complete the other slot if its progress meets the target.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot to check for completion.
           * @param currentDay Current quest day for validation.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _maybeCompleteOther(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              DailyQuest memory quest = quests[slot];
      
              // Skip if quest is not for today
              if (quest.day == 0 || quest.day != currentDay) {
                  return (0, quest.questType, state.streak, false);

1495:      * @dev Attempts to complete the other slot if its progress meets the target.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot to check for completion.
           * @param currentDay Current quest day for validation.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _maybeCompleteOther(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              DailyQuest memory quest = quests[slot];
      
              // Skip if quest is not for today
              if (quest.day == 0 || quest.day != currentDay) {
                  return (0, quest.questType, state.streak, false);
              }
              // Skip if already completed
              if ((state.completionMask & uint8(1 << slot)) != 0) {
                  return (0, quest.questType, state.streak, false);

1495:      * @dev Attempts to complete the other slot if its progress meets the target.
           * @param state Storage reference to player's quest state.
           * @param quests Memory copy of active quests.
           * @param slot The slot to check for completion.
           * @param currentDay Current quest day for validation.
           * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
           * @return reward BURNIE tokens earned (in base units).
           * @return questType The completed quest type.
           * @return streak Player's streak after completion.
           * @return completed True if completion was successful.
           */
          function _maybeCompleteOther(
              address player,
              PlayerQuestState storage state,
              DailyQuest[QUEST_SLOT_COUNT] memory quests,
              uint8 slot,
              uint48 currentDay,
              uint256 mintPrice
          )
              private
              returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
          {
              DailyQuest memory quest = quests[slot];
      
              // Skip if quest is not for today
              if (quest.day == 0 || quest.day != currentDay) {
                  return (0, quest.questType, state.streak, false);
              }
              // Skip if already completed
              if ((state.completionMask & uint8(1 << slot)) != 0) {
                  return (0, quest.questType, state.streak, false);
              }
      
              if (!_questReady(state, quest, slot, mintPrice)) {
                  return (0, quest.questType, state.streak, false);

```

```solidity
File: DegenerusStonk.sol

196:     /// @notice Preview ETH, stETH, and BURNIE output for burning a given amount of DGNRS
         /// @dev Delegates to sDGNRS.previewBurn; does not modify state
         /// @param amount Amount of DGNRS to simulate burning (18 decimals)
         /// @return ethOut ETH that would be received
         /// @return stethOut stETH that would be received
         /// @return burnieOut BURNIE that would be received
         function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             return stonk.previewBurn(amount);

```

```solidity
File: DegenerusVault.sol

689:     /// @notice Claim coinflip winnings for the vault
         /// @param amount Maximum amount to claim
         /// @return claimed Actual amount claimed
         /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
         function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {
             return coinflipPlayer.claimCoinflips(address(this), amount);

739:     /// @notice Burn DGVB shares to redeem proportional BURNIE
         /// @dev Formula: coinOut = (DGVB reserve * sharesBurned) / totalSupply.
         ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
         ///      Pays from vault balance first, then claimable coinflips, then mints remainder.
         /// @param player Player address to burn for (address(0) uses msg.sender)
         /// @param amount Amount of DGVB shares to burn
         /// @return coinOut Amount of BURNIE sent to player
         /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
         /// @custom:reverts NotApproved If caller is not player and not approved operator
         /// @custom:reverts TransferFailed If BURNIE transfer fails
         function burnCoin(address player, uint256 amount) external returns (uint256 coinOut) {
             if (player == address(0)) {
                 player = msg.sender;
             } else if (player != msg.sender) {
                 _requireApproved(player);
             }
             return _burnCoinFor(player, amount);

804:     /// @notice Burn DGVE shares to redeem proportional ETH and stETH
         /// @dev ETH is preferred over stETH (uses ETH first, then stETH for remainder).
         ///      Formula: claimValue = (DGVE reserve * sharesBurned) / totalSupply.
         ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
         ///      May auto-claim game winnings if needed to fulfill the redemption.
         /// @param player Player address to burn for (address(0) uses msg.sender)
         /// @param amount Amount of DGVE shares to burn
         /// @return ethOut Amount of ETH sent to player
         /// @return stEthOut Amount of stETH sent to player
         /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
         /// @custom:reverts NotApproved If caller is not player and not approved operator
         /// @custom:reverts TransferFailed If ETH or stETH transfer fails
         function burnEth(
             address player,
             uint256 amount
         ) external returns (uint256 ethOut, uint256 stEthOut) {
             if (player == address(0)) {
                 player = msg.sender;
             } else if (player != msg.sender) {
                 _requireApproved(player);
             }
             return _burnEthFor(player, amount);

956:     /// @dev Combine msg.value with additional vault-funded ETH
         /// @param extraValue Additional ETH to use from vault balance
         /// @return totalValue Combined ETH value (msg.value + extraValue)
         function _combinedValue(uint256 extraValue) private view returns (uint256 totalValue) {
             if (extraValue == 0) {
                 return msg.value;
             }
             totalValue = msg.value + extraValue;

```

```solidity
File: GNRUS.sol

513:     /// @notice Get proposal details by global ID
         function getProposal(uint48 proposalId) external view returns (
             address recipient, address proposer, uint48 approveWeight, uint48 rejectWeight
         ) {
             Proposal storage p = proposals[proposalId];
             return (p.recipient, p.proposer, p.approveWeight, p.rejectWeight);

521:     /// @notice Get the proposal range for a given level
         function getLevelProposals(uint24 level) external view returns (uint48 start, uint8 count) {
             return (levelProposalStart[level], levelProposalCount[level]);

```

```solidity
File: StakedDegenerusStonk.sol

368:     /// @notice Transfer sDGNRS from a reward pool to a recipient
         /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
         /// @param pool Pool identifier
         /// @param to Recipient address
         /// @param amount Requested amount of sDGNRS to transfer
         /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
         /// @custom:reverts Unauthorized If caller is not game contract
         /// @custom:reverts ZeroAddress If to is zero address
         function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;
             if (to == address(0)) revert ZeroAddress();
             uint8 idx = _poolIndex(pool);
             uint256 available = poolBalances[idx];
             if (available == 0) return 0;
             if (amount > available) {
                 amount = available;
             }
             unchecked {
                 poolBalances[idx] = available - amount;
                 balanceOf[address(this)] -= amount;
                 balanceOf[to] += amount;
             }
             emit Transfer(address(this), to, amount);
             emit PoolTransfer(pool, to, amount);
             return amount;

368:     /// @notice Transfer sDGNRS from a reward pool to a recipient
         /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
         /// @param pool Pool identifier
         /// @param to Recipient address
         /// @param amount Requested amount of sDGNRS to transfer
         /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
         /// @custom:reverts Unauthorized If caller is not game contract
         /// @custom:reverts ZeroAddress If to is zero address
         function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;

368:     /// @notice Transfer sDGNRS from a reward pool to a recipient
         /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
         /// @param pool Pool identifier
         /// @param to Recipient address
         /// @param amount Requested amount of sDGNRS to transfer
         /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
         /// @custom:reverts Unauthorized If caller is not game contract
         /// @custom:reverts ZeroAddress If to is zero address
         function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;
             if (to == address(0)) revert ZeroAddress();
             uint8 idx = _poolIndex(pool);
             uint256 available = poolBalances[idx];
             if (available == 0) return 0;

395:     /// @notice Transfer sDGNRS between two reward pools
         /// @dev Only callable by game contract. No token movement — just rebalances internal pool accounting.
         /// @param from Source pool
         /// @param to Destination pool
         /// @param amount Requested amount to move
         /// @return transferred Actual amount transferred (may be less if source pool has insufficient balance)
         function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;
             uint8 fromIdx = _poolIndex(from);
             uint8 toIdx = _poolIndex(to);
             uint256 available = poolBalances[fromIdx];
             if (available == 0) return 0;
             if (amount > available) {
                 amount = available;
             }
             unchecked {
                 poolBalances[fromIdx] = available - amount;
             }
             poolBalances[toIdx] += amount;
             emit PoolRebalance(from, to, amount);
             return amount;

395:     /// @notice Transfer sDGNRS between two reward pools
         /// @dev Only callable by game contract. No token movement — just rebalances internal pool accounting.
         /// @param from Source pool
         /// @param to Destination pool
         /// @param amount Requested amount to move
         /// @return transferred Actual amount transferred (may be less if source pool has insufficient balance)
         function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;

395:     /// @notice Transfer sDGNRS between two reward pools
         /// @dev Only callable by game contract. No token movement — just rebalances internal pool accounting.
         /// @param from Source pool
         /// @param to Destination pool
         /// @param amount Requested amount to move
         /// @return transferred Actual amount transferred (may be less if source pool has insufficient balance)
         function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {
             if (amount == 0) return 0;
             uint8 fromIdx = _poolIndex(from);
             uint8 toIdx = _poolIndex(to);
             uint256 available = poolBalances[fromIdx];
             if (available == 0) return 0;

435:     /// @notice Burn sDGNRS to claim proportional share of backing assets
         /// @dev Post-gameOver: deterministic payout. During game: gambling path with RNG roll.
         ///      Returns (0,0,0) during game; player must call claimRedemption() after resolution.
         /// @param amount Amount of sDGNRS to burn
         /// @return ethOut ETH received (deterministic path only)
         /// @return stethOut stETH received (deterministic path only)
         /// @return burnieOut BURNIE received (deterministic path only)
         /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
         function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             if (game.gameOver()) {
                 (ethOut, stethOut) = _deterministicBurn(msg.sender, amount);
                 return (ethOut, stethOut, 0);
             }
             if (game.rngLocked()) revert BurnsBlockedDuringRng();
             _submitGamblingClaim(msg.sender, amount);
             return (0, 0, 0);

435:     /// @notice Burn sDGNRS to claim proportional share of backing assets
         /// @dev Post-gameOver: deterministic payout. During game: gambling path with RNG roll.
         ///      Returns (0,0,0) during game; player must call claimRedemption() after resolution.
         /// @param amount Amount of sDGNRS to burn
         /// @return ethOut ETH received (deterministic path only)
         /// @return stethOut stETH received (deterministic path only)
         /// @return burnieOut BURNIE received (deterministic path only)
         /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
         function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             if (game.gameOver()) {
                 (ethOut, stethOut) = _deterministicBurn(msg.sender, amount);
                 return (ethOut, stethOut, 0);

453:     /// @notice Burn wrapped DGNRS (held in the DGNRS contract) to claim proportional backing assets
         /// @dev Calls dgnrsWrapper to convert DGNRS to sDGNRS credit, then burns the resulting sDGNRS.
         ///      Post-gameOver: deterministic payout. During game: gambling path.
         /// @param amount Amount of sDGNRS-equivalent to burn (from DGNRS wrapper balance)
         /// @return ethOut ETH received (deterministic path only)
         /// @return stethOut stETH received (deterministic path only)
         /// @return burnieOut BURNIE received (deterministic path only)
         /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
         function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
             if (game.gameOver()) {
                 (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
                 return (ethOut, stethOut, 0);
             }
             if (game.rngLocked()) revert BurnsBlockedDuringRng();
             _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
             return (0, 0, 0);

453:     /// @notice Burn wrapped DGNRS (held in the DGNRS contract) to claim proportional backing assets
         /// @dev Calls dgnrsWrapper to convert DGNRS to sDGNRS credit, then burns the resulting sDGNRS.
         ///      Post-gameOver: deterministic payout. During game: gambling path.
         /// @param amount Amount of sDGNRS-equivalent to burn (from DGNRS wrapper balance)
         /// @return ethOut ETH received (deterministic path only)
         /// @return stethOut stETH received (deterministic path only)
         /// @return burnieOut BURNIE received (deterministic path only)
         /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
         function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
             if (game.gameOver()) {
                 (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
                 return (ethOut, stethOut, 0);

472:     /// @dev Deterministic burn: player burns their own sDGNRS and receives backing assets directly.
         function _deterministicBurn(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {
             return _deterministicBurnFrom(player, player, amount);

535:     /// @notice Called by game contract to resolve the current redemption period with a dice roll
         /// @dev Adjusts segregated ETH by roll and returns rolled BURNIE amount for the game to credit.
         /// @param roll The random roll result (range 25-175, applied as percentage)
         /// @param flipDay Coinflip day index used for BURNIE gamble resolution
         /// @return burnieToCredit Amount of BURNIE the game should credit to the coinflip contract
         function resolveRedemptionPeriod(uint16 roll, uint48 flipDay) external returns (uint256 burnieToCredit) {
             if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
     
             uint48 period = redemptionPeriodIndex;
             if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0;

645:     /// @notice Preview ETH, stETH, and BURNIE output for burning sDGNRS
         /// @dev Reflects ETH-preferential payout logic using current balances and claimables.
         ///      Deducts pendingRedemptionEthValue and pendingRedemptionBurnie to exclude reserved
         ///      gambling burn amounts (CP-08). GameOver burns pay no BURNIE (pure ETH/stETH).
         /// @param amount Amount of sDGNRS to burn
         /// @return ethOut ETH that would be received
         /// @return stethOut stETH that would be received
         /// @return burnieOut BURNIE that would be received (0 during gameOver)
         function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
             uint256 supply = totalSupply;
             if (amount == 0 || amount > supply) return (0, 0, 0);

810:     /// @dev Get claimable game winnings, accounting for dust (returns 0 if stored <= 1)
         /// @return claimable Claimable winnings minus 1 wei dust
         function _claimableWinnings() private view returns (uint256 claimable) {
             uint256 stored = game.claimableWinningsOf(address(this));
             if (stored <= 1) return 0;
             return stored - 1;

```

```solidity
File: libraries/JackpotBucketLib.sol

53:     /// @dev Scales base bucket counts by jackpot size (excluding solo) with a hard cap.
        ///      1x under 10 ETH, linearly to 2x by 50 ETH, linearly to maxScaleBps by 200 ETH, then capped.
        function scaleTraitBucketCountsWithCap(
            uint16[4] memory baseCounts,
            uint256 ethPool,
            uint256 entropy,
            uint16 maxTotal,
            uint32 maxScaleBps
        ) internal pure returns (uint16[4] memory counts) {
            counts = baseCounts;
    
            if (ethPool < JACKPOT_SCALE_MIN_WEI) return counts;
    
            uint256 scaleBps;
            if (ethPool < JACKPOT_SCALE_FIRST_WEI) {
                uint256 range = JACKPOT_SCALE_FIRST_WEI - JACKPOT_SCALE_MIN_WEI;
                uint256 progress = ethPool - JACKPOT_SCALE_MIN_WEI;
                scaleBps = JACKPOT_SCALE_BASE_BPS + (progress * (JACKPOT_SCALE_FIRST_BPS - JACKPOT_SCALE_BASE_BPS)) / range;
            } else if (ethPool < JACKPOT_SCALE_SECOND_WEI) {
                uint256 range = JACKPOT_SCALE_SECOND_WEI - JACKPOT_SCALE_FIRST_WEI;
                uint256 progress = ethPool - JACKPOT_SCALE_FIRST_WEI;
                scaleBps = JACKPOT_SCALE_FIRST_BPS + (progress * (uint256(maxScaleBps) - JACKPOT_SCALE_FIRST_BPS)) / range;
            } else {
                scaleBps = maxScaleBps;
            }
    
            if (scaleBps != JACKPOT_SCALE_BASE_BPS) {
                for (uint8 i; i < 4; ) {
                    uint16 baseCount = counts[i];
                    if (baseCount > 1) {
                        uint256 scaled = (uint256(baseCount) * scaleBps) / 10_000;
                        if (scaled < baseCount) scaled = baseCount;
                        if (scaled > type(uint16).max) scaled = type(uint16).max;
                        counts[i] = uint16(scaled);
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
    
            return capBucketCounts(counts, maxTotal, entropy);

53:     /// @dev Scales base bucket counts by jackpot size (excluding solo) with a hard cap.
        ///      1x under 10 ETH, linearly to 2x by 50 ETH, linearly to maxScaleBps by 200 ETH, then capped.
        function scaleTraitBucketCountsWithCap(
            uint16[4] memory baseCounts,
            uint256 ethPool,
            uint256 entropy,
            uint16 maxTotal,
            uint32 maxScaleBps
        ) internal pure returns (uint16[4] memory counts) {
            counts = baseCounts;
    
            if (ethPool < JACKPOT_SCALE_MIN_WEI) return counts;

97:     /// @dev Computes base + scaled bucket counts for a given pool with cap; returns zeroes when pool is empty.
        function bucketCountsForPoolCap(
            uint256 ethPool,
            uint256 entropy,
            uint16 maxTotal,
            uint32 maxScaleBps
        ) internal pure returns (uint16[4] memory bucketCounts) {
            if (ethPool == 0) return bucketCounts;
            uint16[4] memory baseCounts = traitBucketCounts(entropy);
            return scaleTraitBucketCountsWithCap(baseCounts, ethPool, entropy, maxTotal, maxScaleBps);

97:     /// @dev Computes base + scaled bucket counts for a given pool with cap; returns zeroes when pool is empty.
        function bucketCountsForPoolCap(
            uint256 ethPool,
            uint256 entropy,
            uint16 maxTotal,
            uint32 maxScaleBps
        ) internal pure returns (uint16[4] memory bucketCounts) {
            if (ethPool == 0) return bucketCounts;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
     
             uint256 total = sumBucketCounts(counts);
             if (total == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
             if (maxTotal == 1) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 capped[soloBucketIndex(entropy)] = 1;
                 return capped;
             }
             if (total <= maxTotal) return capped;
     
             uint256 nonSoloCap = uint256(maxTotal) - 1;
             uint256 nonSoloTotal = total - 1;
             uint256 scaledTotal;
     
             for (uint8 i; i < 4; ) {
                 uint16 bucketCount = counts[i];
                 if (bucketCount > 1) {
                     uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;
                     if (scaled == 0) scaled = 1;
                     capped[i] = uint16(scaled);
                     scaledTotal += scaled;
                 }
                 unchecked {
                     ++i;
                 }
             }
     
             // When nonSoloCap is very small (e.g. 1-2), the minimum-1 guarantee
             // for each non-solo bucket can cause scaledTotal to exceed nonSoloCap.
             // Trim excess by zeroing out the smallest non-solo buckets.
             if (scaledTotal > nonSoloCap) {
                 uint256 excess = scaledTotal - nonSoloCap;
                 uint8 trimOff = uint8((entropy >> 24) & 3);
                 for (uint8 i; i < 4 && excess != 0; ) {
                     uint8 idx = uint8((uint256(trimOff) + 3 - i) & 3);
                     if (capped[idx] == 1 && counts[idx] > 1) {
                         capped[idx] = 0;
                         unchecked {
                             --excess;
                         }
                     }
                     unchecked {
                         ++i;
                     }
                 }
                 return capped;
             }
     
             uint256 remainder = nonSoloCap - scaledTotal;
             if (remainder != 0) {
                 uint8 offset = uint8((entropy >> 24) & 3);
                 for (uint8 i; i < 4 && remainder != 0; ) {
                     uint8 idx = uint8((uint256(offset) + i) & 3);
                     if (capped[idx] > 1) {
                         capped[idx] += 1;
                         unchecked {
                             --remainder;
                         }
                     }
                     unchecked {
                         ++i;
                     }
                 }
             }
     
             return capped;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
     
             uint256 total = sumBucketCounts(counts);
             if (total == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
             if (maxTotal == 1) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 capped[soloBucketIndex(entropy)] = 1;
                 return capped;
             }
             if (total <= maxTotal) return capped;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
     
             uint256 total = sumBucketCounts(counts);
             if (total == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
     
             uint256 total = sumBucketCounts(counts);
             if (total == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
             if (maxTotal == 1) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 capped[soloBucketIndex(entropy)] = 1;
                 return capped;

114:     /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
         function capBucketCounts(
             uint16[4] memory counts,
             uint16 maxTotal,
             uint256 entropy
         ) internal pure returns (uint16[4] memory capped) {
             capped = counts;
             if (maxTotal == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
     
             uint256 total = sumBucketCounts(counts);
             if (total == 0) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 return capped;
             }
             if (maxTotal == 1) {
                 capped[0] = 0;
                 capped[1] = 0;
                 capped[2] = 0;
                 capped[3] = 0;
                 capped[soloBucketIndex(entropy)] = 1;
                 return capped;
             }
             if (total <= maxTotal) return capped;
     
             uint256 nonSoloCap = uint256(maxTotal) - 1;
             uint256 nonSoloTotal = total - 1;
             uint256 scaledTotal;
     
             for (uint8 i; i < 4; ) {
                 uint16 bucketCount = counts[i];
                 if (bucketCount > 1) {
                     uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;
                     if (scaled == 0) scaled = 1;
                     capped[i] = uint16(scaled);
                     scaledTotal += scaled;
                 }
                 unchecked {
                     ++i;
                 }
             }
     
             // When nonSoloCap is very small (e.g. 1-2), the minimum-1 guarantee
             // for each non-solo bucket can cause scaledTotal to exceed nonSoloCap.
             // Trim excess by zeroing out the smallest non-solo buckets.
             if (scaledTotal > nonSoloCap) {
                 uint256 excess = scaledTotal - nonSoloCap;
                 uint8 trimOff = uint8((entropy >> 24) & 3);
                 for (uint8 i; i < 4 && excess != 0; ) {
                     uint8 idx = uint8((uint256(trimOff) + 3 - i) & 3);
                     if (capped[idx] == 1 && counts[idx] > 1) {
                         capped[idx] = 0;
                         unchecked {
                             --excess;
                         }
                     }
                     unchecked {
                         ++i;
                     }
                 }
                 return capped;

```

### <a name="NC-27"></a>[NC-27] Take advantage of Custom Error's return value property
An important feature of Custom Error is that values such as address, tokenID, msg.value can be written inside the () sign, this kind of approach provides a serious advantage in debugging and examining the revert details of dapps such as tenderly.

*Instances (280)*:
```solidity
File: BurnieCoin.sol

444:         if (value > type(uint128).max) revert SupplyOverflow();

454:         if (from == address(0) || to == address(0)) revert ZeroAddress();

480:         if (to == address(0)) revert ZeroAddress();

500:         if (from == address(0)) revert ZeroAddress();

504:             if (amount128 > allowanceVault) revert Insufficient();

529:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

538:         if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity

547:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

637:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

648:         ) revert OnlyTrustedContracts();

659:         ) revert OnlyFlipCreditors();

666:         if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();

673:         if (msg.sender != ContractAddresses.ADMIN) revert OnlyGame();

693:         ) revert OnlyVault();

706:         if (to == address(0)) revert ZeroAddress();

709:         if (amount128 > allowanceVault) revert Insufficient();

728:         if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();

787:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

816:         if (sender != ContractAddresses.GAME) revert OnlyGame();

843:         if (sender != ContractAddresses.GAME) revert OnlyGame();

896:                 revert NotApproved();

901:         if (amount < DECIMATOR_MIN) revert AmountLTMin();

904:         if (!open) revert NotDecimatorWindow();

987:                 revert NotApproved();

992:         if (amount < DECIMATOR_MIN) revert AmountLTMin();

995:         if (!open) revert NotDecimatorWindow();

```

```solidity
File: BurnieCoinflip.sol

191:         if (msg.sender != address(degenerusGame)) revert OnlyDegenerusGame();

199:         ) revert OnlyFlipCreditors();

204:         if (msg.sender != address(burnie)) revert OnlyBurnieCoin();

233:                 revert NotApproved();

249:             if (amount < MIN) revert AmountLTMin();

252:             if (_coinflipLockedDuringTransition()) revert CoinflipLocked();

349:         if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();

576:                 revert RngLocked();

649:                 if (recordAmount > type(uint128).max) revert Insufficient();

706:         if (degenerusGame.rngLocked()) revert RngLocked();

711:                 if (strict) revert AutoRebuyAlreadyEnabled();

756:         if (degenerusGame.rngLocked()) revert RngLocked();

758:         if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();

1117:                 revert NotApproved();

1126:             revert NotApproved();

```

```solidity
File: DegenerusAdmin.sol

323:         if (!vault.isVaultOwner(msg.sender)) revert NotOwner();

359:         if (_feedHealthy(current)) revert FeedHealthy();

364:             revert InvalidFeedDecimals();

375:         if (msg.value == 0) revert InvalidAmount();

402:         if (subscriptionId == 0) revert NotWired();

403:         if (gameAdmin.gameOver()) revert GameOver();

405:             revert ZeroAddress();

413:                 revert AlreadyHasActiveProposal();

422:             if (stall < ADMIN_STALL_THRESHOLD) revert NotStalled();

425:             if (stall < COMMUNITY_STALL_THRESHOLD) revert NotStalled();

428:                 revert InsufficientStake();

456:             revert NotStalled();

460:             revert ProposalNotActive();

465:             revert ProposalExpired();

471:         if (weight == 0) revert InsufficientStake();

652:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

688:         if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();

689:         if (amount == 0) revert InvalidAmount();

692:         if (subId == 0) revert NoSubscription();

693:         if (gameAdmin.gameOver()) revert GameOver();

705:             if (!ok) revert InvalidAmount();

707:             revert InvalidAmount();

```

```solidity
File: DegenerusAffiliate.sol

246:         ) revert Insufficient();

329:         if (referrer == address(0) || referrer == msg.sender) revert Insufficient();

332:         if (existing != bytes32(0) && !_vaultReferralMutable(existing)) revert Insufficient();

411:         ) revert OnlyAuthorized();

764:         if (owner == address(0)) revert Zero();

766:         if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();

768:         if (uint256(code_) <= type(uint160).max) revert Zero();

770:         if (kickbackPct > MAX_KICKBACK_PCT) revert InvalidKickback();

773:         if (info.owner != address(0)) revert Insufficient();

783:         if (player == address(0)) revert Zero();

786:         if (referrer == address(0) || referrer == player) revert Insufficient();

787:         if (playerReferralCode[player] != bytes32(0)) revert Insufficient();

```

```solidity
File: DegenerusDeityPass.sol

72:         if (msg.sender != _contractOwner) revert NotAuthorized();

90:         if (newOwner == address(0)) revert ZeroAddress();

113:             revert InvalidColor();

130:         if (_owners[tokenId] == address(0)) revert InvalidToken();

334:         if (account == address(0)) revert ZeroAddress();

340:         if (ownerAddr == address(0)) revert InvalidToken();

344:         if (_owners[tokenId] == address(0)) revert InvalidToken();

357:         revert Soulbound();

361:         revert Soulbound();

365:         revert Soulbound();

369:         revert Soulbound();

373:         revert Soulbound();

382:         if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();

383:         if (tokenId >= 32) revert InvalidToken();

384:         if (_owners[tokenId] != address(0)) revert InvalidToken();

385:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: DegenerusGame.sol

385:         if (msg.sender != address(this)) revert E();

425:         if (msg.sender != ContractAddresses.COIN) revert E();

443:         ) revert E();

469:         if (operator == address(0)) revert E();

487:             revert NotApproved();

513:         if (msg.sender != ContractAddresses.ADMIN) revert E();

514:         if (newThreshold == 0) revert E();

803:         ) revert E();

824:         if (msg.sender != ContractAddresses.COIN) revert E();

845:         if (msg.sender != address(this)) revert E();

900:         if (recipient == deity) revert E();

937:             if (msg.value < amount) revert E();

942:             if (msg.value != 0) revert E();

945:             if (claimable <= amount) revert E();

954:             if (msg.value > amount) revert E();

972:             if (remaining != 0) revert E(); // Must fully cover cost

975:             revert E();

1022:         if (reason.length == 0) revert E();

1083:         if (data.length == 0) revert E();

1098:         if (msg.sender != address(this)) revert E();

1110:         if (data.length == 0) revert E();

1145:         if (msg.sender != address(this)) revert E();

1157:         if (data.length == 0) revert E();

1181:         if (msg.sender != address(this)) revert E();

1193:         if (data.length == 0) revert E();

1206:         if (msg.sender != address(this)) revert E();

1217:         if (data.length == 0) revert E();

1353:         if (msg.sender != ContractAddresses.VAULT) revert E();

1358:         if (finalSwept) revert E();

1360:         if (amount <= 1) revert E();

1388:         if (currLevel == 0) revert E();

1390:         if (affiliateDgnrsClaimedBy[currLevel][player]) revert E();

1394:         if (!hasDeityPass && score < AFFILIATE_DGNRS_MIN_SCORE) revert E();

1397:         if (denominator == 0) revert E();

1400:         if (allocation == 0) revert E();

1402:         if (reward == 0) revert E();

1409:         if (paid == 0) revert E();

1467:         if (rngLockedFlag) revert RngLocked();

1488:         if (rngLockedFlag) revert RngLocked();

1503:         if (rngLockedFlag) revert RngLocked();

1568:         if (rngLockedFlag) revert RngLocked();

1573:         if (!_hasAnyLazyPass(player)) revert E();

1649:         ) revert E();

1661:         if (msg.sender != ContractAddresses.COINFLIP) revert E();

1680:             if (uint256(level) < unlockLevel) revert AfKingLockActive();

1731:         if (msg.sender != ContractAddresses.SDGNRS) revert E();

1813:         if (msg.sender != ContractAddresses.ADMIN) revert E();

1814:         if (recipient == address(0)) revert E();

1815:         if (amount == 0 || msg.value != amount) revert E();

1818:         if (stBal < amount) revert E();

1819:         if (!steth.transfer(recipient, amount)) revert E();

1830:         if (msg.sender != ContractAddresses.ADMIN) revert E();

1831:         if (amount == 0) revert E();

1834:         if (ethBal < amount) revert E();

1841:         if (ethBal <= reserve) revert E();

1843:         if (amount > stakeable) revert E();

1847:             revert E();

1959:             if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();

1963:         if (!steth.transfer(to, amount)) revert E();

1979:             if (!okEth) revert E();

1994:             if (ethRetry < leftover) revert E();

1996:             if (!ok) revert E();

2015:         if (ethBal < remaining) revert E();

2017:         if (!ok) revert E();

2840:         if (gameOver) revert E();

```

```solidity
File: DegenerusJackpots.sol

142:         if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();

149:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

```

```solidity
File: DegenerusQuests.sol

286:         if (sender != ContractAddresses.COIN && sender != ContractAddresses.COINFLIP) revert OnlyCoin();

291:         if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

```

```solidity
File: DegenerusStonk.sol

90:         if (deposited == 0) revert Insufficient();

99:         if (msg.sender != address(stonk)) revert Unauthorized();

129:             if (amount > allowed) revert Insufficient();

154:         if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();

155:         if (recipient == address(0)) revert ZeroAddress();

158:             revert Unauthorized();

174:         if (!IDegenerusGame(ContractAddresses.GAME).gameOver()) revert GameNotOver();

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

182:             if (!steth.transfer(msg.sender, stethOut)) revert TransferFailed();

186:             if (!success) revert TransferFailed();

211:         if (to == address(0)) revert ZeroAddress();

212:         if (to == address(this)) revert Unauthorized();

214:         if (amount > bal) revert Insufficient();

225:         if (amount == 0 || amount > bal) revert Insufficient();

251:         if (!gameContract.gameOver()) revert SweepNotReady();

253:         if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

256:         if (remaining == 0) revert NothingToSweep();

268:             if (!steth.transfer(ContractAddresses.GNRUS, stethToGnrus)) revert TransferFailed();

271:             if (!steth.transfer(ContractAddresses.VAULT, stethToVault)) revert TransferFailed();

276:             if (!ok) revert TransferFailed();

280:             if (!ok) revert TransferFailed();

296:         if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();

298:         if (amount == 0 || amount > bal) revert Insufficient();

```

```solidity
File: DegenerusVault.sol

187:         if (msg.sender != ContractAddresses.VAULT) revert Unauthorized();

240:             if (allowed < amount) revert Insufficient();

259:         if (to == address(0)) revert ZeroAddress();

275:         if (amount > bal) revert Insufficient();

291:         if (to == address(0)) revert ZeroAddress();

293:         if (amount > bal) revert Insufficient();

394:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

400:         if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();

408:             revert NotApproved();

511:         if (ticketQuantity == 0) revert Insufficient();

520:         if (burnieAmount == 0) revert Insufficient();

537:         if (priceWei == 0) revert Insufficient();

544:         if (address(this).balance < priceWei) revert Insufficient();

578:         if (totalValue > totalBet) revert Insufficient();

764:         if (amount == 0) revert Insufficient();

786:                 if (!coinToken.transfer(player, payBal)) revert TransferFailed();

793:                     if (!coinToken.transfer(player, claimed)) revert TransferFailed();

838:         if (amount == 0) revert Insufficient();

864:             if (stEthOut > stBal) revert Insufficient();

889:         if (coinOut == 0 || coinOut > reserve) revert Insufficient();

906:         if (targetValue == 0 || targetValue > reserve) revert Insufficient();

929:         if (amount == 0 || amount > supply) revert Insufficient();

941:         if (amount == 0 || amount > supply) revert Insufficient();

964:         if (totalValue > address(this).balance) revert Insufficient();

1033:         if (!ok) revert TransferFailed();

1040:         if (!steth.transfer(to, amount)) revert TransferFailed();

1048:         if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();

```

```solidity
File: GNRUS.sol

237:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

255:     function transfer(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

258:     function transferFrom(address, address, uint256) external pure returns (bool) { revert TransferDisabled(); }

261:     function approve(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

275:         if (amount < MIN_BURN) revert InsufficientBurn();

315:             if (!steth.transfer(burner, stethOut)) revert TransferFailed();

319:             if (!ok) revert TransferFailed();

333:         if (finalized) revert AlreadyFinalized();

357:         if (recipient == address(0)) revert ZeroAddress();

358:         if (recipient.code.length != 0) revert RecipientIsContract();

372:             if (creatorProposalCount[level] >= MAX_CREATOR_PROPOSALS) revert ProposalLimitReached();

376:             if ((sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();

377:             if (hasProposed[level][proposer]) revert AlreadyProposed();

411:         if (count == 0 || proposalId < start || proposalId >= start + count) revert InvalidProposal();

414:         if (hasVoted[level][voter][proposalId]) revert AlreadyVoted();

423:         if (weight == 0) revert InsufficientStake();

445:         if (level != currentLevel) revert LevelNotActive();

446:         if (levelResolved[level]) revert LevelAlreadyResolved();

532:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: Icons32Data.sol

154:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

155:         if (_finalized) revert AlreadyFinalized();

156:         if (paths.length > 10) revert MaxBatch();

157:         if (startIndex + paths.length > 33) revert IndexOutOfBounds();

172:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

173:         if (_finalized) revert AlreadyFinalized();

188:             revert InvalidQuadrant();

197:         if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();

198:         if (_finalized) revert AlreadyFinalized();

```

```solidity
File: StakedDegenerusStonk.sol

250:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

311:         if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();

312:         if (to == address(0)) revert ZeroAddress();

314:         if (amount > bal) revert Insufficient();

353:         if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

378:         if (to == address(0)) revert ZeroAddress();

448:         if (game.rngLocked()) revert BurnsBlockedDuringRng();

467:         if (game.rngLocked()) revert BurnsBlockedDuringRng();

483:         if (amount == 0 || amount > bal) revert Insufficient();

509:             if (stethOut > stethBal) revert Insufficient();

513:             if (!steth.transfer(beneficiary, stethOut)) revert TransferFailed();

518:             if (!success) revert TransferFailed();

541:         if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

576:         if (claim.periodIndex == 0) revert NoClaim();

579:         if (period.roll == 0) revert NotResolved();

709:         if (amount == 0 || amount > bal) revert Insufficient();

718:         if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();

752:             revert UnresolvedClaim();

756:         if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

784:             if (!success) revert TransferFailed();

790:                 if (!success) revert TransferFailed();

792:             if (!steth.transfer(player, stethOut)) revert TransferFailed();

802:             if (!coin.transfer(player, payBal)) revert TransferFailed();

806:             if (!coin.transfer(player, remaining)) revert TransferFailed();

830:         if (to == address(0)) revert ZeroAddress();

```

```solidity
File: WrappedWrappedXRP.sol

229:             if (allowed < amount) revert InsufficientAllowance();

242:         if (from == address(0) || to == address(0)) revert ZeroAddress();

243:         if (balanceOf[from] < amount) revert InsufficientBalance();

255:         if (to == address(0)) revert ZeroAddress();

267:         if (from == address(0)) revert ZeroAddress();

268:         if (balanceOf[from] < amount) revert InsufficientBalance();

291:         if (amount == 0) revert ZeroAmount();

294:         if (wXRPReserves < amount) revert InsufficientReserves();

302:             revert TransferFailed();

315:         if (amount == 0) revert ZeroAmount();

319:             revert TransferFailed();

348:             revert OnlyMinter();

350:         if (amount == 0) revert ZeroAmount();

364:         if (msg.sender != MINTER_VAULT) revert OnlyVault();

365:         if (to == address(0)) revert ZeroAddress();

369:         if (amount > allowanceVault) revert InsufficientVaultAllowance();

385:         if (msg.sender != MINTER_GAME) revert OnlyMinter();

```

### <a name="NC-28"></a>[NC-28] Deprecated library used for Solidity `>= 0.8` : SafeMath

*Instances (1)*:
```solidity
File: BurnieCoin.sol

155:       |  0.8+ overflow checks. No SafeMath needed.                           |

```

### <a name="NC-29"></a>[NC-29] Strings should use double quotes rather than single quotes
See the Solidity Style Guide: https://docs.soliditylang.org/en/v0.8.20/style-guide.html#other-recommendations

*Instances (15)*:
```solidity
File: DegenerusDeityPass.sol

163:             '{"name":"Deity Pass #', Strings.toString(tokenId), ' - ', symbolName,

164:             '","description":"Degenerus Deity Pass. Grants divine authority over the ',

165:             symbolName, ' symbol.","image":"data:image/svg+xml;base64,',

167:             '"}'

191:                     ? "'><g style='vector-effect:non-scaling-stroke'>"

192:                     : "'><g class='nonCrypto' style='vector-effect:non-scaling-stroke'>",

199:             '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'

200:             '<defs>'

201:             '<style>.nonCrypto *{fill:',

203:             '!important;stroke:',

205:             '!important;}</style>'

206:             '</defs>'

207:             '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',

209:             '" stroke="',

211:             '" stroke-width="2.2"/>',

```

### <a name="NC-30"></a>[NC-30] Contract does not follow the Solidity style guide's suggested layout ordering
The [style guide](https://docs.soliditylang.org/en/v0.8.16/style-guide.html#order-of-layout) says that, within a contract, the ordering should be:

1) Type declarations
2) State variables
3) Events
4) Modifiers
5) Functions

However, the contract(s) below do not follow this ordering

*Instances (15)*:
```solidity
File: BurnieCoin.sol

1: 
   Current order:
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.claimCoinflipsFromBurnie
   FunctionDefinition.consumeCoinflipsForBurn
   FunctionDefinition.coinflipAmount
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.DecimatorBurn
   EventDefinition.TerminalDecimatorBurn
   EventDefinition.DailyQuestRolled
   EventDefinition.QuestCompleted
   EventDefinition.LinkCreditRecorded
   EventDefinition.VaultEscrowRecorded
   EventDefinition.VaultAllowanceSpent
   ErrorDefinition.OnlyGame
   ErrorDefinition.OnlyVault
   ErrorDefinition.Insufficient
   ErrorDefinition.AmountLTMin
   ErrorDefinition.ZeroAddress
   ErrorDefinition.NotDecimatorWindow
   ErrorDefinition.OnlyAffiliate
   ErrorDefinition.OnlyTrustedContracts
   ErrorDefinition.OnlyFlipCreditors
   ErrorDefinition.NotApproved
   ErrorDefinition.SupplyOverflow
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.DECIMATOR_MIN
   VariableDeclaration.DECIMATOR_BUCKET_BASE
   VariableDeclaration.DECIMATOR_MIN_BUCKET_NORMAL
   VariableDeclaration.DECIMATOR_MIN_BUCKET_100
   VariableDeclaration.DECIMATOR_ACTIVITY_CAP_BPS
   VariableDeclaration.DECIMATOR_BOON_CAP
   VariableDeclaration.QUEST_TYPE_MINT_ETH
   VariableDeclaration.BPS_DENOMINATOR
   StructDefinition.Supply
   VariableDeclaration._supply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.degenerusGame
   VariableDeclaration.questModule
   VariableDeclaration.coinflipContract
   FunctionDefinition.constructor
   FunctionDefinition.claimableCoin
   FunctionDefinition.balanceOfWithClaimable
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.totalSupply
   FunctionDefinition.supplyIncUncirculated
   FunctionDefinition.vaultMintAllowance
   VariableDeclaration.decimals
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition._toUint128
   FunctionDefinition._transfer
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.burnForCoinflip
   FunctionDefinition.mintForCoinflip
   FunctionDefinition.mintForGame
   FunctionDefinition.creditCoin
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.creditLinkReward
   FunctionDefinition._claimCoinflipShortfall
   FunctionDefinition._consumeCoinflipShortfall
   ModifierDefinition.onlyDegenerusGameContract
   ModifierDefinition.onlyTrustedContracts
   ModifierDefinition.onlyFlipCreditors
   ModifierDefinition.onlyVault
   ModifierDefinition.onlyAdmin
   FunctionDefinition.vaultEscrow
   FunctionDefinition.vaultMintTo
   FunctionDefinition.affiliateQuestReward
   FunctionDefinition.rollDailyQuest
   FunctionDefinition.notifyQuestMint
   FunctionDefinition.notifyQuestLootBox
   FunctionDefinition.notifyQuestDegenerette
   FunctionDefinition.burnCoin
   FunctionDefinition.decimatorBurn
   FunctionDefinition.terminalDecimatorBurn
   FunctionDefinition.coinflipAmount
   FunctionDefinition._adjustDecimatorBucket
   FunctionDefinition._decimatorBurnMultiplier
   FunctionDefinition._questApplyReward
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.DECIMATOR_MIN
   VariableDeclaration.DECIMATOR_BUCKET_BASE
   VariableDeclaration.DECIMATOR_MIN_BUCKET_NORMAL
   VariableDeclaration.DECIMATOR_MIN_BUCKET_100
   VariableDeclaration.DECIMATOR_ACTIVITY_CAP_BPS
   VariableDeclaration.DECIMATOR_BOON_CAP
   VariableDeclaration.QUEST_TYPE_MINT_ETH
   VariableDeclaration.BPS_DENOMINATOR
   VariableDeclaration._supply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.degenerusGame
   VariableDeclaration.questModule
   VariableDeclaration.coinflipContract
   VariableDeclaration.decimals
   StructDefinition.Supply
   ErrorDefinition.OnlyGame
   ErrorDefinition.OnlyVault
   ErrorDefinition.Insufficient
   ErrorDefinition.AmountLTMin
   ErrorDefinition.ZeroAddress
   ErrorDefinition.NotDecimatorWindow
   ErrorDefinition.OnlyAffiliate
   ErrorDefinition.OnlyTrustedContracts
   ErrorDefinition.OnlyFlipCreditors
   ErrorDefinition.NotApproved
   ErrorDefinition.SupplyOverflow
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.DecimatorBurn
   EventDefinition.TerminalDecimatorBurn
   EventDefinition.DailyQuestRolled
   EventDefinition.QuestCompleted
   EventDefinition.LinkCreditRecorded
   EventDefinition.VaultEscrowRecorded
   EventDefinition.VaultAllowanceSpent
   ModifierDefinition.onlyDegenerusGameContract
   ModifierDefinition.onlyTrustedContracts
   ModifierDefinition.onlyFlipCreditors
   ModifierDefinition.onlyVault
   ModifierDefinition.onlyAdmin
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.claimCoinflipsFromBurnie
   FunctionDefinition.consumeCoinflipsForBurn
   FunctionDefinition.coinflipAmount
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.constructor
   FunctionDefinition.claimableCoin
   FunctionDefinition.balanceOfWithClaimable
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.totalSupply
   FunctionDefinition.supplyIncUncirculated
   FunctionDefinition.vaultMintAllowance
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition._toUint128
   FunctionDefinition._transfer
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.burnForCoinflip
   FunctionDefinition.mintForCoinflip
   FunctionDefinition.mintForGame
   FunctionDefinition.creditCoin
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.creditLinkReward
   FunctionDefinition._claimCoinflipShortfall
   FunctionDefinition._consumeCoinflipShortfall
   FunctionDefinition.vaultEscrow
   FunctionDefinition.vaultMintTo
   FunctionDefinition.affiliateQuestReward
   FunctionDefinition.rollDailyQuest
   FunctionDefinition.notifyQuestMint
   FunctionDefinition.notifyQuestLootBox
   FunctionDefinition.notifyQuestDegenerette
   FunctionDefinition.burnCoin
   FunctionDefinition.decimatorBurn
   FunctionDefinition.terminalDecimatorBurn
   FunctionDefinition.coinflipAmount
   FunctionDefinition._adjustDecimatorBucket
   FunctionDefinition._decimatorBurnMultiplier
   FunctionDefinition._questApplyReward

```

```solidity
File: BurnieCoinflip.sol

1: 
   Current order:
   FunctionDefinition.burnForCoinflip
   FunctionDefinition.mintForCoinflip
   FunctionDefinition.mintPrize
   EventDefinition.CoinflipDeposit
   EventDefinition.CoinflipAutoRebuyToggled
   EventDefinition.CoinflipAutoRebuyStopSet
   EventDefinition.QuestCompleted
   EventDefinition.CoinflipStakeUpdated
   EventDefinition.CoinflipDayResolved
   EventDefinition.CoinflipTopUpdated
   EventDefinition.BiggestFlipUpdated
   EventDefinition.BountyOwed
   EventDefinition.BountyPaid
   ErrorDefinition.AmountLTMin
   ErrorDefinition.CoinflipLocked
   ErrorDefinition.OnlyFlipCreditors
   ErrorDefinition.OnlyBurnieCoin
   ErrorDefinition.OnlyStakedDegenerusStonk
   ErrorDefinition.OnlyDegenerusGame
   ErrorDefinition.AutoRebuyNotEnabled
   ErrorDefinition.AutoRebuyAlreadyEnabled
   ErrorDefinition.RngLocked
   ErrorDefinition.Insufficient
   ErrorDefinition.NotApproved
   VariableDeclaration.burnie
   VariableDeclaration.degenerusGame
   VariableDeclaration.jackpots
   VariableDeclaration.wwxrp
   VariableDeclaration.MIN
   VariableDeclaration.COINFLIP_LOSS_WWXRP_REWARD
   VariableDeclaration.COINFLIP_EXTRA_MIN_PERCENT
   VariableDeclaration.COINFLIP_EXTRA_RANGE
   VariableDeclaration.BPS_DENOMINATOR
   VariableDeclaration.AFKING_RECYCLE_BONUS_BPS
   VariableDeclaration.AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS
   VariableDeclaration.AFKING_DEITY_BONUS_MAX_HALF_BPS
   VariableDeclaration.DEITY_RECYCLE_CAP
   VariableDeclaration.JACKPOT_RESET_TIME
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.COIN_CLAIM_DAYS
   VariableDeclaration.COIN_CLAIM_FIRST_DAYS
   VariableDeclaration.AUTO_REBUY_OFF_CLAIM_DAYS_MAX
   VariableDeclaration.MAX_BAF_BRACKET
   VariableDeclaration.AFKING_KEEP_MIN_COIN
   VariableDeclaration.questModule
   StructDefinition.CoinflipDayResult
   StructDefinition.PlayerCoinflipState
   VariableDeclaration.coinflipBalance
   VariableDeclaration.coinflipDayResult
   VariableDeclaration.playerState
   VariableDeclaration.currentBounty
   VariableDeclaration.biggestFlipEver
   VariableDeclaration.bountyOwedTo
   VariableDeclaration.flipsClaimableDay
   StructDefinition.PlayerScore
   VariableDeclaration.coinflipTopByDay
   FunctionDefinition.constructor
   ModifierDefinition.onlyDegenerusGameContract
   ModifierDefinition.onlyFlipCreditors
   ModifierDefinition.onlyBurnieCoin
   FunctionDefinition.settleFlipModeChange
   FunctionDefinition.depositCoinflip
   FunctionDefinition._depositCoinflip
   FunctionDefinition.claimCoinflips
   FunctionDefinition.claimCoinflipsFromBurnie
   FunctionDefinition.claimCoinflipsForRedemption
   FunctionDefinition.getCoinflipDayResult
   FunctionDefinition.consumeCoinflipsForBurn
   FunctionDefinition._claimCoinflipsAmount
   FunctionDefinition._claimCoinflipsInternal
   FunctionDefinition._addDailyFlip
   FunctionDefinition.setCoinflipAutoRebuy
   FunctionDefinition.setCoinflipAutoRebuyTakeProfit
   FunctionDefinition._setCoinflipAutoRebuy
   FunctionDefinition._setCoinflipAutoRebuyTakeProfit
   FunctionDefinition.processCoinflipPayouts
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.coinflipAmount
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.coinflipTopLastDay
   FunctionDefinition._viewClaimableCoin
   FunctionDefinition._coinflipLockedDuringTransition
   FunctionDefinition._recyclingBonus
   FunctionDefinition._afKingRecyclingBonus
   FunctionDefinition._afKingDeityBonusHalfBpsWithLevel
   FunctionDefinition._targetFlipDay
   FunctionDefinition._questApplyReward
   FunctionDefinition._score96
   FunctionDefinition._updateTopDayBettor
   FunctionDefinition._bafBracketLevel
   FunctionDefinition._resolvePlayer
   FunctionDefinition._requireApproved
   
   Suggested order:
   VariableDeclaration.burnie
   VariableDeclaration.degenerusGame
   VariableDeclaration.jackpots
   VariableDeclaration.wwxrp
   VariableDeclaration.MIN
   VariableDeclaration.COINFLIP_LOSS_WWXRP_REWARD
   VariableDeclaration.COINFLIP_EXTRA_MIN_PERCENT
   VariableDeclaration.COINFLIP_EXTRA_RANGE
   VariableDeclaration.BPS_DENOMINATOR
   VariableDeclaration.AFKING_RECYCLE_BONUS_BPS
   VariableDeclaration.AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS
   VariableDeclaration.AFKING_DEITY_BONUS_MAX_HALF_BPS
   VariableDeclaration.DEITY_RECYCLE_CAP
   VariableDeclaration.JACKPOT_RESET_TIME
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.COIN_CLAIM_DAYS
   VariableDeclaration.COIN_CLAIM_FIRST_DAYS
   VariableDeclaration.AUTO_REBUY_OFF_CLAIM_DAYS_MAX
   VariableDeclaration.MAX_BAF_BRACKET
   VariableDeclaration.AFKING_KEEP_MIN_COIN
   VariableDeclaration.questModule
   VariableDeclaration.coinflipBalance
   VariableDeclaration.coinflipDayResult
   VariableDeclaration.playerState
   VariableDeclaration.currentBounty
   VariableDeclaration.biggestFlipEver
   VariableDeclaration.bountyOwedTo
   VariableDeclaration.flipsClaimableDay
   VariableDeclaration.coinflipTopByDay
   StructDefinition.CoinflipDayResult
   StructDefinition.PlayerCoinflipState
   StructDefinition.PlayerScore
   ErrorDefinition.AmountLTMin
   ErrorDefinition.CoinflipLocked
   ErrorDefinition.OnlyFlipCreditors
   ErrorDefinition.OnlyBurnieCoin
   ErrorDefinition.OnlyStakedDegenerusStonk
   ErrorDefinition.OnlyDegenerusGame
   ErrorDefinition.AutoRebuyNotEnabled
   ErrorDefinition.AutoRebuyAlreadyEnabled
   ErrorDefinition.RngLocked
   ErrorDefinition.Insufficient
   ErrorDefinition.NotApproved
   EventDefinition.CoinflipDeposit
   EventDefinition.CoinflipAutoRebuyToggled
   EventDefinition.CoinflipAutoRebuyStopSet
   EventDefinition.QuestCompleted
   EventDefinition.CoinflipStakeUpdated
   EventDefinition.CoinflipDayResolved
   EventDefinition.CoinflipTopUpdated
   EventDefinition.BiggestFlipUpdated
   EventDefinition.BountyOwed
   EventDefinition.BountyPaid
   ModifierDefinition.onlyDegenerusGameContract
   ModifierDefinition.onlyFlipCreditors
   ModifierDefinition.onlyBurnieCoin
   FunctionDefinition.burnForCoinflip
   FunctionDefinition.mintForCoinflip
   FunctionDefinition.mintPrize
   FunctionDefinition.constructor
   FunctionDefinition.settleFlipModeChange
   FunctionDefinition.depositCoinflip
   FunctionDefinition._depositCoinflip
   FunctionDefinition.claimCoinflips
   FunctionDefinition.claimCoinflipsFromBurnie
   FunctionDefinition.claimCoinflipsForRedemption
   FunctionDefinition.getCoinflipDayResult
   FunctionDefinition.consumeCoinflipsForBurn
   FunctionDefinition._claimCoinflipsAmount
   FunctionDefinition._claimCoinflipsInternal
   FunctionDefinition._addDailyFlip
   FunctionDefinition.setCoinflipAutoRebuy
   FunctionDefinition.setCoinflipAutoRebuyTakeProfit
   FunctionDefinition._setCoinflipAutoRebuy
   FunctionDefinition._setCoinflipAutoRebuyTakeProfit
   FunctionDefinition.processCoinflipPayouts
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.coinflipAmount
   FunctionDefinition.coinflipAutoRebuyInfo
   FunctionDefinition.coinflipTopLastDay
   FunctionDefinition._viewClaimableCoin
   FunctionDefinition._coinflipLockedDuringTransition
   FunctionDefinition._recyclingBonus
   FunctionDefinition._afKingRecyclingBonus
   FunctionDefinition._afKingDeityBonusHalfBpsWithLevel
   FunctionDefinition._targetFlipDay
   FunctionDefinition._questApplyReward
   FunctionDefinition._score96
   FunctionDefinition._updateTopDayBettor
   FunctionDefinition._bafBracketLevel
   FunctionDefinition._resolvePlayer
   FunctionDefinition._requireApproved

```

```solidity
File: DegenerusAdmin.sol

1: 
   Current order:
   FunctionDefinition.addConsumer
   FunctionDefinition.cancelSubscription
   FunctionDefinition.createSubscription
   FunctionDefinition.getSubscription
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.jackpotPhase
   FunctionDefinition.gameOver
   FunctionDefinition.updateVrfCoordinatorAndSub
   FunctionDefinition.wireVrf
   FunctionDefinition.adminSwapEthForStEth
   FunctionDefinition.adminStakeEthForStEth
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.purchaseInfo
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.transferAndCall
   FunctionDefinition.creditLinkReward
   FunctionDefinition.latestRoundData
   FunctionDefinition.decimals
   FunctionDefinition.isVaultOwner
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   EnumDefinition.Vote
   EnumDefinition.ProposalPath
   EnumDefinition.ProposalState
   StructDefinition.Proposal
   ErrorDefinition.NotOwner
   ErrorDefinition.NotAuthorized
   ErrorDefinition.ZeroAddress
   ErrorDefinition.NotStalled
   ErrorDefinition.NotWired
   ErrorDefinition.NoSubscription
   ErrorDefinition.InvalidAmount
   ErrorDefinition.GameOver
   ErrorDefinition.FeedHealthy
   ErrorDefinition.InvalidFeedDecimals
   ErrorDefinition.ProposalNotActive
   ErrorDefinition.ProposalExpired
   ErrorDefinition.InsufficientStake
   ErrorDefinition.AlreadyHasActiveProposal
   EventDefinition.CoordinatorUpdated
   EventDefinition.ConsumerAdded
   EventDefinition.SubscriptionCreated
   EventDefinition.SubscriptionCancelled
   EventDefinition.SubscriptionShutdown
   EventDefinition.LinkCreditRecorded
   EventDefinition.LinkEthFeedUpdated
   EventDefinition.ProposalCreated
   EventDefinition.VoteCast
   EventDefinition.ProposalExecuted
   EventDefinition.ProposalKilled
   VariableDeclaration.vrfCoordinator
   VariableDeclaration.gameAdmin
   VariableDeclaration.linkToken
   VariableDeclaration.coinLinkReward
   VariableDeclaration.sDGNRS
   VariableDeclaration.coordinator
   VariableDeclaration.subscriptionId
   VariableDeclaration.vrfKeyHash
   VariableDeclaration.proposalCount
   VariableDeclaration.proposals
   VariableDeclaration.votes
   VariableDeclaration.voteWeight
   VariableDeclaration.activeProposalId
   VariableDeclaration.voidedUpTo
   VariableDeclaration.linkEthPriceFeed
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.LINK_ETH_FEED_DECIMALS
   VariableDeclaration.LINK_ETH_MAX_STALE
   VariableDeclaration.ADMIN_STALL_THRESHOLD
   VariableDeclaration.COMMUNITY_STALL_THRESHOLD
   VariableDeclaration.COMMUNITY_PROPOSE_BPS
   VariableDeclaration.PROPOSAL_LIFETIME
   VariableDeclaration.BPS
   VariableDeclaration.vault
   ModifierDefinition.onlyOwner
   FunctionDefinition.constructor
   FunctionDefinition.setLinkEthPriceFeed
   FunctionDefinition.swapGameEthForStEth
   FunctionDefinition.stakeGameEthToStEth
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.propose
   FunctionDefinition.vote
   FunctionDefinition.circulatingSupply
   FunctionDefinition.threshold
   FunctionDefinition.canExecute
   FunctionDefinition._executeSwap
   FunctionDefinition._voidAllActive
   FunctionDefinition.shutdownVrf
   FunctionDefinition.onTokenTransfer
   FunctionDefinition.linkAmountToEth
   FunctionDefinition._linkRewardMultiplier
   FunctionDefinition._feedHealthy
   
   Suggested order:
   VariableDeclaration.vrfCoordinator
   VariableDeclaration.gameAdmin
   VariableDeclaration.linkToken
   VariableDeclaration.coinLinkReward
   VariableDeclaration.sDGNRS
   VariableDeclaration.coordinator
   VariableDeclaration.subscriptionId
   VariableDeclaration.vrfKeyHash
   VariableDeclaration.proposalCount
   VariableDeclaration.proposals
   VariableDeclaration.votes
   VariableDeclaration.voteWeight
   VariableDeclaration.activeProposalId
   VariableDeclaration.voidedUpTo
   VariableDeclaration.linkEthPriceFeed
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.LINK_ETH_FEED_DECIMALS
   VariableDeclaration.LINK_ETH_MAX_STALE
   VariableDeclaration.ADMIN_STALL_THRESHOLD
   VariableDeclaration.COMMUNITY_STALL_THRESHOLD
   VariableDeclaration.COMMUNITY_PROPOSE_BPS
   VariableDeclaration.PROPOSAL_LIFETIME
   VariableDeclaration.BPS
   VariableDeclaration.vault
   EnumDefinition.Vote
   EnumDefinition.ProposalPath
   EnumDefinition.ProposalState
   StructDefinition.Proposal
   ErrorDefinition.NotOwner
   ErrorDefinition.NotAuthorized
   ErrorDefinition.ZeroAddress
   ErrorDefinition.NotStalled
   ErrorDefinition.NotWired
   ErrorDefinition.NoSubscription
   ErrorDefinition.InvalidAmount
   ErrorDefinition.GameOver
   ErrorDefinition.FeedHealthy
   ErrorDefinition.InvalidFeedDecimals
   ErrorDefinition.ProposalNotActive
   ErrorDefinition.ProposalExpired
   ErrorDefinition.InsufficientStake
   ErrorDefinition.AlreadyHasActiveProposal
   EventDefinition.CoordinatorUpdated
   EventDefinition.ConsumerAdded
   EventDefinition.SubscriptionCreated
   EventDefinition.SubscriptionCancelled
   EventDefinition.SubscriptionShutdown
   EventDefinition.LinkCreditRecorded
   EventDefinition.LinkEthFeedUpdated
   EventDefinition.ProposalCreated
   EventDefinition.VoteCast
   EventDefinition.ProposalExecuted
   EventDefinition.ProposalKilled
   ModifierDefinition.onlyOwner
   FunctionDefinition.addConsumer
   FunctionDefinition.cancelSubscription
   FunctionDefinition.createSubscription
   FunctionDefinition.getSubscription
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.jackpotPhase
   FunctionDefinition.gameOver
   FunctionDefinition.updateVrfCoordinatorAndSub
   FunctionDefinition.wireVrf
   FunctionDefinition.adminSwapEthForStEth
   FunctionDefinition.adminStakeEthForStEth
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.purchaseInfo
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.transferAndCall
   FunctionDefinition.creditLinkReward
   FunctionDefinition.latestRoundData
   FunctionDefinition.decimals
   FunctionDefinition.isVaultOwner
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   FunctionDefinition.constructor
   FunctionDefinition.setLinkEthPriceFeed
   FunctionDefinition.swapGameEthForStEth
   FunctionDefinition.stakeGameEthToStEth
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.propose
   FunctionDefinition.vote
   FunctionDefinition.circulatingSupply
   FunctionDefinition.threshold
   FunctionDefinition.canExecute
   FunctionDefinition._executeSwap
   FunctionDefinition._voidAllActive
   FunctionDefinition.shutdownVrf
   FunctionDefinition.onTokenTransfer
   FunctionDefinition.linkAmountToEth
   FunctionDefinition._linkRewardMultiplier
   FunctionDefinition._feedHealthy

```

```solidity
File: DegenerusAffiliate.sol

1: 
   Current order:
   FunctionDefinition.creditCoin
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.affiliateQuestReward
   EventDefinition.Affiliate
   EventDefinition.ReferralUpdated
   EventDefinition.AffiliateEarningsRecorded
   EventDefinition.AffiliateTopUpdated
   ErrorDefinition.OnlyAuthorized
   ErrorDefinition.Zero
   ErrorDefinition.Insufficient
   ErrorDefinition.InvalidKickback
   StructDefinition.PlayerScore
   StructDefinition.AffiliateCodeInfo
   VariableDeclaration.AFFILIATE_BONUS_MAX
   VariableDeclaration.MAX_KICKBACK_PCT
   VariableDeclaration.REWARD_SCALE_FRESH_L1_3_BPS
   VariableDeclaration.REWARD_SCALE_FRESH_L4P_BPS
   VariableDeclaration.REWARD_SCALE_RECYCLED_BPS
   VariableDeclaration.BPS_DENOMINATOR
   VariableDeclaration.LOOTBOX_TAPER_START_SCORE
   VariableDeclaration.LOOTBOX_TAPER_END_SCORE
   VariableDeclaration.LOOTBOX_TAPER_MIN_BPS
   VariableDeclaration.MAX_COMMISSION_PER_REFERRER_PER_LEVEL
   VariableDeclaration.AFFILIATE_ROLL_TAG
   VariableDeclaration.REF_CODE_LOCKED
   VariableDeclaration.AFFILIATE_CODE_VAULT
   VariableDeclaration.AFFILIATE_CODE_DGNRS
   VariableDeclaration.coin
   VariableDeclaration.game
   VariableDeclaration.affiliateCode
   VariableDeclaration.affiliateCoinEarned
   VariableDeclaration.playerReferralCode
   VariableDeclaration.affiliateTopByLevel
   VariableDeclaration._totalAffiliateScore
   VariableDeclaration.affiliateCommissionFromSender
   FunctionDefinition.constructor
   FunctionDefinition.createAffiliateCode
   FunctionDefinition.referPlayer
   FunctionDefinition.getReferrer
   FunctionDefinition.defaultCode
   FunctionDefinition.payAffiliate
   FunctionDefinition.affiliateTop
   FunctionDefinition.affiliateScore
   FunctionDefinition.totalAffiliateScore
   FunctionDefinition.affiliateBonusPointsBest
   FunctionDefinition._vaultReferralMutable
   FunctionDefinition._setReferralCode
   FunctionDefinition._resolveCodeOwner
   FunctionDefinition._referrerAddress
   FunctionDefinition._createAffiliateCode
   FunctionDefinition._bootstrapReferral
   FunctionDefinition._routeAffiliateReward
   FunctionDefinition._score96
   FunctionDefinition._updateTopAffiliate
   FunctionDefinition._applyLootboxTaper
   FunctionDefinition._rollWeightedAffiliateWinner
   
   Suggested order:
   VariableDeclaration.AFFILIATE_BONUS_MAX
   VariableDeclaration.MAX_KICKBACK_PCT
   VariableDeclaration.REWARD_SCALE_FRESH_L1_3_BPS
   VariableDeclaration.REWARD_SCALE_FRESH_L4P_BPS
   VariableDeclaration.REWARD_SCALE_RECYCLED_BPS
   VariableDeclaration.BPS_DENOMINATOR
   VariableDeclaration.LOOTBOX_TAPER_START_SCORE
   VariableDeclaration.LOOTBOX_TAPER_END_SCORE
   VariableDeclaration.LOOTBOX_TAPER_MIN_BPS
   VariableDeclaration.MAX_COMMISSION_PER_REFERRER_PER_LEVEL
   VariableDeclaration.AFFILIATE_ROLL_TAG
   VariableDeclaration.REF_CODE_LOCKED
   VariableDeclaration.AFFILIATE_CODE_VAULT
   VariableDeclaration.AFFILIATE_CODE_DGNRS
   VariableDeclaration.coin
   VariableDeclaration.game
   VariableDeclaration.affiliateCode
   VariableDeclaration.affiliateCoinEarned
   VariableDeclaration.playerReferralCode
   VariableDeclaration.affiliateTopByLevel
   VariableDeclaration._totalAffiliateScore
   VariableDeclaration.affiliateCommissionFromSender
   StructDefinition.PlayerScore
   StructDefinition.AffiliateCodeInfo
   ErrorDefinition.OnlyAuthorized
   ErrorDefinition.Zero
   ErrorDefinition.Insufficient
   ErrorDefinition.InvalidKickback
   EventDefinition.Affiliate
   EventDefinition.ReferralUpdated
   EventDefinition.AffiliateEarningsRecorded
   EventDefinition.AffiliateTopUpdated
   FunctionDefinition.creditCoin
   FunctionDefinition.creditFlip
   FunctionDefinition.creditFlipBatch
   FunctionDefinition.affiliateQuestReward
   FunctionDefinition.constructor
   FunctionDefinition.createAffiliateCode
   FunctionDefinition.referPlayer
   FunctionDefinition.getReferrer
   FunctionDefinition.defaultCode
   FunctionDefinition.payAffiliate
   FunctionDefinition.affiliateTop
   FunctionDefinition.affiliateScore
   FunctionDefinition.totalAffiliateScore
   FunctionDefinition.affiliateBonusPointsBest
   FunctionDefinition._vaultReferralMutable
   FunctionDefinition._setReferralCode
   FunctionDefinition._resolveCodeOwner
   FunctionDefinition._referrerAddress
   FunctionDefinition._createAffiliateCode
   FunctionDefinition._bootstrapReferral
   FunctionDefinition._routeAffiliateReward
   FunctionDefinition._score96
   FunctionDefinition._updateTopAffiliate
   FunctionDefinition._applyLootboxTaper
   FunctionDefinition._rollWeightedAffiliateWinner

```

```solidity
File: DegenerusDeityPass.sol

1: 
   Current order:
   FunctionDefinition.data
   FunctionDefinition.symbol
   FunctionDefinition.render
   ErrorDefinition.NotAuthorized
   ErrorDefinition.InvalidToken
   ErrorDefinition.ZeroAddress
   ErrorDefinition.InvalidColor
   ErrorDefinition.Soulbound
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.ApprovalForAll
   EventDefinition.OwnershipTransferred
   EventDefinition.RendererUpdated
   EventDefinition.RenderColorsUpdated
   VariableDeclaration._owners
   VariableDeclaration._balances
   VariableDeclaration._contractOwner
   VariableDeclaration.renderer
   VariableDeclaration.ICON_VB
   VariableDeclaration.SYMBOL_HALF_SIZE
   VariableDeclaration._outlineColor
   VariableDeclaration._backgroundColor
   VariableDeclaration._nonCryptoSymbolColor
   ModifierDefinition.onlyOwner
   FunctionDefinition.constructor
   FunctionDefinition.name
   FunctionDefinition.symbol
   FunctionDefinition.owner
   FunctionDefinition.transferOwnership
   FunctionDefinition.setRenderer
   FunctionDefinition.setRenderColors
   FunctionDefinition.renderColors
   FunctionDefinition.tokenURI
   FunctionDefinition._renderSvgInternal
   FunctionDefinition._tryRenderExternal
   FunctionDefinition._isHexColor
   FunctionDefinition._symbolFitScale
   FunctionDefinition._symbolTranslate
   FunctionDefinition._mat6
   FunctionDefinition._dec6
   FunctionDefinition._dec6s
   FunctionDefinition._pad6
   FunctionDefinition.supportsInterface
   FunctionDefinition.balanceOf
   FunctionDefinition.ownerOf
   FunctionDefinition.getApproved
   FunctionDefinition.isApprovedForAll
   FunctionDefinition.approve
   FunctionDefinition.setApprovalForAll
   FunctionDefinition.transferFrom
   FunctionDefinition.safeTransferFrom
   FunctionDefinition.safeTransferFrom
   FunctionDefinition.mint
   
   Suggested order:
   VariableDeclaration._owners
   VariableDeclaration._balances
   VariableDeclaration._contractOwner
   VariableDeclaration.renderer
   VariableDeclaration.ICON_VB
   VariableDeclaration.SYMBOL_HALF_SIZE
   VariableDeclaration._outlineColor
   VariableDeclaration._backgroundColor
   VariableDeclaration._nonCryptoSymbolColor
   ErrorDefinition.NotAuthorized
   ErrorDefinition.InvalidToken
   ErrorDefinition.ZeroAddress
   ErrorDefinition.InvalidColor
   ErrorDefinition.Soulbound
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.ApprovalForAll
   EventDefinition.OwnershipTransferred
   EventDefinition.RendererUpdated
   EventDefinition.RenderColorsUpdated
   ModifierDefinition.onlyOwner
   FunctionDefinition.data
   FunctionDefinition.symbol
   FunctionDefinition.render
   FunctionDefinition.constructor
   FunctionDefinition.name
   FunctionDefinition.symbol
   FunctionDefinition.owner
   FunctionDefinition.transferOwnership
   FunctionDefinition.setRenderer
   FunctionDefinition.setRenderColors
   FunctionDefinition.renderColors
   FunctionDefinition.tokenURI
   FunctionDefinition._renderSvgInternal
   FunctionDefinition._tryRenderExternal
   FunctionDefinition._isHexColor
   FunctionDefinition._symbolFitScale
   FunctionDefinition._symbolTranslate
   FunctionDefinition._mat6
   FunctionDefinition._dec6
   FunctionDefinition._dec6s
   FunctionDefinition._pad6
   FunctionDefinition.supportsInterface
   FunctionDefinition.balanceOf
   FunctionDefinition.ownerOf
   FunctionDefinition.getApproved
   FunctionDefinition.isApprovedForAll
   FunctionDefinition.approve
   FunctionDefinition.setApprovalForAll
   FunctionDefinition.transferFrom
   FunctionDefinition.safeTransferFrom
   FunctionDefinition.safeTransferFrom
   FunctionDefinition.mint

```

```solidity
File: DegenerusGame.sol

1: 
   Current order:
   FunctionDefinition.playerQuestStates
   ErrorDefinition.AfKingLockActive
   ErrorDefinition.NotApproved
   EventDefinition.LootboxRngThresholdUpdated
   EventDefinition.OperatorApproval
   VariableDeclaration.coin
   VariableDeclaration.coinflip
   VariableDeclaration.steth
   VariableDeclaration.affiliate
   VariableDeclaration.dgnrs
   VariableDeclaration.questView
   VariableDeclaration.DEPLOY_IDLE_TIMEOUT_DAYS
   VariableDeclaration.AFKING_KEEP_MIN_ETH
   VariableDeclaration.AFKING_KEEP_MIN_COIN
   VariableDeclaration.AFKING_LOCK_LEVELS
   VariableDeclaration.PURCHASE_TO_FUTURE_BPS
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_BPS
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_MIN_BET
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_MIN_POOL
   VariableDeclaration.AFFILIATE_DGNRS_DEITY_BONUS_BPS
   VariableDeclaration.AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH
   VariableDeclaration.AFFILIATE_DGNRS_MIN_SCORE
   VariableDeclaration.DEITY_PASS_ACTIVITY_BONUS_BPS
   VariableDeclaration.PASS_STREAK_FLOOR_POINTS
   VariableDeclaration.PASS_MINT_COUNT_FLOOR_POINTS
   FunctionDefinition.constructor
   FunctionDefinition.advanceGame
   FunctionDefinition.wireVrf
   FunctionDefinition.recordMint
   FunctionDefinition.recordMintQuestStreak
   FunctionDefinition.payCoinflipBountyDgnrs
   FunctionDefinition.setOperatorApproval
   FunctionDefinition.isOperatorApproved
   FunctionDefinition._requireApproved
   FunctionDefinition._resolvePlayer
   FunctionDefinition.currentDayView
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.purchase
   FunctionDefinition._purchaseFor
   FunctionDefinition.purchaseCoin
   FunctionDefinition.purchaseBurnieLootbox
   FunctionDefinition.purchaseWhaleBundle
   FunctionDefinition._purchaseWhaleBundleFor
   FunctionDefinition.purchaseLazyPass
   FunctionDefinition._purchaseLazyPassFor
   FunctionDefinition.purchaseDeityPass
   FunctionDefinition._purchaseDeityPassFor
   FunctionDefinition.openLootBox
   FunctionDefinition.openBurnieLootBox
   FunctionDefinition._openLootBoxFor
   FunctionDefinition._openBurnieLootBoxFor
   FunctionDefinition.placeFullTicketBets
   FunctionDefinition.resolveDegeneretteBets
   FunctionDefinition.consumeCoinflipBoon
   FunctionDefinition.consumeDecimatorBoon
   FunctionDefinition.consumePurchaseBoost
   FunctionDefinition.deityBoonData
   FunctionDefinition.issueDeityBoon
   FunctionDefinition._processMintPayment
   FunctionDefinition._revertDelegate
   FunctionDefinition._recordMintDataModule
   FunctionDefinition.recordDecBurn
   FunctionDefinition.runDecimatorJackpot
   FunctionDefinition.recordTerminalDecBurn
   FunctionDefinition.runTerminalDecimatorJackpot
   FunctionDefinition.terminalDecWindow
   FunctionDefinition.runTerminalJackpot
   FunctionDefinition.consumeDecClaim
   FunctionDefinition.claimDecimatorJackpot
   FunctionDefinition.decClaimable
   FunctionDefinition._unpackDecWinningSubbucket
   EventDefinition.WinningsClaimed
   EventDefinition.ClaimableSpent
   EventDefinition.AffiliateDgnrsClaimed
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWinningsStethFirst
   FunctionDefinition._claimWinningsInternal
   FunctionDefinition.claimAffiliateDgnrs
   EventDefinition.AutoRebuyToggled
   EventDefinition.DecimatorAutoRebuyToggled
   EventDefinition.AutoRebuyTakeProfitSet
   EventDefinition.AfKingModeToggled
   FunctionDefinition.setAutoRebuy
   FunctionDefinition.setDecimatorAutoRebuy
   FunctionDefinition.setAutoRebuyTakeProfit
   FunctionDefinition._setAutoRebuy
   FunctionDefinition._setAutoRebuyTakeProfit
   FunctionDefinition.autoRebuyEnabledFor
   FunctionDefinition.decimatorAutoRebuyEnabledFor
   FunctionDefinition.autoRebuyTakeProfitFor
   FunctionDefinition.setAfKingMode
   FunctionDefinition._setAfKingMode
   FunctionDefinition._hasAnyLazyPass
   FunctionDefinition.hasActiveLazyPass
   FunctionDefinition.afKingModeFor
   FunctionDefinition.afKingActivatedLevelFor
   FunctionDefinition.deactivateAfKingFromCoin
   FunctionDefinition.syncAfKingLazyPassFromCoin
   FunctionDefinition._deactivateAfKing
   FunctionDefinition.claimWhalePass
   FunctionDefinition._claimWhalePassFor
   FunctionDefinition.resolveRedemptionLootbox
   FunctionDefinition.adminSwapEthForStEth
   FunctionDefinition.adminStakeEthForStEth
   FunctionDefinition.updateVrfCoordinatorAndSub
   FunctionDefinition.requestLootboxRng
   FunctionDefinition.reverseFlip
   FunctionDefinition.rawFulfillRandomWords
   FunctionDefinition._transferSteth
   FunctionDefinition._payoutWithStethFallback
   FunctionDefinition._payoutWithEthFallback
   FunctionDefinition.prizePoolTargetView
   FunctionDefinition.nextPrizePoolView
   FunctionDefinition.futurePrizePoolView
   FunctionDefinition.futurePrizePoolTotalView
   FunctionDefinition.ticketsOwedView
   FunctionDefinition.lootboxStatus
   FunctionDefinition.degeneretteBetInfo
   FunctionDefinition.lootboxPresaleActiveFlag
   FunctionDefinition.lootboxRngIndexView
   FunctionDefinition.lootboxRngWord
   FunctionDefinition.lootboxRngThresholdView
   FunctionDefinition.lootboxRngMinLinkBalanceView
   FunctionDefinition.currentPrizePoolView
   FunctionDefinition.rewardPoolView
   FunctionDefinition.claimablePoolView
   FunctionDefinition.isFinalSwept
   FunctionDefinition.gameOverTimestamp
   FunctionDefinition.yieldPoolView
   FunctionDefinition.yieldAccumulatorView
   FunctionDefinition.mintPrice
   FunctionDefinition.rngWordForDay
   FunctionDefinition.lastRngWord
   FunctionDefinition.rngLocked
   FunctionDefinition.isRngFulfilled
   FunctionDefinition._threeDayRngGap
   FunctionDefinition.rngStalledForThreeDays
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.decWindow
   FunctionDefinition.decWindowOpenFlag
   FunctionDefinition.jackpotCompressionTier
   FunctionDefinition._isGameoverImminent
   FunctionDefinition._activeTicketLevel
   FunctionDefinition.jackpotPhase
   FunctionDefinition.purchaseInfo
   FunctionDefinition.ethMintLastLevel
   FunctionDefinition.ethMintLevelCount
   FunctionDefinition.ethMintStreakCount
   FunctionDefinition.ethMintStats
   FunctionDefinition.playerActivityScore
   FunctionDefinition._playerActivityScore
   FunctionDefinition._mintCountBonusPoints
   FunctionDefinition.getWinnings
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.whalePassClaimAmount
   FunctionDefinition.deityPassCountFor
   FunctionDefinition.deityPassPurchasedCountFor
   FunctionDefinition.deityPassTotalIssuedCount
   FunctionDefinition.sampleTraitTickets
   FunctionDefinition.sampleTraitTicketsAtLevel
   FunctionDefinition.sampleFarFutureTickets
   FunctionDefinition.getTickets
   FunctionDefinition.getPlayerPurchases
   FunctionDefinition.getDailyHeroWager
   FunctionDefinition.getDailyHeroWinner
   FunctionDefinition.getPlayerDegeneretteWager
   FunctionDefinition.getTopDegenerette
   FunctionDefinition.receive
   
   Suggested order:
   VariableDeclaration.coin
   VariableDeclaration.coinflip
   VariableDeclaration.steth
   VariableDeclaration.affiliate
   VariableDeclaration.dgnrs
   VariableDeclaration.questView
   VariableDeclaration.DEPLOY_IDLE_TIMEOUT_DAYS
   VariableDeclaration.AFKING_KEEP_MIN_ETH
   VariableDeclaration.AFKING_KEEP_MIN_COIN
   VariableDeclaration.AFKING_LOCK_LEVELS
   VariableDeclaration.PURCHASE_TO_FUTURE_BPS
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_BPS
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_MIN_BET
   VariableDeclaration.COINFLIP_BOUNTY_DGNRS_MIN_POOL
   VariableDeclaration.AFFILIATE_DGNRS_DEITY_BONUS_BPS
   VariableDeclaration.AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH
   VariableDeclaration.AFFILIATE_DGNRS_MIN_SCORE
   VariableDeclaration.DEITY_PASS_ACTIVITY_BONUS_BPS
   VariableDeclaration.PASS_STREAK_FLOOR_POINTS
   VariableDeclaration.PASS_MINT_COUNT_FLOOR_POINTS
   ErrorDefinition.AfKingLockActive
   ErrorDefinition.NotApproved
   EventDefinition.LootboxRngThresholdUpdated
   EventDefinition.OperatorApproval
   EventDefinition.WinningsClaimed
   EventDefinition.ClaimableSpent
   EventDefinition.AffiliateDgnrsClaimed
   EventDefinition.AutoRebuyToggled
   EventDefinition.DecimatorAutoRebuyToggled
   EventDefinition.AutoRebuyTakeProfitSet
   EventDefinition.AfKingModeToggled
   FunctionDefinition.playerQuestStates
   FunctionDefinition.constructor
   FunctionDefinition.advanceGame
   FunctionDefinition.wireVrf
   FunctionDefinition.recordMint
   FunctionDefinition.recordMintQuestStreak
   FunctionDefinition.payCoinflipBountyDgnrs
   FunctionDefinition.setOperatorApproval
   FunctionDefinition.isOperatorApproved
   FunctionDefinition._requireApproved
   FunctionDefinition._resolvePlayer
   FunctionDefinition.currentDayView
   FunctionDefinition.setLootboxRngThreshold
   FunctionDefinition.purchase
   FunctionDefinition._purchaseFor
   FunctionDefinition.purchaseCoin
   FunctionDefinition.purchaseBurnieLootbox
   FunctionDefinition.purchaseWhaleBundle
   FunctionDefinition._purchaseWhaleBundleFor
   FunctionDefinition.purchaseLazyPass
   FunctionDefinition._purchaseLazyPassFor
   FunctionDefinition.purchaseDeityPass
   FunctionDefinition._purchaseDeityPassFor
   FunctionDefinition.openLootBox
   FunctionDefinition.openBurnieLootBox
   FunctionDefinition._openLootBoxFor
   FunctionDefinition._openBurnieLootBoxFor
   FunctionDefinition.placeFullTicketBets
   FunctionDefinition.resolveDegeneretteBets
   FunctionDefinition.consumeCoinflipBoon
   FunctionDefinition.consumeDecimatorBoon
   FunctionDefinition.consumePurchaseBoost
   FunctionDefinition.deityBoonData
   FunctionDefinition.issueDeityBoon
   FunctionDefinition._processMintPayment
   FunctionDefinition._revertDelegate
   FunctionDefinition._recordMintDataModule
   FunctionDefinition.recordDecBurn
   FunctionDefinition.runDecimatorJackpot
   FunctionDefinition.recordTerminalDecBurn
   FunctionDefinition.runTerminalDecimatorJackpot
   FunctionDefinition.terminalDecWindow
   FunctionDefinition.runTerminalJackpot
   FunctionDefinition.consumeDecClaim
   FunctionDefinition.claimDecimatorJackpot
   FunctionDefinition.decClaimable
   FunctionDefinition._unpackDecWinningSubbucket
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWinningsStethFirst
   FunctionDefinition._claimWinningsInternal
   FunctionDefinition.claimAffiliateDgnrs
   FunctionDefinition.setAutoRebuy
   FunctionDefinition.setDecimatorAutoRebuy
   FunctionDefinition.setAutoRebuyTakeProfit
   FunctionDefinition._setAutoRebuy
   FunctionDefinition._setAutoRebuyTakeProfit
   FunctionDefinition.autoRebuyEnabledFor
   FunctionDefinition.decimatorAutoRebuyEnabledFor
   FunctionDefinition.autoRebuyTakeProfitFor
   FunctionDefinition.setAfKingMode
   FunctionDefinition._setAfKingMode
   FunctionDefinition._hasAnyLazyPass
   FunctionDefinition.hasActiveLazyPass
   FunctionDefinition.afKingModeFor
   FunctionDefinition.afKingActivatedLevelFor
   FunctionDefinition.deactivateAfKingFromCoin
   FunctionDefinition.syncAfKingLazyPassFromCoin
   FunctionDefinition._deactivateAfKing
   FunctionDefinition.claimWhalePass
   FunctionDefinition._claimWhalePassFor
   FunctionDefinition.resolveRedemptionLootbox
   FunctionDefinition.adminSwapEthForStEth
   FunctionDefinition.adminStakeEthForStEth
   FunctionDefinition.updateVrfCoordinatorAndSub
   FunctionDefinition.requestLootboxRng
   FunctionDefinition.reverseFlip
   FunctionDefinition.rawFulfillRandomWords
   FunctionDefinition._transferSteth
   FunctionDefinition._payoutWithStethFallback
   FunctionDefinition._payoutWithEthFallback
   FunctionDefinition.prizePoolTargetView
   FunctionDefinition.nextPrizePoolView
   FunctionDefinition.futurePrizePoolView
   FunctionDefinition.futurePrizePoolTotalView
   FunctionDefinition.ticketsOwedView
   FunctionDefinition.lootboxStatus
   FunctionDefinition.degeneretteBetInfo
   FunctionDefinition.lootboxPresaleActiveFlag
   FunctionDefinition.lootboxRngIndexView
   FunctionDefinition.lootboxRngWord
   FunctionDefinition.lootboxRngThresholdView
   FunctionDefinition.lootboxRngMinLinkBalanceView
   FunctionDefinition.currentPrizePoolView
   FunctionDefinition.rewardPoolView
   FunctionDefinition.claimablePoolView
   FunctionDefinition.isFinalSwept
   FunctionDefinition.gameOverTimestamp
   FunctionDefinition.yieldPoolView
   FunctionDefinition.yieldAccumulatorView
   FunctionDefinition.mintPrice
   FunctionDefinition.rngWordForDay
   FunctionDefinition.lastRngWord
   FunctionDefinition.rngLocked
   FunctionDefinition.isRngFulfilled
   FunctionDefinition._threeDayRngGap
   FunctionDefinition.rngStalledForThreeDays
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.decWindow
   FunctionDefinition.decWindowOpenFlag
   FunctionDefinition.jackpotCompressionTier
   FunctionDefinition._isGameoverImminent
   FunctionDefinition._activeTicketLevel
   FunctionDefinition.jackpotPhase
   FunctionDefinition.purchaseInfo
   FunctionDefinition.ethMintLastLevel
   FunctionDefinition.ethMintLevelCount
   FunctionDefinition.ethMintStreakCount
   FunctionDefinition.ethMintStats
   FunctionDefinition.playerActivityScore
   FunctionDefinition._playerActivityScore
   FunctionDefinition._mintCountBonusPoints
   FunctionDefinition.getWinnings
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.whalePassClaimAmount
   FunctionDefinition.deityPassCountFor
   FunctionDefinition.deityPassPurchasedCountFor
   FunctionDefinition.deityPassTotalIssuedCount
   FunctionDefinition.sampleTraitTickets
   FunctionDefinition.sampleTraitTicketsAtLevel
   FunctionDefinition.sampleFarFutureTickets
   FunctionDefinition.getTickets
   FunctionDefinition.getPlayerPurchases
   FunctionDefinition.getDailyHeroWager
   FunctionDefinition.getDailyHeroWinner
   FunctionDefinition.getPlayerDegeneretteWager
   FunctionDefinition.getTopDegenerette
   FunctionDefinition.receive

```

```solidity
File: DegenerusJackpots.sol

1: 
   Current order:
   FunctionDefinition.coinflipTopLastDay
   ErrorDefinition.OnlyCoin
   ErrorDefinition.OnlyGame
   EventDefinition.BafFlipRecorded
   StructDefinition.PlayerScore
   VariableDeclaration.coin
   VariableDeclaration.degenerusGame
   VariableDeclaration.BAF_SCATTER_ROUNDS
   VariableDeclaration.bafTotals
   VariableDeclaration.bafTop
   VariableDeclaration.bafTopLen
   VariableDeclaration.bafEpoch
   VariableDeclaration.bafPlayerEpoch
   VariableDeclaration.lastBafResolvedDay
   ModifierDefinition.onlyCoin
   ModifierDefinition.onlyGame
   FunctionDefinition.recordBafFlip
   FunctionDefinition.runBafJackpot
   FunctionDefinition._creditOrRefund
   FunctionDefinition._bafScore
   FunctionDefinition._score96
   FunctionDefinition._updateBafTop
   FunctionDefinition._bafTop
   FunctionDefinition._clearBafTop
   FunctionDefinition.getLastBafResolvedDay
   
   Suggested order:
   VariableDeclaration.coin
   VariableDeclaration.degenerusGame
   VariableDeclaration.BAF_SCATTER_ROUNDS
   VariableDeclaration.bafTotals
   VariableDeclaration.bafTop
   VariableDeclaration.bafTopLen
   VariableDeclaration.bafEpoch
   VariableDeclaration.bafPlayerEpoch
   VariableDeclaration.lastBafResolvedDay
   StructDefinition.PlayerScore
   ErrorDefinition.OnlyCoin
   ErrorDefinition.OnlyGame
   EventDefinition.BafFlipRecorded
   ModifierDefinition.onlyCoin
   ModifierDefinition.onlyGame
   FunctionDefinition.coinflipTopLastDay
   FunctionDefinition.recordBafFlip
   FunctionDefinition.runBafJackpot
   FunctionDefinition._creditOrRefund
   FunctionDefinition._bafScore
   FunctionDefinition._score96
   FunctionDefinition._updateBafTop
   FunctionDefinition._bafTop
   FunctionDefinition._clearBafTop
   FunctionDefinition.getLastBafResolvedDay

```

```solidity
File: DegenerusQuests.sol

1: 
   Current order:
   ErrorDefinition.OnlyCoin
   ErrorDefinition.OnlyGame
   EventDefinition.QuestSlotRolled
   EventDefinition.QuestProgressUpdated
   EventDefinition.QuestCompleted
   EventDefinition.QuestStreakShieldUsed
   EventDefinition.QuestStreakBonusAwarded
   EventDefinition.QuestStreakReset
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.QUEST_SLOT_COUNT
   VariableDeclaration.QUEST_SLOT0_REWARD
   VariableDeclaration.QUEST_RANDOM_REWARD
   VariableDeclaration.QUEST_TYPE_MINT_BURNIE
   VariableDeclaration.QUEST_TYPE_MINT_ETH
   VariableDeclaration.QUEST_TYPE_FLIP
   VariableDeclaration.QUEST_TYPE_AFFILIATE
   VariableDeclaration.QUEST_TYPE_RESERVED
   VariableDeclaration.QUEST_TYPE_DECIMATOR
   VariableDeclaration.QUEST_TYPE_LOOTBOX
   VariableDeclaration.QUEST_TYPE_DEGENERETTE_ETH
   VariableDeclaration.QUEST_TYPE_DEGENERETTE_BURNIE
   VariableDeclaration.QUEST_TYPE_COUNT
   VariableDeclaration.QUEST_STATE_STREAK_CREDITED
   VariableDeclaration.QUEST_MINT_TARGET
   VariableDeclaration.QUEST_BURNIE_TARGET
   VariableDeclaration.QUEST_LOOTBOX_TARGET_MULTIPLIER
   VariableDeclaration.QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER
   VariableDeclaration.QUEST_ETH_TARGET_CAP
   VariableDeclaration.DECIMATOR_SPECIAL_LEVEL
   VariableDeclaration.questGame
   StructDefinition.DailyQuest
   StructDefinition.PlayerQuestState
   VariableDeclaration.activeQuests
   VariableDeclaration.questPlayerState
   VariableDeclaration.questStreakShieldCount
   VariableDeclaration.questVersionCounter
   ModifierDefinition.onlyCoin
   ModifierDefinition.onlyGame
   FunctionDefinition.rollDailyQuest
   FunctionDefinition.awardQuestStreakBonus
   FunctionDefinition._rollDailyQuest
   FunctionDefinition.handleMint
   FunctionDefinition.handleFlip
   FunctionDefinition.handleDecimator
   FunctionDefinition.handleAffiliate
   FunctionDefinition.handleLootBox
   FunctionDefinition.handleDegenerette
   FunctionDefinition.getActiveQuests
   FunctionDefinition._materializeActiveQuestsForView
   FunctionDefinition.playerQuestStates
   FunctionDefinition.getPlayerQuestView
   FunctionDefinition._questViewData
   FunctionDefinition._questRequirements
   FunctionDefinition._currentDayQuestOfType
   FunctionDefinition._canRollDecimatorQuest
   FunctionDefinition._clampedAdd128
   FunctionDefinition._nextQuestVersion
   FunctionDefinition._questHandleProgressSlot
   FunctionDefinition._questSyncState
   FunctionDefinition._questSyncProgress
   FunctionDefinition._questProgressValid
   FunctionDefinition._questProgressValidStorage
   FunctionDefinition._questCompleted
   FunctionDefinition._questTargetValue
   FunctionDefinition._bonusQuestType
   FunctionDefinition._questComplete
   FunctionDefinition._questCompleteWithPair
   FunctionDefinition._maybeCompleteOther
   FunctionDefinition._questReady
   FunctionDefinition._seedQuestType
   FunctionDefinition._currentQuestDay
   
   Suggested order:
   VariableDeclaration.PRICE_COIN_UNIT
   VariableDeclaration.QUEST_SLOT_COUNT
   VariableDeclaration.QUEST_SLOT0_REWARD
   VariableDeclaration.QUEST_RANDOM_REWARD
   VariableDeclaration.QUEST_TYPE_MINT_BURNIE
   VariableDeclaration.QUEST_TYPE_MINT_ETH
   VariableDeclaration.QUEST_TYPE_FLIP
   VariableDeclaration.QUEST_TYPE_AFFILIATE
   VariableDeclaration.QUEST_TYPE_RESERVED
   VariableDeclaration.QUEST_TYPE_DECIMATOR
   VariableDeclaration.QUEST_TYPE_LOOTBOX
   VariableDeclaration.QUEST_TYPE_DEGENERETTE_ETH
   VariableDeclaration.QUEST_TYPE_DEGENERETTE_BURNIE
   VariableDeclaration.QUEST_TYPE_COUNT
   VariableDeclaration.QUEST_STATE_STREAK_CREDITED
   VariableDeclaration.QUEST_MINT_TARGET
   VariableDeclaration.QUEST_BURNIE_TARGET
   VariableDeclaration.QUEST_LOOTBOX_TARGET_MULTIPLIER
   VariableDeclaration.QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER
   VariableDeclaration.QUEST_ETH_TARGET_CAP
   VariableDeclaration.DECIMATOR_SPECIAL_LEVEL
   VariableDeclaration.questGame
   VariableDeclaration.activeQuests
   VariableDeclaration.questPlayerState
   VariableDeclaration.questStreakShieldCount
   VariableDeclaration.questVersionCounter
   StructDefinition.DailyQuest
   StructDefinition.PlayerQuestState
   ErrorDefinition.OnlyCoin
   ErrorDefinition.OnlyGame
   EventDefinition.QuestSlotRolled
   EventDefinition.QuestProgressUpdated
   EventDefinition.QuestCompleted
   EventDefinition.QuestStreakShieldUsed
   EventDefinition.QuestStreakBonusAwarded
   EventDefinition.QuestStreakReset
   ModifierDefinition.onlyCoin
   ModifierDefinition.onlyGame
   FunctionDefinition.rollDailyQuest
   FunctionDefinition.awardQuestStreakBonus
   FunctionDefinition._rollDailyQuest
   FunctionDefinition.handleMint
   FunctionDefinition.handleFlip
   FunctionDefinition.handleDecimator
   FunctionDefinition.handleAffiliate
   FunctionDefinition.handleLootBox
   FunctionDefinition.handleDegenerette
   FunctionDefinition.getActiveQuests
   FunctionDefinition._materializeActiveQuestsForView
   FunctionDefinition.playerQuestStates
   FunctionDefinition.getPlayerQuestView
   FunctionDefinition._questViewData
   FunctionDefinition._questRequirements
   FunctionDefinition._currentDayQuestOfType
   FunctionDefinition._canRollDecimatorQuest
   FunctionDefinition._clampedAdd128
   FunctionDefinition._nextQuestVersion
   FunctionDefinition._questHandleProgressSlot
   FunctionDefinition._questSyncState
   FunctionDefinition._questSyncProgress
   FunctionDefinition._questProgressValid
   FunctionDefinition._questProgressValidStorage
   FunctionDefinition._questCompleted
   FunctionDefinition._questTargetValue
   FunctionDefinition._bonusQuestType
   FunctionDefinition._questComplete
   FunctionDefinition._questCompleteWithPair
   FunctionDefinition._maybeCompleteOther
   FunctionDefinition._questReady
   FunctionDefinition._seedQuestType
   FunctionDefinition._currentQuestDay

```

```solidity
File: DegenerusStonk.sol

1: 
   Current order:
   FunctionDefinition.burn
   FunctionDefinition.balanceOf
   FunctionDefinition.wrapperTransferTo
   FunctionDefinition.previewBurn
   FunctionDefinition.transfer
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.gameOver
   FunctionDefinition.gameOverTimestamp
   ErrorDefinition.Unauthorized
   ErrorDefinition.Insufficient
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.GameNotOver
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.BurnThrough
   EventDefinition.UnwrapTo
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.stonk
   VariableDeclaration.burnie
   VariableDeclaration.steth
   FunctionDefinition.constructor
   FunctionDefinition.receive
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.approve
   FunctionDefinition.unwrapTo
   FunctionDefinition.burn
   FunctionDefinition.previewBurn
   FunctionDefinition._transfer
   FunctionDefinition._burn
   ErrorDefinition.SweepNotReady
   ErrorDefinition.NothingToSweep
   EventDefinition.YearSweep
   FunctionDefinition.yearSweep
   FunctionDefinition.burnForSdgnrs
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.stonk
   VariableDeclaration.burnie
   VariableDeclaration.steth
   ErrorDefinition.Unauthorized
   ErrorDefinition.Insufficient
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.GameNotOver
   ErrorDefinition.SweepNotReady
   ErrorDefinition.NothingToSweep
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.BurnThrough
   EventDefinition.UnwrapTo
   EventDefinition.YearSweep
   FunctionDefinition.burn
   FunctionDefinition.balanceOf
   FunctionDefinition.wrapperTransferTo
   FunctionDefinition.previewBurn
   FunctionDefinition.transfer
   FunctionDefinition.lastVrfProcessed
   FunctionDefinition.gameOver
   FunctionDefinition.gameOverTimestamp
   FunctionDefinition.constructor
   FunctionDefinition.receive
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.approve
   FunctionDefinition.unwrapTo
   FunctionDefinition.burn
   FunctionDefinition.previewBurn
   FunctionDefinition._transfer
   FunctionDefinition._burn
   FunctionDefinition.yearSweep
   FunctionDefinition.burnForSdgnrs

```

```solidity
File: DegenerusVault.sol

1: 
   Current order:
   FunctionDefinition.advanceGame
   FunctionDefinition.purchase
   FunctionDefinition.openLootBox
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWinningsStethFirst
   FunctionDefinition.claimWhalePass
   FunctionDefinition.claimDecimatorJackpot
   FunctionDefinition.setDecimatorAutoRebuy
   FunctionDefinition.purchaseBurnieLootbox
   FunctionDefinition.purchaseDeityPass
   FunctionDefinition.placeFullTicketBets
   FunctionDefinition.resolveDegeneretteBets
   FunctionDefinition.setAutoRebuy
   FunctionDefinition.setAutoRebuyTakeProfit
   FunctionDefinition.setAfKingMode
   FunctionDefinition.setOperatorApproval
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.purchaseCoin
   FunctionDefinition.depositCoinflip
   FunctionDefinition.claimCoinflips
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.setCoinflipAutoRebuy
   FunctionDefinition.setCoinflipAutoRebuyTakeProfit
   FunctionDefinition.decimatorBurn
   FunctionDefinition.vaultMintTo
   FunctionDefinition.vaultMintAllowance
   ErrorDefinition.Unauthorized
   ErrorDefinition.ZeroAddress
   ErrorDefinition.Insufficient
   EventDefinition.Transfer
   EventDefinition.Approval
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   ModifierDefinition.onlyVault
   FunctionDefinition.constructor
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.vaultMint
   FunctionDefinition.vaultBurn
   FunctionDefinition._transfer
   ErrorDefinition.Unauthorized
   ErrorDefinition.NotVaultOwner
   ErrorDefinition.Insufficient
   ErrorDefinition.TransferFailed
   ErrorDefinition.NotApproved
   EventDefinition.Deposit
   EventDefinition.Claim
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.REFILL_SUPPLY
   VariableDeclaration.coinShare
   VariableDeclaration.ethShare
   VariableDeclaration.game
   VariableDeclaration.gamePlayer
   VariableDeclaration.coinflipPlayer
   VariableDeclaration.coinPlayer
   VariableDeclaration.coinToken
   VariableDeclaration.wwxrpToken
   VariableDeclaration.steth
   VariableDeclaration.coinTracked
   ModifierDefinition.onlyGame
   ModifierDefinition.onlyVaultOwner
   FunctionDefinition._requireApproved
   FunctionDefinition._isVaultOwner
   FunctionDefinition.isVaultOwner
   FunctionDefinition.constructor
   FunctionDefinition.deposit
   FunctionDefinition.receive
   FunctionDefinition.gameAdvance
   FunctionDefinition.gamePurchase
   FunctionDefinition.gamePurchaseTicketsBurnie
   FunctionDefinition.gamePurchaseBurnieLootbox
   FunctionDefinition.gameOpenLootBox
   FunctionDefinition.gamePurchaseDeityPassFromBoon
   FunctionDefinition.gameClaimWinnings
   FunctionDefinition.gameClaimWhalePass
   FunctionDefinition.gameDegeneretteBetEth
   FunctionDefinition.gameDegeneretteBetBurnie
   FunctionDefinition.gameDegeneretteBetWwxrp
   FunctionDefinition.gameResolveDegeneretteBets
   FunctionDefinition.gameSetAutoRebuy
   FunctionDefinition.gameSetAutoRebuyTakeProfit
   FunctionDefinition.gameSetDecimatorAutoRebuy
   FunctionDefinition.gameSetAfKingMode
   FunctionDefinition.gameSetOperatorApproval
   FunctionDefinition.coinDepositCoinflip
   FunctionDefinition.coinClaimCoinflips
   FunctionDefinition.coinDecimatorBurn
   FunctionDefinition.coinSetAutoRebuy
   FunctionDefinition.coinSetAutoRebuyTakeProfit
   FunctionDefinition.wwxrpMint
   FunctionDefinition.jackpotsClaimDecimator
   FunctionDefinition.burnCoin
   FunctionDefinition._burnCoinFor
   FunctionDefinition.burnEth
   FunctionDefinition._burnEthFor
   FunctionDefinition.previewBurnForCoinOut
   FunctionDefinition.previewBurnForEthOut
   FunctionDefinition.previewCoin
   FunctionDefinition.previewEth
   FunctionDefinition._combinedValue
   FunctionDefinition._syncEthReserves
   FunctionDefinition._syncCoinReserves
   FunctionDefinition._coinReservesView
   FunctionDefinition._ethReservesView
   FunctionDefinition._stethBalance
   FunctionDefinition._payEth
   FunctionDefinition._paySteth
   FunctionDefinition._pullSteth
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.REFILL_SUPPLY
   VariableDeclaration.coinShare
   VariableDeclaration.ethShare
   VariableDeclaration.game
   VariableDeclaration.gamePlayer
   VariableDeclaration.coinflipPlayer
   VariableDeclaration.coinPlayer
   VariableDeclaration.coinToken
   VariableDeclaration.wwxrpToken
   VariableDeclaration.steth
   VariableDeclaration.coinTracked
   ErrorDefinition.Unauthorized
   ErrorDefinition.ZeroAddress
   ErrorDefinition.Insufficient
   ErrorDefinition.Unauthorized
   ErrorDefinition.NotVaultOwner
   ErrorDefinition.Insufficient
   ErrorDefinition.TransferFailed
   ErrorDefinition.NotApproved
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.Deposit
   EventDefinition.Claim
   ModifierDefinition.onlyVault
   ModifierDefinition.onlyGame
   ModifierDefinition.onlyVaultOwner
   FunctionDefinition.advanceGame
   FunctionDefinition.purchase
   FunctionDefinition.openLootBox
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWinningsStethFirst
   FunctionDefinition.claimWhalePass
   FunctionDefinition.claimDecimatorJackpot
   FunctionDefinition.setDecimatorAutoRebuy
   FunctionDefinition.purchaseBurnieLootbox
   FunctionDefinition.purchaseDeityPass
   FunctionDefinition.placeFullTicketBets
   FunctionDefinition.resolveDegeneretteBets
   FunctionDefinition.setAutoRebuy
   FunctionDefinition.setAutoRebuyTakeProfit
   FunctionDefinition.setAfKingMode
   FunctionDefinition.setOperatorApproval
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.purchaseCoin
   FunctionDefinition.depositCoinflip
   FunctionDefinition.claimCoinflips
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.setCoinflipAutoRebuy
   FunctionDefinition.setCoinflipAutoRebuyTakeProfit
   FunctionDefinition.decimatorBurn
   FunctionDefinition.vaultMintTo
   FunctionDefinition.vaultMintAllowance
   FunctionDefinition.constructor
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.vaultMint
   FunctionDefinition.vaultBurn
   FunctionDefinition._transfer
   FunctionDefinition._requireApproved
   FunctionDefinition._isVaultOwner
   FunctionDefinition.isVaultOwner
   FunctionDefinition.constructor
   FunctionDefinition.deposit
   FunctionDefinition.receive
   FunctionDefinition.gameAdvance
   FunctionDefinition.gamePurchase
   FunctionDefinition.gamePurchaseTicketsBurnie
   FunctionDefinition.gamePurchaseBurnieLootbox
   FunctionDefinition.gameOpenLootBox
   FunctionDefinition.gamePurchaseDeityPassFromBoon
   FunctionDefinition.gameClaimWinnings
   FunctionDefinition.gameClaimWhalePass
   FunctionDefinition.gameDegeneretteBetEth
   FunctionDefinition.gameDegeneretteBetBurnie
   FunctionDefinition.gameDegeneretteBetWwxrp
   FunctionDefinition.gameResolveDegeneretteBets
   FunctionDefinition.gameSetAutoRebuy
   FunctionDefinition.gameSetAutoRebuyTakeProfit
   FunctionDefinition.gameSetDecimatorAutoRebuy
   FunctionDefinition.gameSetAfKingMode
   FunctionDefinition.gameSetOperatorApproval
   FunctionDefinition.coinDepositCoinflip
   FunctionDefinition.coinClaimCoinflips
   FunctionDefinition.coinDecimatorBurn
   FunctionDefinition.coinSetAutoRebuy
   FunctionDefinition.coinSetAutoRebuyTakeProfit
   FunctionDefinition.wwxrpMint
   FunctionDefinition.jackpotsClaimDecimator
   FunctionDefinition.burnCoin
   FunctionDefinition._burnCoinFor
   FunctionDefinition.burnEth
   FunctionDefinition._burnEthFor
   FunctionDefinition.previewBurnForCoinOut
   FunctionDefinition.previewBurnForEthOut
   FunctionDefinition.previewCoin
   FunctionDefinition.previewEth
   FunctionDefinition._combinedValue
   FunctionDefinition._syncEthReserves
   FunctionDefinition._syncCoinReserves
   FunctionDefinition._coinReservesView
   FunctionDefinition._ethReservesView
   FunctionDefinition._stethBalance
   FunctionDefinition._payEth
   FunctionDefinition._paySteth
   FunctionDefinition._pullSteth

```

```solidity
File: DeityBoonViewer.sol

1: 
   Current order:
   FunctionDefinition.deityBoonData
   VariableDeclaration.DEITY_DAILY_BOON_COUNT
   VariableDeclaration.DEITY_BOON_COINFLIP_5
   VariableDeclaration.DEITY_BOON_COINFLIP_10
   VariableDeclaration.DEITY_BOON_COINFLIP_25
   VariableDeclaration.DEITY_BOON_LOOTBOX_5
   VariableDeclaration.DEITY_BOON_LOOTBOX_15
   VariableDeclaration.DEITY_BOON_PURCHASE_5
   VariableDeclaration.DEITY_BOON_PURCHASE_15
   VariableDeclaration.DEITY_BOON_PURCHASE_25
   VariableDeclaration.DEITY_BOON_DECIMATOR_10
   VariableDeclaration.DEITY_BOON_DECIMATOR_25
   VariableDeclaration.DEITY_BOON_DECIMATOR_50
   VariableDeclaration.DEITY_BOON_WHALE_10
   VariableDeclaration.DEITY_BOON_ACTIVITY_10
   VariableDeclaration.DEITY_BOON_ACTIVITY_25
   VariableDeclaration.DEITY_BOON_ACTIVITY_50
   VariableDeclaration.DEITY_BOON_LOOTBOX_25
   VariableDeclaration.DEITY_BOON_WHALE_25
   VariableDeclaration.DEITY_BOON_WHALE_50
   VariableDeclaration.DEITY_BOON_DEITY_PASS_10
   VariableDeclaration.DEITY_BOON_DEITY_PASS_25
   VariableDeclaration.DEITY_BOON_DEITY_PASS_50
   VariableDeclaration.DEITY_BOON_WHALE_PASS
   VariableDeclaration.DEITY_BOON_LAZY_PASS_10
   VariableDeclaration.DEITY_BOON_LAZY_PASS_25
   VariableDeclaration.DEITY_BOON_LAZY_PASS_50
   VariableDeclaration.W_COINFLIP_5
   VariableDeclaration.W_COINFLIP_10
   VariableDeclaration.W_COINFLIP_25
   VariableDeclaration.W_LOOTBOX_5
   VariableDeclaration.W_LOOTBOX_15
   VariableDeclaration.W_LOOTBOX_25
   VariableDeclaration.W_PURCHASE_5
   VariableDeclaration.W_PURCHASE_15
   VariableDeclaration.W_PURCHASE_25
   VariableDeclaration.W_DECIMATOR_10
   VariableDeclaration.W_DECIMATOR_25
   VariableDeclaration.W_DECIMATOR_50
   VariableDeclaration.W_WHALE_10
   VariableDeclaration.W_WHALE_25
   VariableDeclaration.W_WHALE_50
   VariableDeclaration.W_DEITY_PASS_10
   VariableDeclaration.W_DEITY_PASS_25
   VariableDeclaration.W_DEITY_PASS_50
   VariableDeclaration.W_ACTIVITY_10
   VariableDeclaration.W_ACTIVITY_25
   VariableDeclaration.W_ACTIVITY_50
   VariableDeclaration.W_WHALE_PASS
   VariableDeclaration.W_LAZY_PASS_10
   VariableDeclaration.W_LAZY_PASS_25
   VariableDeclaration.W_LAZY_PASS_50
   VariableDeclaration.W_DEITY_PASS_ALL
   VariableDeclaration.W_TOTAL
   VariableDeclaration.W_TOTAL_NO_DECIMATOR
   FunctionDefinition.deityBoonSlots
   FunctionDefinition._boonFromRoll
   
   Suggested order:
   VariableDeclaration.DEITY_DAILY_BOON_COUNT
   VariableDeclaration.DEITY_BOON_COINFLIP_5
   VariableDeclaration.DEITY_BOON_COINFLIP_10
   VariableDeclaration.DEITY_BOON_COINFLIP_25
   VariableDeclaration.DEITY_BOON_LOOTBOX_5
   VariableDeclaration.DEITY_BOON_LOOTBOX_15
   VariableDeclaration.DEITY_BOON_PURCHASE_5
   VariableDeclaration.DEITY_BOON_PURCHASE_15
   VariableDeclaration.DEITY_BOON_PURCHASE_25
   VariableDeclaration.DEITY_BOON_DECIMATOR_10
   VariableDeclaration.DEITY_BOON_DECIMATOR_25
   VariableDeclaration.DEITY_BOON_DECIMATOR_50
   VariableDeclaration.DEITY_BOON_WHALE_10
   VariableDeclaration.DEITY_BOON_ACTIVITY_10
   VariableDeclaration.DEITY_BOON_ACTIVITY_25
   VariableDeclaration.DEITY_BOON_ACTIVITY_50
   VariableDeclaration.DEITY_BOON_LOOTBOX_25
   VariableDeclaration.DEITY_BOON_WHALE_25
   VariableDeclaration.DEITY_BOON_WHALE_50
   VariableDeclaration.DEITY_BOON_DEITY_PASS_10
   VariableDeclaration.DEITY_BOON_DEITY_PASS_25
   VariableDeclaration.DEITY_BOON_DEITY_PASS_50
   VariableDeclaration.DEITY_BOON_WHALE_PASS
   VariableDeclaration.DEITY_BOON_LAZY_PASS_10
   VariableDeclaration.DEITY_BOON_LAZY_PASS_25
   VariableDeclaration.DEITY_BOON_LAZY_PASS_50
   VariableDeclaration.W_COINFLIP_5
   VariableDeclaration.W_COINFLIP_10
   VariableDeclaration.W_COINFLIP_25
   VariableDeclaration.W_LOOTBOX_5
   VariableDeclaration.W_LOOTBOX_15
   VariableDeclaration.W_LOOTBOX_25
   VariableDeclaration.W_PURCHASE_5
   VariableDeclaration.W_PURCHASE_15
   VariableDeclaration.W_PURCHASE_25
   VariableDeclaration.W_DECIMATOR_10
   VariableDeclaration.W_DECIMATOR_25
   VariableDeclaration.W_DECIMATOR_50
   VariableDeclaration.W_WHALE_10
   VariableDeclaration.W_WHALE_25
   VariableDeclaration.W_WHALE_50
   VariableDeclaration.W_DEITY_PASS_10
   VariableDeclaration.W_DEITY_PASS_25
   VariableDeclaration.W_DEITY_PASS_50
   VariableDeclaration.W_ACTIVITY_10
   VariableDeclaration.W_ACTIVITY_25
   VariableDeclaration.W_ACTIVITY_50
   VariableDeclaration.W_WHALE_PASS
   VariableDeclaration.W_LAZY_PASS_10
   VariableDeclaration.W_LAZY_PASS_25
   VariableDeclaration.W_LAZY_PASS_50
   VariableDeclaration.W_DEITY_PASS_ALL
   VariableDeclaration.W_TOTAL
   VariableDeclaration.W_TOTAL_NO_DECIMATOR
   FunctionDefinition.deityBoonData
   FunctionDefinition.deityBoonSlots
   FunctionDefinition._boonFromRoll

```

```solidity
File: GNRUS.sol

1: 
   Current order:
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.gameOver
   FunctionDefinition.isVaultOwner
   ErrorDefinition.Unauthorized
   ErrorDefinition.TransferDisabled
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.InsufficientBurn
   ErrorDefinition.ProposalLimitReached
   ErrorDefinition.InsufficientStake
   ErrorDefinition.AlreadyProposed
   ErrorDefinition.AlreadyVoted
   ErrorDefinition.InvalidProposal
   ErrorDefinition.LevelAlreadyResolved
   ErrorDefinition.LevelNotActive
   ErrorDefinition.RecipientIsContract
   ErrorDefinition.GameNotOver
   ErrorDefinition.AlreadyFinalized
   EventDefinition.Transfer
   EventDefinition.Burn
   EventDefinition.ProposalCreated
   EventDefinition.Voted
   EventDefinition.LevelResolved
   EventDefinition.LevelSkipped
   EventDefinition.GameOverFinalized
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   StructDefinition.Proposal
   VariableDeclaration.currentLevel
   VariableDeclaration.proposalCount
   VariableDeclaration.finalized
   VariableDeclaration.proposals
   VariableDeclaration.levelProposalStart
   VariableDeclaration.levelProposalCount
   VariableDeclaration.levelResolved
   VariableDeclaration.hasProposed
   VariableDeclaration.creatorProposalCount
   VariableDeclaration.hasVoted
   VariableDeclaration.levelSdgnrsSnapshot
   VariableDeclaration.levelVaultOwner
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.MIN_BURN
   VariableDeclaration.DISTRIBUTION_BPS
   VariableDeclaration.BPS_DENOM
   VariableDeclaration.PROPOSE_THRESHOLD_BPS
   VariableDeclaration.VAULT_VOTE_BPS
   VariableDeclaration.MAX_CREATOR_PROPOSALS
   VariableDeclaration.steth
   VariableDeclaration.sdgnrs
   VariableDeclaration.game
   VariableDeclaration.vault
   ModifierDefinition.onlyGame
   FunctionDefinition.constructor
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.approve
   FunctionDefinition.burn
   FunctionDefinition.burnAtGameOver
   FunctionDefinition.propose
   FunctionDefinition.vote
   FunctionDefinition.pickCharity
   FunctionDefinition.receive
   FunctionDefinition.getProposal
   FunctionDefinition.getLevelProposals
   FunctionDefinition._mint
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.currentLevel
   VariableDeclaration.proposalCount
   VariableDeclaration.finalized
   VariableDeclaration.proposals
   VariableDeclaration.levelProposalStart
   VariableDeclaration.levelProposalCount
   VariableDeclaration.levelResolved
   VariableDeclaration.hasProposed
   VariableDeclaration.creatorProposalCount
   VariableDeclaration.hasVoted
   VariableDeclaration.levelSdgnrsSnapshot
   VariableDeclaration.levelVaultOwner
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.MIN_BURN
   VariableDeclaration.DISTRIBUTION_BPS
   VariableDeclaration.BPS_DENOM
   VariableDeclaration.PROPOSE_THRESHOLD_BPS
   VariableDeclaration.VAULT_VOTE_BPS
   VariableDeclaration.MAX_CREATOR_PROPOSALS
   VariableDeclaration.steth
   VariableDeclaration.sdgnrs
   VariableDeclaration.game
   VariableDeclaration.vault
   StructDefinition.Proposal
   ErrorDefinition.Unauthorized
   ErrorDefinition.TransferDisabled
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.InsufficientBurn
   ErrorDefinition.ProposalLimitReached
   ErrorDefinition.InsufficientStake
   ErrorDefinition.AlreadyProposed
   ErrorDefinition.AlreadyVoted
   ErrorDefinition.InvalidProposal
   ErrorDefinition.LevelAlreadyResolved
   ErrorDefinition.LevelNotActive
   ErrorDefinition.RecipientIsContract
   ErrorDefinition.GameNotOver
   ErrorDefinition.AlreadyFinalized
   EventDefinition.Transfer
   EventDefinition.Burn
   EventDefinition.ProposalCreated
   EventDefinition.Voted
   EventDefinition.LevelResolved
   EventDefinition.LevelSkipped
   EventDefinition.GameOverFinalized
   ModifierDefinition.onlyGame
   FunctionDefinition.totalSupply
   FunctionDefinition.balanceOf
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.gameOver
   FunctionDefinition.isVaultOwner
   FunctionDefinition.constructor
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.approve
   FunctionDefinition.burn
   FunctionDefinition.burnAtGameOver
   FunctionDefinition.propose
   FunctionDefinition.vote
   FunctionDefinition.pickCharity
   FunctionDefinition.receive
   FunctionDefinition.getProposal
   FunctionDefinition.getLevelProposals
   FunctionDefinition._mint

```

```solidity
File: Icons32Data.sol

1: 
   Current order:
   ErrorDefinition.OnlyCreator
   ErrorDefinition.AlreadyFinalized
   ErrorDefinition.MaxBatch
   ErrorDefinition.IndexOutOfBounds
   ErrorDefinition.InvalidQuadrant
   VariableDeclaration._paths
   VariableDeclaration._symQ1
   VariableDeclaration._symQ2
   VariableDeclaration._symQ3
   VariableDeclaration._finalized
   FunctionDefinition.constructor
   FunctionDefinition.setPaths
   FunctionDefinition.setSymbols
   FunctionDefinition.finalize
   FunctionDefinition.data
   FunctionDefinition.symbol
   
   Suggested order:
   VariableDeclaration._paths
   VariableDeclaration._symQ1
   VariableDeclaration._symQ2
   VariableDeclaration._symQ3
   VariableDeclaration._finalized
   ErrorDefinition.OnlyCreator
   ErrorDefinition.AlreadyFinalized
   ErrorDefinition.MaxBatch
   ErrorDefinition.IndexOutOfBounds
   ErrorDefinition.InvalidQuadrant
   FunctionDefinition.constructor
   FunctionDefinition.setPaths
   FunctionDefinition.setSymbols
   FunctionDefinition.finalize
   FunctionDefinition.data
   FunctionDefinition.symbol

```

```solidity
File: StakedDegenerusStonk.sol

1: 
   Current order:
   FunctionDefinition.advanceGame
   FunctionDefinition.setAfKingMode
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWhalePass
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.rngLocked
   FunctionDefinition.gameOver
   FunctionDefinition.currentDayView
   FunctionDefinition.rngWordForDay
   FunctionDefinition.playerActivityScore
   FunctionDefinition.resolveRedemptionLootbox
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.claimCoinflips
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.claimCoinflipsForRedemption
   FunctionDefinition.getCoinflipDayResult
   FunctionDefinition.burnForSdgnrs
   ErrorDefinition.Unauthorized
   ErrorDefinition.Insufficient
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.BurnsBlockedDuringRng
   ErrorDefinition.UnresolvedClaim
   ErrorDefinition.NoClaim
   ErrorDefinition.NotResolved
   ErrorDefinition.ExceedsDailyRedemptionCap
   EventDefinition.Transfer
   EventDefinition.Burn
   EventDefinition.Deposit
   EventDefinition.PoolTransfer
   EventDefinition.PoolRebalance
   EventDefinition.RedemptionSubmitted
   EventDefinition.RedemptionResolved
   EventDefinition.RedemptionClaimed
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   EnumDefinition.Pool
   VariableDeclaration.poolBalances
   StructDefinition.PendingRedemption
   StructDefinition.RedemptionPeriod
   VariableDeclaration.pendingRedemptions
   VariableDeclaration.redemptionPeriods
   VariableDeclaration.pendingRedemptionEthValue
   VariableDeclaration.pendingRedemptionBurnie
   VariableDeclaration.pendingRedemptionEthBase
   VariableDeclaration.pendingRedemptionBurnieBase
   VariableDeclaration.redemptionPeriodSupplySnapshot
   VariableDeclaration.redemptionPeriodIndex
   VariableDeclaration.redemptionPeriodBurned
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.BPS_DENOM
   VariableDeclaration.CREATOR_BPS
   VariableDeclaration.WHALE_POOL_BPS
   VariableDeclaration.AFFILIATE_POOL_BPS
   VariableDeclaration.LOOTBOX_POOL_BPS
   VariableDeclaration.REWARD_POOL_BPS
   VariableDeclaration.EARLYBIRD_POOL_BPS
   VariableDeclaration.MAX_DAILY_REDEMPTION_EV
   VariableDeclaration.game
   VariableDeclaration.coin
   VariableDeclaration.coinflip
   VariableDeclaration.dgnrsWrapper
   VariableDeclaration.steth
   ModifierDefinition.onlyGame
   FunctionDefinition.constructor
   FunctionDefinition.wrapperTransferTo
   FunctionDefinition.gameAdvance
   FunctionDefinition.gameClaimWhalePass
   FunctionDefinition.receive
   FunctionDefinition.depositSteth
   FunctionDefinition.poolBalance
   FunctionDefinition.transferFromPool
   FunctionDefinition.transferBetweenPools
   FunctionDefinition.burnAtGameOver
   FunctionDefinition.burn
   FunctionDefinition.burnWrapped
   FunctionDefinition._deterministicBurn
   FunctionDefinition._deterministicBurnFrom
   FunctionDefinition.hasPendingRedemptions
   FunctionDefinition.resolveRedemptionPeriod
   FunctionDefinition.claimRedemption
   FunctionDefinition.previewBurn
   FunctionDefinition.burnieReserve
   FunctionDefinition._submitGamblingClaim
   FunctionDefinition._submitGamblingClaimFrom
   FunctionDefinition._payEth
   FunctionDefinition._payBurnie
   FunctionDefinition._claimableWinnings
   FunctionDefinition._poolIndex
   FunctionDefinition._mint
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.balanceOf
   VariableDeclaration.poolBalances
   VariableDeclaration.pendingRedemptions
   VariableDeclaration.redemptionPeriods
   VariableDeclaration.pendingRedemptionEthValue
   VariableDeclaration.pendingRedemptionBurnie
   VariableDeclaration.pendingRedemptionEthBase
   VariableDeclaration.pendingRedemptionBurnieBase
   VariableDeclaration.redemptionPeriodSupplySnapshot
   VariableDeclaration.redemptionPeriodIndex
   VariableDeclaration.redemptionPeriodBurned
   VariableDeclaration.INITIAL_SUPPLY
   VariableDeclaration.BPS_DENOM
   VariableDeclaration.CREATOR_BPS
   VariableDeclaration.WHALE_POOL_BPS
   VariableDeclaration.AFFILIATE_POOL_BPS
   VariableDeclaration.LOOTBOX_POOL_BPS
   VariableDeclaration.REWARD_POOL_BPS
   VariableDeclaration.EARLYBIRD_POOL_BPS
   VariableDeclaration.MAX_DAILY_REDEMPTION_EV
   VariableDeclaration.game
   VariableDeclaration.coin
   VariableDeclaration.coinflip
   VariableDeclaration.dgnrsWrapper
   VariableDeclaration.steth
   EnumDefinition.Pool
   StructDefinition.PendingRedemption
   StructDefinition.RedemptionPeriod
   ErrorDefinition.Unauthorized
   ErrorDefinition.Insufficient
   ErrorDefinition.ZeroAddress
   ErrorDefinition.TransferFailed
   ErrorDefinition.BurnsBlockedDuringRng
   ErrorDefinition.UnresolvedClaim
   ErrorDefinition.NoClaim
   ErrorDefinition.NotResolved
   ErrorDefinition.ExceedsDailyRedemptionCap
   EventDefinition.Transfer
   EventDefinition.Burn
   EventDefinition.Deposit
   EventDefinition.PoolTransfer
   EventDefinition.PoolRebalance
   EventDefinition.RedemptionSubmitted
   EventDefinition.RedemptionResolved
   EventDefinition.RedemptionClaimed
   ModifierDefinition.onlyGame
   FunctionDefinition.advanceGame
   FunctionDefinition.setAfKingMode
   FunctionDefinition.claimWinnings
   FunctionDefinition.claimWhalePass
   FunctionDefinition.claimableWinningsOf
   FunctionDefinition.rngLocked
   FunctionDefinition.gameOver
   FunctionDefinition.currentDayView
   FunctionDefinition.rngWordForDay
   FunctionDefinition.playerActivityScore
   FunctionDefinition.resolveRedemptionLootbox
   FunctionDefinition.balanceOf
   FunctionDefinition.transfer
   FunctionDefinition.claimCoinflips
   FunctionDefinition.previewClaimCoinflips
   FunctionDefinition.claimCoinflipsForRedemption
   FunctionDefinition.getCoinflipDayResult
   FunctionDefinition.burnForSdgnrs
   FunctionDefinition.constructor
   FunctionDefinition.wrapperTransferTo
   FunctionDefinition.gameAdvance
   FunctionDefinition.gameClaimWhalePass
   FunctionDefinition.receive
   FunctionDefinition.depositSteth
   FunctionDefinition.poolBalance
   FunctionDefinition.transferFromPool
   FunctionDefinition.transferBetweenPools
   FunctionDefinition.burnAtGameOver
   FunctionDefinition.burn
   FunctionDefinition.burnWrapped
   FunctionDefinition._deterministicBurn
   FunctionDefinition._deterministicBurnFrom
   FunctionDefinition.hasPendingRedemptions
   FunctionDefinition.resolveRedemptionPeriod
   FunctionDefinition.claimRedemption
   FunctionDefinition.previewBurn
   FunctionDefinition.burnieReserve
   FunctionDefinition._submitGamblingClaim
   FunctionDefinition._submitGamblingClaimFrom
   FunctionDefinition._payEth
   FunctionDefinition._payBurnie
   FunctionDefinition._claimableWinnings
   FunctionDefinition._poolIndex
   FunctionDefinition._mint

```

```solidity
File: WrappedWrappedXRP.sol

1: 
   Current order:
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.balanceOf
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.Unwrapped
   EventDefinition.Donated
   EventDefinition.VaultAllowanceSpent
   ErrorDefinition.ZeroAddress
   ErrorDefinition.ZeroAmount
   ErrorDefinition.InsufficientBalance
   ErrorDefinition.InsufficientAllowance
   ErrorDefinition.InsufficientReserves
   ErrorDefinition.TransferFailed
   ErrorDefinition.OnlyMinter
   ErrorDefinition.OnlyVault
   ErrorDefinition.InsufficientVaultAllowance
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.INITIAL_VAULT_ALLOWANCE
   VariableDeclaration.vaultAllowance
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.wXRP
   VariableDeclaration.MINTER_GAME
   VariableDeclaration.MINTER_COIN
   VariableDeclaration.MINTER_COINFLIP
   VariableDeclaration.MINTER_VAULT
   VariableDeclaration.wXRPReserves
   FunctionDefinition.supplyIncUncirculated
   FunctionDefinition.vaultMintAllowance
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition._transfer
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.unwrap
   FunctionDefinition.donate
   FunctionDefinition.mintPrize
   FunctionDefinition.vaultMintTo
   FunctionDefinition.burnForGame
   
   Suggested order:
   VariableDeclaration.name
   VariableDeclaration.symbol
   VariableDeclaration.decimals
   VariableDeclaration.totalSupply
   VariableDeclaration.INITIAL_VAULT_ALLOWANCE
   VariableDeclaration.vaultAllowance
   VariableDeclaration.balanceOf
   VariableDeclaration.allowance
   VariableDeclaration.wXRP
   VariableDeclaration.MINTER_GAME
   VariableDeclaration.MINTER_COIN
   VariableDeclaration.MINTER_COINFLIP
   VariableDeclaration.MINTER_VAULT
   VariableDeclaration.wXRPReserves
   ErrorDefinition.ZeroAddress
   ErrorDefinition.ZeroAmount
   ErrorDefinition.InsufficientBalance
   ErrorDefinition.InsufficientAllowance
   ErrorDefinition.InsufficientReserves
   ErrorDefinition.TransferFailed
   ErrorDefinition.OnlyMinter
   ErrorDefinition.OnlyVault
   ErrorDefinition.InsufficientVaultAllowance
   EventDefinition.Transfer
   EventDefinition.Approval
   EventDefinition.Unwrapped
   EventDefinition.Donated
   EventDefinition.VaultAllowanceSpent
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition.balanceOf
   FunctionDefinition.supplyIncUncirculated
   FunctionDefinition.vaultMintAllowance
   FunctionDefinition.approve
   FunctionDefinition.transfer
   FunctionDefinition.transferFrom
   FunctionDefinition._transfer
   FunctionDefinition._mint
   FunctionDefinition._burn
   FunctionDefinition.unwrap
   FunctionDefinition.donate
   FunctionDefinition.mintPrize
   FunctionDefinition.vaultMintTo
   FunctionDefinition.burnForGame

```

### <a name="NC-31"></a>[NC-31] Use Underscores for Number Literals (add an underscore every 3 digits)

*Instances (29)*:
```solidity
File: BurnieCoin.sol

347:       |  accumulates 1000 BURNIE per coinflip window. When a player sets     |

```

```solidity
File: BurnieCoinflip.sol

128:     uint48 private constant JACKPOT_RESET_TIME = 82620;

129:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

132:     uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;

1021:         uint256 bonusCap = 1000 ether;

```

```solidity
File: DegenerusAdmin.sol

288:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

313:     uint256 private constant BPS = 10000;

534:         if (elapsed >= 120 hours) return 1000;  // 10%

535:         if (elapsed >= 96 hours)  return 2000;  // 20%

536:         if (elapsed >= 72 hours)  return 3000;  // 30%

537:         if (elapsed >= 48 hours)  return 4000;  // 40%

538:         return 5000; // 50%

761:         if (subBal >= 1000 ether) return 0;

```

```solidity
File: DegenerusGame.sol

186:     uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

194:     uint16 private constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

203:     uint16 private constant DEITY_PASS_ACTIVITY_BONUS_BPS = 8000;

2490:                     bonusBps += 1000; // +10% for 10-level bundle

2492:                     bonusBps += 4000; // +40% for 100-level bundle

```

```solidity
File: DegenerusQuests.sol

125:     uint256 private constant PRICE_COIN_UNIT = 1000 ether;

```

```solidity
File: DegenerusVault.sol

418:         return balance * 1000 > supply * 501;

```

```solidity
File: DeityBoonViewer.sol

76:     uint16 private constant W_TOTAL = 1298;

77:     uint16 private constant W_TOTAL_NO_DECIMATOR = 1248;

```

```solidity
File: StakedDegenerusStonk.sol

217:     uint16 private constant CREATOR_BPS = 2000;

220:     uint16 private constant WHALE_POOL_BPS = 1000;

221:     uint16 private constant AFFILIATE_POOL_BPS = 3500;

222:     uint16 private constant LOOTBOX_POOL_BPS = 2000;

224:     uint16 private constant EARLYBIRD_POOL_BPS = 1000;

607:                 burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;

```

```solidity
File: libraries/GameTimeLib.sol

14:     uint48 internal constant JACKPOT_RESET_TIME = 82620;

```

### <a name="NC-32"></a>[NC-32] Internal and private variables and functions names should begin with an underscore
According to the Solidity Style Guide, Non-`external` variable and function names should begin with an [underscore](https://docs.soliditylang.org/en/latest/style-guide.html#underscore-prefix-for-non-external-functions-and-variables)

*Instances (50)*:
```solidity
File: BurnieCoinflip.sol

155:     mapping(uint48 => mapping(address => uint256)) internal coinflipBalance;

156:     mapping(uint48 => CoinflipDayResult) internal coinflipDayResult;

157:     mapping(address => PlayerCoinflipState) internal playerState;

163:     address internal bountyOwedTo;

166:     uint48 internal flipsClaimableDay;

173:     mapping(uint48 => PlayerScore) internal coinflipTopByDay;

```

```solidity
File: DegenerusAdmin.sol

278:     uint256 private voidedUpTo;

```

```solidity
File: DegenerusAffiliate.sol

209:     mapping(uint24 => mapping(address => uint256)) private affiliateCoinEarned;

214:     mapping(address => bytes32) private playerReferralCode;

219:     mapping(uint24 => PlayerScore) private affiliateTopByLevel;

229:     mapping(uint24 => mapping(address => mapping(address => uint256))) private affiliateCommissionFromSender;

```

```solidity
File: DegenerusJackpots.sol

116:     mapping(uint24 => mapping(address => uint256)) internal bafTotals;

119:     mapping(uint24 => PlayerScore[4]) internal bafTop;

122:     mapping(uint24 => uint8) internal bafTopLen;

125:     mapping(uint24 => uint256) internal bafEpoch;

128:     mapping(uint24 => mapping(address => uint256)) internal bafPlayerEpoch;

131:     uint48 internal lastBafResolvedDay;

```

```solidity
File: DegenerusQuests.sol

268:     DailyQuest[QUEST_SLOT_COUNT] private activeQuests;

271:     mapping(address => PlayerQuestState) private questPlayerState;

274:     mapping(address => uint16) private questStreakShieldCount;

277:     uint24 private questVersionCounter = 1;

```

```solidity
File: DegenerusTraitUtils.sol

113:     function weightedBucket(uint32 rnd) internal pure returns (uint8) {

143:     function traitFromWord(uint64 rnd) internal pure returns (uint8) {

172:     function packedTraitsFromSeed(uint256 rand) internal pure returns (uint32) {

```

```solidity
File: DegenerusVault.sol

389:     // ---------------------------------------------------------------------

```

```solidity
File: StakedDegenerusStonk.sol

176:     uint256[5] private poolBalances;

198:     uint256 internal pendingRedemptionBurnie;       // total reserved BURNIE

199:     uint256 internal pendingRedemptionEthBase;      // current unresolved period ETH base

200:     uint256 internal pendingRedemptionBurnieBase;   // current unresolved period BURNIE base

202:     uint256 internal redemptionPeriodSupplySnapshot;

203:     uint48  internal redemptionPeriodIndex;

204:     uint256 internal redemptionPeriodBurned;

```

```solidity
File: libraries/BitPackingLib.sol

79:     function setPacked(

```

```solidity
File: libraries/EntropyLib.sol

16:     function entropyStep(uint256 state) internal pure returns (uint256) {

```

```solidity
File: libraries/GameTimeLib.sol

21:     function currentDayIndex() internal view returns (uint48) {

31:     function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {

```

```solidity
File: libraries/JackpotBucketLib.sol

36:     function traitBucketCounts(uint256 entropy) internal pure returns (uint16[4] memory counts) {

55:     function scaleTraitBucketCountsWithCap(

98:     function bucketCountsForPoolCap(

110:     function sumBucketCounts(uint16[4] memory counts) internal pure returns (uint256 total) {

115:     function capBucketCounts(

211:     function bucketShares(

240:     function soloBucketIndex(uint256 entropy) internal pure returns (uint8) {

245:     function rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) internal pure returns (uint16) {

251:     function shareBpsByBucket(uint64 packed, uint8 offset) internal pure returns (uint16[4] memory shares) {

264:     function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed) {

269:     function unpackWinningTraits(uint32 packed) internal pure returns (uint8[4] memory traits) {

278:     function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {

290:     function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order) {

```

```solidity
File: libraries/PriceLookupLib.sol

21:     function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {

```

### <a name="NC-33"></a>[NC-33] Event is missing `indexed` fields
Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

*Instances (67)*:
```solidity
File: BurnieCoin.sol

50:     event Transfer(address indexed from, address indexed to, uint256 amount);

53:     event Approval(

63:     event DecimatorBurn(

70:     event TerminalDecimatorBurn(

79:     event DailyQuestRolled(

90:     event QuestCompleted(

100:     event LinkCreditRecorded(address indexed player, uint256 amount);

105:     event VaultEscrowRecorded(address indexed sender, uint256 amount);

109:     event VaultAllowanceSpent(address indexed spender, uint256 amount);

```

```solidity
File: BurnieCoinflip.sol

41:     event CoinflipDeposit(address indexed player, uint256 creditedFlip);

42:     event CoinflipAutoRebuyToggled(address indexed player, bool enabled);

43:     event CoinflipAutoRebuyStopSet(address indexed player, uint256 stopAmount);

44:     event QuestCompleted(

55:     event CoinflipStakeUpdated(

68:     event CoinflipDayResolved(

80:     event CoinflipTopUpdated(

88:     event BiggestFlipUpdated(address indexed player, uint256 recordAmount);

89:     event BountyOwed(address indexed player, uint128 bounty, uint256 recordFlip);

90:     event BountyPaid(address indexed to, uint256 amount);

```

```solidity
File: DegenerusAdmin.sol

200:     event SubscriptionShutdown(

205:     event LinkCreditRecorded(address indexed player, uint256 amount);

209:     event ProposalCreated(

216:     event VoteCast(

222:     event ProposalExecuted(

```

```solidity
File: DegenerusAffiliate.sol

72:     event Affiliate(uint256 amount, bytes32 indexed code, address sender);

105:     event AffiliateTopUpdated(

```

```solidity
File: DegenerusDeityPass.sol

49:     event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

52:     event RenderColorsUpdated(string outlineColor, string backgroundColor, string nonCryptoSymbolColor);

```

```solidity
File: DegenerusGame.sol

122:     event LootboxRngThresholdUpdated(uint256 previous, uint256 current);

127:     event OperatorApproval(

1304:         address indexed caller,

1317:         uint256 newBalance,

1436:     /// @notice Emitted when a player toggles decimator auto-rebuy on or off.

1439:     /// @notice Emitted when a player sets the auto-rebuy take profit.

1442:     /// @notice Emitted when a player toggles afKing mode on or off.

1445:     /// @notice Enable or disable auto-rebuy for claimable winnings.

```

```solidity
File: DegenerusJackpots.sol

64:     event BafFlipRecorded(

```

```solidity
File: DegenerusQuests.sol

65:     event QuestSlotRolled(

95:     event QuestStreakShieldUsed(

103:     event QuestStreakBonusAwarded(

111:     event QuestStreakReset(

```

```solidity
File: DegenerusStonk.sol

52:     event Transfer(address indexed from, address indexed to, uint256 amount);

54:     event Approval(address indexed owner, address indexed spender, uint256 amount);

56:     event BurnThrough(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);

58:     event UnwrapTo(address indexed recipient, uint256 amount);

244:     event YearSweep(uint256 ethToGnrus, uint256 stethToGnrus, uint256 ethToVault, uint256 stethToVault);

```

```solidity
File: DegenerusVault.sol

156:     event Transfer(address indexed from, address indexed to, uint256 amount);

161:     event Approval(address indexed owner, address indexed spender, uint256 amount);

332:     event Deposit(address indexed from, uint256 ethAmount, uint256 stEthAmount, uint256 coinAmount);

339:     event Claim(address indexed from, uint256 sharesBurned, uint256 ethOut, uint256 stEthOut, uint256 coinOut);

```

```solidity
File: GNRUS.sol

96:     event Transfer(address indexed from, address indexed to, uint256 amount);

99:     event Burn(address indexed burner, uint256 gnrusAmount, uint256 ethOut, uint256 stethOut);

108:     event LevelResolved(uint24 indexed level, uint48 indexed winningProposalId, address recipient, uint256 gnrusDistributed);

114:     event GameOverFinalized(uint256 gnrusBurned, uint256 ethClaimed, uint256 stethClaimed);

```

```solidity
File: StakedDegenerusStonk.sol

101:     event Transfer(address indexed from, address indexed to, uint256 amount);

109:     event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);

116:     event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieAmount);

122:     event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

128:     event PoolRebalance(Pool indexed from, Pool indexed to, uint256 amount);

131:     event RedemptionSubmitted(address indexed player, uint256 sdgnrsAmount, uint256 ethValueOwed, uint256 burnieOwed, uint48 periodIndex);

134:     event RedemptionResolved(uint48 indexed periodIndex, uint16 roll, uint256 rolledBurnie, uint48 flipDay);

137:     event RedemptionClaimed(address indexed player, uint16 roll, bool flipResolved, uint256 ethPayout, uint256 burniePayout, uint256 lootboxEth);

```

```solidity
File: WrappedWrappedXRP.sol

51:     event Transfer(address indexed from, address indexed to, uint256 amount);

57:     event Approval(

66:     event Unwrapped(address indexed user, uint256 amount);

71:     event Donated(address indexed donor, uint256 amount);

76:     event VaultAllowanceSpent(address indexed spender, uint256 amount);

```

### <a name="NC-34"></a>[NC-34] Constants should be defined rather than using magic numbers

*Instances (8)*:
```solidity
File: DegenerusDeityPass.sol

313:             b[5 - k] = bytes1(uint8(48 + (f % 10)));

```

```solidity
File: DegenerusGame.sol

223:       |  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |

279:       |  • RNG must be ready (not locked) or recently stale (18h timeout)                      |

1785:       |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |

1786:       |  • BAF - Big-ass-flip jackpot (20% of pool at L%100=0)                                        |

```

```solidity
File: DegenerusJackpots.sol

195:       |  | 45% | Scatter 1st place (50 rounds x 4 multi-level trait tickets) | |

196:       |  | 25% | Scatter 2nd place (50 rounds x 4 multi-level trait tickets) | |

```

```solidity
File: GNRUS.sol

148:         address proposer;        // 20 bytes ── slot 1 (12 bytes free)

```

### <a name="NC-35"></a>[NC-35] Variables need not be initialized to zero
The default value for variables is zero, so initializing them to zero is superfluous.

*Instances (15)*:
```solidity
File: DegenerusGame.sol

412:         uint256 earlybirdEth = 0;

2787:         for (uint8 q = 0; q < 4; ++q) {

2789:             for (uint8 s = 0; s < 8; ++s) {

```

```solidity
File: DegenerusJackpots.sol

381:             for (uint8 round = 0; round < BAF_SCATTER_ROUNDS; ) {

```

```solidity
File: DegenerusQuests.sol

773:         uint256 mintPrice = 0;

946:             uint256 currentPrice = 0;

```

```solidity
File: DeityBoonViewer.sol

100:         for (uint8 i = 0; i < DEITY_DAILY_BOON_COUNT; ) {

114:         uint256 cursor = 0;

```

```solidity
File: GNRUS.sol

338:             balanceOf[address(this)] = 0;

466:         for (uint8 i = 0; i < count;) {

```

```solidity
File: Icons32Data.sol

159:         for (uint256 i = 0; i < paths.length; ++i) {

176:             for (uint256 i = 0; i < 8; ++i) {

180:             for (uint256 i = 0; i < 8; ++i) {

184:             for (uint256 i = 0; i < 8; ++i) {

```

```solidity
File: StakedDegenerusStonk.sol

424:             balanceOf[address(this)] = 0;

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) | `approve()`/`safeApprove()` may revert if the current approval is not zero | 1 |
| [L-2](#L-2) | Some tokens may revert when zero value transfers are made | 3 |
| [L-3](#L-3) | Missing checks for `address(0)` when assigning values to address state variables | 2 |
| [L-4](#L-4) | `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()` | 35 |
| [L-5](#L-5) | `decimals()` is not a part of the ERC-20 standard | 2 |
| [L-6](#L-6) | Deprecated approve() function | 1 |
| [L-7](#L-7) | Division by zero not prevented | 27 |
| [L-8](#L-8) | Empty `receive()/payable fallback()` function does not authenticate requests | 1 |
| [L-9](#L-9) | External call recipient may consume all transaction gas | 11 |
| [L-10](#L-10) | Fallback lacking `payable` | 5 |
| [L-11](#L-11) | Signature use at deadlines should be allowed | 2 |
| [L-12](#L-12) | Prevent accidentally burning tokens | 67 |
| [L-13](#L-13) | Possible rounding issue | 15 |
| [L-14](#L-14) | Loss of precision | 24 |
| [L-15](#L-15) | Solidity version 0.8.20+ may not work on other chains due to `PUSH0` | 9 |
| [L-16](#L-16) | Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership` | 1 |
| [L-17](#L-17) | Sweeping may break accounting if tokens with multiple addresses are used | 9 |
| [L-18](#L-18) | Consider using OpenZeppelin's SafeCast library to prevent unexpected overflows when downcasting | 50 |
| [L-19](#L-19) | Unsafe ERC20 operation(s) | 20 |
| [L-20](#L-20) | Upgradeable contract not initialized | 1 |
### <a name="L-1"></a>[L-1] `approve()`/`safeApprove()` may revert if the current approval is not zero
- Some tokens (like the *very popular* USDT) do not work when changing the allowance from an existing non-zero allowance value (it will revert if the current approval is not zero to protect against front-running changes of approvals). These tokens must first be approved for zero and then the actual allowance can be approved.
- Furthermore, OZ's implementation of safeApprove would throw an error if an approve is attempted from a non-zero value (`"SafeERC20: approve from non-zero to non-zero allowance"`)

Set the allowance to zero immediately before each of the existing allowance calls

*Instances (1)*:
```solidity
File: DegenerusGame.sol

1959:             if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();

```

### <a name="L-2"></a>[L-2] Some tokens may revert when zero value transfers are made
Example: https://github.com/d-xo/weird-erc20#revert-on-zero-value-transfers.

In spite of the fact that EIP-20 [states](https://github.com/ethereum/EIPs/blob/46b9b698815abbfa628cd1097311deee77dd45c5/EIPS/eip-20.md?plain=1#L116) that zero-valued transfers must be accepted, some tokens, such as LEND will revert if this is attempted, which may cause transactions that involve other tokens (such as batch operations) to fully revert. Consider skipping the transfer if the amount is zero, which will also save gas.

*Instances (3)*:
```solidity
File: DegenerusStonk.sol

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

```

```solidity
File: WrappedWrappedXRP.sol

301:         if (!wXRP.transfer(msg.sender, amount)) {

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

```

### <a name="L-3"></a>[L-3] Missing checks for `address(0)` when assigning values to address state variables

*Instances (2)*:
```solidity
File: BurnieCoinflip.sol

662:                     bountyOwedTo = player;

```

```solidity
File: DegenerusDeityPass.sol

99:         renderer = newRenderer;

```

### <a name="L-4"></a>[L-4] `abi.encodePacked()` should not be used with dynamic types when passing the result to a hash function such as `keccak256()`
Use `abi.encode()` instead which will pad items to 32 bytes, which will [prevent hash collisions](https://docs.soliditylang.org/en/v0.8.13/abi-spec.html#non-standard-packed-mode) (e.g. `abi.encodePacked(0x123,0x456)` => `0x123456` => `abi.encodePacked(0x1,0x23456)`, but `abi.encode(0x123,0x456)` => `0x0...1230...456`). "Unless there is a compelling reason, `abi.encode` should be preferred". If there is only one argument to `abi.encodePacked()` it can often be cast to `bytes()` or `bytes32()` [instead](https://ethereum.stackexchange.com/questions/30912/how-to-compare-strings-in-solidity#answer-82739).
If all arguments are strings and or bytes, `bytes.concat()` should be used instead

*Instances (35)*:
```solidity
File: DegenerusDeityPass.sol

138:             symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));

163:             '{"name":"Deity Pass #', Strings.toString(tokenId), ' - ', symbolName,

164:             '","description":"Degenerus Deity Pass. Grants divine authority over the ',

165:             symbolName, ' symbol.","image":"data:image/svg+xml;base64,',

166:             Base64.encode(bytes(svg)),

167:             '"}'

171:             "data:application/json;base64,",

172:             Base64.encode(bytes(json))

188:                 "<g transform='",

189:                 _mat6(sSym1e6, txm, tyn),

190:                 isCrypto

193:                 iconPath,

194:                 "</g></g>"

199:             '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'

202:             _nonCryptoSymbolColor,

203:             '!important;stroke:',

204:             _nonCryptoSymbolColor,

205:             '!important;}</style>'

208:             _backgroundColor,

209:             '" stroke="',

210:             _outlineColor,

211:             '" stroke-width="2.2"/>',

212:             symbolGroup,

213:             "</svg>"

284:                 "matrix(",

285:                 s,

286:                 " 0 0 ",

287:                 s,

288:                 " ",

289:                 _dec6s(tx1e6),

290:                 " ",

291:                 _dec6s(ty1e6),

292:                 ")"

300:         return string(abi.encodePacked(Strings.toString(i), ".", _pad6(uint32(f))));

305:             return string(abi.encodePacked("-", _dec6(uint256(-x))));

```

### <a name="L-5"></a>[L-5] `decimals()` is not a part of the ERC-20 standard
The `decimals()` function is not a part of the [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20), and was added later as an [optional extension](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/IERC20Metadata.sol). As such, some valid ERC20 tokens do not support this interface, so it is unsafe to blindly cast all tokens to this interface, and then call this function.

*Instances (2)*:
```solidity
File: DegenerusAdmin.sol

362:             IAggregatorV3(feed).decimals() != LINK_ETH_FEED_DECIMALS

793:             try IAggregatorV3(feed).decimals() returns (uint8 dec) {

```

### <a name="L-6"></a>[L-6] Deprecated approve() function
Due to the inheritance of ERC20's approve function, there's a vulnerability to the ERC20 approve and double spend front running attack. Briefly, an authorized spender could spend both allowances by front running an allowance-changing transaction. Consider implementing OpenZeppelin's `.safeApprove()` function to help mitigate this.

*Instances (1)*:
```solidity
File: DegenerusGame.sol

1961:             return;

```

### <a name="L-7"></a>[L-7] Division by zero not prevented
The divisions below take an input parameter which does not have any zero-value checks, which may lead to the functions reverting when zero is passed.

*Instances (27)*:
```solidity
File: BurnieCoinflip.sol

514:                             uint256 reserved = (payout / takeProfit) *

1035:             return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1039:             / (uint256(BPS_DENOMINATOR) * 2);

```

```solidity
File: DegenerusAdmin.sol

721:         uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;

```

```solidity
File: DegenerusAffiliate.sol

705:         points = sum / ethUnit;

842:         uint256 reductionBps = (BPS_DENOMINATOR - LOOTBOX_TAPER_MIN_BPS) * excess / range;

```

```solidity
File: DegenerusGame.sol

1401:         uint256 reward = (allocation * score) / denominator;

1416:                 PRICE_COIN_UNIT) / price;

2520:         return (uint256(mintCount) * 25) / uint256(currLevel);

```

```solidity
File: DegenerusVault.sol

115: |  |   Formula: claimAmount = (reserveBalance * sharesBurned) / totalShareSupply                       | |

773:         coinOut = (coinBal * amount) / supplyBefore;

851:         uint256 claimValue = (reserve * amount) / supplyBefore;

891:         burnAmount = (coinOut * supply + reserve - 1) / reserve;

908:         burnAmount = (targetValue * supply + reserve - 1) / reserve;

910:         uint256 claimValue = (reserve * burnAmount) / supply;

931:         coinOut = (coinBal * amount) / supply;

943:         uint256 claimValue = (reserve * amount) / supply;

```

```solidity
File: GNRUS.sol

293:         uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;

```

```solidity
File: StakedDegenerusStonk.sol

490:         uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

661:         uint256 totalValueOwed = (totalMoney * amount) / supply;

681:             burnieOut = (totalBurnie * amount) / supply;

728:         uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

734:         uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;

```

```solidity
File: libraries/JackpotBucketLib.sol

70:             scaleBps = JACKPOT_SCALE_BASE_BPS + (progress * (JACKPOT_SCALE_FIRST_BPS - JACKPOT_SCALE_BASE_BPS)) / range;

74:             scaleBps = JACKPOT_SCALE_FIRST_BPS + (progress * (uint256(maxScaleBps) - JACKPOT_SCALE_FIRST_BPS)) / range;

154:                 uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;

226:                         share = (share / unitBucket) * unitBucket;

```

### <a name="L-8"></a>[L-8] Empty `receive()/payable fallback()` function does not authenticate requests
If the intention is for the Ether to be used, the function should call another function, otherwise it should revert (e.g. require(msg.sender == address(weth))). Having no access control on the function means that someone may send Ether to the contract, and have no way to get anything back out, which is a loss of funds. If the concern is having to spend a small amount of gas to check the sender against an immutable address, the code should at least have a function to rescue unused Ether.

*Instances (1)*:
```solidity
File: GNRUS.sol

507:     receive() external payable {}

```

### <a name="L-9"></a>[L-9] External call recipient may consume all transaction gas
There is no limit specified on the amount of gas used, so the recipient can use up all of the transaction's gas, causing it to revert. Use `addr.call{gas: <amount>}("")` or [this](https://github.com/nomad-xyz/ExcessivelySafeCall) library instead.

*Instances (11)*:
```solidity
File: DegenerusGame.sol

1978:             (bool okEth, ) = payable(to).call{value: ethSend}("");

1995:             (bool ok, ) = payable(to).call{value: leftover}("");

2016:         (bool ok, ) = payable(to).call{value: remaining}("");

```

```solidity
File: DegenerusStonk.sol

185:             (bool success, ) = msg.sender.call{value: ethOut}("");

275:             (bool ok,) = payable(ContractAddresses.GNRUS).call{value: ethToGnrus}("");

279:             (bool ok,) = payable(ContractAddresses.VAULT).call{value: ethToVault}("");

```

```solidity
File: DegenerusVault.sol

1032:         (bool ok, ) = to.call{value: amount}("");

```

```solidity
File: GNRUS.sol

318:             (bool ok,) = burner.call{value: ethOut}("");

```

```solidity
File: StakedDegenerusStonk.sol

517:             (bool success, ) = beneficiary.call{value: ethOut}("");

783:             (bool success, ) = player.call{value: amount}("");

789:                 (bool success, ) = player.call{value: ethOut}("");

```

### <a name="L-10"></a>[L-10] Fallback lacking `payable`

*Instances (5)*:
```solidity
File: DegenerusGame.sol

1369:             _payoutWithEthFallback(player, payout);

1371:             _payoutWithStethFallback(player, payout);

1953:       |  Implements fallback logic when one asset is insufficient.           |

1971:     function _payoutWithStethFallback(address to, uint256 amount) private {

2004:     function _payoutWithEthFallback(address to, uint256 amount) private {

```

### <a name="L-11"></a>[L-11] Signature use at deadlines should be allowed
According to [EIP-2612](https://github.com/ethereum/EIPs/blob/71dc97318013bf2ac572ab63fab530ac9ef419ca/EIPS/eip-2612.md?plain=1#L58), signatures used on exactly the deadline timestamp are supposed to be allowed. While the signature may or may not be used for the exact EIP-2612 use case (transfer approvals), for consistency's sake, all deadlines should follow this semantic. If the timestamp is an expiration rather than a deadline, consider whether it makes more sense to include the expiration timestamp as a valid timestamp, as is done for deadlines.

*Instances (2)*:
```solidity
File: DegenerusAdmin.sol

749:         if (updatedAt > block.timestamp) return 0;

788:             if (updatedAt > block.timestamp) return false;

```

### <a name="L-12"></a>[L-12] Prevent accidentally burning tokens
Minting and burning tokens to address(0) prevention

*Instances (67)*:
```solidity
File: BurnieCoin.sol

272:         _mint(ContractAddresses.SDGNRS, 2_000_000 ether);

530:         _burn(from, amount);

539:         _mint(to, amount);

549:         _mint(to, amount);

558:         _mint(player, amount);

874:         _burn(target, amount - consumed);

908:         _burn(caller, amount - consumed);

998:         _burn(caller, amount - consumed);

```

```solidity
File: BurnieCoinflip.sol

180:         burnie = IBurnieCoin(_burnie);

198:             msg.sender != address(burnie)

204:         if (msg.sender != address(burnie)) revert OnlyBurnieCoin();

220:             state.claimableStored = uint128(uint256(state.claimableStored) + mintable);

257:             state.claimableStored = uint128(uint256(state.claimableStored) + mintable);

266:         burnie.burnForCoinflip(caller, amount);

393:                 burnie.mintForCoinflip(player, toClaim);

746:             burnie.mintForCoinflip(player, mintable);

765:             burnie.mintForCoinflip(player, mintable);

```

```solidity
File: DegenerusGame.sol

412:         uint256 earlybirdEth = 0;

430:     /// @notice Pay DGNRS bounty for the biggest flip record holder.

608:             .delegatecall(

610:                     IDegenerusGameMintModule.purchaseBurnieLootbox.selector,

1041:                 abi.encodeWithSelector(

1042:                     IDegenerusGameMintModule.recordMintData.selector,

1608:                 BitPackingLib.MASK_24

1620:                 BitPackingLib.MASK_24

2344:                     BitPackingLib.MASK_24

2358:                     BitPackingLib.MASK_24

2373:     /// @dev Batches multiple stats into single call for gas efficiency.

2393:     /*+======================================================================+

2435:             (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &

2458:                 // Active pass = full participation credit (always had pass active)

2523:     /*+======================================================================+

```

```solidity
File: DegenerusQuests.sol

483:                     uint256 target = _questTargetValue(quest, slot, mintPrice);

484:                     (reward, questType, streak, completed) = _questHandleProgressSlot(

496:                     uint256 target = _questTargetValue(quest, slot, mintPrice);

497:                     (reward, questType, streak, completed) = _questHandleProgressSlot(

614:         state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], burnAmount);

777:         uint256 target = _questTargetValue(quest, slotIndex, mintPrice);

778:         return _questHandleProgressSlot(

1088:             return _questCompleteWithPair(player, state, quests, slot, quest, currentDay, mintPrice);

1482:         ) = _maybeCompleteOther(player, state, quests, otherSlot, currentDay, mintPrice);

1528:         if (!_questReady(state, quest, slot, mintPrice)) {

```

```solidity
File: DegenerusStonk.sol

159:         _burn(msg.sender, amount);

173:         _burn(msg.sender, amount);

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

189:         emit BurnThrough(msg.sender, amount, ethOut, stethOut, burnieOut);

```

```solidity
File: DegenerusVault.sol

521:         gamePlayer.purchaseBurnieLootbox(address(this), burnieAmount);

756:     }

826:     }

```

```solidity
File: GNRUS.sol

247:         _mint(address(this), INITIAL_SUPPLY);

310:         emit Transfer(burner, address(0), amount);

311:         emit Burn(burner, amount, ethOut, stethOut);

315:             if (!steth.transfer(burner, stethOut)) revert TransferFailed();

318:             (bool ok,) = burner.call{value: ethOut}("");

```

```solidity
File: StakedDegenerusStonk.sol

280:         _mint(ContractAddresses.DGNRS, creatorAmount);

281:         _mint(address(this), poolTotal);

496:         emit Transfer(burnFrom, address(0), amount);

564:         emit RedemptionResolved(period, roll, burnieToCredit, flipDay);

632:             _payBurnie(player, burniePayout);

635:         emit RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth);

741:         emit Transfer(burnFrom, address(0), amount);

760:         claim.burnieOwed += uint96(burnieOwed);

768:         emit RedemptionSubmitted(beneficiary, amount, ethValueOwed, burnieOwed, currentPeriod);

```

```solidity
File: WrappedWrappedXRP.sol

297:         _burn(msg.sender, amount);

353:         _mint(to, amount);

373:         _mint(to, amount);

387:         _burn(from, amount);

```

### <a name="L-13"></a>[L-13] Possible rounding issue
Division by large numbers may result in the result being zero, due to solidity not supporting fractions. Consider requiring a minimum amount for the numerator to ensure that it is always larger than the denominator. Also, there is indication of multiplication and division without the use of parenthesis which could result in issues.

*Instances (15)*:
```solidity
File: DegenerusVault.sol

115: |  |   Formula: claimAmount = (reserveBalance * sharesBurned) / totalShareSupply                       | |

773:         coinOut = (coinBal * amount) / supplyBefore;

851:         uint256 claimValue = (reserve * amount) / supplyBefore;

891:         burnAmount = (coinOut * supply + reserve - 1) / reserve;

908:         burnAmount = (targetValue * supply + reserve - 1) / reserve;

910:         uint256 claimValue = (reserve * burnAmount) / supply;

931:         coinOut = (coinBal * amount) / supply;

943:         uint256 claimValue = (reserve * amount) / supply;

```

```solidity
File: GNRUS.sol

293:         uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;

```

```solidity
File: StakedDegenerusStonk.sol

490:         uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

661:         uint256 totalValueOwed = (totalMoney * amount) / supply;

681:             burnieOut = (totalBurnie * amount) / supply;

728:         uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

734:         uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;

```

```solidity
File: libraries/JackpotBucketLib.sol

154:                 uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;

```

### <a name="L-14"></a>[L-14] Loss of precision
Division by large numbers may result in the result being zero, due to solidity not supporting fractions. Consider requiring a minimum amount for the numerator to ensure that it is always larger than the denominator

*Instances (24)*:
```solidity
File: BurnieCoin.sol

953:             uint256 boost = (cappedBase * boonBps) / BPS_DENOMINATOR;

1040:         uint256 reduction = (range * bonusBps + (DECIMATOR_ACTIVITY_CAP_BPS / 2)) / DECIMATOR_ACTIVITY_CAP_BPS;

```

```solidity
File: BurnieCoinflip.sol

1035:             return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);

1039:             / (uint256(BPS_DENOMINATOR) * 2);

```

```solidity
File: DegenerusAffiliate.sol

513:         uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;

838:             return (amt * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

843:         return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;

```

```solidity
File: DegenerusDeityPass.sol

183:         uint32 sSym1e6 = uint32((uint256(2) * SYMBOL_HALF_SIZE * fitSym1e6) / ICON_VB);

```

```solidity
File: DegenerusJackpots.sol

193:       |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)  | |

452:             uint256 perRoundFirst = scatterTop / BAF_SCATTER_ROUNDS;

453:             uint256 perRoundSecond = scatterSecond / BAF_SCATTER_ROUNDS;

```

```solidity
File: DegenerusVault.sol

115: |  |   Formula: claimAmount = (reserveBalance * sharesBurned) / totalShareSupply                       | |

891:         burnAmount = (coinOut * supply + reserve - 1) / reserve;

908:         burnAmount = (targetValue * supply + reserve - 1) / reserve;

```

```solidity
File: GNRUS.sol

376:             if ((sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();

421:             weight += uint48((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / BPS_DENOM);

484:         uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;

```

```solidity
File: StakedDegenerusStonk.sol

263:         uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;

264:         uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;

265:         uint256 earlybirdAmount = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;

266:         uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;

267:         uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;

268:         uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;

```

```solidity
File: WrappedWrappedXRP.sol

277:       |                       WRAP / UNWRAP FUNCTIONS                        |

```

### <a name="L-15"></a>[L-15] Solidity version 0.8.20+ may not work on other chains due to `PUSH0`
The compiler for Solidity 0.8.20 switches the default target EVM version to [Shanghai](https://blog.soliditylang.org/2023/05/10/solidity-0.8.20-release-announcement/#important-note), which includes the new `PUSH0` op code. This op code may not yet be implemented on all L2s, so deployment on these chains will fail. To work around this issue, use an earlier [EVM](https://docs.soliditylang.org/en/v0.8.20/using-the-compiler.html?ref=zaryabs.com#setting-the-evm-version-to-target) [version](https://book.getfoundry.sh/reference/config/solidity-compiler#evm_version). While the project itself may or may not compile with 0.8.20, other projects with which it integrates, or which extend this project may, and those projects will have problems deploying these contracts/libraries.

*Instances (9)*:
```solidity
File: ContractAddresses.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: DegenerusQuests.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: DegenerusTraitUtils.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: Icons32Data.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: libraries/BitPackingLib.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: libraries/EntropyLib.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: libraries/GameTimeLib.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: libraries/JackpotBucketLib.sol

2: pragma solidity ^0.8.20;

```

```solidity
File: libraries/PriceLookupLib.sol

2: pragma solidity ^0.8.20;

```

### <a name="L-16"></a>[L-16] Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership`
Use [Ownable2Step.transferOwnership](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol) which is safer. Use it as it is more secure due to 2-stage ownership transfer.

**Recommended Mitigation Steps**

Use <a href="https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol">Ownable2Step.sol</a>
  
  ```solidity
      function acceptOwnership() external {
          address sender = _msgSender();
          require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
          _transferOwnership(sender);
      }
```

*Instances (1)*:
```solidity
File: DegenerusDeityPass.sol

89:     function transferOwnership(address newOwner) external onlyOwner {

```

### <a name="L-17"></a>[L-17] Sweeping may break accounting if tokens with multiple addresses are used
There have been [cases](https://blog.openzeppelin.com/compound-tusd-integration-issue-retrospective/) in the past where a token mistakenly had two addresses that could control its balance, and transfers using one address impacted the balance of the other. To protect against this potential scenario, sweep functions should ensure that the balance of the non-sweepable token does not change after the transfer of the swept tokens.

*Instances (9)*:
```solidity
File: DegenerusStonk.sol

238:     error SweepNotReady();

241:     error NothingToSweep();

244:     event YearSweep(uint256 ethToGnrus, uint256 stethToGnrus, uint256 ethToVault, uint256 stethToVault);

249:     function yearSweep() external {

251:         if (!gameContract.gameOver()) revert SweepNotReady();

253:         if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

256:         if (remaining == 0) revert NothingToSweep();

283:         emit YearSweep(ethToGnrus, stethToGnrus, ethToVault, stethToVault);

```

```solidity
File: GNRUS.sol

284:             amount = burnerBal; // sweep

```

### <a name="L-18"></a>[L-18] Consider using OpenZeppelin's SafeCast library to prevent unexpected overflows when downcasting
Downcasting from `uint256`/`int256` in Solidity does not revert on overflow. This can result in undesired exploitation or bugs, since developers usually assume that overflows raise errors. [OpenZeppelin's SafeCast library](https://docs.openzeppelin.com/contracts/3.x/api/utils#SafeCast) restores this intuition by reverting the transaction when such an operation overflows. Using this library eliminates an entire class of bugs, so it's recommended to use it always. Some exceptions are acceptable like with the classic `uint256(uint160(address(variable)))`

*Instances (50)*:
```solidity
File: BurnieCoin.sol

445:         return uint128(value);

1043:         adjustedBucket = uint8(bucket);

```

```solidity
File: BurnieCoinflip.sol

388:             state.claimableStored = uint128(stored - toClaim);

593:             state.autoRebuyCarry = uint128(carry);

650:                 biggestFlipEver = uint128(recordAmount);

712:                 state.autoRebuyStop = uint128(takeProfit);

716:                     state.autoRebuyStop = uint128(takeProfit);

725:                     state.autoRebuyStop = uint128(takeProfit);

761:         state.autoRebuyStop = uint128(takeProfit);

797:             rewardPercent = uint16(

827:                 currentBounty_ -= uint128(slice);

835:                 bountyPaid = uint128(slice);

847:             currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT);

1088:         return uint96(wholeTokens);

1109:         return uint24(bracket);

```

```solidity
File: DegenerusAffiliate.sol

350:         return bytes32(uint256(uint160(addr)));

```

```solidity
File: DegenerusDeityPass.sol

134:         uint8 quadrant = uint8(tokenId / 8);

135:         uint8 symbolIdx = uint8(tokenId % 8);

300:         return string(abi.encodePacked(Strings.toString(i), ".", _pad6(uint32(f))));

```

```solidity
File: DegenerusGame.sol

400:                     pFuture + uint128(futureShare)

406:                     future + uint128(futureShare)

1751:             _setPrizePools(next, future + uint128(amount));

2438:         uint8 bundleType = uint8(

2618:         traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word

2846:             _setPrizePools(next, future + uint128(msg.value));

```

```solidity
File: DegenerusJackpots.sol

272:             uint8 pick = 2 + uint8(entropy & 1);

393:                     else if (round < 8) targetLvl = lvl + 1 + uint24(entropy % 3);

394:                     else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);

397:                         targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;

401:                     else targetLvl = lvl + 1 + uint24(entropy % 4);

546:         return uint96(wholeTokens);

```

```solidity
File: DegenerusQuests.sol

944:             req.mints = uint32(_questTargetValue(quest, slot, 0));

```

```solidity
File: DegenerusTraitUtils.sol

174:         uint8 traitA = traitFromWord(uint64(rand)); // Quadrant 0: bits 7-6 = 00

175:         uint8 traitB = traitFromWord(uint64(rand >> 64)) | 64; // Quadrant 1: bits 7-6 = 01

176:         uint8 traitC = traitFromWord(uint64(rand >> 128)) | 128; // Quadrant 2: bits 7-6 = 10

177:         uint8 traitD = traitFromWord(uint64(rand >> 192)) | 192; // Quadrant 3: bits 7-6 = 11

```

```solidity
File: GNRUS.sol

363:             levelSdgnrsSnapshot[level] = uint48(sdgnrs.totalSupply() / 1e18);

417:         uint48 weight = uint48(sdgnrs.balanceOf(voter) / 1e18);

```

```solidity
File: StakedDegenerusStonk.sol

758:         claim.ethValueOwed += uint96(ethValueOwed);

760:         claim.burnieOwed += uint96(burnieOwed);

765:             claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;

```

```solidity
File: libraries/JackpotBucketLib.sol

44:         uint8 offset = uint8(entropy & 3);

86:                     counts[i] = uint16(scaled);

156:                 capped[i] = uint16(scaled);

169:             uint8 trimOff = uint8((entropy >> 24) & 3);

187:             uint8 offset = uint8((entropy >> 24) & 3);

279:         w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63

280:         w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127

281:         w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191

282:         w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255

```

### <a name="L-19"></a>[L-19] Unsafe ERC20 operation(s)

*Instances (20)*:
```solidity
File: DegenerusAdmin.sol

665:             try linkToken.transfer(target, bal) returns (bool ok) {

```

```solidity
File: DegenerusGame.sol

1819:         if (!steth.transfer(recipient, amount)) revert E();

1959:             if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();

1963:         if (!steth.transfer(to, amount)) revert E();

```

```solidity
File: DegenerusStonk.sol

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

182:             if (!steth.transfer(msg.sender, stethOut)) revert TransferFailed();

268:             if (!steth.transfer(ContractAddresses.GNRUS, stethToGnrus)) revert TransferFailed();

271:             if (!steth.transfer(ContractAddresses.VAULT, stethToVault)) revert TransferFailed();

```

```solidity
File: DegenerusVault.sol

786:                 if (!coinToken.transfer(player, payBal)) revert TransferFailed();

793:                     if (!coinToken.transfer(player, claimed)) revert TransferFailed();

1040:         if (!steth.transfer(to, amount)) revert TransferFailed();

1048:         if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();

```

```solidity
File: GNRUS.sol

315:             if (!steth.transfer(burner, stethOut)) revert TransferFailed();

```

```solidity
File: StakedDegenerusStonk.sol

353:         if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

513:             if (!steth.transfer(beneficiary, stethOut)) revert TransferFailed();

792:             if (!steth.transfer(player, stethOut)) revert TransferFailed();

802:             if (!coin.transfer(player, payBal)) revert TransferFailed();

806:             if (!coin.transfer(player, remaining)) revert TransferFailed();

```

```solidity
File: WrappedWrappedXRP.sol

301:         if (!wXRP.transfer(msg.sender, amount)) {

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

```

### <a name="L-20"></a>[L-20] Upgradeable contract not initialized
Upgradeable contracts are initialized via an initializer function rather than by a constructor. Leaving such a contract uninitialized may lead to it being taken over by a malicious user

*Instances (1)*:
```solidity
File: DegenerusGame.sol

232:       |  Initialize storage wiring and set up initial approvals.             |

```


## Medium Issues


| |Issue|Instances|
|-|:-|:-:|
| [M-1](#M-1) | Contracts are vulnerable to fee-on-transfer accounting-related issues | 1 |
| [M-2](#M-2) | Centralization Risk for trusted owners | 7 |
| [M-3](#M-3) | Chainlink's `latestRoundData` might return stale or incorrect results | 1 |
| [M-4](#M-4) | Missing checks for whether the L2 Sequencer is active | 1 |
| [M-5](#M-5) | Return values of `transfer()`/`transferFrom()` not checked | 3 |
| [M-6](#M-6) | Unsafe use of `transfer()`/`transferFrom()` with `IERC20` | 3 |
### <a name="M-1"></a>[M-1] Contracts are vulnerable to fee-on-transfer accounting-related issues
Consistently check account balance before and after transfers for Fee-On-Transfer discrepancies. As arbitrary ERC20 tokens can be used, the amount here should be calculated every time to take into consideration a possible fee-on-transfer or deflation.
Also, it's a good practice for the future of the solution.

Use the balance before and after the transfer to calculate the received amount instead of assuming that it would be equal to the amount passed as a parameter. Or explicitly document that such tokens shouldn't be used and won't be supported

*Instances (1)*:
```solidity
File: WrappedWrappedXRP.sol

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

```

### <a name="M-2"></a>[M-2] Centralization Risk for trusted owners

#### Impact:
Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

*Instances (7)*:
```solidity
File: DegenerusAdmin.sol

357:     function setLinkEthPriceFeed(address feed) external onlyOwner {

374:     function swapGameEthForStEth() external payable onlyOwner {

379:     function stakeGameEthToStEth(uint256 amount) external onlyOwner {

383:     function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {

```

```solidity
File: DegenerusDeityPass.sol

89:     function transferOwnership(address newOwner) external onlyOwner {

97:     function setRenderer(address newRenderer) external onlyOwner {

111:     ) external onlyOwner {

```

### <a name="M-3"></a>[M-3] Chainlink's `latestRoundData` might return stale or incorrect results
- This is a common issue: https://github.com/code-423n4/2022-12-tigris-findings/issues/655, https://code4rena.com/reports/2022-10-inverse#m-17-chainlink-oracle-data-feed-is-not-sufficiently-validated-and-can-return-stale-price, https://app.sherlock.xyz/audits/contests/41#issue-m-12-chainlinks-latestrounddata--return-stale-or-incorrect-result and many more occurrences.

`latestRoundData()` is used to fetch the asset price from a Chainlink aggregator, but it's missing additional validations to ensure that the round is complete. If there is a problem with Chainlink starting a new round and finding consensus on the new value for the oracle (e.g. Chainlink nodes abandon the oracle, chain congestion, vulnerability/attacks on the Chainlink system) consumers of this contract may continue using outdated stale data / stale prices.

More bugs related to chainlink here: [Chainlink Oracle Security Considerations](https://medium.com/cyfrin/chainlink-oracle-defi-attacks-93b6cb6541bf#99af)

*Instances (1)*:
```solidity
File: DegenerusAdmin.sol

741:             uint80 roundId,
                 int256 answer,
                 ,
                 uint256 updatedAt,
                 uint80 answeredInRound

```

### <a name="M-4"></a>[M-4] Missing checks for whether the L2 Sequencer is active
Chainlink recommends that users using price oracles, check whether the Arbitrum Sequencer is [active](https://docs.chain.link/data-feeds/l2-sequencer-feeds#arbitrum). If the sequencer goes down, the Chainlink oracles will have stale prices from before the downtime, until a new L2 OCR transaction goes through. Users who submit their transactions via the [L1 Dealyed Inbox](https://developer.arbitrum.io/tx-lifecycle#1b--or-from-l1-via-the-delayed-inbox) will be able to take advantage of these stale prices. Use a [Chainlink oracle](https://blog.chain.link/how-to-use-chainlink-price-feeds-on-arbitrum/#almost_done!_meet_the_l2_sequencer_health_flag) to determine whether the sequencer is offline or not, and don't allow operations to take place while the sequencer is offline.

*Instances (1)*:
```solidity
File: DegenerusAdmin.sol

741:             uint80 roundId,
                 int256 answer,
                 ,
                 uint256 updatedAt,
                 uint80 answeredInRound

```

### <a name="M-5"></a>[M-5] Return values of `transfer()`/`transferFrom()` not checked
Not all `IERC20` implementations `revert()` when there's a failure in `transfer()`/`transferFrom()`. The function signature has a `boolean` return value and they indicate errors that way instead. By not checking the return value, operations that should have marked as failed, may potentially go through without actually making a payment

*Instances (3)*:
```solidity
File: DegenerusStonk.sol

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

```

```solidity
File: WrappedWrappedXRP.sol

301:         if (!wXRP.transfer(msg.sender, amount)) {

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

```

### <a name="M-6"></a>[M-6] Unsafe use of `transfer()`/`transferFrom()` with `IERC20`
Some tokens do not implement the ERC20 standard properly but are still accepted by most code that accepts ERC20 tokens.  For example Tether (USDT)'s `transfer()` and `transferFrom()` functions on L1 do not return booleans as the specification requires, and instead have no return value. When these sorts of tokens are cast to `IERC20`, their [function signatures](https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca) do not match and therefore the calls made, revert (see [this](https://gist.github.com/IllIllI000/2b00a32e8f0559e8f386ea4f1800abc5) link for a test case). Use OpenZeppelin's `SafeERC20`'s `safeTransfer()`/`safeTransferFrom()` instead

*Instances (3)*:
```solidity
File: DegenerusStonk.sol

179:             if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();

```

```solidity
File: WrappedWrappedXRP.sol

301:         if (!wXRP.transfer(msg.sender, amount)) {

318:         if (!wXRP.transferFrom(msg.sender, address(this), amount)) {

```


## High Issues


| |Issue|Instances|
|-|:-|:-:|
| [H-1](#H-1) | Incorrect comparison implementation | 8 |
| [H-2](#H-2) | Using `delegatecall` inside a loop | 1 |
### <a name="H-1"></a>[H-1] Incorrect comparison implementation

#### Impact:
Use `require` or `if` to compare values. Otherwise comparison will be ignored.

*Instances (8)*:
```solidity
File: DegenerusVault.sol

73: +========================================================================================================+

76: +========================================================================================================+

129: +========================================================================================================+*/

```

```solidity
File: Icons32Data.sol

7: +=======================================================================================================+

10: +=======================================================================================================+

46: +=======================================================================================================+

73: +=======================================================================================================+

81: +=======================================================================================================+

```

### <a name="H-2"></a>[H-2] Using `delegatecall` inside a loop

#### Impact:
When calling `delegatecall` the same `msg.value` amount will be accredited multiple times.

*Instances (1)*:
```solidity
File: DegenerusGame.sol

1756:         while (remaining != 0) {

```

