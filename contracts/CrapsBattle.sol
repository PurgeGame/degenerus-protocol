// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "./libraries/MineFlipGas.sol";
import {BitPackingLib} from "./libraries/BitPackingLib.sol";
import {Craps} from "./Craps.sol";
import {CrapsPriceLib} from "./libraries/CrapsPriceLib.sol";
import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {CrapsCustomTerms} from "./CrapsCustomTerms.sol";
import {LootboxCraps} from "./LootboxCraps.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

/// @dev The dice engine, a pure function at its own pinned address: the table hands it a slip's
///      packed chips and every term of the run, and reads the run back. Reached by STATICCALL —
///      the engine holds no storage and can change nothing.
interface ICrapsEngine {
    function settleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll,
        uint256 goal, uint48 bound, uint256 field, uint256 word) external pure returns (Craps.SlipResult memory);

    function customDefinition(uint32 played, uint8 bankMult, uint16 goalMult, uint24 stakeUnits, uint40 closeTime, bool multiEntry, uint16 highRollerMult) external view returns (uint256);

    /// @notice CrapsEngine's pure play of one slip to its stop, the merit composite in the
    ///         fifth word (see `CrapsEngine.settleRanked`).
    function settleRanked(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 salt,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory);
}

/// @dev The one FLIP sink this game uses, authorized to `ContractAddresses.CRAPS` in the
///      protocol's FLIP.sol. Craps only ever BURNS: a stake goes in and nothing here hands liquid
///      FLIP back, because nothing here is ever given back. Every payment — a run's winnings, a
///      pot, a lane — ships as coinflip credit.
interface IFlipCoin {
    /// @notice FLIP.sol's burn of `amount` from `target`'s FLIP balance, consuming settled
    ///         coinflip winnings only for the shortfall.
    function burnCoin(address target, uint256 amount) external;
    /// @dev The paid-craps twin. Takes the price with action flags in its low byte and hands back
    ///      the one-hot craps-boon tier consumed by this burn (0 on every burn that consumed none).
    ///      The FLIP burn stays on `target`'s address, which is the account's PAYEE (the caller
    ///      for a self door, a smurf's owner, or an ordinary account's own key); `id` is the
    ///      account's nonzero wallet ID, obtained by the table before the bet body, which keys
    ///      the craps boon lane and the craps quest. A comp burn ignores `id`.
    function burnCoinForCraps(address target, uint32 id, uint256 grossAndFlags) external returns (uint8 boonMask);
    /// @dev Feed the craps comp lane: two percent of a completed field's eligible bankroll.
    function creditCrapsComps(uint256 amount) external;
}

/// @dev The vault's ownership test — a majority DGVE holder. The only authority this contract
///      recognises: it opens a custom battle and grants or revokes battle creators
///      (`setBattleCreator`). The vault saves its board through the ordinary player surface.
interface IVaultOwnership {
    /// @notice DegenerusVault's majority-DGVE-holder check for `account`.
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev Mint-history entry pricing, account resolution and the daily RNG lock.
interface IGameCraps {
    /// @notice Raw mint history: lifetime count, last mint level and deity ownership. Read for
    ///         the ACCOUNT key (newcomer pricing follows the account, a smurf's hash key included).
    function mintPackedFor(address player) external view returns (uint256);
    /// @notice Resolve account `id` for `caller`: key, payee and whether `caller` may act for it
    ///         (its key, a smurf's owner, or an approved operator). Reverts for an unallocated
    ///         or zero `id`; never reverts on authorization. Player doors require `authorized`;
    ///         `vaultComp` uses only the key.
    function resolveAccount(uint32 id, address caller)
        external view returns (address key, address payee, bool authorized);
    function level() external view returns (uint24);
    /// @notice Daily request through final day seal, including a fulfilled, pending jackpot battle.
    function rngLocked() external view returns (bool);
}

interface IHighRollerReserve {
    function settleHighRollerReserve(uint64 slot) external;
}

/// @dev Run winnings and competitive battle pots pay as next-day coinflip stake. The batch lane
///      lets a slot settle many entrants with one external call.
interface ICoinflipStake {
    /// @notice Coinflip's credit of `amount` FLIP stake to wallet `id` (0 is a no-op).
    function creditFlip(uint32 id, uint256 amount) external;
    /// @notice Coinflip's batched credit of `amounts` FLIP stake to wallets `ids` (zero IDs and
    ///         zero amounts are skipped).
    function creditFlipBatch(uint32[] calldata ids, uint256[] calldata amounts) external;
    /// @notice Arm THE BIGGEST DICE RUN — the fifth category of the shared BIGGEST record.
    /// @dev CRAPS only, and this kind only: the generic `armRecord` door is the GAME's and
    ///      carries the four existing kinds' 20%-improvement claim rule, which is not this one's.
    ///      Coinflip credits the claim itself, so a finalization makes ONE call and the player
    ///      takes ONE credit.
    ///      The claim is credited by wallet ID; the sDGNRS leg and the trophy go to the payee
    ///      Game's `payRecordSdgnrs` returns. Bets hold nonzero IDs, so the table never passes 0.
    /// @param id The run owner's wallet ID, credited with the claim.
    /// @param candidate The winner's high point over its starting bankroll, in basis points.
    /// @dev DECLARED WITHOUT ITS RETURN, deliberately. `Coinflip` returns the FLIP it claimed and
    ///      logs it in `BigRecordUpdated`; nothing on this side of the call needs the figure, so
    ///      the table does not pay to decode one. The selector is the same either way.
    function armDiceRunRecord(uint32 id, uint256 candidate) external;
}

/// @title CrapsBattle
/// @notice Slot-based FLIP craps battles. A slot fixes one bankroll, goal, ten-chip round,
///         battle stake for every entrant. A player places zero through seven
///         chips and leaves the rest of the ten to the draw.
///
/// @dev Entry burns the bankroll plus any battle stake. Closing a slot binds it to
///      `_writeBuffer()`, the table whose word cannot exist yet, and asks for that word. `_resolveSlotRange`
///      walks the slot's dense, 1-based seats and credits each run's rounded return as coinflip
///      stake. A non-zero battle stake also records a single running leader, and the seat that
///      completes the field hands that leader the pot in the same call — there is no claim.
///
///      Bet ids encode membership as `(slot << 64) | seat`. The stored bet word therefore needs
///      only the owner, selected chip counts and game flags. A per-slot cursor carries
///      the settled high-water mark without one write per bet. Until its slot closes, an
///      owner may name or re-spread those chip counts with `amendSlip`, a blank ticket included —
///      the terms and the seat are the slot's, so nothing an amendment touches can move value or
///      change the field.
///
///      Bonus slots are derived from the protocol day and opened from a committed daily word.
///      Custom slots are opened by approved creators with explicit terms and a future close time.
///      In both cases entrants know the terms but not the settlement word before entry closes.
///
///      This contract depends on the pinned FLIP, Coinflip, Vault and Game addresses. FLIP and
///      Coinflip must in turn authorize `ContractAddresses.CRAPS` for burns and credits.
interface IReadCohortLifecycle {
    function admitCustom(uint64 slot) external;
    function registerRngSlot(uint48 index, uint64 slot, bytes32 key) external;
    function resolveRngSlot(uint64 slot, uint256 allowance) external returns (MineFlipGas.Result memory);
    function finalizeBattle(CrapsBattleStorage.Window calldata w, uint256 board, uint256 word) external;
    function payBattlePot(uint64 slot, bytes32 key, uint256 winnerId, uint256 pot, uint256 boost, uint256 word) external;
}

contract CrapsBattle is CrapsBattleStorage {
    /// @dev Pinned cold lifecycle module; both contracts inherit the same append-only layout.
    fallback() external { _delegateJackpot(); }

    function _delegateJackpot() private {
        address target = ContractAddresses.JACKPOT_BATTLE;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }

    function resolveRngSlot(uint64 slot, uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != address(this)) revert OnlyGame();
        return _resolveSlotRange(slot, allowance, _RESOLVE_MAX_SEATS);
    }

    function runDailyBattleWork(uint256) external returns (MineFlipGas.Result memory) { _delegateJackpot(); }

    function _isJackpotSlot(uint256 slot) internal pure returns (bool) {
        return slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY >= _BONUS_PERIODS_PER_DAY;
    }

    function _slotWord(uint256 slot) internal view returns (uint256) {
        if (_isJackpotSlot(slot)) return _jackpotRounds[slot].word;
        uint48 index = _slotIndexOf(slot);
        // The subtraction is evaluated only for a nonzero stored index.
        unchecked { return index == 0 ? 0 : _wordAt(index - 1); }
    }

    /// @dev Paid own seats, paid day tickets, then awarded own seats. The cursor uses this dense order.
    function _seatId(uint256 slot, uint64 seat, uint64 ownN, uint256 dayBase, uint64 dayN)
        private pure returns (uint256)
    {
        // Both counts come from uint32 fields. The sum fits uint64, and each
        // subtraction is guarded by the preceding ordinal comparisons.
        unchecked {
            if (seat <= ownN) return (slot << 64) | seat;
            if (seat <= ownN + dayN) return dayBase | (seat - ownN);
            return (slot << 64) | (seat - dayN);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Deployment
    // ---------------------------------------------------------------------------------------

    /// @dev Register this contract's ENS reverse name (best-effort; skipped when the registrar is
    ///      unset — local/test/testnet builds). The `setName(string)` selector is shared by the L1
    ///      ReverseRegistrar and Base's L2ReverseRegistrar. Constructor code is init code, so this
    ///      costs nothing against the deployed contract's EIP-170 ceiling.
    constructor() {
        // THE DEPLOYMENT DAY IS A WARM-UP DAY WITH NO WINDOWS. Genesis is marked consumed and the
        // scheduled cursor born pointing at TOMORROW'S separator, so the first Craps windows open
        // on genesis + 1 and nothing can ever fall behind initialization: a pass awarded on
        // genesis reserves genesis + 1 normally, and the cursor is already standing there.
        // Derived from the clock rather than hard-coded, so deployment timing cannot move the
        // rule — and written from INIT code, which costs the runtime nothing.
        uint24 genesis = _currentDayIndex();
        unchecked {
            _bonus = uint256(genesis) + 1;
            _keeperSlot = uint64(_daySlotOf(uint256(genesis) + 1));
        }

        // TWENTY SEED DAYS EACH, banked to the two protocol bodies. The day lane seats both of
        // them every day and spends a banked pass before it burns anything, so this is twenty days
        // of protocol seats bought at deployment rather than out of the reserve — which is what
        // the opening days need, because the lootboxes that normally feed these two lanes have not
        // paid a pass yet. Banked rather than reserved: credit never expires, so it is spent one
        // day at a time by whichever days actually open. Written from INIT code, so the runtime
        // carries none of it.
        _credit(_SDGNRS_ID, false, _SEED_PASSES);
        _credit(_VAULT_ID, false, _SEED_PASSES);

        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok,) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "craps.degenerus.eth")
            );
            ok;
        }
    }

    // ---------------------------------------------------------------------------------------
    // Placing
    // ---------------------------------------------------------------------------------------

    /// @dev The one placement there is: a seat at a slot, on terms the slot already fixed.
    ///      Nothing here is caller-chosen but the chips, so nothing has to be vetted against a
    ///      caller's arithmetic — the terms were proven once, for the whole field, when the slot
    ///      was made. The whole bet is ONE word.
    /// @dev A battle entry is BINARY: one copy of the run, or exactly the field's high-roller
    ///      multiple. Nothing between is legal, and that is what makes a variable daily multiple
    ///      safe to quote — a transaction submitted naming ten cannot be silently filled at a
    ///      hundred, because a hundred-day rejects ten outright rather than reinterpreting it.
    ///      Zero and one-as-a-high-multiple both fall to the same floor.
    function _vetMultiple(uint256 highMult, uint256 multiple) internal pure returns (bool) {
        if (multiple == 1) return false;
        if (multiple < 2 || multiple != highMult) revert BadEntryMultiple();
        return true;
    }

    function _place(Window memory w, uint256 chips, uint256 multiple, uint256 account, uint256 flags)
        private
        returns (uint256 betId)
    {
        if (w.bound >= _CUSTOM_SLOT_BASE && _battles[w.key] == 0) {
            IReadCohortLifecycle(address(this)).admitCustom(w.bound);
        }
        uint8 boonMask;
        bool high = _vetMultiple(w.highMult, multiple);
        uint32 id = uint32(account >> _ACCOUNT_ID_SHIFT);
        // One seat per wallet unless the battle was opened saying otherwise. A bonus window
        // never says otherwise: house money there buys a field of distinct players, not a field of
        // one player's entries.
        if (!w.multiEntry) {
            if (w.bound < _CUSTOM_SLOT_BASE) {
                _claimScheduledSeat(w.bound, id);
            } else {
                if (_bonusSeated[w.key][id]) revert AlreadyInBonus();
                _bonusSeated[w.key][id] = true;
            }
        }
        unchecked {
            // A high roller buys the WHOLE seat over again — the bankroll it runs and the bounty
            // it posts — which is what makes the lane a race rather than a bigger bet in the same
            // one. Exactly one of those bounties stays in the main pot; the other `H - 1` are what
            // the high lane plays for. Bounded far below 2^256: a uint128 bankroll by at most 255
            // fits 136 bits.
            boonMask = _burnForCraps(
                account, _tag((uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple, _CRAPS_FLAG_JOIN | flags)
            );
            // The id IS the seat: this battle's slot, and this entrant's place in its field.
            betId = (uint256(w.bound) << 64) | _enterBattle(w.key, w.stakeUnits);
            // The sideboard is touched ONLY by a field that actually takes a high seat, so an
            // ordinary battle never pays for a lane it does not run.
            if (high) ++_highField[w.key];
        }
        // Settlement never writes this word. Before the slot closes, `amendSlip` may replace its
        // chip slice; the owner and the stakes flag remain fixed.
        _writeSlip(betId, id, chips, high ? _BET_HIGH_BIT : 0, multiple - 1, boonMask);
    }

    /// @dev The one assembler of a stored bet word and its `CrapsSlipPlaced` echo — the window
    ///      door and the day lane both land here, so storage and the log cannot drift apart.
    function _writeSlip(
        uint256 betId,
        uint32 id,
        uint256 chips,
        uint256 highBits,
        uint256 evMult,
        uint256 boonMask
    ) private {
        uint256 boon = boonMask << _BET_BOON_SHIFT;
        _storeBet(betId, uint256(id) | (chips << _BET_CHIPS_SHIFT)
            | boon | highBits);
        // The high flag rides in the echo too: `highBits` already sits at bit 217 (window seat) or
        // 217..223 (day ticket, one per period), above every other field of the event word. A
        // banked HIGH pass spent by `_seatBody` carries `evMult = 0`, so without this an indexer
        // reads the house's high day seat as an ordinary 1x ticket and can only learn otherwise
        // from storage.
        emit CrapsSlipPlaced(
            id,
            chips | (betId << _EV_BET_SHIFT) | (evMult << _EV_MULT_SHIFT) | boon | highBits
        );
    }

    /// @dev The terms of any slot, window or custom alike — the one place a settler or a preview
    ///      reads what a field is playing. Read ONCE for a whole field rather than copied into
    ///      every header, which is what makes a bet a single word.
    function _slotWindow(uint256 slot) internal view returns (Window memory w) {
        if (slot >= _CUSTOM_SLOT_BASE) {
            (w,) = _customTerms(slot);
        } else {
            unchecked {
                // `_slotOf(day, period)` is `day * _BONUS_SLOTS_PER_DAY + period + 1`, so the
                // remainder names the period and zero is the reserved gap between days.
                uint256 p = slot % _BONUS_SLOTS_PER_DAY;
                if (p == 0 || (p > _BONUS_PERIODS_PER_DAY && _jackpotRounds[slot].requestDay == 0)) revert NoSuchBattle();
                w = _windowTerms(uint24(slot / _BONUS_SLOTS_PER_DAY), p == 7 ? 5 : p - 1);
                if (p == 7) { w.bound = uint48(slot); w.key = bytes32(slot); }
                if (_isJackpotSlot(slot)) {
                    JackpotRound storage r = _jackpotRounds[slot];
                    if (r.word != 0) {
                        w.bankroll = r.bankroll;
                        w.goal = uint128(uint256(r.bankroll) * _SCHED_GOAL);
                        w.played = uint256(r.bankroll) / _SCHED_BANK_MULT;
                        w.postedStake = w.played / _BONUS_CHIPS * _MAX_PICKED_CHIPS;
                        w.stakeUnits = r.bountyUnits;
                        w.drawn = r.drawnCount;
                        w.extraUnits = r.drawnUnits - r.drawnCount;
                        w.extraPot = r.potRemainder;
                        // Each high seat's extra fee allocation is split equally between its
                        // bankroll rider and the high-only bounty. Added never enters either.
                        if (w.highMult > 1) {
                            w.highExtra = (w.highMult - 1) * r.entryPrice * r.multiplierBps / 20_000;
                        }
                    }
                }
                // The decode must round-trip: the day is read as a uint24, so a slot offset by a
                // multiple of 2^27 would name this same window while the clock and arm latch
                // are checked on the caller's number. Only the window's own slot is a slot.
                if (w.bound != slot) revert NoSuchBattle();
            }
        }
        w.entrants = uint32(_battles[w.key]);
    }

    /// @dev A ticket's ten leg counts, packed into the thirty-bit chip word, with their sum.
    ///      Each leg is a COUNT of chips, not an amount — the slot fixes what a chip is worth, so
    ///      an entrant chooses only where up to seven go. The sum is the board-wide ceiling; the
    ///      separate per-leg check keeps each count within the priced spread.
    ///
    ///      The one composition rule on top of that: PICK A SIDE. A ticket may not name both the
    ///      pass line and don't pass. Checked here rather than at each door, so every way in — a
    ///      window, a day ticket, a custom battle, an amendment — is held to it identically.
    ///      The DICE are not: a scatter chip may still land on the side a ticket did not pick,
    ///      which is the draw's doing and not a wager the player chose.
    function _packChips(uint32 c) internal pure returns (uint256 packed, uint256 count) {
        packed = c;
        // Bits 30-31 are outside the ten three-bit legs. Letting either through would overlap the
        // adjacent flags when `chips` is shifted into the stored bet word.
        if (packed > _BET_CHIPS_MASK) revert BadRandomCount();
        if (packed & 7 != 0 && (packed >> _CHIP_DONT_SHIFT) & _CHIP_DONT_MASK != 0) {
            revert BoardPlaysBothSides();
        }
        // Three is the ceiling, so bit 2 being set in any three-bit leg is the whole cap test.
        if ((packed >> 2) & _CHIP_LO_MASK != 0) revert TooManyChipsOnALeg();
        unchecked {
            // Pair the ten validated 0..3 counts into five base-64 digits.
            // Their total is at most 30, so reducing modulo 63 gives the exact sum.
            count = ((packed & 0x071C71C7) + ((packed >> 3) & 0x071C71C7)) % 63;
        }
    }

    /// @notice Save account `id`'s board (0 = the caller) for comped tickets and the jackpot
    ///         battle. Zero restores random.
    /// @dev The vault's automatic day seats also use its saved preference.
    /// @dev Input is the same canonical thirty-bit board paid entries accept. First save sets
    ///      a permanent sentinel, including for zero; identical initialized boards are no-ops.
    /// @custom:reverts BetLocked If initialization or a change would move a committed daily draw.
    /// @custom:reverts NoWalletId If the Game has no wallet ID for the caller.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function setPreferredBoard(uint32 id, uint32 chips) external {
        _upToSeven(chips);
        (address key,, uint256 word) = _door(id, false);
        if (!_rememberBoard(key, word, chips)) revert BetLocked();
    }

    /// @notice A wallet's saved board in the paid-entry encoding, by Game wallet ID; unset and
    ///         explicit random return zero.
    function preferredBoardOf(uint32 walletId) external view returns (uint32 chips) {
        (chips,) = CrapsPreferenceLib.decode(_passCreditsById[walletId]);
    }

    /// @dev Every player door's prologue: the account it acts for. `id == 0` is the caller,
    ///      whose ID comes from its own address word (`allocate` registers a paying caller).
    ///      Any other `id` is resolved by the Game, which reverts for an unallocated ID, and the
    ///      caller must be authorized for it. Game state follows the account; burns come from
    ///      the payee (a smurf's owner, otherwise the key).
    /// @return key The account key, whose address word carries the board and the ID cache.
    /// @return payee The address the door's FLIP burns come from.
    /// @return word The key's address word with the account's wallet ID filled in.
    function _door(uint32 id, bool allocate) private returns (address key, address payee, uint256 word) {
        if (id == 0) {
            word = _walletWord(msg.sender, allocate);
            return (msg.sender, msg.sender, word);
        }
        bool authorized;
        (key, payee, authorized) = _resolveAccount(id);
        if (!authorized) revert NotApproved();
        // A cached ID equals `id`: both come from the Game's canonical pair for `key`.
        word = _passCredits[key] | (uint256(id) << CrapsPreferenceLib.ID_SHIFT);
    }

    /// @dev The Game's `resolveAccount` for the caller: key, payee and authorization of `id`.
    function _resolveAccount(uint32 id) private view returns (address, address, bool) {
        return IGameCraps(_GAME).resolveAccount(id, msg.sender);
    }

    /// @dev A paying door's prologue: its account (`_door`, allocating for a new caller) and the
    ///      packed burn account — the payee, the wallet ID, and the newcomer rate when the
    ///      account's own mint history earns it.
    function _paidDoor(uint32 id) private returns (address key, uint256 word, uint256 account) {
        address payee;
        (key, payee, word) = _door(id, true);
        account = uint256(uint160(payee)) | ((word >> CrapsPreferenceLib.ID_SHIFT) << _ACCOUNT_ID_SHIFT);
        if (_newcomer(key)) account |= _ACCOUNT_NEWCOMER;
    }

    /// @dev Every board door's epilogue, on the account's address word as its prologue read it
    ///      (`_door`, ID filled). `chips` is already validated. An unchanged initialized board
    ///      touches nothing: an initialized word always holds its wallet ID. Otherwise the word
    ///      is written back with its ID, and the board is saved to it and to the ID word unless
    ///      the daily lock is on. Nothing between the prologue and this epilogue writes the
    ///      account's address word.
    /// @return saved False only when the daily lock prevents a first save or a changed board.
    function _rememberBoard(address key, uint256 word, uint32 chips) private returns (bool saved) {
        uint256 field = CrapsPreferenceLib.compress(chips)
            | (CrapsPreferenceLib.INITIALIZED >> CrapsPreferenceLib.SHIFT);
        // Compare the twenty board bits and the adjacent initialized bit together.
        if ((word >> CrapsPreferenceLib.SHIFT) & 0x1FFFFF == field) return true;
        saved = !IGameCraps(_GAME).rngLocked();
        if (saved) {
            uint32 id = uint32(word >> CrapsPreferenceLib.ID_SHIFT);
            word = (word & ~CrapsPreferenceLib.MASK) | (field << CrapsPreferenceLib.SHIFT);
            uint256 byId = _passCreditsById[id];
            _passCreditsById[id] = (byId & ~CrapsPreferenceLib.MASK) | (field << CrapsPreferenceLib.SHIFT);
            emit CrapsPreferredBoardSet(id, chips);
        }
        _passCredits[key] = word;
    }

    /// @notice Name or re-spread zero through seven chips on an open slip.
    ///         The bankroll, target, bounty and seat are
    ///         all the SLOT's, so no value moves and no field changes. A blank ticket may name a
    ///         pick this way, which is how the vault steers the seats it takes automatically.
    ///         Allowed until the slot closes, which is the moment its table is bound — for a slip
    ///         that came in through `enterBonusDay`, only until the first window of that entry
    ///         closes, and for a DAY ticket, its own day's period zero: a reservation on a future
    ///         day re-spreads freely until then.
    /// @param id The account that owns the slip (0 = the caller).
    /// @param betId The slip: `(slot << 64) | seat`.
    /// @param chips Where up to seven chips go; the draw places the remainder of ten.
    /// @custom:reverts NotYourBet If the account does not own the slip.
    /// @custom:reverts BetLocked If a day-wide entry's first window has closed.
    /// @custom:reverts BonusPeriodSpent If a scheduled window's period has come round, its
    ///         table is already bound, or a custom battle's close time has passed.
    /// @custom:reverts BadRandomCount If the new board names more than seven chips.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    /// @custom:reverts NoWalletId If the Game has no wallet ID for the caller.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function amendSlip(uint32 id, uint256 betId, uint32 chips) public {
        (address key,, uint256 word) = _door(id, false);
        uint256 header = _loadBet(betId);
        if (uint32(header) != uint32(word >> CrapsPreferenceLib.ID_SHIFT)) revert NotYourBet();
        uint256 slot = betId >> 64;
        // A slip re-spreads until its slot closes, which is the moment its table is chosen and so
        // the moment its word first becomes possible. A DAY ticket has no slot of its own to shut,
        // so it freezes when ITS day's first window stops taking bets — the same instant its own
        // door closes, and before any table it plays can be picked. Until then it is the
        // holder's to move: a FUTURE reservation amends freely, since nothing about a future day
        // is frozen yet — no word, no armed window, not even the field's head count — so there is
        // nothing an early re-spread could be tuned against.
        if (slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY == 0) {
            (uint24 nowDay, uint256 nowPeriod,) = _currentBonusSlot();
            uint256 liveDaySlot = _daySlotOf(nowDay);
            if (slot < liveDaySlot || (slot == liveDaySlot && nowPeriod != 0)) revert BetLocked();
        } else {
            // THE ENTRY CLOSE, not the arm — and through the very test every door that takes
            // money already uses, so the two can never drift apart. Closing on the arm instead
            // left a window between the moment a field stopped forming and the moment somebody
            // got round to shutting it, in which the last amender could re-tune a board against a
            // field that was already public and frozen. Nobody who entered on time had that move.
            _joinableSlot(slot);
        }
        // ZERO THROUGH SEVEN CHIPS, the same range every entry door takes. The stored count fixes
        // both how many of the ten the dice scatter and, on scheduled windows alone, which
        // shooter-profit row the slip receives. There is no separate mode bit to update.
        uint256 packed = _upToSeven(chips);

        _storeBet(betId, (header & ~(_BET_CHIPS_MASK << _BET_CHIPS_SHIFT)) | (packed << _BET_CHIPS_SHIFT));

        emit CrapsSlipAmended(betId, packed);
        _rememberBoard(key, word, chips);
    }

    /// @dev One ticket, every window of the day. Nothing per-window is written here: the field
    ///      each window plays is folded in when that window shuts, which is safe precisely because
    ///      this door closes before any window can.
    ///
    ///      SHARED BY BOTH DOORS. `reserved` is zero for an ordinary paid entry and the holder's
    ///      reservation bit when a commitment is being redeemed, and the two differ in exactly
    ///      three places: which day state is required, where the multiple comes from, and whether
    ///      anything is burned. Everything else — the board, the seven-window open check, the ticket counts, the slip event and the quest streak — is the
    ///      same code, so a redeemed seat cannot drift from a bought one.
    function _enterDayLane(uint24 today, uint256 word, uint32 chips, uint256 multiple, uint256 account, uint256 flags)
        private
        returns (uint256 placed, uint256 cost)
    {
        // ONE lane for the whole day, so one multiple: the draw is the day's, and every window
        // the ticket sits in runs it.
        bool high = _vetMultiple(_highMultOf(word), multiple);
        uint256 daySlot = _daySlotOf(today);
        // A day already claimed — seated here, or seated in advance by a pass — is not for sale
        // twice. A prepaid day needs no door of its own: the seat was written when the pass was
        // spent, so there is nothing left to redeem.
        uint32 id = uint32(account >> _ACCOUNT_ID_SHIFT);
        if (_loadDaySeat(daySlot, id) != 0) revert AlreadyInBonus();
        uint256 packed = _upToSeven(chips);

        unchecked {
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                Window memory w = _windowTermsOn(today, p, word);
                // The day has to be OPEN: its windows are what the ticket plays.
                if (_battles[w.key] == 0) revert BonusPeriodSpent();
                // The shared day-seat word already rejected every existing window seat.
                cost += (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple;
            }
        }

        // ONE tagged burn buys the whole day: the join, the day pass and the day-kept streak all
        // ride the same report, so the quest ledger hears about the day once, from the burn.
        uint8 boonMask = _burnForCraps(
            account, _tag(cost, _CRAPS_FLAG_JOIN | _CRAPS_FLAG_PASS | (high ? _CRAPS_FLAG_HIGH : _CRAPS_FLAG_NORMAL) | flags)
        );
        _writeDaySeat(daySlot, id, packed, high, multiple - 1, boonMask);
        placed = _BONUS_PERIODS_PER_DAY;
    }

    /// @dev THE ONE WRITER of a day-lane seat — the paid door, a reservation and a protocol body
    ///      all land here, so a seat cannot drift by how it was funded. It writes the three
    ///      things a day ticket is: its slice of the ticket counters (a HIGH ticket bumps every
    ///      period's high count — the whole day is high), the bet word (a high ticket carries all
    ///      seven period flags), and the holder's SEAT NUMBER in `_daySeated`, which is what lets
    ///      a later per-window upgrade name the ticket without a walk.
    function _writeDaySeat(
        uint256 daySlot,
        uint32 id,
        uint256 chips,
        bool high,
        uint256 evMult,
        uint256 boonMask
    ) private {
        unchecked {
            uint256 t = _dayTickets[daySlot] + 1 + (high ? _DT_ALL_HIGH : 0);
            _dayTickets[daySlot] = t;
            uint256 seat = t & _MASK32;
            _storeDaySeat(daySlot, id, seat);
            _writeSlip(
                (daySlot << 64) | seat, id, chips, high ? _BET_DAYHIGH_MASK : 0, evMult, boonMask
            );
        }
    }

    /// @dev Count an entrant into its battle. The first one carries the stake echo in with it;
    ///      after that the word is a bare increment.
    /// @param key        The battle being entered.
    /// @param stakeUnits The bounty this battle posts, echoed in only by the first entrant.
    /// @return n This entrant's index within its own field, 1-based — the low half of its bet id.
    function _enterBattle(bytes32 key, uint256 stakeUnits) private returns (uint256 n) {
        uint256 g = _battles[key];
        unchecked {
            g = g == 0 ? 1 | (stakeUnits << _BG_STAKE_SHIFT) : g + 1;
            n = g & _MASK32;
        }
        _battles[key] = g;
    }

    // ---------------------------------------------------------------------------------------
    // Settling
    // ---------------------------------------------------------------------------------------

    function _resolveSlotRange(uint64 slot, uint256 allowance, uint64 seatLimit) internal returns (MineFlipGas.Result memory result) {
        if (allowance == 0) return result;
        if (_scheduledExpired(slot)) { result.done = true; return result; }
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX)) return result;
        Window memory w = _slotWindow(slot);
        uint256 board = _battles[w.key];
        if (uint32(board >> _BG_RESOLVED_SHIFT) == uint32(board) && board != 0) {
            result.done = true;
            return result;
        }
        uint256 word = _slotWord(slot);
        if (word == 0) revert RngNotReady();
        uint64 end0 = uint64(uint32(board)) + 1;
        uint64 from = _bonusCursorOf(slot) + 1;
        uint64 end = end0;
        if (from + seatLimit < end) end = from + seatLimit;
        if (end <= from) { result.done = true; return result; }
        (uint256 dayBase, uint64 dayN) = _dayField(slot);
        (uint256 put, uint256 hi) = _settleBatch(slot, from, end, (end0 - 1) - dayN - w.drawn, dayBase, w, word, meter);
        uint64 afterCursor = _bonusCursorOf(slot);
        result.progressed = afterCursor >= from;
        result.rewardBasis = result.progressed ? afterCursor - from + 1 : 0;
        result.done = afterCursor + 1 == end0;
        if (result.progressed) {
            if (slot < _CUSTOM_SLOT_BASE && !_isJackpotSlot(slot)) {
                _bookDay(uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY), put, hi);
            } else if (_isJackpotSlot(slot)) {
                IHighRollerReserve(address(this)).settleHighRollerReserve(slot);
            }
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Each atomic seat includes sole-high and final-field payments. Credit arrays are
    /// flushed once; the admission tail grows for every already accumulated cold beneficiary.
    function _settleBatch(
        uint64 slot, uint64 from, uint64 end, uint64 ownN, uint256 dayBase,
        Window memory w, uint256 word, MineFlipGas.Meter memory meter
    ) private returns (uint256 staked, uint256 high) {
        uint32[] memory ids = new uint32[](end - from);
        uint256[] memory amounts = new uint256[](end - from);
        uint256 k;
        uint256 freePtr;
        assembly ("memory-safe") { freePtr := mload(0x40) }
        uint64 done;
        for (uint64 n = from; n < end; ++n) {
            if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + (k + 1) * _CREDIT_GAS_MAX)) break;
            assembly ("memory-safe") { mstore(0x40, freePtr) }
            uint256 id = _seatId(slot, n, ownN, dayBase, w.entrants - ownN - w.drawn);
            SeatResult memory result = _resolve(id, n, _loadBet(id), w, word);
            staked += result.staked;
            high += result.high;
            if (result.paid != 0) {
                ids[k] = result.id;
                amounts[k] = result.paid;
                ++k;
            }
            done = n;
        }
        // Reserve the cursor write in _SETTLE_TAIL_GAS even on a budget stop.
        // No admitted seat means no write. The fresh masked write preserves the
        // field binding, and commits before the accumulated stake credits leave.
        if (done != 0) _setBonusCursor(slot, done);
        if (k != 0) {
            assembly ("memory-safe") { mstore(ids, k) mstore(amounts, k) }
            ICoinflipStake(ContractAddresses.COINFLIP).creditFlipBatch(ids, amounts);
        }
    }

    /// @notice Constant-time predicate for the next scheduled maintenance step.
    /// @dev Read settlement and the dedicated daily battle have their own earlier stages.
    function minerMaintenancePending() external view returns (bool) {
        uint64 cur = _keeperSlot;
        if (_scheduledExpired(cur)) return true;
        uint24 day = uint24(uint256(cur) / _BONUS_SLOTS_PER_DAY);
        uint256 period = cur % _BONUS_SLOTS_PER_DAY;
        if (period == 0) return _boostBudget[day] != 0 || day < _currentDayIndex();
        if (period > _BONUS_PERIODS_PER_DAY) return true;
        uint256 board = _battles[bytes32(uint256(cur))];
        if (_slotIndexOf(cur) == 0) {
            (,, uint256 open) = _currentBonusSlot();
            return cur < open && !_isJackpotSlot(cur);
        }
        uint256 entrants = uint32(board);
        return entrants == 0 || uint32(board >> _BG_RESOLVED_SHIFT) == entrants;
    }

    /// @notice When the oldest substantive scheduled maintenance became due, or zero.
    /// @dev Uses only the current head: cheap cursor cleanup cannot borrow the age of a
    ///      resolved battle. Lapsed refunds retain their original midnight across batches.
    function minerMaintenanceDueAt() external view returns (uint256 due) {
        uint256 cur = _keeperSlot;
        if (_scheduledExpired(cur)) return 0;
        uint256 boundary = ContractAddresses.DEPLOY_DAY_BOUNDARY;
        // Five ordinary close offsets in 17-bit lanes; the sixth is the daily jackpot.
        uint256 closes = uint256(20 minutes) | (uint256(6 hours + 3 minutes) << 17)
            | (uint256(12 hours + 3 minutes) << 34) | (uint256(18 hours + 3 minutes) << 51)
            | (uint256(1 days - 20 minutes) << 68);
        assembly ("memory-safe") {
            // Scratch-only mapping reads. Masks match the declared packed value widths.
            function read(key, slot) -> value {
                mstore(0, key)
                mstore(32, slot)
                value := sload(keccak256(0, 64))
            }
            let day := and(shr(3, cur), 0xffffff)
            let period := and(cur, 7)
            let midnight := add(mul(add(boundary, day), 86400), 82620)
            switch period
            case 0 {
                if and(iszero(read(day, _boostBudget.slot)), iszero(lt(timestamp(), midnight))) {
                    // One day field plus six window fields, independent of seat count.
                    for { let p := 0 } lt(p, 7) { p := add(p, 1) } {
                        let slot := add(cur, p)
                        let map := _battles.slot
                        if iszero(p) { map := _dayTickets.slot }
                        let count := and(read(slot, map), 0xffffffff)
                        if lt(and(shr(48, read(slot, _slotState.slot)), 0xffffffffffffffff), count) {
                            due := midnight
                            break
                        }
                    }
                }
            }
            default {
                if and(lt(period, 6), iszero(and(read(cur, _slotState.slot), 0xffffffffffff))) {
                    let count := or(read(cur, _battles.slot), read(sub(cur, period), _dayTickets.slot))
                    if and(count, 0xffffffff) {
                        let close := add(sub(midnight, 86400), and(shr(mul(sub(period, 1), 17), closes), 0x1ffff))
                        if iszero(lt(timestamp(), close)) { due := close }
                    }
                }
            }
        }
    }

    function runCrapsMaintenance(uint256) external returns (MineFlipGas.Result memory) {
        _delegateJackpot();
    }



    /// @dev Refund one lapsed day in dense reservation order. The complete comp flush and
    /// cursor writeback are reserved before each refund, including an empty-slot scan.


    /// @notice GAME-only: bank a rolled pass award as credits and nothing else — no reservation
    ///         attempt, no external call, no way to revert past the saturation the credit lane
    ///         already announces.
    /// @dev REVERT-FREE for the authorized caller, and that is load-bearing: the advance's
    ///      level-close sDGNRS passes call this bare from inside the daily advance, so a new
    ///      revert path here is an advance-liveness regression, not a local style choice.
    /// @param id     The wallet credited; the Game passes the nonzero ID it holds.
    /// @param normal Normal-lane passes to bank.
    /// @param high   High-lane passes to bank.
    function creditPasses(uint32 id, uint32 normal, uint32 high) external {
        if (msg.sender != _GAME) revert OnlyGame();
        if (normal != 0) _credit(id, false, normal);
        if (high != 0) _credit(id, true, high);
    }

    /// @notice The Craps progressive's live balance, in whole FLIP — one pool, shared by every
    ///         scheduled window.
    /// @dev The SECOND reader production keeps, and for the same kind of reason as the first: it
    ///      is the one figure of the whole system that is not a pure function of published inputs.
    ///      Reconstructing it means replaying every day's funding and every finalized field's
    ///      funding and awards from genesis, so a client that only wants to show what is
    ///      on the table would otherwise have to index the entire history to do it.
    function progressivePool() external view returns (uint256) {
        return _progressive;
    }

    /// @notice Read a raw storage slot. Periphery escape hatch for lens/viewer contracts, the
    ///         same read surface `DegenerusGame.extsload` gives the game: packed-state decodes
    ///         and client replay live off-contract where EIP-170 headroom is free, and new read
    ///         surfaces deploy without touching this contract. Read-only — storage is already
    ///         public to off-chain readers via eth_getStorageAt; this mirrors that visibility to
    ///         eth_call/staticcall consumers.
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /// @notice Read multiple raw slots in one call, preserving order. Used by the Game to
    ///         attach saved boards to a draw's field before handing it to JackpotBattle.
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        assembly ("memory-safe") {
            let out := mload(0x40)
            mstore(out, 32)
            mstore(add(out, 32), slots.length)
            let size := shl(5, slots.length)
            for { let i := 0 } lt(i, size) { i := add(i, 32) } {
                mstore(add(add(out, 64), i), sload(calldataload(add(slots.offset, i))))
            }
            return(out, add(64, size))
        }
    }



    /// @notice Open a custom battle: a race on terms of your own, on its own slot, settling on a
    ///         table nobody can know until it shuts. The whole definition is vetted ONCE, here,
    ///         for the whole field — an entrant restates nothing and so can key nothing else.
    ///         Served by JackpotBattle.
    /// @param played    The round a slip puts down, in whole FLIP. A whole ten chips.
    /// @param bankMult  How many of those rounds deep the bankroll runs.
    /// @param goalMult  The target, as a multiple of that bankroll.
    /// @param stakeUnits The bounty each entrant posts, in `_BATTLE_STAKE_UNIT` granules.
    /// @param closeTime When entry shuts. From then, anyone may `closeBattle` it.
    /// @param multiEntry Whether one account may hold more than one seat in this battle.
    /// @param highRollerMult The high-roller lane's multiple, or zero for no high lane.
    /// @return slot The battle's slot — what an entrant joins and a settler resolves.
    /// @custom:reverts NotBattleCreator If the caller is neither a granted creator nor the
    ///         vault's majority holder.
    function createBattle(
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) external returns (uint64 slot) {
        _delegateJackpot();
    }

    /// @notice Join a custom battle for account `id` (0 = the caller), placing zero through seven
    ///         chips and leaving the rest of the ten-chip round to the dice. Custom tickets
    ///         receive no shooter-profit boost.
    /// @custom:reverts BoardPlaysBothSides If the ticket names both the pass line and don't pass.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function enterBattle(uint32 id, uint64 slot, uint32 chips, uint16 multiple) public returns (uint256 betId) {
        (address key, uint256 word, uint256 account) = _paidDoor(id);
        betId = _enterWindow(_joinableSlot(slot), chips, multiple, account, 0);
        _rememberBoard(key, word, chips);
    }

    /// @notice Shut a custom battle and take the table it will settle on. Permissionless once its
    ///         close time has passed.
    /// @dev The same shape as a window's arm, for the same reason: the index is chosen NOW, so
    ///      nobody could know it while joining. Custom slots carry no in-order rule — a window
    ///      lane needs slot order to BE table order so a settler can walk a day in sequence, but
    ///      a custom battle is resolved through its own slot alone.
    function closeBattle(uint64 slot) external returns (uint48 index) {
        (Window memory w, uint256 c) = _customTerms(slot);
        unchecked {
            if (block.timestamp < ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusStillRunning();
        }
        if (_slotIndexOf(slot) != 0) revert BonusPeriodSpent();
        // A battle nobody joined is not shut, it never happened — and binding it would strand a
        // table index on nothing.
        if (_battles[w.key] == 0) revert BonusPeriodSpent();
        index = _armSlot(slot, w);
    }

    /// @dev Decode a custom battle into the same `Window` representation used by bonus slots, so
    ///      entry, settlement and payment share one path.
    function _customTerms(uint256 slot) internal view returns (Window memory w, uint256 c) {
        c = _customBattle[slot];
        if (c == 0) revert NoSuchBattle();
        unchecked {
            w.played = (c & _CB_PLAYED_MASK);
            w.bankroll = uint128(w.played * ((c >> _CB_BANK_SHIFT) & _CB_BANK_MASK));
            w.goal = uint128(uint256(w.bankroll) * ((c >> _CB_GOAL_SHIFT) & _CB_GOAL_MASK));
            // The maximum a player may place directly: seven of the ten chips.
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.stakeUnits = (c >> _CB_STAKE_SHIFT) & _BSTAKE_MAX;
            // Fixed at creation, and no day's draw can move it: a custom battle's high lane is a
            // term its creator named, not a thing the protocol rolls.
            w.highMult = (c >> _CB_HIGH_SHIFT) & _CB_HIGH_MASK;
            w.terms = w.stakeUnits | (w.highMult << _TERM_HIGH_SHIFT);
            // Fixed at creation and never revisited: how much has been seeded onto a battle has
            // nothing to do with how many seats one wallet may take.
            w.multiEntry = c & _CB_MULTI_BIT != 0;
            w.bound = uint48(slot);
        }
        w.key = _battleKey(w.bound, w.bankroll, w.goal, w.played, w.terms);
    }

    /// @notice Grant or revoke the right to open a custom battle. The vault's majority holder is
    ///         the only caller — and always holds the right itself — and this roll is the only
    ///         thing it confers: a creator has no say over settlement, arming or anyone else's
    ///         money, and every battle they open is joinable by anyone clearing its terms.
    /// @dev Held as a mapping rather than resolved through the vault on each placement so a
    ///      granted creator pays one warm SLOAD instead of a cross-contract call.
    /// @custom:reverts NotVaultOwner If the caller does not hold the vault's DGVE majority.
    function setBattleCreator(address account, bool allowed) external {
        _delegateJackpot();
    }

    /// @dev Whether `header` takes the high lane in the window at `windowSlot`. A window-local or
    ///      custom slip stores ONE flag at bit 217. A DAY ticket — the one case where the bet's
    ///      own slot differs from the window settling it — stores seven, and the window's period
    ///      picks its own: bit `217 + p`, where `p + 1` is the slot's remainder.
    function _highOn(uint256 header, uint256 betId, uint256 windowSlot) private pure returns (bool) {
        uint256 bit = _BET_HIGH_BIT;
        unchecked {
            if ((betId >> 64) != windowSlot) bit <<= (windowSlot % _BONUS_SLOTS_PER_DAY) - 1;
        }
        return header & bit != 0;
    }

    /// @dev Settle one loaded bet. The slot's terms and word are supplied by `_resolveSlotRange`, which
    ///      reads each once for the whole batch.
    function _resolve(uint256 betId, uint64 seat, uint256 header, Window memory w, uint256 word)
        private
        returns (SeatResult memory result)
    {
        // The combined ordinal is the rotation's seat: a day ticket's own id names its day-local
        // seat, not where it sits in this window's field.
        w.seat = seat;
        Settlement memory s = _settlementOf(betId, header, w, word);
        // High for THIS window: a day ticket may be high in some of its seven and ordinary in the
        // rest, and the window being settled names which flag applies.
        bool hi = _highOn(header, betId, uint256(w.bound));
        if (w.bound < _CUSTOM_SLOT_BASE) {
            uint256 f = _highField[w.key];
            if (s.hottestHand > ((f >> _HF_HOTTEST_SHIFT) & _HF_HOTTEST_MASK)) {
                _highField[w.key] = (f & ~(_HF_HOTTEST_MASK << _HF_HOTTEST_SHIFT))
                    | (s.hottestHand << _HF_HOTTEST_SHIFT);
            }
        }

        // NOTHING is written back to the bet. The verdict folds into the battle's own word as a
        // single composite score, and the scoreboard remembers which bet is holding the lead — so
        // a settlement touches one shared word rather than one word per entrant, and the slot's
        // cursor is the only mark a slip needs.
        //
        // EVERY field ranks, bounty or none. A friendly battle is an ordinary battle whose pot
        // happens to be empty: it gathers, ranks, finalizes and names a winner exactly the same
        // way, and the only thing that falls out at the end is the payment.
        // THE LANE FOLDS FIRST, and the ordering is load-bearing: scoring the main board is what
        // finalizes the field, and finalization is what PAYS — so the last high seat has to be in
        // the sideboard before the main board can go looking for a lane winner.
        uint256 ride;
        if (hi) (ride, result.staked) = _foldHigh(w, s.rank, seat, word, header, s.paid);
        _scoreBattle(w, s.rank, seat, word);
        uint256 runCapital = _runCapital(w, header, hi);
        result.staked += runCapital;
        if (hi) result.high = result.staked;

        // Scale only the payment, after ranking the common unscaled run. Ordinary high seats
        // still buy H copies. Jackpot extras ride only their own rolled fees, so more Added
        // cannot multiply their capital. The base run's rounding precedes either kind of rider.

        // The award is handed BACK rather than paid here: a field settles into one batched
        // credit at the end of the walk, not one cross-contract call per entrant.
        result.id = uint32(header);
        unchecked {
            // A sole rider's return rides home with the run. What this seat PUT UP is the bankroll
            // it ran; the bounty is deliberately not action, since it is posted by a seat and
            // handed to a winner and so nets to zero across the field.
            // The boon lands HERE and only here: after `_foldHigh` has already run on the
            // unscaled figure and after `_scoreBattle` has closed the field, so it cannot reach
            // the rider, the lane, the ranking, the pots or `staked` — and `won` below stays the
            // unboosted scaled result. It moves `paid`, and nothing else.
            uint256 basePaid = _ride(s.paid, runCapital, w.bankroll);
            // THE BOON RIDES EVERY WINDOW THE TICKET PLAYS. It was bought with the burn, and a
            // DAY ticket's burn paid for all seven — so a boon spent on a day purchase lifts all
            // seven bankroll payments rather than one of them. Settlement order cannot reach it:
            // the lift is a function of the run and the mask, so every window's answer is fixed
            // before any of them is cranked.
            // Jackpot high extras earn the normal run's return, but no extra protocol boon.
            uint256 boonBase = hi && w.highExtra != 0 ? s.paid : basePaid;
            result.paid = basePaid + ride + _boonBonus((header >> _BET_BOON_SHIFT) & _BET_BOON_MASK, boonBase);

            // A contested lane pays one winner when the field closes; its individual high seats
            // have no rider payment to announce. A one-seat lane really does ride this run, and
            // still emits zero when the run busts because that zero is its final disposition.
            if (hi && uint32(_highField[w.key]) == 1) {
                emit CrapsHighRollerPaid(betId, w.key, result.id, ride, true);
            }

        }
        emit CrapsBetSettled(betId, result.id, _ride(s.won, runCapital, w.bankroll), result.paid);
    }

    /// @dev Capital sharing a seat's common reference run. Jackpot high extras are fee-funded;
    ///      all other fields retain their original integer-copy scaling.
    function _runCapital(Window memory w, uint256 header, bool high) internal pure returns (uint256) {
        if (high && w.highExtra != 0) return uint256(w.bankroll) + w.highExtra;
        uint256 units = header >> _AWARD_UNITS_SHIFT;
        if (units == 0) units = high ? w.highMult : 1;
        return uint256(w.bankroll) * units;
    }

    /// @dev The extra bounty posted by one high seat, separate from its one main-pot bounty.
    function _highBounty(Window memory w) internal pure returns (uint256) {
        return w.highExtra != 0 ? w.highExtra : (w.highMult - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT;
    }

    /// @dev The entire settlement of `betId`, decided the moment its table's word landed. Shared
    ///      by the paying path and the preview so the two can never disagree about what a bet is
    ///      worth. Pure in the committed inputs — the caller supplies the word.
    function _settlementOf(uint256 betId, uint256 header, Window memory w, uint256 word)
        internal view returns (Settlement memory s)
    {
        SlipResult memory r = ICrapsEngine(ContractAddresses.CRAPS_ENGINE).settleBattle(
            betId, header, w.played / 10, w.bankroll, w.goal, w.bound,
            (uint256(w.entrants) << 64) | w.seat, word);
        assembly ("memory-safe") { s := r }
    }

    // ---------------------------------------------------------------------------------------
    // The battle
    // ---------------------------------------------------------------------------------------

    /// @dev One bonus window, resolved from the day's word. Every field is a pure function of
    ///      (day, period), so a front end and this contract always agree without a call.


    /// @dev The slot a day's shared field lives at — remainder ZERO, the one `_slotWindow`
    ///      refuses and no window ever takes.
    function _daySlotOf(uint256 day) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY;
        }
    }

    /// @dev Where a slot's day tickets live and how many of them there are. Custom battles are not
    ///      on the day clock and never carry any.
    function _dayField(uint256 slot) internal view returns (uint256 base, uint64 n) {
        if (slot >= _CUSTOM_SLOT_BASE || slot % _BONUS_SLOTS_PER_DAY == 7) return (0, 0);
        unchecked {
            uint256 d = _daySlotOf(slot / _BONUS_SLOTS_PER_DAY);
            return (d << 64, uint32(_dayTickets[d]));
        }
    }

    /// @dev A window's slot in the bonus lane. Period zero starts at remainder one; remainder
    ///      zero is reserved and identifies no field.
    function _slotOf(uint256 day, uint256 period) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY + period + 1;
        }
    }

    /// @dev Decode retained RNG or the compact terms saved when this window opened.
    function _windowTerms(uint24 day, uint256 period) internal view returns (Window memory w) {
        uint256 slot = _slotOf(day, period);
        uint256 state = _battles[bytes32(slot)];
        uint256 frozen = state >> _BG_TERM_TIER_SHIFT;
        if (frozen & _BG_TERMS_FROZEN == 0) {
            uint256 word = _dailyWordAt(day);
            if (word == 0 && period != _BONUS_PERIODS_PER_DAY - 1) revert RngNotReady();
            return _windowTermsOn(day, period, word);
        }
        // Opened terms survive word retirement in the existing scoreboard. Settlement
        // entropy still comes from the committed normal RNG cohort (or jackpot round).
        w.tier = frozen & 3;
        w.stakeUnits = (state >> _BG_STAKE_SHIFT) & _BSTAKE_MAX;
        if (w.tier != 0) {
            unchecked {
                uint256 bank = (uint256(0x119407080258) >> ((w.tier - 1) * 16)) & 0xffff;
                w.bankroll = uint128(bank);
                w.goal = uint128(bank * _SCHED_GOAL);
                w.played = bank / _SCHED_BANK_MULT;
            }
        }
        return _finishWindowTerms(day, period, w,
            frozen & _BG_TERM_HIGH_TAIL != 0 ? CrapsPriceLib.HIGH_TAIL : CrapsPriceLib.HIGH_BASE);
    }

    /// @dev Populate the fixed schedule fields after either RNG decoding or snapshot decoding.
    function _finishWindowTerms(uint24 day, uint256 period, Window memory w, uint256 highMult)
        private pure returns (Window memory)
    {
        unchecked {
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.bound = uint48(_slotOf(day, period));
            w.highMult = highMult;
            w.terms = w.stakeUnits | (highMult << _TERM_HIGH_SHIFT);
        }
        w.key = bytes32(uint256(w.bound));
        return w;
    }

    /// @dev Decode the day's word while it is retained; opened terms also have a compact snapshot.
    function _windowTermsOn(uint24 day, uint256 period, uint256 word) internal view returns (Window memory w) {
        (w.bankroll, w.goal, w.played, w.stakeUnits, w.tier) = _bonusPreset(_bonusRoll(word, period), period);
        return _finishWindowTerms(day, period, w, _highMultOf(word));
    }

    /// @notice GAME only: deliver a day-pass award. Reserves ONE pass on tomorrow where
    ///         tomorrow is free, and banks everything else as credit.
    /// @dev ONE CALL PER BATCH, and it is also the eligibility test. Whether tomorrow is already
    ///      taken and whether its word has landed are both facts about state held here, so the
    ///      Game does not pre-screen either — asking twice would either duplicate the rule in two
    ///      contracts that can drift apart, or cost a second call to learn what the first returns.
    ///
    ///      NOTHING HERE REVERTS on an ineligible day. It runs inside lootbox settlement, where a
    ///      revert would cost the player their whole box rather than one day's reservation, so an
    ///      unavailable tomorrow silently becomes credit instead. Credit never expires, so nothing
    ///      is lost by that.
    ///
    ///      The HIGH pass takes the slot when a batch holds both. It is the more valuable of the
    ///      two, and only one can be seated.
    ///
    ///      REVERT-FREE for the authorized caller, and that is load-bearing: lootbox settlement
    ///      calls this bare, so a new revert path here would wedge every box that rolls a pass.
    /// @param id The award owner's wallet; the Game passes the nonzero ID it holds.
    /// @param normal Normal passes the batch rolled.
    /// @param high High-roller passes the batch rolled.
    /// @return day The day a pass was reserved on, or zero if none was.
    /// @custom:reverts OnlyGame If the caller is not the pinned game.
    function deliverPasses(uint32 id, uint32 normal, uint32 high) external returns (uint24 day) {
        if (msg.sender != _GAME) revert OnlyGame();
        unchecked {
            uint256 tomorrow = uint256(_currentDayIndex()) + 1;
            // A day index that will not fit is not a day anyone can reserve; the award simply
            // banks. The protocol runs out of uint24 days long before this matters.
            if (tomorrow <= type(uint24).max && (normal | high) != 0) {
                bool takeHigh = high != 0;
                // Automatic award: snapshot the saved board; later preference changes cannot move it.
                (uint32 chips,) = CrapsPreferenceLib.decode(_passCreditsById[id]);
                if (_reserveDay(id, uint24(tomorrow), takeHigh, chips, 0)) {
                    day = uint24(tomorrow);
                    if (takeHigh) --high;
                    else --normal;
                }
            }
            if (normal != 0) _credit(id, false, normal);
            if (high != 0) _credit(id, true, high);
        }
    }

    /// @dev Take one future day, or report that it could not be taken. A day is takeable only
    ///      while it is within the next 30 days and its word has not landed: the second condition is what
    ///      makes the commitment blind, and it fails closed if a future word is ever filled in
    ///      early.
    ///
    ///      A PASS BUYS THE SEAT, NOT A CLAIM ON ONE. The whole ticket is written here — the day's
    ///      dense seat number, board and lane — so there is nothing to come back and redeem, no window
    ///      to be present for. Scheduled settlement and lapsed-day refunds expire after D+30.
    ///      `amendSlip` re-spreads the chips until the day's first window closes.
    ///
    ///      The MULTIPLE is deliberately not stored. Entry is binary, so a high seat runs at
    ///      exactly its day's `highMult` — a number drawn from a word that cannot exist yet — and
    ///      settlement reads it off the window instead.
    function _reserveDay(
        uint32 id,
        uint24 day,
        bool high,
        uint256 packed,
        uint256 boonMask
    ) private returns (bool) {
        if (!_reservableDay(day)) return false;
        return _reserveDaySeat(id, day, high, packed, boonMask);
    }

    /// @dev The caller has checked the date range and absence of its daily word.
    function _reserveDaySeat(uint32 id, uint24 day, bool high, uint256 packed, uint256 boonMask)
        private returns (bool)
    {
        uint256 daySlot = _daySlotOf(day);
        if (_loadDaySeat(daySlot, id) != 0) return false;
        // The whole seat, exactly as the paid door writes one, on the board the reservation
        // named — chip COUNTS, so one shape is legal at every window whatever its chip is worth.
        // Writing it days early only strengthens the freeze the arm relies on: the total still
        // cannot move once the day's first window stops taking bets.
        _writeDaySeat(daySlot, id, packed, high, 0, boonMask);
        emit CrapsDayReserved(id, day, high);
        return true;
    }

    /// @dev ONE encoder for every tagged craps burn — the paid doors and the comps share this
    ///      plumbing. `account` packs the burning address, its wallet ID (`_ACCOUNT_ID_SHIFT`)
    ///      and the newcomer rate, which only a paid door's account carries.
    function _burnForCraps(uint256 account, uint256 grossAndFlags) private returns (uint8) {
        if (account & _ACCOUNT_NEWCOMER != 0) grossAndFlags += ((grossAndFlags >> 8) / 20) << 8;
        return IFlipCoin(ContractAddresses.COIN).burnCoinForCraps(
            address(uint160(account)), uint32(account >> _ACCOUNT_ID_SHIFT), grossAndFlags
        );
    }

    /// @dev Newcomer pricing (five percent on the burn) changes the burn only, never the entry's
    ///      game capital or rewards. It reads the account key's mint history: established
    ///      accounts and deity holders need only that read, and a level lookup is needed only to
    ///      check recency for an account with some recorded minting.
    function _newcomer(address key) internal view returns (bool) {
        uint256 packed = IGameCraps(_GAME).mintPackedFor(key);
        if (uint24(packed >> BitPackingLib.LEVEL_COUNT_SHIFT) > 2
            || ((packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1) != 0) return false;
        uint256 lastMintLevel = uint24(packed);
        return lastMintLevel == 0 || lastMintLevel + 1 < IGameCraps(_GAME).level();
    }

    /// @dev ONE encoder for the plain burns. The lapse sweep's guarded burn stays direct —
    ///      a `try` needs the external call in its own hands.
    function _burnCoin(address from, uint256 amount) private {
        IFlipCoin(ContractAddresses.COIN).burnCoin(from, amount);
    }

    /// @notice Commit `count` of account `id`'s day-pass credits (0 = the caller) to `count`
    ///         consecutive future days.
    /// @dev ALL OR NOTHING. The whole range is checked before a single credit is spent, and any
    ///      day in it that is already taken, already worded or not yet future takes the entire
    ///      call down. There is no skipping, no partial application and no partial debit — a
    ///      caller who wanted the days either side of an occupied one asks for them separately.
    ///
    ///      A run this walks is bounded by `count`'s own byte, so the caller pays for exactly what
    ///      they asked for and nothing here can be made to walk further.
    /// @param startDay The first day to reserve. Every day in the run must be within tomorrow..today+30.
    /// @param count    How many consecutive days, 1..255.
    /// @param high     Which credit lane to spend.
    /// @param chips    The packed board every reserved day starts on — zero through seven named
    ///                 chips in the same packed shape every live door takes. Each day may still
    ///                 be re-spread on its own through
    ///                 `amendSlip` once that day opens.
    /// @custom:reverts BadPassCount If `count` is zero.
    /// @custom:reverts DayNotReservable If any day in the range is taken, worded or not future.
    /// @custom:reverts BadRandomCount If `chips` names more than seven chips.
    /// @custom:reverts TooManyChipsOnALeg If any leg stacks more than three chips.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    /// @custom:reverts NoWalletId If the Game has no wallet ID for the caller.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function applyCrapsPasses(uint32 id, uint24 startDay, uint8 count, bool high, uint32 chips) public {
        (address key,, uint256 word) = _door(id, false);
        id = uint32(word >> CrapsPreferenceLib.ID_SHIFT);
        _takeCredits(id, high, count);
        _reserveRun(startDay, count, high, chips, 0, id);
        _rememberBoard(key, word, chips);
    }

    /// @notice Buy `count` consecutive future days outright for account `id` (0 = the caller),
    ///         at the fixed price.
    /// @dev The PRICE IS FIXED AND PAID NOW, before the target days draw their terms or their
    ///      high-roller multiple. That is what is being bought: a day whose cost is not yet known,
    ///      at a number that cannot move. The seat itself is written now — there is nothing to
    ///      redeem — and whichever terms the day draws, nothing is topped up or returned. A day
    ///      the advance never opens is swept by the scheduled cursor, and each seat on it comes
    ///      back as one pass credit of its lane.
    ///
    ///      The burn goes FIRST and the run is vetted as it is written; a day the run cannot
    ///      take reverts the whole call and the burn unwinds with it, so a rejected range still
    ///      costs nothing.
    /// @param startDay The first day to reserve. Every day in the run must be within tomorrow..today+30.
    /// @param count    How many consecutive days, 1..255.
    /// @param high     Whether these are high-roller days.
    /// @param chips    The packed board every reserved day starts on — zero through seven named
    ///                 chips, exactly as `applyCrapsPasses` takes it.
    /// @custom:reverts BadPassCount If `count` is zero.
    /// @custom:reverts DayNotReservable If any day in the range is taken, worded or not future.
    /// @custom:reverts BadRandomCount If `chips` names more than seven chips.
    /// @custom:reverts TooManyChipsOnALeg If any leg stacks more than three chips.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function buyFutureCrapsDays(uint32 id, uint24 startDay, uint8 count, bool high, uint32 chips) public {
        (address key, uint256 word, uint256 account) = _paidDoor(id);
        if (count == 0) revert BadPassCount();
        uint8 boonMask;
        unchecked {
            boonMask = _burnForCraps(
                account,
                _tag(
                    uint256(count) * (high ? _HIGH_FUTURE_DAY_PRICE : _NORMAL_FUTURE_DAY_PRICE),
                    _CRAPS_FLAG_PASS
                )
            );
        }
        // The burn goes FIRST and the run is vetted as it is written. A day the run cannot take
        // reverts the whole call, and the burn unwinds with it — so a rejected range still costs
        // nothing, and the rule lives in one place instead of being restated in a pre-walk that
        // could drift from the writer.
        _reserveRun(startDay, count, high, chips, boonMask, uint32(word >> CrapsPreferenceLib.ID_SHIFT));
        _rememberBoard(key, word, chips);
    }

    /// @notice Convert account `id`'s uncommitted normal pass credits (0 = the caller) into
    ///         high-roller credits, at twenty-one normals per high — the credits' own value
    ///         ratio, exactly.
    /// @dev ONE PACKED WRITE moves both lanes, so the debit and the credit are all-or-nothing by
    ///      construction and no failure can leave either lane half-moved. Only BANKED credits are
    ///      reachable: a reservation already committed to a day lives in that day's seat word,
    ///      not here. ONE-WAY — a high credit never breaks back into normals.
    /// @param highCount How many high-roller credits to buy. Costs `21 * highCount` normals.
    /// @custom:reverts BadPassCount If `highCount` is zero.
    /// @custom:reverts PassLaneFull If the high lane cannot hold the conversion.
    /// @custom:reverts Panic(0x11) If the account holds fewer than `21 * highCount` normals.
    /// @custom:reverts NoWalletId If the Game has no wallet ID for the caller.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function convertNormalToHigh(uint32 id, uint32 highCount) external { _delegateJackpot(); }

    /// @notice Turn account `id`'s NORMAL reservation on a future day (0 = the caller) into a
    ///         HIGH one by spending one banked high-roller credit; the normal credit the day was
    ///         taken with is banked back.
    /// @dev A swap of like for like, so nothing is priced here: the seat already exists, blank
    ///      or on its named board, and only its lane changes — the
    ///      whole-day high mask on the bet word and one high ticket in every period's counter,
    ///      exactly what `_writeDaySeat` writes for a high reservation. The day's multiple is
    ///      still read off the window at settlement. Only a day that is STRICTLY FUTURE and not
    ///      yet worded qualifies, the same test a fresh reservation passes: once the day opens,
    ///      `upgradeDayWindows` is the door and it prices each window off the word. The high
    ///      credit is debited before the normal one is banked, so a caller with no high credit
    ///      fails on the debit and nothing moves. ONE-WAY, like `convertNormalToHigh`.
    /// @param day The reserved day.
    /// @custom:reverts DayNotReservable If `day` is today, past, or its word has landed.
    /// @custom:reverts NoSuchBet If the account holds no day ticket on `day`.
    /// @custom:reverts NothingToUpgrade If that ticket is already high.
    /// @custom:reverts Panic(0x11) If the account holds no high-roller credit.
    /// @custom:reverts NoWalletId If the Game has no wallet ID for the caller.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function upgradeReservedDay(uint32 id, uint24 day) external { _delegateJackpot(); }

    /// @dev What a seat in a window of each class is expected to cost, times the expected high
    ///      multiple for the high lane.
    function _windowAheadPrice(uint256 period, bool high) private pure returns (uint256 price) {
        unchecked {
            price = period == 0 || period == _BONUS_PERIODS_PER_DAY - 2
                ? _EV_WINDOW_OPENER
                : (period == _BONUS_PERIODS_PER_DAY - 1 ? _EV_WINDOW_TAIL : _EV_WINDOW_ROUTINE);
            if (high) price *= _EV_HIGH_MULT;
        }
    }

    /// @dev Reserve wallet `id` a seat in `period` of `day`, a day strictly ahead and not yet drawn:
    ///      an ordinary seat placed early. The field is keyed by its slot, so the seat joins it
    ///      now, on its saved board, exactly as a live entrant would — same counter, same one-seat rule, same
    ///      high count — with nothing to burn. Its high flag is binary and the day's multiple is
    ///      read at settlement, exactly as a day ticket's is.
    function _reserveWindow(uint32 id, uint24 day, uint256 period, bool high, uint32 chips) private {
        if (period >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
        if (!_reservableDay(day)) revert DayNotReservable();
        uint256 slot = _slotOf(day, period);
        bytes32 key = bytes32(slot);
        _claimScheduledSeat(slot, id);
        uint256 betId = (slot << 64) | _enterBattle(key, 0);
        if (high) ++_highField[key];
        // `CrapsSlipPlaced` is the whole record: its bet id names the day, the period and the seat.
        _writeSlip(
            betId,
            id,
            chips,
            high ? _BET_HIGH_BIT : 0,
            0,
            0
        );
    }

    /// @dev Write the run, vetting each day as it goes. ALL OR NOTHING: the first day that
    ///      cannot be taken takes the whole call down, and everything already written — the
    ///      earlier days, the credit debit, the burn — unwinds with it. There is no skipping and
    ///      no partial run.
    ///
    ///      The day index is widened before the add so a run that would walk off the end of the
    ///      `uint24` day space fails on the day itself rather than wrapping into the past.
    function _reserveRun(uint24 startDay, uint8 count, bool high, uint32 chips, uint256 boonMask, uint32 id)
        private
    {
        // The board is vetted ONCE for the whole run, by the same test every live door uses:
        // zero through seven chips within the per-leg cap and off the both-sides trap. One
        // slip serves every day of the run; `amendSlip` still re-spreads any single day once that
        // day opens.
        uint256 packed = _upToSeven(chips);
        // Funding and its callbacks have finished. Only STATICCALLs to Game occur
        // during this loop, so the two daily-word tags stay fixed across the run.
        // Keep the per-day word check: even an early future word must reject entry.
        uint256 today = _currentDayIndex();
        uint256 dayTags = _dailyWordTags();
        unchecked {
            for (uint256 i = 0; i < count; ++i) {
                uint256 d = uint256(startDay) + i;
                // ONE boon, ONE ticket: a multi-day purchase marks only its first reserved day,
                // and the boon rides that day's seat exactly as a day ticket's does — every
                // window the seat plays. Marking more days would multiply one boon over a run of
                // independent tickets.
                if (
                    d > type(uint24).max || d <= today || d > today + _RESERVATION_DAYS
                        || _dailyWordAt(uint24(d), dayTags) != 0
                        || !_reserveDaySeat(id, uint24(d), high, packed, i == 0 ? boonMask : 0)
                ) {
                    revert DayNotReservable();
                }
            }
        }
    }

    /// @notice Upgrade chosen windows of account `id`'s whole-day ticket (0 = the caller) to the
    ///         day's high-roller lane, paying each window's missing `H - 1` seat copies. The
    ///         ticket already supplies one, so after the delta burns the selected windows settle
    ///         exactly as a native high seat: `H` copies of the ONE run, one main-scoreboard
    ///         entry, one bounty in the main pot and `H - 1` in the lane — same board, same dice,
    ///         same rounding.
    /// @dev ALL OR NOTHING over the NEW bits: every window still being bought is vetted through
    ///      the same joinability test the paid doors use before anything burns, so a mask naming
    ///      one shut, armed or nonexistent window buys nothing anywhere. Bits already high are
    ///      ignored rather than charged twice — but a mask naming ONLY those has nothing to buy
    ///      and reverts. There is no downgrade, no transfer and no refund, and no quest credit
    ///      moves here: the streak was paid when the day was taken, and this is the same day.
    ///
    ///      A banked pass or an unworded future reservation cannot come through this door at
    ///      calculated terms: a day that is not OPEN fails the joinability test on every period,
    ///      so in practice `day` is today, upgraded window by window while each still takes bets.
    /// @param day        The ticket's day.
    /// @param periodMask Which periods to upgrade, bit `p` for period `p`. Bits 0..5 only.
    /// @return burned The exact FLIP delta charged: the sum over the newly upgraded windows of
    ///         `(bankroll + bounty) * (H - 1)`.
    /// @custom:reverts BonusPeriodSpent If the mask names a period past the sixth, or any newly
    ///         selected window is closed by the clock, already armed, or not yet opened.
    /// @custom:reverts RngNotReady If a newly selected window is on a day whose word has not landed
    ///         — a banked pass or an unworded future reservation cannot be upgraded at calculated
    ///         terms, so its every period fails this before anything burns.
    /// @custom:reverts NoSuchBet If the account holds no day ticket on `day`.
    /// @custom:reverts NothingToUpgrade If no selected period is newly upgradable.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function upgradeDayWindows(uint32 id, uint24 day, uint8 periodMask) external returns (uint256 burned) {
        (,, uint256 account) = _paidDoor(id);
        return _upgradeDayWindows(account, day, periodMask, false);
    }

    /// @dev The upgrade itself, for the account's own ticket. A comp charges the comp lane the
    ///      very figure the paid door burns; the seat, the bits and the counters are written the same.
    function _upgradeDayWindows(uint256 account, uint24 day, uint8 periodMask, bool comp)
        private
        returns (uint256 burned)
    {
        // Bits above the seven periods name windows that do not exist.
        if (periodMask > 0x3F) revert BonusPeriodSpent();
        uint256 daySlot = _daySlotOf(day);
        uint32 id = uint32(account >> _ACCOUNT_ID_SHIFT);
        // The player's own ticket or nothing: the seat lookup is keyed to the player, so nobody
        // can reach — or be charged for — anyone else's.
        uint256 seat = _loadDaySeat(daySlot, id) & _MASK32;
        if (seat == 0) revert NoSuchBet();
        uint256 betId = (daySlot << 64) | seat;
        uint256 header = _loadBet(betId);
        uint256 newMask = periodMask & ~(header >> _BET_HIGH_SHIFT);
        if (newMask == 0) revert NothingToUpgrade();
        uint256 counters;
        unchecked {
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                if (newMask & (1 << p) == 0) continue;
                // The very test every paid door uses: opened, unarmed, and its period still to
                // come. A window shut by the CLOCK fails it whether or not anyone has armed it
                // yet — the same instant its own entry door closed.
                Window memory w = _joinableSlot(_slotOf(day, p));
                // The missing copies of the WHOLE seat — the bankroll each runs and the bounty
                // each posts, exactly as the high door prices them. The ticket itself is the one
                // copy already paid for.
                burned += (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * (w.highMult - 1);
                counters += 1 << (_DT_HIGH_SHIFT * (p + 1));
            }
        }
        if (comp) _burnForCraps(account, _tag(burned, _CRAPS_FLAG_COMP));
        else {
            if (account & _ACCOUNT_NEWCOMER != 0) burned += burned / 20;
            _burnCoin(address(uint160(account)), burned);
        }
        _storeBet(betId, header | (newMask << _BET_HIGH_SHIFT));
        unchecked {
            _dayTickets[daySlot] += counters;
        }
        emit CrapsDayWindowsUpgraded(id, day, uint8(newMask), burned);
    }

    /// @notice The vault's comp door: seat, reserve, upgrade or bank passes for a recipient
    ///         account, charged to the FLIP comp lane at exactly the price the paid door would burn.
    /// @dev ONE door, one small tuple, no caller-supplied price and no caller-supplied target.
    ///      Every kind runs the SAME private path its paid twin runs — the same validation, seat
    ///      writer, counters and logs — with the recipient in the owner's place and the comp bit
    ///      on the burn, which is what makes FLIP charge the lane instead of a wallet. A comped
    ///      seat snapshots its recipient's preferred board; `amendSlip` re-spreads it like any other seat
    ///      once its day is live. A window-ahead reservation (kind 5) snapshots that same board
    ///      before the future day's terms are known. A comp consumes no
    ///      boon and reports no quest, and a boon already on an upgraded seat is kept. Scheduled
    ///      windows only: a custom battle is its creator's to fill. Any failure reverts the
    ///      whole call, and an insufficient lane reverts inside FLIP.
    /// @param code One comp, packed:
    ///             bits 0..31    the recipient's wallet ID — allocated, never zero; bits
    ///                           32..159 are zero;
    ///             bits 160..167 the kind — 0 one of today's windows · 1 today's whole day ·
    ///                           2 future days · 3 day upgrade · 4 banked passes · 5 one window
    ///                           on each of `count` days ahead, priced at what such a window is
    ///                           expected to cost;
    ///             bit 168       high: the day's multiple on a window or day, the high lane on
    ///                           future days and passes; an upgrade is high by definition;
    ///             bits 176..199 arg: the window's period 0..5 (kind 0), the first day (kinds 2
    ///                           and 5), the ticket's day (kind 3);
    ///             bits 200..207 count: days (kinds 2 and 5) or passes (kind 4); the period mask,
    ///                           bits 0..5, for an upgrade (kind 3); for kind 5 the period rides
    ///                           in bits 208..215.
    /// @return charged What the lane paid, in whole FLIP — for kind 4 the passes actually banked
    ///                 times their value, since a full lane banks fewer and is billed for fewer.
    ///      ADMIN-DRIVEN, so it vets only what would corrupt state: the vault checks the
    ///      recipient, an unknown kind or a zero count simply charges nothing, and each path's own
    ///      rules — a shut window, an occupied day, a period past the sixth — revert as they do
    ///      for a paid entry.
    /// @custom:reverts NotVaultOwner If the caller is not the vault.
    /// @custom:reverts E (Game) If the recipient ID is zero or unallocated.
    /// @custom:reverts DayNotReservable If a reserved window's day is not strictly ahead.
    /// @custom:reverts AlreadyInBonus If the player already holds that window or that day.
    function vaultComp(uint256 code) external returns (uint256 charged) {
        if (msg.sender != ContractAddresses.VAULT) revert NotVaultOwner();
        uint32 id = uint32(code);
        // A comp pays nothing for its recipient, so the recipient must be an allocated account:
        // the Game's resolution reverts otherwise. Only the key is used; the comp lane pays.
        (address key,,) = _resolveAccount(id);
        uint256 account = uint256(uint160(key)) | (uint256(id) << _ACCOUNT_ID_SHIFT);
        uint256 kind = (code >> _COMP_KIND_SHIFT) & 0xFF;
        bool high = code & _COMP_HIGH_BIT != 0;
        uint24 arg = uint24(code >> _COMP_ARG_SHIFT);
        uint8 count = uint8(code >> _COMP_COUNT_SHIFT);
        (uint32 chips,) = CrapsPreferenceLib.decode(_passCreditsById[id]);
        if (kind == _COMP_WINDOW) {
            Window memory w = _joinableWindow(arg);
            uint256 multiple = high ? w.highMult : 1;
            _enterWindow(w, chips, multiple, account, _CRAPS_FLAG_COMP);
            charged = (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple;
        } else if (kind == _COMP_DAY) {
            (uint24 today,,) = _currentBonusSlot();
            (, charged) = _enterToday(chips, high ? _highMultOf(_dailyWordAt(today)) : 1, account, _CRAPS_FLAG_COMP);
        } else if (kind == _COMP_FUTURE_DAYS) {
            charged = uint256(count) * (high ? _HIGH_FUTURE_DAY_PRICE : _NORMAL_FUTURE_DAY_PRICE);
            uint8 boonMask = _burnForCraps(account, _tag(charged, _CRAPS_FLAG_PASS | _CRAPS_FLAG_COMP));
            _reserveRun(arg, count, high, chips, boonMask, id);
        } else if (kind == _COMP_UPGRADE) {
            charged = _upgradeDayWindows(account, arg, count, true);
        } else if (kind == _COMP_PASSES) {
            uint256 banked = _credit(id, high, count);
            charged = banked * (high ? _HIGH_PASS_VALUE : _NORMAL_PASS_VALUE);
            _burnForCraps(account, _tag(charged, _CRAPS_FLAG_COMP));
        } else if (kind == _COMP_WINDOW_AHEAD) {
            uint256 period = (code >> _COMP_PERIOD_SHIFT) & 0xFF;
            charged = uint256(count) * _windowAheadPrice(period, high);
            _burnForCraps(account, _tag(charged, _CRAPS_FLAG_COMP));
            unchecked {
                // A day past the width wraps to one long gone, which the reservation refuses.
                for (uint256 i = 0; i < count; ++i) {
                    _reserveWindow(id, uint24(uint256(arg) + i), period, high, chips);
                }
            }
        }
    }

    /// @notice Open all seven of today's bonus windows at once, once a day. Each is joinable from
    ///         here, in any order and for as long as its own period has not passed, so a player
    ///         picks the windows they want rather than waiting at each. The terms were public the
    ///         moment the day's word landed.
    /// @dev Called by the GAME, on the daily advance that applies that word — never by a player,
    ///      which is what keeps the opening on the same crank as the word it depends on.
    ///
    ///      NOTHING HERE REVERTS. It runs inside the advance, so a revert would not skip the
    ///      opening, it would take the whole protocol's daily crank down with it. A day already
    ///      open and a day whose word has not landed both simply do nothing, and the absence of
    ///      `CrapsBonusOpened` is how either is seen. The seat burns are already fail-soft for the
    ///      same reason.
    /// @custom:reverts OnlyGame If the caller is not the pinned game.
    /// @dev Opening walks nothing but today. A window that this day leaves unshut is not stranded
    ///      and does not need sweeping up: the scheduled keeper shuts every window that has
    ///      stopped taking bets, in order.
    function openBonusDay() external {
        if (msg.sender != _GAME) revert OnlyGame();
        uint24 today = _currentDayIndex();
        unchecked {
            if (_bonus >= uint256(today) + 1) return;
            // The word is what draws every window's terms, and it is what makes the house's seat
            // payable: sDGNRS holds its FLIP entirely as coinflip backing, which only settles once
            // the day it belongs to has resolved. The advance applies it two calls before this
            // one, so it is here; if it ever is not, the day goes unopened rather than unadvanced.
            // Read ONCE for the whole day and hand it to all seven. Having it here is also what
            // lets a missing word be a day that does not open rather than a revert: this runs
            // inside the advance, where reverting stops the protocol's crank and not just the
            // opening.
            uint256 word = _dailyWordAt(today);
            if (word == 0) return;
            _bonus = uint256(today) + 1;
            // The day's bonus budgets, drawn ONCE off the table's own recent books and fixed
            // here. Every window of the day shares them, so what a window offers is settled
            // before anyone can sit down at it. The routine weighting rides home in the same word
            // it divides: it is a pure function of `word`, but every later read of a window's
            // share would otherwise have to re-roll all six routine windows to recover it.
            (uint256 rawMain, uint256 highBudget) = _drawBudgets(today);
            // HALF THE MAIN ALLOCATION NEVER REACHES A WINDOW. The ladder gets one half; the other
            // is banked in the progressive, here and exactly once — this whole block is behind the
            // `_bonus` guard set above, so however many times the day is arbed, opened or
            // advanced, it funds once.
            (uint256 mainBudget, uint256 contribution) = _splitMainBudget(rawMain);
            _boostBudget[today] = mainBudget | (_routineWeight(word) << _BUDGET_W_SHIFT);
            // A day that banked no high action has no high budget, and writing a zero would cost
            // a slot to say so.
            if (highBudget != 0) _highBudget[today] = highBudget;
            uint256 pool = _progressive + contribution;
            _progressive = pool;
            emit CrapsProgressiveFunded(today, contribution, pool);
            emit CrapsHighRollerDayOpened(today, uint16(_highMultOf(word)), mainBudget, highBudget);
            uint256 cost;
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                cost += _openWindow(today, p, word);
            }
            // The house and the vault take DAY seats — one ticket each for the whole day, rather
            // than one per window. Two bet writes instead of fourteen, for the same field in every
            // window and the same price paid for it.
            _seatDayLane(_daySlotOf(today), cost);
        }
    }

    /// @dev Open one window, seat the house and the vault in it, and announce it.
    function _openWindow(uint24 day, uint256 period, uint256 word) private returns (uint256 cost) {
        Window memory w = _windowTermsOn(day, period, word);
        // Only the stake echo is banked. The seed is a pure function of the day's word, so it is
        // recomputed wherever it is needed and never stored — which is also why an uncontested
        // window creates nothing to reclaim, and why the seed field below belongs entirely to
        // donations. Seats reserved ahead of the word are already counted in this field — the key
        // is the slot, so they joined it as ordinary entrants — and the stake echo lands beside them.
        uint256 frozen = w.tier | (w.highMult == CrapsPriceLib.HIGH_TAIL ? _BG_TERM_HIGH_TAIL : 0) | _BG_TERMS_FROZEN;
        _battles[w.key] |= (w.stakeUnits << _BG_STAKE_SHIFT) | (frozen << _BG_TERM_TIER_SHIFT);

        unchecked {
            cost = uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT;
        }

        emit CrapsBonusOpened(
            w.key,
            w.bound,
            _boostBase(w) * _BOOST_MAX_MULT,
            w.bankroll,
            w.goal,
            w.postedStake,
            w.stakeUnits * _BATTLE_STAKE_UNIT
        );
    }

    /// @dev The arm itself — shared by the scheduled cursor, which has already proven a window's
    ///      preconditions on its own walk, and by `closeBattle` for custom battles.
    function _armSlot(uint64 slot, Window memory w) internal returns (uint48 index) {
        unchecked {
            index = _writeBuffer();
            _setSlotIndex(slot, index + 1);
            // The day field joins the window HERE rather than at the ticket sale, so selling a day
            // ticket never touches seven scoreboards. Both counts are already frozen — tickets
            // stop when the day's first window stops taking bets, and THIS period's high count
            // stops moving at this window's own entry close, before anything can be shut.
            // One read carries all the counts; the window folds in the total and the high count
            // that belongs to its own period — counter `p + 1` of the word, which is
            // `slot % _BONUS_SLOTS_PER_DAY` exactly. A custom battle is not on the day clock and
            // carries no day field at all.
            if (slot < _CUSTOM_SLOT_BASE) {
                uint256 tickets = _dayTickets[_daySlotOf(uint256(slot) / _BONUS_SLOTS_PER_DAY)];
                if (uint32(tickets) != 0) _battles[w.key] += uint32(tickets);
                uint256 dayHigh = (tickets >> (_DT_HIGH_SHIFT * (uint256(slot) % _BONUS_SLOTS_PER_DAY))) & _MASK32;
                if (dayHigh != 0) _highField[w.key] += dayHigh;
            }
        }
        // The shut window joins the write buffer's RNG round like any other consumer: the next
        // request, daily or mid-day, settles it. Its pending bit counts as work for that request.
        IReadCohortLifecycle(address(this)).registerRngSlot(index, slot, w.key);
        emit CrapsBonusArmed(w.key, uint48(slot), index);
    }

    /// @dev The window a player may still join: one of today's, opened, not yet shut, and not in
    ///      a period that has already run out.
    /// @dev THE joinability test: a battle you can still bet into. Every door that takes money on
    ///      a battle's behalf — an entry, a donation — goes through this one function, so a
    ///      donation can never reach a field an entrant could not also have reached.
    function _joinableSlot(uint256 slot) internal view returns (Window memory w) {
        if (slot >= _CUSTOM_SLOT_BASE) {
            uint256 c;
            (w, c) = _customTerms(slot);
            unchecked {
                if (block.timestamp >= ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusPeriodSpent();
            }
        } else {
            // A window whose period has already come round is shut whether or not anyone armed it.
            if (_isJackpotSlot(slot)) {
                if (slot != _slotOf(_bonus - 1, _BONUS_PERIODS_PER_DAY - 1)
                    || IGameCraps(_GAME).rngLocked()) revert BonusPeriodSpent();
            } else {
                (,, uint256 live) = _currentBonusSlot();
                if (slot < live) revert BonusPeriodSpent();
            }
            w = _slotWindow(slot);
            // A window nobody opened is not a battle yet.
            if (_battles[w.key] == 0) revert BonusPeriodSpent();
        }
        // Shut is shut: a battle whose table has been taken takes no more of anything, whatever
        // some clock says.
        if (_slotIndexOf(slot) != 0) revert BonusPeriodSpent();
    }

    function _joinableWindow(uint256 period) private view returns (Window memory w) {
        if (period >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
        uint24 today = period == _BONUS_PERIODS_PER_DAY - 1 ? uint24(_bonus - 1) : _currentDayIndex();
        return _joinableSlot(_slotOf(today, period));
    }

    /// @dev The one placement path every bonus door funnels through. Kept single on purpose:
    ///      `_place` is private and the optimizer inlines a full copy at each call site, so a
    ///      door of its own per entry mode costs more than the mode is worth.
    function _enterWindow(Window memory w, uint32 chips, uint256 multiple, uint256 account, uint256 flags)
        private
        returns (uint256)
    {
        return _place(w, _upToSeven(chips), multiple, account, flags);
    }

    /// @dev A door's board: zero through seven named chips. Every count grows to the same ten-chip
    ///      round at settlement, so none of them changes the field key or creates a private race.
    function _upToSeven(uint32 chips) private pure returns (uint256 packed) {
        uint256 count;
        (packed, count) = _packChips(chips);
        if (count > _MAX_PICKED_CHIPS) revert BadRandomCount();
    }

    /// @notice Join one of today's bonus windows for account `id` (0 = the caller), placing up to
    ///         seven chips. `chips` names them by COUNT — how many of the stack go on each leg —
    ///         rather than by FLIP, so ONE allocation enters any window whatever its chip is worth.
    ///         The window dictates bankroll, target and bounty, so there is nothing else to supply.
    ///
    ///         The dice scatter the rest of the ten: an all-zero `chips` leaves the whole board
    ///         to the draw.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function enterBonusBattle(uint32 id, uint256 period, uint32 chips, uint16 multiple)
        public
        returns (uint256 betId)
    {
        (address key, uint256 word, uint256 account) = _paidDoor(id);
        Window memory w = _joinableWindow(period);
        betId = _enterWindow(w, chips, multiple, account, 0);
        _rememberBoard(key, word, chips);
    }

    /// @notice Enter EVERY one of today's windows for account `id` (0 = the caller) with the same
    ///         chip allocation, in one call.
    ///         Each window scales the allocation to its own chip, so a single board is a legal
    ///         entry at all of them however differently they are sized — which is the whole
    ///         reason the allocation is counted in chips rather than in FLIP. An all-zero
    ///         allocation takes the whole day blind, every chip of every window left to the dice.
    ///
    ///         Sold only while the first window is still taking bets: a whole-day ticket is a
    ///         commitment made before any of the day is spent. Past that, take what is left one
    ///         window at a time through `enterBonusBattle`.
    /// @param chips    Chip allocation entered at every window; an all-zero allocation takes the
    ///                 whole day blind.
    /// @param multiple The day's high-roller multiple to enter at, or 1 for the ordinary lane.
    /// @return placed How many windows took the entry.
    /// @custom:reverts BonusPeriodSpent If the day's first window has already closed.
    /// @custom:reverts NotApproved If the caller may not act for account `id`.
    function enterBonusDay(uint32 id, uint32 chips, uint16 multiple) public returns (uint256 placed) {
        (address key, uint256 word, uint256 account) = _paidDoor(id);
        (placed,) = _enterToday(chips, multiple, account, 0);
        _rememberBoard(key, word, chips);
    }

    /// @dev Today's whole-day ticket for `account`, and what it cost: the paid door and the comp
    ///      door land here.
    function _enterToday(uint32 chips, uint256 multiple, uint256 account, uint256 flags)
        private
        returns (uint256 placed, uint256 cost)
    {
        (uint24 today, uint256 period,) = _currentBonusSlot();
        uint256 word = _dailyWordAt(today);
        if (word == 0) revert RngNotReady();
        // THE DAY LANE OR NOTHING. A whole-day ticket is a commitment made before any of the day
        // is spent, so it is sold only while the first window is still taking bets. Past that the
        // day is part-spent and what is left is taken one window at a time through
        // `enterBonusBattle` — the same seats at the same prices, without a SET of slips that has
        // to be stamped with where it began, locked as one and amended as one.
        if (period != 0) revert BonusPeriodSpent();
        return _enterDayLane(today, word, chips, multiple, account, flags);
    }

    /// @notice Add FLIP to a battle's seed, so its winner takes more than the entrants put in.
    /// @dev Permissionless, but accepted only while the battle remains joinable. The explicit
    ///      ceiling protects the scoreboard's 31-bit seed field. VAULT donations charge the
    ///      comp lane; all other callers burn their own FLIP. Neither consumes a boon or
    ///      reports quest progress. Donations do not earn comp allowance at settlement.
    /// @param custom   True for a custom battle, false for one of today's bonus windows.
    /// @param index    The custom battle's number, or the window's period.
    /// @param granules What to add, in `_BATTLE_STAKE_UNIT` granules.
    /// @return amount The amount added, in whole FLIP, also charged to the donor or comp lane.
    function donate(bool custom, uint256 index, uint24 granules) external returns (uint256 amount) {
        uint256 slot;
        unchecked {
            if (custom) {
                slot = _CUSTOM_SLOT_BASE + index;
            } else {
                if (index >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
                uint24 today = _currentDayIndex();
                slot = _slotOf(today, index);
            }
        }
        Window memory w = _joinableSlot(slot);
        uint256 g = _battles[w.key];
        if (granules == 0 || g == 0) revert SeedAboveMax();
        uint256 seed;
        unchecked {
            seed = ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK) + granules;
            amount = uint256(granules) * _BATTLE_STAKE_UNIT;
        }
        if (seed > _BG_SEED_MASK) revert SeedAboveMax();
        if (msg.sender == ContractAddresses.VAULT) {
            _burnForCraps(
                uint256(uint160(ContractAddresses.VAULT)) | (uint256(_VAULT_ID) << _ACCOUNT_ID_SHIFT),
                _tag(amount, _CRAPS_FLAG_COMP)
            );
        } else {
            _burnCoin(msg.sender, amount);
        }
        _battles[w.key] = (g & ~(_BG_SEED_MASK << _BG_SEED_SHIFT)) | (seed << _BG_SEED_SHIFT);
        emit CrapsBonusDonated(w.key, msg.sender, amount, seed * _BATTLE_STAKE_UNIT);
    }

    /// @dev Seat the house and the vault on the DAY lane: one ticket each, playing every window
    ///      of the day, at the sum of what those windows cost. They take whatever seats are next:
    ///      a day whose passes were spent in advance already has a field, and these two join it
    ///      rather than heading it. A window therefore always has a field: a lone entrant arrives
    ///      to a race rather than an empty table, and a window nobody turns up to is still one the
    ///      two of them settle between themselves.
    ///
    ///      Each body pays with a banked pass first and a fail-soft FLIP burn second. When
    ///      neither covers it, the two part ways: the vault sits the day out, and the HOUSE is
    ///      seated anyway — one unfunded seat that still counts in `entrants`, so the field pays
    ///      one bounty nobody burned. That is the price of every window having a field, bounded
    ///      to a single seat per day and visible as a `CrapsSlipPlaced` with no burn beside it.
    function _seatDayLane(uint256 daySlot, uint256 cost) private {
        // Keep one shared seating body in the deployed code, in the same house-then-vault order.
        for (uint256 i; i < 2; ++i) {
            _seatBody(
                daySlot,
                i == 0
                    ? uint256(uint160(ContractAddresses.SDGNRS)) | (uint256(_SDGNRS_ID) << _ACCOUNT_ID_SHIFT)
                    : uint256(uint160(ContractAddresses.VAULT)) | (uint256(_VAULT_ID) << _ACCOUNT_ID_SHIFT),
                cost
            );
        }
    }

    /// @dev Seat ONE protocol body, cheapest funding first: a day it already holds a reservation
    ///      on, then a banked pass credit, then FLIP.
    ///
    ///      THIS IS WHERE BOTH BODIES SPEND THEIR PASSES. Both open lootboxes — the vault buys
    ///      them outright, sDGNRS resolves its own self-subscription boxes — so both are handed
    ///      passes by `deliverPasses` like any other winner, and the house banks its level cut as
    ///      high passes at every level close besides. sDGNRS has no controller to call
    ///      `applyCrapsPasses`, and the vault's own surface has no such door (only an operator its
    ///      owner approves for wallet 1 could reach it). So the daily seat spends them, and a
    ///      body that arrives already paid for is not charged twice.
    ///
    ///      A HIGH pass is honoured as a high seat, exactly as the paid door builds one: the
    ///      day's own multiple, the high bit, and the high half of the ticket counter — which is
    ///      what `_armSlot` folds into each window's sideboard. The FLIP fallback is always
    ///      an ordinary 1x seat, so `cost` is only ever the plain seven-window bill.
    function _seatBody(uint256 daySlot, uint256 account, uint256 cost) private {
        uint32 id = uint32(account >> _ACCOUNT_ID_SHIFT);
        // Already sitting: a pass spent on this day wrote the seat the moment it was spent, so
        // there is nothing here to buy.
        if (_loadDaySeat(daySlot, id) != 0) return;
        // Automatic seats use the body's saved board, read from the same word as its credits; an
        // unset preference is fully random.
        uint256 credits = _passCreditsById[id];
        (uint32 chips,) = CrapsPreferenceLib.decode(credits);
        // THE BANK FIRST, FLIP SECOND. A pass is a claim on a day that is already bought and
        // cannot be spent on anything else, so it is what the seat reaches for; FLIP is liquid and
        // is only burned for a day the bank cannot cover. The burn pays the whole day — every
        // window's bankroll AND its bounty.
        bool high;
        bool funded;
        if ((credits >> _PASS_HIGH_SHIFT) & _PASS_MAX != 0) {
            (high, funded) = (true, true);
        } else if (credits & _PASS_MAX != 0) {
            funded = true;
        }
        if (funded) {
            _takeCredits(id, high, 1);
        } else {
            try IFlipCoin(ContractAddresses.COIN).burnCoin(address(uint160(account)), cost) {
                funded = true;
            } catch (bytes memory reason) { MineFlipGas.rethrowGasFailure(reason); }
        }
        if (!funded) {
            // THE HOUSE SITS ANYWAY, bounty included. A bonus that waits on the reserve is a bonus
            // that silently stops happening, and the day still has to have somebody in it. The
            // seat costs the field one bounty it never burned, which is the price of the day
            // running at all — bounded to a single seat, and visible without a log of its own:
            // the seat's `CrapsSlipPlaced` lands with no matching burn beside it.
            //
            // The VAULT gets no such comp: it seeds nothing and is just another body at the table.
            if (id != _SDGNRS_ID) return;
        }
        // The house usually names no board, so the dice place all ten in every window it sits
        // in — naming nothing is also the one shape that cannot be read off in advance.
        //
        // Seated plain, with no multiplier and no boon. These two are the protocol itself, so
        // they collect a window they win in full rather than burning a subsidy one of them just
        // paid for.
        _writeDaySeat(daySlot, id, chips, high, 0, 0);
    }

    /// @notice Where the seven-window daily schedule stands: protocol day, next closable window,
    ///         and its monotonic slot.
    function _currentBonusSlot() internal view returns (uint24 day, uint256 period, uint256 slot) {
        day = _currentDayIndex();
        uint256 elapsed = (block.timestamp - 82_620) % 1 days;
        if (elapsed < 20 minutes) period = 0;
        else if (elapsed < 6 hours + 3 minutes) period = 1;
        else if (elapsed < 12 hours + 3 minutes) period = 2;
        else if (elapsed < 18 hours + 3 minutes) period = 3;
        else if (elapsed < 1 days - 20 minutes) period = 4;
        else period = 5;
        slot = _slotOf(day, period);
    }

    /// @dev A domain-separated draw per period, with matching bookends sharing period zero's terms.
    function _bonusRoll(uint256 word, uint256 period) private pure returns (uint256) {
        unchecked {
            return _hash3(word, SCHEDULE_TAG, period == _BONUS_PERIODS_PER_DAY - 2 ? 0 : period);
        }
    }

    /// @dev Both matching bookends use 20/30/50 tier odds; the three routines use 55/25/20.
    ///      Pricing and budget weights share one decoder so they cannot disagree on a tier.
    function _tierPick(uint256 word, uint256 period) internal pure returns (uint256) {
        return CrapsPriceLib.tier(_bonusRoll(word, period), period == 0 || period == _BONUS_PERIODS_PER_DAY - 2);
    }

    /// @dev Sum the five ordinary windows' 1:2:4 tier weights for their shared daily allocation.
    function _routineWeight(uint256 word) internal pure returns (uint256 total) {
        unchecked {
            for (uint256 p = 0; p + 1 < _BONUS_PERIODS_PER_DAY; ++p) {
                total += 1 << _tierPick(word, p);
            }
        }
    }

    /// @dev Split the ordinary allocation by tier weight. The jackpot has its own Added funding.
    function _windowShare(uint256 budget, uint256 weight, uint256 period, uint256 tier) private pure returns (uint256) {
        if (period == _BONUS_PERIODS_PER_DAY - 1 || weight == 0) return 0;
        return budget * (1 << (tier - 1)) / weight;
    }

    function _bonusPreset(uint256 roll, uint256 period) internal pure
        returns (uint128 bankroll, uint128 goal, uint256 boardStake, uint256 stakeUnits, uint256 tier)
    {
        // The jackpot fee is known now. Its bankroll/pot are derived only after its field locks.
        if (period == _BONUS_PERIODS_PER_DAY - 1) return (0, 0, 0, CrapsPriceLib.jackpotPrice(roll) / _BATTLE_STAKE_UNIT, 0);
        uint256 pick = CrapsPriceLib.tier(roll, period == 0 || period == _BONUS_PERIODS_PER_DAY - 2);
        uint256 bank = (uint256(0x119407080258) >> (pick * 16)) & 0xffff;
        uint256 bounty = (uint256(0xdac09c405dc057803e802580190012c00c8) >> ((pick * 3 + ((roll >> 8) % 3)) * 16)) & 0xffff;
        return (uint128(bank), uint128(bank * _SCHED_GOAL),
            bank / _SCHED_BANK_MULT, bounty / 100, pick + 1);
    }

    /// @dev The match key: one slot and the exact numeric terms every entrant shares. The round
    ///      played is included; chip composition is not, because every zero-through-seven choice
    ///      deliberately races in the same field.
    function _battleKey(uint48 bound, uint256 staked, uint256 goal, uint256 played, uint256 terms)
        private
        pure
        returns (bytes32 key)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, BATTLE_TAG)
            mstore(add(ptr, 0x20), bound)
            mstore(add(ptr, 0x40), staked)
            mstore(add(ptr, 0x60), goal)
            mstore(add(ptr, 0x80), played)
            mstore(add(ptr, 0xA0), terms)
            key := keccak256(ptr, 0xC0)
        }
    }

    /// @dev The craps boon's payout-base ceiling. The percentage runs on the bankroll payment up
    ///      to this much, so the three tiers top out at 3,000 / 6,000 / 9,000 FLIP PER WINDOW — a
    ///      whole-day ticket plays seven, and its boon lifts every one of them, which is what its
    ///      seven-window burn paid for. The TOP TIER is 15%, not the 25% a one-window anchor
    ///      could afford: seven windows at a quarter would have let one boon add 105,000 FLIP,
    ///      and 15% holds the whole-ticket ceiling near where the anchored quarter sat.
    ///
    ///      A SHARED base ceiling rather than three separate caps: capping each tier at 9,000
    ///      would flatten all three to the same number on a big enough return and delete the
    ///      tier spread.
    uint256 internal constant _BOON_PAYOUT_BASE_CAP = 60_000;

    /// @dev What a stored boon mask adds to an already-rounded, already-scaled bankroll payment.
    ///      Fails CLOSED: mask 0 and the unreachable 3/5/6/7 pay nothing, and a busted run pays
    ///      nothing because its payment is zero — which is also why a boon can never turn a bust
    ///      into a credit and move a settlement's `_CREDIT_UNITS` accounting.
    function _boonBonus(uint256 mask, uint256 basePaid) internal pure returns (uint256) {
        if (basePaid == 0) return 0;
        uint256 bps;
        if (mask == 1) bps = 500;
        else if (mask == 2) bps = 1000;
        else if (mask == 4) bps = 1500;
        else return 0;
        unchecked {
            uint256 base = basePaid > _BOON_PAYOUT_BASE_CAP ? _BOON_PAYOUT_BASE_CAP : basePaid;
            return (base * bps) / _BPS_DENOMINATOR;
        }
    }

    /// @dev Keep the full integer price above an explicit flag byte. Reject out-of-range
    ///      amounts and unknown action bits before shifting, including on discounted paths.
    function _tag(uint256 cost, uint256 flags) internal pure returns (uint256) {
        if (cost > type(uint248).max || flags & ~uint256(0x1F) != 0) revert BadBurnTag();
        return (cost << 8) | flags;
    }

    /// @dev Fold one settlement into its battle's scoreboard: a running (best score, the bet
    ///      holding it) pair, which is order-invariant — whatever settles last completes it, and
    ///      that IS the finalization. Nothing here ever loops, and nothing is written back to the
    ///      bet: the leader lives in this one shared word.
    /// @dev Breaks a dead-level score on the table's own word: the entrant whose tag is larger
    ///      takes the lead. A random total order rather than a running coin, so a field of any
    ///      size picks uniformly among its tied runs instead of favouring the last one to settle,
    ///      and arrival order carries no advantage at all. Replayable off-chain from the word.
    function _tieBreak(uint256 word, uint48 bound, uint64 challenger, uint64 leader) private pure returns (bool) {
        uint256 field = uint256(bound) << 64;
        return _hash3(word, TIE_TAG, field | challenger) > _hash3(word, TIE_TAG, field | leader);
    }

    function _scoreBattle(Window memory w, uint256 score, uint64 betId, uint256 word)
        internal
        returns (bool finalized)
    {
        bytes32 key = w.key;
        uint256 g = _battles[key];
        unchecked {
            g += 1 << _BG_RESOLVED_SHIFT;
            // Greater displaces outright. Dead level — same rank, same ending bankroll, same
            // ending bankroll — goes to the coin, so the last tiebreak is the dice rather than arrival
            // order. `leader == 0` is the first entrant to score, who leads unopposed.
            uint64 leader = uint64(uint32(g >> _BG_WINNER_SHIFT));
            uint256 leading = (g >> _BG_BEST_SHIFT) & _SC_BEST_MASK;
            if (score > leading || leader == 0 || (score == leading && _tieBreak(word, w.bound, betId, leader))) {
                // ONE CLEAR-AND-REPLACE over the composite and the seat holding it. Everything a
                // finalization reports about the winner — its stop, its high point, its ending
                // bankroll — is inside the composite, so a displaced leader leaves nothing behind
                // for the seat that beat it.
                g = (g & ~((_SC_BEST_MASK << _BG_BEST_SHIFT) | (uint256(_MASK32) << _BG_WINNER_SHIFT)))
                    | (score << _BG_BEST_SHIFT) | (uint256(betId) << _BG_WINNER_SHIFT);
            }
            uint256 entrants = g & _MASK32;
            // BANKED BEFORE ANYTHING LEAVES THE CONTRACT. `_payout` takes `g` by value and reads
            // no scoreboard, so committing the word here costs the same single write it always
            // did — and it means a finished field is already marked finished by the time the
            // first external credit is made, rather than while one is in flight.
            _battles[key] = g;
            if (((g >> _BG_RESOLVED_SHIFT) & _MASK32) == entrants) {
                // AND IT PAYS, here, in the same transaction that finished it. Everything a
                // payment needs was just computed to finalize the field — the winner, the boost,
                // the table's word — so a separate claim would only re-derive all of it and cost
                // the player a second transaction to collect what is already decided.
                IReadCohortLifecycle(address(this)).finalizeBattle(w, g, word);
                finalized = true;
            }
        }
    }

    /// @dev What a window pays its winner on top of the stakes, in stake units — the window's
    ///      share of the day's budget (`_windowShare`) times whichever rung the table drew.
    ///
    ///      EVERY WINDOW IS A LOTTERY, and the rung always comes off the word that SETTLES the
    ///      table. That word does not exist while entry is open, so a field forms knowing the
    ///      ceiling and the odds and nothing else; it lands the moment the table's VRF word does,
    ///      which is BEFORE a single hand is settled. The ladder averages exactly one before the
    ///      payout granule rounding, so a day spends its budget in EXPECTATION and any single
    ///      window can pay `_BOOST_MAX_MULT` — a hundred — times its share.
    /// @dev A FRACTIONAL COPY of a run's result: `floor(p * y / r)`, where `r` is the bankroll
    ///      the run actually played and `y` is capital riding alongside it. A bust has `p == 0`
    ///      and so returns nothing; a run that doubled its bankroll doubles `y` too.
    ///
    ///      Done WITHOUT a 512-bit product. `p` splits into whole copies of the bankroll and a
    ///      remainder below one, and `floor(p*y/r)` is exactly `(p/r)*y + floor((p%r)*y/r)` — so
    ///      the only multiplication left has a factor smaller than the bankroll. CHECKED on
    ///      purpose: these are the one pair of operands here that are not obviously small, and a
    ///      revert is a better answer than a payout that wrapped.
    function _ride(uint256 p, uint256 y, uint256 r) internal pure returns (uint256) {
        if (p == 0 || y == 0) return 0;
        return (p / r) * y + ((p % r) * y) / r;
    }

    /// @dev The high lane's boost for this window, in granules. The SAME rung as the main lane —
    ///      one draw off the settling word, keyed to the battle — so the high lane adds no second
    ///      source of randomness and cannot be timed apart from the main one.
    function _highBoostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            return (_highBase(w) * _boostMult(word, w.bound)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    /// @dev The high lane's rounded protocol bonus, in wei, equal for every entrant.
    function _laneBoost(Window memory w, uint256 word) internal view returns (uint256) {
        return _roundBoost(_highBoostUnits(w, word)) * _BATTLE_STAKE_UNIT;
    }

    /// @dev Fold one high seat's verdict into the sideboard, and — where it turns out to be the
    ///      lane's ONLY seat — settle the whole lane here, on that seat's own run.
    ///
    ///      A field of one is not a race. Refunding its extra bounties would hand back money the
    ///      seat chose to put at risk, and paying them out whole would pay a contest it never had
    ///      to win. So they ride the run it did make: the same dice, the same bankroll, pro rata.
    ///      The lane's boost rides with them — placed at RISK rather than paid, which is what stops a sole high roller from
    ///      being a way to draw house money down for free.
    /// @param w      The window the high seat belongs to.
    /// @param sc     The seat's settlement score, compared against the lane's running best.
    /// @param seat   The seat's dense ordinal, used as the tie-break and lane winner id.
    /// @param word   The window's settling word.
    /// @param header The seat's bet header.
    /// @param p      The seat's own settled payout, ridden pro rata against the lane's combined
    ///               extra plus boost.
    /// @return ride What the run returned on that capital; zero on a bust, and zero is expected.
    /// @return extra The bounty part of it, which is player money and therefore real action. The
    ///         boost part is protocol money and is deliberately NOT booked — recycling emitted
    ///         boost into the burn that sizes the next boost would compound on itself.
    function _foldHigh(Window memory w, uint256 sc, uint64 seat, uint256 word, uint256 header, uint256 p)
        private
        returns (uint256 ride, uint256 extra)
    {
        uint256 f = _highField[w.key];
        unchecked {
            uint256 best = (f >> _HF_SCORE_SHIFT) & _SC_BEST_MASK;
            uint64 lead = uint64((f >> _HF_WINNER_SHIFT) & _MASK32);
            // The SAME comparator the main scoreboard runs, on the SAME unscaled composite: a
            // high roller buys copies of a run, never a better one, so the money it staked must
            // not reach either ranking.
            if (sc > best || lead == 0 || (sc == best && _tieBreak(word, w.bound, seat, lead))) {
                f = (f & ~((_SC_BEST_MASK << _HF_SCORE_SHIFT) | (uint256(_MASK32) << _HF_WINNER_SHIFT)))
                    | (sc << _HF_SCORE_SHIFT) | (uint256(seat) << _HF_WINNER_SHIFT);
            }
            if (uint32(f) == 1) {
                extra = _highBounty(w);
                uint256 lane = _laneBoost(w, word);
                ride = _ride(p, extra + lane, w.bankroll);
                // The pass slice comes off the PROTOCOL's part of the ride alone, measured as its
                // own pro-rata copy — never by flooring the bounty and boost rides separately,
                // whose floors could sum away from the combined figure the seat is owed. The
                // bounty part is player money and stays liquid whole, and a Bust rides nothing
                // and so awards nothing: its protocol ride is zero and zero banks zero.
                ride -= _splitAward(
                    w.key, uint32(header), _SPLIT_SRC_HIGH_SOLE | _ride(p, lane, w.bankroll)
                );
                // The lane's final disposition, recorded in the same write the fold makes; the
                // resolve cursor is what keeps a later call from re-walking the seat.
                f |= _HF_DONE_BIT;
            }
            _highField[w.key] = f;
        }
    }

    /// @dev The base a window's boost is drawn around, in whole FLIP. FLAT — the same figure
    ///      whether three sit down or three hundred, because that is what makes a window's size
    ///      the thing turnout is measured AGAINST.
    ///
    ///      A window puts up a share of its own day's budget, and that budget is a flat base plus
    ///      a rate on the ACTION the week before it put through the table. So the lever is
    ///      turnover: a busier week buys a bigger bonus, and a quiet one shrinks back toward the
    ///      base the day is opened with regardless.
    ///
    ///      NOT a break-even argument. There is no deterministic minimum a seat burns — place
    ///      4/10 and 5/9 pay true odds, so a whole field may legally play a fair board — and the
    ///      schedule does not pretend otherwise. What actually pays for the subsidy is the
    ///      remainder deleted out of every busted run, which no term here measures.
    function _boostBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, false);
    }

    /// @dev What the HIGH lane offers this window, drawn off the day's high budget with the same
    ///      split the main one uses. No floor and no fallback quote: the high budget is funded by
    ///      what high rollers actually burned, so a day that banked none has none, and there is
    ///      nothing to advertise on a day that never opened.
    function _highBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, true);
    }

    /// @dev One window's slice of its OWN day's budget. A day that has not opened yet has nothing
    ///      banked, so the schedule quotes what it WOULD draw — a pure function of days already
    ///      settled, so a day about to open quotes exactly what it will get.
    ///
    ///      A CUSTOM battle puts up no house money at all. Its pot is the bounties its entrants
    ///      posted plus whatever anyone donated onto it — the protocol's purse backs the windows
    ///      it schedules itself, not a table someone else opened.
    function _shareOf(Window memory w, bool high) private view returns (uint256) {
        if (w.bound >= _CUSTOM_SLOT_BASE || _isJackpotSlot(w.bound)) return 0;
        unchecked {
            uint256 slot = uint256(w.bound);
            uint24 day = uint24(slot / _BONUS_SLOTS_PER_DAY);
            uint256 packed = _boostBudget[day];
            uint256 budget;
            uint256 weight;
            if (packed != 0) {
                weight = packed >> _BUDGET_W_SHIFT;
                budget = high ? _highBudget[day] : packed & _BUDGET_MASK;
            } else {
                uint256 word = _dailyWordAt(day);
                if (word == 0) return 0;
                weight = _routineWeight(word);
                (uint256 m, uint256 h) = _drawBudgets(day);
                // The HIGH budget is whole and unsplit. The main one is quoted at the ladder half
                // it will be stored as, through the same helper the opening uses.
                if (high) budget = h;
                else (budget,) = _splitMainBudget(m);
            }
            // `slot % _BONUS_SLOTS_PER_DAY` names the period plus one — zero is the gap between
            // days — so the period this window shares on is one below it.
            return _windowShare(budget, weight, (slot % _BONUS_SLOTS_PER_DAY) - 1, w.tier);
        }
    }

    /// @dev Fold one settle batch's staked bankroll into its day. Unchecked: the figure only ever
    ///      sizes a later bonus, and no real table can approach a uint256.
    function _bookDay(uint24 day, uint256 staked, uint256 high) internal {
        unchecked {
            _dayStaked[day] += staked + (high << _DAY_HIGH_SHIFT);
        }
    }

    /// @dev THE DAY'S RAW ALLOCATION: `_BASE_MAIN_BUDGET` plus `_BOOST_ACTION_BPS` of the average
    ///      daily action of the seven days before `day`. The base is ADDED, never a floor — a day
    ///      that banked real action is paid for it ON TOP of the base, not instead of it. Drawn
    ///      ONCE, when the day opens, so every window of it offers the same figure and a window
    ///      armed days later still pays what its own day advertised.
    ///
    ///      `mainBudget` here is the RAW main figure, BEFORE the progressive split. Nothing may
    ///      read it as a ladder without passing it through `_splitMainBudget` first. The high
    ///      budget is final as returned.
    function _drawBudgets(uint24 day) internal view returns (uint256 mainBudget, uint256 highBudget) {
        unchecked {
            uint256 er;
            uint256 eh;
            for (uint256 i = 1; i <= _BOOST_ACTION_WINDOW_DAYS; ++i) {
                if (day < i) break;
                uint24 d = day - uint24(i);
                uint256 action = _dayStaked[d];
                uint256 high = action >> _DAY_HIGH_SHIFT;
                // The two lanes are rated the same and NEVER share an amount: what a high seat put
                // up is in the high half and taken back out of the total, so no wei of action can
                // feed both components.
                er += ((uint256(uint128(action)) - high) * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
                eh += (high * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
            }
            // AVERAGED OVER THE WINDOW, NEVER SUMMED. A budget is drawn EVERY day, off a window
            // that overlaps the six before it — so handing one day the whole week's figure would
            // let every unit of action fund seven budgets and put emission at seven times what
            // the rule intends. The divisor is the window itself, so widening the window changes
            // how smooth the figure is and nothing about its level.
            er /= _BOOST_ACTION_WINDOW_DAYS;
            eh /= _BOOST_ACTION_WINDOW_DAYS;

            // THE HIGH LANE'S COMPONENT SPLITS TWO WAYS: two parts in five to the main boost and
            // the other three to the lane that earned them. Floored on the main side, which puts
            // the one-wei split remainder with the high lane.
            uint256 fromHigh = (eh * _HIGH_MAIN_NUM) / _HIGH_MAIN_DEN;
            highBudget = eh - fromHigh;
            // The base rides the MAIN lane alone. Subsidising a high lane nobody played would
            // print house money against action that was never put through it.
            //
            // RAW, and the only place the raw figure exists. Both callers split it through
            // `_splitMainBudget` before anything reads it as a ladder.
            mainBudget = _BASE_MAIN_BUDGET + er + fromHigh;
        }
    }

    /// @dev THE SPLIT, and the one statement of it. Half the day's raw main allocation is the
    ///      ladder its seven windows share; the other half is banked in the progressive. Floored
    ///      on the ladder side, so the odd wei goes to the pool and the two ALWAYS sum back to the
    ///      raw figure.
    ///
    ///      Both callers go through here — the day that opens and stores the ladder, and the quote
    ///      a window gives before its day has opened — which is what stops a pre-open quote from
    ///      advertising twice what the ladder will actually hold.
    function _splitMainBudget(uint256 rawMain) internal pure returns (uint256 ladder, uint256 progressive) {
        unchecked {
            ladder = rawMain / 2;
            progressive = rawMain - ladder;
        }
    }

    /// @dev THE LADDER. In QUARTERS, drawn in THOUSANDTHS because the top rung is too rare to
    ///      name in hundredths, and to a mean of EXACTLY one:
    ///
    ///        76.8%   a quarter of the share      1 quarter    carries 19.2% of the budget
    ///        20.8%   the share itself            4            carries 20.8%
    ///         2.0%   TEN times it               40            carries 20.0%
    ///         0.4%   A HUNDRED times it        400            carries 40.0%
    ///
    ///      `768(1) + 208(4) + 20(40) + 4(400) = 4000` quarters over 1,000 draws.
    ///
    ///      Four rungs, each an order up from the last, and each carrying about a fifth of the
    ///      budget except the top, which carries twice that. Three windows in four pay a quarter
    ///      of their share; the hundred-times rung lands about once in every 250 windows, which
    ///      across a seven-window day is roughly once a month. The mean being exactly one is what
    ///      keeps a day's budget the thing actually spent IN EXPECTATION while no single window is
    ///      capped by it. Drawn off the word that SETTLES the table and keyed to the battle, so it
    ///      cannot be read while anyone can still enter.
    ///
    ///      THE REVEAL IS A CLIENT CONCERN, and needs nothing from here. The rung lands the
    ///      instant the table's VRF word does — after entry shuts, before any run is settled — and
    ///      everything it is drawn from is already public: `CrapsBonusArmed` carries the battle
    ///      key and the table index, `_wordAt` the word, `boostBudgetOf` the day's budget and
    ///      `CrapsBonusDonated` the donations. So a front end spins its own wheel off the chain's own
    ///      inputs rather than paying for a view that restates them.
    /// @dev The scheduled window's immutable slot identifies its boost draw. Its monetary
    ///      terms and match key price/locate the battle but cannot select another multiplier.
    function _boostMult(uint256 word, uint48 bound) internal pure returns (uint256) {
        unchecked {
            uint256 roll = _hash3(word, bound, BOOST_TAG) % 1000;
            if (roll < 768) return 1;
            if (roll < 976) return 4;
            if (roll < 996) return 40;
            return 400;
        }
    }

    /// @dev Collapse a boost, in granules, onto the figure it is actually paid at.
    function _roundBoost(uint256 units) internal pure returns (uint256) {
        if (units <= _BOOST_ROUND_ABOVE) return units;
        unchecked {
            return ((units + _BOOST_ROUND_STEP / 2) / _BOOST_ROUND_STEP) * _BOOST_ROUND_STEP;
        }
    }



    /// @dev The progressive's award accounting. The caller supplies the already-qualified share;
    ///      all pool debits and pass/liquid splits live here.


}
