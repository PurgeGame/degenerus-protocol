// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {
    IVRFCoordinator,
    VRFRandomWordsRequest
} from "../interfaces/IVRFCoordinator.sol";

/// @dev Minimal stETH interface (ERC20 subset)
interface IStETH {
    /// @notice stETH balance of an account.
    /// @param account Address to query balance of.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Transfer stETH to a recipient.
    /// @param to Recipient address.
    /// @param amount Transfer amount in wei.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Admin interface for VRF shutdown during final sweep.
interface IDegenerusAdminShutdown {
    /// @notice Cancel the VRF subscription and sweep LINK to the vault (DegenerusAdmin,
    ///         game-over only).
    function shutdownVrf() external;
}

/// @dev GNRUS interface for gameover GNRUS cleanup.
interface IGNRUSGameOver {
    /// @notice Burn GNRUS's remaining unallocated balance at game over (GNRUS, one-shot).
    function burnAtGameOver() external;
    /// @notice Record the final-sweep timestamp on GNRUS, anchoring its post-sweep recovery gates.
    function onFinalSweep() external;
}

/// @dev FLIP interface for the gameover worthless-token tombstone flood.
interface IFlipTombstone {
    /// @notice Flood FLIP's vault mint allowance with the one-shot worthless-token
    ///         tombstone signal.
    function tombstoneAtGameOver() external;
}

/**
 * @title DegenerusGameGameOverModule
 * @notice Handles game over logic including jackpot distribution and final sweeps.
 * @dev Executed via delegatecall from DegenerusGame. Inherits storage layout.
 */
contract DegenerusGameGameOverModule is DegenerusGameStorage {
    /// @notice stETH token contract for liquid staking rewards
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Admin contract for VRF shutdown
    IDegenerusAdminShutdown private constant admin =
        IDegenerusAdminShutdown(ContractAddresses.ADMIN);

    /// @notice GNRUS contract for gameover cleanup
    IGNRUSGameOver private constant charityGameOver =
        IGNRUSGameOver(ContractAddresses.GNRUS);

    /// @notice FLIP coin contract for the gameover worthless-token tombstone flood
    IFlipTombstone private constant flip =
        IFlipTombstone(ContractAddresses.COIN);

    /// @notice Refund cap per deity pass for early game over (levels 0-9)
    uint256 private constant DEITY_PASS_EARLY_GAMEOVER_REFUND =
        20 ether;

    /// @dev VRF request parameters (mirror the advance module's daily/mid-day lanes).
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;

    /// @notice Emitted when the VRF coordinator is wired or rotated.
    /// @param previous Coordinator address before this update (zero on the initial wiring).
    /// @param current Coordinator address now in effect.
    event VrfCoordinatorUpdated(
        address indexed previous,
        address indexed current
    );

    /// @dev Deity-pass early-gameover refunds, as one aggregate. `totalRefunded` bounds
    ///      the refund credits exactly, without a separate refund event per holder.
    event DeityPassRefundsSettled(uint256 totalRefunded);

    /// @notice The terminal level's leading affiliate received its one-time ETH share.
    event TerminalAffiliatePaid(address indexed affiliate, uint24 indexed level, uint256 amount);

    /// @notice The deterministic (VRF-dead) ending fixed its payout: `pot` is shared by every
    ///         ticket of `level`. Uncreated entries (queued or in an undrained foil pack, whose
    ///         traits were never rolled) take pot * weight / total each, weight in QTY_SCALE
    ///         units. Created tickets share pot * created * QTY_SCALE / total, split equally
    ///         across the `traits` non-empty trait buckets and equally within each.
    event DeadVrfPayoutFixed(
        uint24 indexed level,
        uint256 pot,
        uint256 created,
        uint256 uncreated,
        uint256 traits
    );

    /// @notice A deterministic-ending claim credited `amount` to `player`'s claimable winnings.
    event DeadVrfClaimed(address indexed player, uint256 amount);

    // error E() — inherited from DegenerusGameStorage

    /// @dev Tally units per call: one registry position, one foil pack, or one foil day
    ///      stepped. Every unit is a single cold read at most, so a call stays near 7.5M gas.
    uint256 private constant DEAD_TALLY_UNITS = 3000;

    /// @dev claimDeadVrf reference kinds, in the top byte of each reference.
    uint256 private constant DEAD_REF_CREATED = 0;
    uint256 private constant DEAD_REF_QUEUED = 1;

    /// @notice Process game over by distributing remaining funds.
    /// @dev Called when the game-over trigger fires: the purchase deadline (365 days at level
    ///      0, 30 after), the 30-day no-seal deadman, or a VRF request unanswered for 14 days.
    ///      Sets terminal gameOver flag.
    ///
    ///      Distribution logic:
    ///      - If game ended early (levels 0-9): refund of the price paid (capped at 20 ETH) per deity pass,
    ///        FIFO by purchase order, budget-capped to available funds minus claimablePool
    ///      - Normal ending: 2% to the terminal level's top affiliate, 98% to its ticket cohort by
    ///        the terminal jackpot (all of it when no affiliate is ranked)
    ///      - Deterministic (VRF-dead) ending: no affiliate share and no draw; the remainder is
    ///        fixed as the pot every terminal-level ticket claims from (claimDeadVrf)
    ///      - Any uncredited remainder later swept by handleFinalSweep three-way to vault / sDGNRS / GNRUS
    ///
    ///      The normal ending reads rngWordByDay[day] and reverts if funds exist but the word
    ///      is not yet available. The deterministic ending reads no word.
    /// @param day Day index for RNG word lookup from rngWordByDay mapping.
    /// @custom:reverts Invariant When distributable funds exist but the RNG word is unavailable (defense-in-depth).
    /// @custom:reverts TransferFailed When an stETH or ETH transfer fails.
    function handleGameOverDrain(uint24 day) external {
        if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0) return; // Already processed

        bool dead = _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0;
        uint24 lvl = level;

        uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));

        // Compute available funds FIRST (before any side effects)
        // Deity pass refunds have not happened yet, so claimablePool is pre-refund.
        // sDGNRS redemption reservations are backed sDGNRS-side at submit (pullRedemptionReserve's
        // ETH leg moves the ETH out of the game; its custody leg pins sDGNRS's own holdings), so
        // they are never part of totalFunds here — subtracting pendingRedemptionEthValue would
        // double-count them.
        uint256 reserved = uint256(claimablePool);
        uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;

        // RNG gate: when distributable funds exist, require RNG word.
        // Defense-in-depth -- caller (_handleGameOverPath) already guarantees
        // rngWordByDay[day] != 0 before calling, so this revert should never fire.
        uint256 rngWord;
        if (preRefundAvailable != 0 && !dead) {
            rngWord = rngWordByDay[day];
            if (rngWord == 0) revert Invariant();
        }

        // === All side effects below this line (RNG confirmed or no funds to distribute) ===

        // The deterministic ending has no word to roll a pending sDGNRS gambling-burn pool
        // with, so it resolves at the roll's expected value, 100%. The pool's ETH is
        // segregated in sDGNRS, so this moves nothing out of the game's balance.
        if (dead) {
            uint24 pendingDay = dgnrs.pendingResolveDay();
            if (pendingDay != 0) dgnrs.resolveRedemptionPeriod(100, pendingDay);
        }

        // Deity pass refunds (levels 0-9): refund each owner what they paid, capped at the flat
        // DEITY_PASS_EARLY_GAMEOVER_REFUND so a boon-discounted deity (paid < 20 ETH) never refunds
        // more than it paid, then clamped to the remaining distributable budget (FIFO).
        if (lvl < 10) {
            uint256 ownerCount = deityPassOwners.length;
            uint256 budget = preRefundAvailable;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint256 refund = deityPassPricePaid[owner];
                if (refund != 0) {
                    if (refund > DEITY_PASS_EARLY_GAMEOVER_REFUND) {
                        refund = DEITY_PASS_EARLY_GAMEOVER_REFUND;
                    }
                    if (refund > budget) {
                        refund = budget;
                    }
                    if (refund != 0) {
                        _creditClaimable(owner, refund);
                        unchecked {
                            totalRefunded += refund;
                            budget -= refund;
                        }
                    }
                    if (budget == 0) break;
                }
                unchecked {
                    ++i;
                }
            }
            if (totalRefunded != 0) {
                claimablePool += uint128(totalRefunded); // Safe: totalRefunded bounded by preRefundAvailable which fits uint128
                // The per-owner credits above carry no domain event. One aggregate marker
                // names the refund total separately from the affiliate and ticket awards.
                emit DeityPassRefundsSettled(totalRefunded);
            }
        }

        // Latch terminal state
        gameOver = true;
        earlyBirdWhalePasses = 0;
        _goWrite(GO_TIME_SHIFT, GO_TIME_MASK, uint48(block.timestamp));

        // Burn unallocated tokens
        charityGameOver.burnAtGameOver();
        dgnrs.burnAtGameOver();
        // Flood FLIP's VAULT mint allowance as a one-shot worthless-token tombstone
        flip.tombstoneAtGameOver();

        _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
        // next|future share one slot; zero both in a single SSTORE (no read needed). currentPrizePool
        // is a separate slot, still zeroed below.
        _setPrizePools(0, 0);
        _setCurrentPrizePool(0);
        yieldAccumulator = 0;
        // Terminal state also clears the freeze: with the live pools drained, _unlockRng's
        // _unfreezePool must not resurrect the pending pool back into them, and no
        // post-gameOver box/Degenerette resolution may draw ETH from a phantom pending pool.
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
        // All three pools are drained to zero at game over. Emit the terminal snapshot here —
        // before the available==0 early return below — so every game-over path logs it once. The
        // daily snapshot in _unlockRng skips game-over (gameOver is set above) to avoid a duplicate.
        emit PrizePoolDailySnapshot(
            0,
            0,
            0,
            claimablePool,
            totalFunds, // ETH + stETH unchanged since line 82 (burns/tombstone move no ETH/stETH)
            0, // yieldAccumulator was just zeroed above
            day
        );

        // Recalculate available after refunds (claimablePool may have grown).
        // sDGNRS redemption reservations are backed sDGNRS-side at submit, so they are not part
        // of totalFunds here — only claimablePool is reserved.
        uint256 postRefundReserved = uint256(claimablePool);
        uint256 available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;

        if (available == 0) return;

        emit GameOverDrained(lvl, available, claimablePool);

        // remaining tracks unallocated funds.
        uint256 remaining = available;

        // The winner was latched with the terminal cohort level before the terminal word
        // existed (_handleGameOverPath); credit it here once.
        uint24 terminalLevel = _gameOverTicketLevel(lvl);

        // Deterministic ending: no affiliate share, no draw. Fix the pot and the total weight
        // it divides by (tallied by tallyDeadVrf before this ran); every terminal-level ticket
        // then claims its share through claimDeadVrf until the final sweep.
        if (dead) {
            uint256 created = deadCreated;
            uint256 uncreated = deadUncreated;
            deadPot = uint128(remaining);
            deadTotal = uint64(created * QTY_SCALE + uncreated);
            deadUncreatedLeft = uint64(uncreated);
            emit DeadVrfPayoutFixed(terminalLevel, remaining, created, uncreated, deadTraitCount);
            return;
        }
        address top = terminalAffiliate;
        uint256 affiliateShare = remaining / 50;
        if (top != address(0) && affiliateShare != 0) {
            _creditClaimable(top, affiliateShare);
            claimablePool += uint128(affiliateShare);
            remaining -= affiliateShare;
            emit TerminalAffiliatePaid(top, terminalLevel, affiliateShare);
        }

        // All remaining ETH goes to the final ticket cohort (Final-day distribution).
        // gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game).
        // Pay from the SAME phase-correct level the AdvanceModule terminal drain materialized:
        // current `lvl` in jackpot phase and in the locked last-purchase transition (where level was
        // already promoted), otherwise purchase-phase `lvl + 1`. Any leftover from empty trait
        // buckets stays in the contract until handleFinalSweep (30 days later) folds it into the
        // three-way split to vault / sDGNRS / GNRUS.
        IDegenerusGame(address(this)).runTerminalJackpot(remaining, terminalLevel, rngWord);
    }

    /// @notice Final sweep of all remaining funds after 30 days post-gameover.
    /// @dev Pays each sink (vault, sDGNRS, GNRUS) its whole game-side balance still
    ///      owed to it — claimable plus prepaid afking — then splits the remainder ~1/3
    ///      each (GNRUS absorbs the rounding wei). All other unclaimed player balances
    ///      are forfeited.
    ///      After GO_SWEPT=1, claimWinnings() reverts, so this is the last
    ///      chance for the three sinks to receive what they earned in-game.
    ///      Also shuts down the VRF subscription and sweeps LINK to vault.
    /// @custom:reverts TransferFailed When ETH or stETH transfer fails
    function handleFinalSweep() external {
        uint256 goTime = _goRead(GO_TIME_SHIFT, GO_TIME_MASK);
        if (goTime == 0) return; // Game not over yet
        if (block.timestamp < goTime + 30 days) return; // Too early
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return; // Already swept

        _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);
        charityGameOver.onFinalSweep(); // stamp GNRUS with the sweep time (anchors its recovery gates)

        uint256 owedV  = _takeSinkBalance(ContractAddresses.VAULT);
        uint256 owedSD = _takeSinkBalance(ContractAddresses.SDGNRS);
        uint256 owedG  = _takeSinkBalance(ContractAddresses.GNRUS);
        claimablePool = 0;

        // Shutdown VRF subscription (fire-and-forget; failure must not block sweep)
        try admin.shutdownVrf() {} catch {}

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        emit FinalSwept(totalFunds);

        if (totalFunds == 0) return;

        // Protocol balances are fully backed: totalFunds >= owedV + owedSD + owedG.
        // A shortfall reverts the sweep.
        uint256 remainder  = totalFunds - (owedV + owedSD + owedG);
        uint256 thirdShare = remainder / 3;
        uint256 gnrusExtra = remainder - thirdShare - thirdShare;

        stBal = _sendStethFirst(ContractAddresses.VAULT,  owedV  + thirdShare, stBal);
        stBal = _sendStethFirst(ContractAddresses.SDGNRS, owedSD + thirdShare, stBal);
        _sendStethFirst(ContractAddresses.GNRUS,          owedG  + gnrusExtra, stBal);
    }

    /// @dev Zero a sink's packed balance — claimable (low half) and prepaid afking (high half),
    ///      both inside claimablePool — and return the total the final sweep owes it.
    function _takeSinkBalance(address sink) private returns (uint256 owed) {
        uint256 claimable = _claimableOf(sink);
        uint256 afking = _afkingOf(sink);
        _debitClaimableAndAfking(sink, claimable, afking);
        if (claimable != 0) emit ClaimableSpent(sink, claimable, 0, MintPaymentKind.Internal, claimable);
        if (afking != 0) emit AfkingSpent(sink, afking);
        owed = claimable + afking;
    }

    /*+========================================================================================+
      |                    DETERMINISTIC (VRF-DEAD) ENDING                                     |
      +========================================================================================+
      |  When a VRF request goes unanswered for 14 days the game ends with no entropy at all.  |
      |  Every ticket of the terminal level shares the pot: an uncreated one (queued, or in an |
      |  undrained foil pack, its traits never rolled) takes the average; the created ones     |
      |  share the rest equally per non-empty trait bucket, then equally within each bucket.   |
      +========================================================================================+*/

    /// @notice Count the terminal level's tickets for the deterministic ending.
    /// @dev Advance-only delegate target (_handleGameOverPath, after the dead ending latched).
    ///      No ticket or foil drain runs once it is latched and every entry point that could
    ///      add a ticket is closed by the liveness trigger, so what is counted here stays
    ///      put. Resumable, DEAD_TALLY_UNITS per call — a pure function of state, never of
    ///      the gas supplied. Three stages:
    ///        0 — uncreated queued entries: the owed balance on every registry position of
    ///            `lvl`, snap-adjusted as the ticket drain would have applied it, in QTY_SCALE
    ///            units (a fractional remainder counts as its fraction of an entry);
    ///        1 — undrained foil packs of `lvl`, FOIL_PACK_ENTRIES entries each;
    ///        2 — created tickets: every trait bucket's occurrence count, and how many of the
    ///            256 buckets are non-empty.
    /// @param lvl The latched terminal ticket level.
    /// @return finished True once all three stages are done.
    function tallyDeadVrf(uint24 lvl) external returns (bool finished) {
        uint256 stage = deadTallyStage;
        if (stage == 3) return true;
        uint256 units = DEAD_TALLY_UNITS;
        uint256 uncreated = deadUncreated;
        uint24 dd = deadTallyFoilDay;
        uint256 idx = deadTallyFoilIdx;

        if (stage == 0) {
            EntryOwner[] storage owners = lvlEntryOwner[lvl];
            uint256 len = owners.length;
            // The registry is immutable during this tally. Reuse its data base for
            // the bounded walk instead of hashing the same array slot per owner.
            uint256 records;
            assembly ("memory-safe") {
                mstore(0, owners.slot)
                records := keccak256(0, 32)
            }
            uint256 pos = deadTallyPos;
            uint8 shift = _snapShiftFor(lvl);
            while (pos < len) {
                if (units == 0) {
                    deadTallyPos = uint32(pos);
                    deadUncreated = uint64(uncreated);
                    return false;
                }
                unchecked {
                    --units;
                    ++pos;
                }
                // pos was below len before the increment; this reads that owner's
                // single-slot record, whose owed field starts at bit 160.
                uint80 packed;
                assembly ("memory-safe") { packed := shr(160, sload(add(records, sub(pos, 1)))) }
                uncreated += _deadWeight(packed, shift);
            }
            deadTallyPos = uint32(pos);
            stage = 1;
            // The foil walk starts at the drain's own low-water mark.
            dd = foilDrainDay;
            idx = foilCursor;
        }

        if (stage == 1) {
            uint24 last = foilLastResolveDay;
            while (dd != 0 && dd <= last) {
                uint256[] storage bucket = foilBuyers[dd];
                uint256 n = bucket.length;
                if (idx < n) {
                    uint256 packs;
                    assembly ("memory-safe") {
                        mstore(0, bucket.slot)
                        packs := keccak256(0, 32)
                    }
                    do {
                        if (units == 0) {
                            _saveDeadTally(1, dd, idx, uncreated);
                            return false;
                        }
                        unchecked {
                            --units;
                        }
                        // idx < n proves this cached-base read is within the day's bucket.
                        uint256 pack;
                        assembly ("memory-safe") { pack := sload(add(packs, idx)) }
                        if (uint24(pack >> 160) == lvl) {
                            uncreated += FOIL_PACK_ENTRIES * QTY_SCALE;
                        }
                        unchecked {
                            ++idx;
                        }
                    } while (idx < n);
                }
                // Charge the day step too, so a long run of empty days stays metered.
                if (units == 0) {
                    _saveDeadTally(1, dd, idx, uncreated);
                    return false;
                }
                unchecked {
                    --units;
                    ++dd;
                }
                idx = 0;
            }
            stage = 2;
        }

        // Stage 2: the 256 bucket lengths, in one call once enough units remain.
        if (units < 256) {
            _saveDeadTally(2, dd, idx, uncreated);
            return false;
        }
        uint256 created;
        uint256 traits;
        for (uint256 t; t < 256; ) {
            uint256 n = lvlTraitEntry[lvl][t].length;
            if (n != 0) {
                created += n;
                unchecked {
                    ++traits;
                }
            }
            unchecked {
                ++t;
            }
        }
        deadCreated = uint64(created);
        deadTraitCount = uint16(traits);
        _saveDeadTally(3, dd, idx, uncreated);
        return true;
    }

    /// @dev Persist a paused (or finished) tally.
    function _saveDeadTally(uint256 stage, uint24 dd, uint256 idx, uint256 uncreated) private {
        deadTallyStage = uint8(stage);
        deadTallyFoilDay = dd;
        deadTallyFoilIdx = uint32(idx);
        deadUncreated = uint64(uncreated);
    }

    /// @dev An owed word's uncreated weight in QTY_SCALE units, snap-adjusted exactly as the
    ///      ticket drain applies it on first touch (_processOneTicketEntry).
    function _deadWeight(uint80 packed, uint8 shift) private pure returns (uint256) {
        uint256 weight = uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
        // Only the scaled weight is needed here. The drain's snap helper repacks the
        // quotient and remainder for storage; unpacking those again gives weight >> shift.
        if (shift != 0 && packed & SNAP_DONE_BIT == 0) return weight >> shift;
        return weight;
    }

    /// @notice Claim deterministic-ending shares for `player`'s terminal-level tickets.
    /// @dev Delegatecall target of DegenerusGame.claimDeadVrf. Permissionless: every share
    ///      credits the holding's owner, never the caller. Open from the dead ending's payout
    ///      until the final sweep. Each reference names one holding; the top byte is its kind:
    ///        DEAD_REF_CREATED (0) — a created ticket: trait at bits 64..71, occurrence index
    ///          at bits 0..63 of lvlTraitEntry[level][trait]. Pays the trait's equal share of
    ///          the created pot, divided equally among that trait's tickets.
    ///        DEAD_REF_QUEUED (1) — uncreated queued entries: registry position plus one at
    ///          bits 0..31. Pays pot * weight / total for the position's whole owed balance.
    ///        any other kind — an undrained foil pack: resolve day at bits 64..87, index into
    ///          foilBuyers[day] at bits 0..63. Pays pot * FOIL_PACK_ENTRIES * QTY_SCALE / total.
    ///      Each holding pays once: a created ticket sets its claimed bit, a queued position
    ///      has its owed balance zeroed, a foil pack has its bucket word zeroed. Uncreated
    ///      weight claimed is debited from the tallied total, so claims can never exceed it.
    ///      Rounding dust stays in the contract for the final sweep.
    /// @param player Owner of every referenced holding.
    /// @param refs The holdings to claim.
    /// @custom:reverts E When no deterministic payout is open, or a reference is invalid,
    ///      not `player`'s, or already claimed.
    function claimDeadVrf(address player, uint256[] calldata refs) external {
        uint256 total = deadTotal;
        if (total == 0 || _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        uint256 pot = deadPot;
        uint24 lvl = _gameOverTicketLevel(level);
        uint256 traits = deadTraitCount;
        uint256 perTrait = traits == 0 ? 0 : (pot * uint256(deadCreated) * QTY_SCALE) / total / traits;
        uint8 shift = _snapShiftFor(lvl);
        uint256 amount;
        uint256 weight;
        for (uint256 i; i < refs.length; ) {
            uint256 ref = refs[i];
            uint256 kind = ref >> 248;
            if (kind == DEAD_REF_CREATED) {
                uint8 trait = uint8(ref >> 64);
                uint256 k = uint64(ref);
                uint256 n = lvlTraitEntry[lvl][trait].length;
                if (k >= n || _bucketOwnerAt(lvl, trait, k) != player) revert E();
                uint256 key = (uint256(trait) << 64) | (k >> 8);
                uint256 bits = deadClaimed[key];
                uint256 bit = uint256(1) << (k & 255);
                if (bits & bit != 0) revert E();
                deadClaimed[key] = bits | bit;
                amount += perTrait / n;
            } else if (kind == DEAD_REF_QUEUED) {
                uint32 pos = uint32(ref);
                uint256 record = _entryRecord(lvl, pos);
                if (address(uint160(record)) != player) revert E();
                uint256 w = _deadWeight(uint80(record >> 160), shift);
                if (w == 0) revert E();
                _setEntryOwed(lvl, pos, 0);
                weight += w;
                amount += (pot * w) / total;
            } else {
                uint24 day = uint24(ref >> 64);
                uint256 idx = uint64(ref);
                uint24 low = foilDrainDay;
                if (day < low || day > foilLastResolveDay || (day == low && idx < foilCursor)) revert E();
                uint256[] storage bucket = foilBuyers[day];
                if (idx >= bucket.length) revert E();
                uint256 pack = bucket[idx];
                if (address(uint160(pack)) != player || uint24(pack >> 160) != lvl) revert E();
                bucket[idx] = 0;
                uint256 w = FOIL_PACK_ENTRIES * QTY_SCALE;
                weight += w;
                amount += (pot * w) / total;
            }
            unchecked {
                ++i;
            }
        }
        uint256 left = deadUncreatedLeft;
        if (weight > left) revert E();
        deadUncreatedLeft = uint64(left - weight);
        if (amount != 0) {
            _creditClaimable(player, amount);
            claimablePool += uint128(amount);
            emit DeadVrfClaimed(player, amount);
        }
    }

    /// @dev Send stETH first to a recipient, then ETH for the remainder. Returns updated stETH balance.
    ///      IMPORTANT: Hard-reverts on stETH/ETH transfer failure. handleFinalSweep latches
    ///      GO_SWEPT before transferring, so a stuck stETH transfer reverts the whole sweep
    ///      (GO_SWEPT rolls back), blocking the final sweep until the transfer succeeds.
    /// @param to Recipient address.
    /// @param amount Total amount to send (stETH preferred, ETH as fallback).
    /// @param stethBal Remaining stETH balance available for transfers.
    /// @return Updated stETH balance after transfer.
    function _sendStethFirst(address to, uint256 amount, uint256 stethBal) private returns (uint256) {
        if (amount == 0) return stethBal;
        if (amount <= stethBal) {
            if (!steth.transfer(to, amount)) revert TransferFailed();
            return stethBal - amount;
        }
        if (stethBal != 0) {
            if (!steth.transfer(to, stethBal)) revert TransferFailed();
        }
        uint256 ethAmount = amount - stethBal;
        if (ethAmount != 0) {
            (bool ok, ) = payable(to).call{value: ethAmount}("");
            if (!ok) revert TransferFailed();
        }
        return 0;
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  Deploy-only VRF setup called from the ContractAddresses.ADMIN constructor, and the    |
      |  governance-gated emergency coordinator rotation. Cold administrative paths hosted     |
      |  here for the advance module's EIP-170 headroom; both operate on the shared VRF        |
      |  storage the daily request path reads.                                                 |
      +========================================================================================+*/

    /// @notice Wire VRF config, called once from the ADMIN constructor during deployment.
    /// @dev Access: ContractAddresses.ADMIN only. No post-deploy caller exists on ADMIN;
    ///      emergency VRF rotation uses updateVrfCoordinatorAndSub instead.
    /// @param coordinator_ Chainlink VRF V2.5 coordinator address.
    /// @param subId VRF subscription ID for LINK billing.
    /// @param keyHash_ VRF key hash for gas lane selection.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();

        address current = address(vrfCoordinator);
        _setVrfConfig(coordinator_, subId, keyHash_);
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit VrfCoordinatorUpdated(current, coordinator_);
    }

    /// @notice Emergency VRF coordinator rotation (governance-gated).
    /// @dev Access: ContractAddresses.ADMIN only. The Admin contract enforces
    ///      stall duration via sDGNRS-holder governance (propose/vote/execute).
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the gas lane.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();

        address current = address(vrfCoordinator);
        _setVrfConfig(newCoordinator, newSubId, newKeyHash);

        // Once the game has ended, or the deterministic ending has latched, no word can count
        // for anything: repoint the config only, never re-issue.
        if (gameOver || _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0) {
            emit VrfCoordinatorUpdated(current, newCoordinator);
            return;
        }

        // Detect what is in flight and re-issue on the new coordinator. A re-issue is the same
        // request sent again: rngRequestTime is left as it was, so the request keeps the day it
        // was first issued for and the VRF-dead window keeps running from the original send.
        // The request is accepted before the new subscription is LINK-funded; DegenerusAdmin
        // funds it in the same _executeSwap transaction (transferAndCall), and the VRF node
        // fulfills once funded. If the new coordinator also stalls, the vault owner's one retry is
        // the remaining recourse, and a request unanswered _VRF_DEAD_TIMEOUT from its original
        // send reaches the VRF-dead ending.
        if (!rngLockedFlag) {
            // Mid-day request in flight, lootbox-only or with a swapped ticket cohort alike:
            // LR_INDEX is preserved, so the new word lands in the same reserved slot via the
            // mid-day fulfillment branch. `vrfRequestId != 0` is what marks it outstanding: the
            // mid-day fulfillment clears it, whereas LR_MID_DAY stays set after the word lands
            // until the ticket batch drains, and _gameOverEntropy's failed-request stamp sets
            // rngRequestTime with no request in flight — re-issuing then would send a spurious
            // request whose fulfillment overwrites an already-delivered write-once lootbox word.
            // A mid-day request re-fired by the vault owner's retry holds the daily lock and takes
            // the daily branch below.
            // Nothing in flight: config repoint only.
            if (vrfRequestId != 0) vrfRequestId = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);
        } else {
            // Daily in flight: KEEP rngLockedFlag=true.
            if (rngWordCurrent == 0) {
                // Daily word not yet delivered: re-request on the new coordinator. The swap spends
                // the vault owner's single retry (the low bit; the stamp itself does not move): the
                // retry is the last resort before a swap, and re-armed here it could discard the
                // new coordinator's first answer. A replacement that stalls too is recovered by
                // another swap or reaches the VRF-dead ending.
                vrfRequestId = _requestVrfWord(VRF_REQUEST_CONFIRMATIONS);
                rngRequestTime |= 1;
            }
            // else: daily word already delivered and valid -> preserve it; no re-issue
            // (a fresh callback would be rejected by the advance module's
            // rngWordCurrent != 0 fulfillment guard).
        }

        // Intentional: totalFlipReversals is NOT reset here. Nudges were purchased
        // with irreversible FLIP burns before or during the stall. They carry over
        // and apply to the first post-swap VRF word via _applyDailyRng. Resetting
        // would steal user value (burned FLIP for zero effect).

        emit VrfCoordinatorUpdated(current, newCoordinator);
    }

    /// @dev Write the VRF coordinator, subscription, and key hash together.
    /// @param coord VRF coordinator address.
    /// @param sub VRF subscription ID for LINK billing.
    /// @param key VRF key hash for gas lane selection.
    function _setVrfConfig(address coord, uint256 sub, bytes32 key) private {
        vrfCoordinator = IVRFCoordinator(coord);
        vrfSubscriptionId = sub;
        vrfKeyHash = key;
    }

    /// @dev Submit a single-word VRF request on the current coordinator.
    /// @param confirmations Block confirmations for this request's gas lane.
    /// @return id The Chainlink request ID.
    function _requestVrfWord(uint16 confirmations) private returns (uint256 id) {
        id = vrfCoordinator.requestRandomWords(
            VRFRandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: confirmations,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: hex""
            })
        );
    }
}
