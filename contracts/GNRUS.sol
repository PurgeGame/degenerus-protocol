// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";

/// @notice Minimal interface for sDGNRS balance snapshots used by GNRUS governance.
interface ISDGNRSSnapshot {
    /// @notice Get sDGNRS balance for an address.
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal interface for DegenerusGame donation-facing functions used by GNRUS.
interface IDegenerusGameDonations {
    /// @notice Claim accumulated ETH winnings for a player.
    function claimWinnings(address player) external;
    /// @notice View claimable ETH winnings for a player.
    function claimableWinningsOf(address player) external view returns (uint256);
}

/// @notice Minimal interface for DegenerusVault owner check used by GNRUS governance.
interface IDegenerusVaultOwner {
    /// @notice Check if an address is the vault owner (>50.1% DGVE).
    function isVaultOwner(address account) external view returns (bool);
}

/**
 * @title DegenerusDonations (GNRUS)
 * @notice Soulbound GNRUS token with proportional burn-for-ETH/stETH redemption
 *         and per-level sDGNRS-weighted governance controlling GNRUS distribution.
 * @dev GNRUS is minted entirely to this contract at deploy. Each level, the winning
 *      charity slot's recipient receives 2% of the remaining unallocated GNRUS.
 *      GNRUS holders can burn tokens to redeem a proportional share of both ETH and stETH
 *      held by this contract. Funding arrives via game distributions.
 *
 * ARCHITECTURE:
 * - 1T GNRUS minted to address(this) at deploy (unallocated pool)
 * - Each level, governance distributes 2% of remaining unallocated GNRUS to winning recipient
 * - GNRUS holders burn tokens to claim proportional ETH + stETH
 * - At GAMEOVER: all unallocated GNRUS burned, game pushes final ETH/stETH
 * - Soulbound: transfer, transferFrom, approve all revert
 */
contract GNRUS {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();

    /// @notice Thrown when transfer, transferFrom, or approve is called (soulbound)
    error TransferDisabled();

    /// @notice Thrown when ETH or stETH transfer fails
    error TransferFailed();

    /// @notice Thrown when burn amount is 0 or below minimum
    error InsufficientBurn();

    /// @notice Thrown when burnAtGameOver has already been called
    error AlreadyFinalized();

    /// @notice Thrown when a time-locked recovery action is called before its delay elapses
    error TooEarly();

    /// @notice Thrown when a post-sweep recovery action is called before the final sweep has run
    error NotSwept();

    /// @notice Thrown when slot index is >= MAX_ACTIVE_SLOTS
    error InvalidSlot();

    /// @notice Thrown when setCharity is called with recipient=0 on an already-empty slot with no pending edit
    error SlotAlreadyEmpty();

    /// @notice Thrown when setCharity attempts to replace or remove a filled locked slot (0, 1, or 2)
    error SlotLocked();

    /// @notice Thrown by vote() when the slot fails a state-based pre-condition.
    /// @dev Reason codes: REJECT_EMPTY_SLOT (0), REJECT_ALREADY_VOTED (1), REJECT_ZERO_WEIGHT (2)
    error VoteRejected(uint8 reason);

    /// @notice Thrown by pickCharity() when the level argument fails a state-based pre-condition.
    /// @dev Reason code: REJECT_LEVEL_NOT_ACTIVE (0)
    error PickCharityRejected(uint8 reason);

    /// @notice Thrown by vote() when the targeted slot's current recipient equals the previous level's winner.
    /// @dev Prevents consecutive wins by the same recipient. Storage slot lastWinningRecipient is written
    ///      by pickCharity() in the distribution-paid path and read here on every vote(). Skipped levels
    ///      do not advance the block — a skipped level retains the prior level's winner-block state.
    error PreviousWinnerNotVotable();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted on mint, burn, and governance distribution (indexer compat)
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when GNRUS is burned for proportional ETH + stETH
    event Burn(address indexed burner, uint256 gnrusAmount, uint256 ethOut, uint256 stethOut);

    /// @notice Emitted when a vote is cast on a charity slot
    event Voted(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight);

    /// @notice Emitted when a level resolves with a winning slot
    event LevelResolved(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed);

    /// @notice Emitted when a level resolves with no eligible winner
    event LevelSkipped(uint24 indexed level);

    /// @notice Emitted when gameover finalization burns unallocated GNRUS (ethClaimed/stethClaimed always 0; final ETH/stETH is pushed to the vault/sDGNRS/GNRUS by the game, not claimed here)
    event GameOverFinalized(uint256 gnrusBurned, uint256 ethClaimed, uint256 stethClaimed);

    /// @notice Emitted when the vault owner sweeps unredeemed GNRUS residual to the vault after the recovery delay
    event ResidualSweptToVault(uint256 ethSwept, uint256 stethSwept);

    /// @notice Emitted when setCharity writes directly to current slate (instant-apply branch)
    event CharityApplied(uint8 indexed slot, address indexed recipient);

    /// @notice Emitted when setCharity writes to pending edit queue (queue branch)
    event CharityQueued(uint8 indexed slot, address indexed recipient);

    /// @notice Emitted per applied pending edit during pickCharity flush. recipient == address(0) signals a flush-removed slot.
    event CharityFlushed(uint8 indexed slot, address indexed recipient);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "GNRUS Donations";

    /// @notice Token symbol
    string public constant symbol = "GNRUS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of GNRUS tokens
    uint256 public totalSupply;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

    // =====================================================================
    //                      GOVERNANCE STATE
    // =====================================================================

    /// @notice Current governance level
    uint24 public currentLevel;

    /// @notice Whether burnAtGameOver has been called
    bool public finalized;

    /// @notice Bitmap of active slots in the current slate; bit `i` set ⇔ `currentSlate[i] != address(0)`
    uint32 public currentActiveBitmap;

    /// @notice Bitmap of slots with a pending edit; bit `i` set ⇔ a pending edit exists for slot `i`
    uint32 public pendingEditSet;

    /// @notice Timestamp of the final sweep (set once by onFinalSweep); anchors the residual-recovery delay
    uint40 public sweptAt;

    // ^ currentLevel (3) + finalized (1) + currentActiveBitmap (4) + pendingEditSet (4) + sweptAt (5) = 17 bytes, one slot, 15 free

    /// @notice Whether a voter has already voted for a given (level, voter, slot) tuple
    mapping(uint24 => mapping(address => mapping(uint8 => bool))) public hasVoted;

    /// @notice Current-level charity slate. Index = uint8 slot id (0..19). Address-only, no metadata.
    /// @dev `private` — access is exposed only via the explicit `getCharity(uint8)` view (with its own bounds check), not an auto-generated array getter.
    address[20] private currentSlate;

    /// @notice Pending edit queue. Recipient value at slot index; sentinel via `pendingEditSet` bitmap.
    /// @dev bit set + value zero  = pending-remove; bit set + value !zero = pending-replace; bit clear = no
    ///      pending edit. Values are NOT zeroed when a bit clears — every read is gated on the bit, so a
    ///      stale value is unobservable, and a later re-queue overwrites it (nonzero→nonzero SSTORE).
    mapping(uint8 => address) private pendingEdit;

    /// @notice Per-(level, slot) accumulator for approve weight cast via vote(). Old-level entries persist deliberately.
    /// @dev Old-level entries are never wiped — clearing 20 cold SSTOREs per level would burn gas for no
    ///      functional benefit, and indexers gain free historical query as a side-benefit.
    mapping(uint24 => mapping(uint8 => uint256)) public slotApproveWeight;

    /// @notice Recipient that won the most recent paid level. Used by vote() to block consecutive wins.
    /// @dev Written by pickCharity() ONLY when the level distributed (paid branch). Skipped levels leave
    ///      the value unchanged so the previous-winner block survives a skipped level. Initialized to
    ///      address(0) — no slot is blocked at deploy time.
    address public lastWinningRecipient;

    // =====================================================================
    //                            CONSTANTS
    // =====================================================================

    /// @notice Initial GNRUS supply: 1 trillion tokens
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @notice Minimum burn amount: 1 GNRUS
    uint256 private constant MIN_BURN = 1e18;

    /// @notice Delay after the final sweep before the vault owner may recover unredeemed GNRUS
    ///         residual: a 3-year holder grace period measured from the sweep.
    uint256 private constant RESIDUAL_RECOVERY_DELAY = 3 * 365 days;

    /// @notice Distribution per level: 2% of remaining unallocated GNRUS
    uint16 private constant DISTRIBUTION_BPS = 200;

    /// @notice BPS denominator
    uint16 private constant BPS_DENOM = 10_000;

    /// @notice Number of locked foundational slots — slots 0..2 are immutable once filled
    uint8 private constant LOCKED_SLOTS = 3;

    /// @notice Maximum number of simultaneously-active charity slots
    uint8 private constant MAX_ACTIVE_SLOTS = 20;

    /// @notice VoteRejected reason: slot is empty in current slate
    uint8 private constant REJECT_EMPTY_SLOT = 0;

    /// @notice VoteRejected reason: voter has already voted on this (level, slot)
    uint8 private constant REJECT_ALREADY_VOTED = 1;

    /// @notice VoteRejected reason: voter has zero whole-token sDGNRS balance
    uint8 private constant REJECT_ZERO_WEIGHT = 2;

    /// @notice PickCharityRejected reason: level argument does not match currentLevel
    uint8 private constant REJECT_LEVEL_NOT_ACTIVE = 0;

    // =====================================================================
    //                       IMMUTABLE REFERENCES
    // =====================================================================

    /// @dev stETH token for proportional redemption on burn
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @dev sDGNRS token for governance vote weight snapshots
    ISDGNRSSnapshot private constant sdgnrs = ISDGNRSSnapshot(ContractAddresses.SDGNRS);

    /// @dev Game contract for winnings claims backing redemptions
    IDegenerusGameDonations private constant game = IDegenerusGameDonations(ContractAddresses.GAME);

    /// @dev Vault contract for owner (>50.1% DGVE) checks
    IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);

    // =====================================================================
    //                            MODIFIERS
    // =====================================================================

    /// @notice Restricts access to the game contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    // =====================================================================
    //                           CONSTRUCTOR
    // =====================================================================

    /// @notice Deploys GNRUS with 1T supply minted to the contract itself (unallocated pool)
    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[address(this)] = INITIAL_SUPPLY;
        emit Transfer(address(0), address(this), INITIAL_SUPPLY);
    }

    // =====================================================================
    //                      SOULBOUND ENFORCEMENT
    // =====================================================================

    /// @notice Disabled -- GNRUS is soulbound
    function transfer(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    /// @notice Disabled -- GNRUS is soulbound
    function transferFrom(address, address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    /// @notice Disabled -- GNRUS is soulbound
    function approve(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    // =====================================================================
    //                       BURN-FOR-REDEMPTION
    // =====================================================================

    /// @notice Burn GNRUS to receive proportional ETH and stETH
    /// @dev Burns `amount` GNRUS from msg.sender and transfers proportional shares of
    ///      both ETH and stETH held by this contract. Last-holder sweep: if the caller's
    ///      entire balance equals `amount` or all externally-held GNRUS equals `amount`,
    ///      sweeps the full caller balance to avoid dust.
    ///      CEI: state updates and events before external transfers. stETH before ETH (ETH last).
    /// @param amount Amount of GNRUS to burn (minimum 1 GNRUS)
    function burn(uint256 amount) external {
        if (amount < MIN_BURN) revert InsufficientBurn();

        uint256 supply = totalSupply;
        address burner = msg.sender;
        uint256 burnerBal = balanceOf[burner];

        // Last-holder sweep: if burning all remaining non-contract balance,
        // use the full balance even if slightly above `amount`
        if (burnerBal == amount || (supply - balanceOf[address(this)]) == amount) {
            amount = burnerBal; // sweep
        }

        _redeemTo(burner, amount, burnerBal, supply, burner);
    }

    /// @dev Shared proportional-redemption core. Burns `amount` GNRUS from `account` and pays the
    ///      proportional ETH + stETH share to `recipient`. Backing = on-hand ETH + stETH plus the
    ///      game-side claimable (less the 1-wei sentinel); the game is drawn from only when on-hand
    ///      is short. CEI: supply/balance are updated and events emitted before any external value
    ///      transfer; the only pre-burn external call is game.claimWinnings, which cannot write GNRUS
    ///      balances, so `acctBal` (read by the caller) is still fresh at the burn. Checked
    ///      subtraction — the underflow revert is the over-burn guard.
    function _redeemTo(address account, uint256 amount, uint256 acctBal, uint256 supply, address recipient) private {
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimable = game.claimableWinningsOf(address(this));
        if (claimable > 1) { unchecked { claimable -= 1; } } else { claimable = 0; }

        uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;

        // Pay from on-hand first (ETH-preferred), pull remainder from game
        if (owed > ethBal + stethBal) {
            game.claimWinnings(address(this));
            ethBal = address(this).balance;
            stethBal = steth.balanceOf(address(this));
        }

        uint256 ethOut = owed <= ethBal ? owed : ethBal;
        uint256 stethOut = owed - ethOut;

        balanceOf[account] = acctBal - amount;
        unchecked { totalSupply = supply - amount; }

        emit Transfer(account, address(0), amount);
        emit Burn(account, amount, ethOut, stethOut);

        // stETH transfer first (ERC20), ETH transfer last (raw call — CEI)
        if (stethOut != 0) {
            if (!steth.transfer(recipient, stethOut)) revert TransferFailed();
        }
        if (ethOut != 0) {
            (bool ok,) = recipient.call{value: ethOut}("");
            if (!ok) revert TransferFailed();
        }
    }

    // =====================================================================
    //                        GAMEOVER HANDLING
    // =====================================================================

    /// @notice Finalize at gameover: burn all remaining unallocated GNRUS
    /// @dev Only callable by the game contract. Can only be called once.
    ///      The game contract pushes final ETH/stETH to VAULT, sDGNRS, and GNRUS
    ///      during gameover processing. This function handles the GNRUS-side cleanup
    ///      of burning unallocated tokens.
    function burnAtGameOver() external onlyGame {
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        uint256 unallocated = balanceOf[address(this)];
        if (unallocated != 0) {
            balanceOf[address(this)] = 0;
            unchecked { totalSupply -= unallocated; }
            emit Transfer(address(this), address(0), unallocated);
        }

        emit GameOverFinalized(unallocated, 0, 0);
    }

    /// @notice Record the final-sweep timestamp; the game calls this once from handleFinalSweep when
    ///         the terminal ETH/stETH has been distributed to sDGNRS, GNRUS, and the vault.
    /// @dev onlyGame. Anchors the post-sweep recovery gates (vaultRedeemFor availability and the
    ///      3-year sweepResidualToVault delay). The game's final sweep is one-shot (GO_SWEPT latch).
    function onFinalSweep() external onlyGame {
        sweptAt = uint40(block.timestamp);
    }

    // =====================================================================
    //                     POST-GAMEOVER RECOVERY
    // =====================================================================

    /// @notice Redeem a holder's entire GNRUS on their behalf, paying the holder its full
    ///         proportional ETH + stETH share.
    /// @dev Vault-owner-only, post-gameOver. Lets a holder that never calls burn() itself (a lost or
    ///      contract address, or a charity that has wound down) be made whole so its share is not left
    ///      stranded. Value-preserving — the holder receives exactly what burn() would pay it; the
    ///      vault owner cannot extract the holder's value. Reverts if the holder's ETH sink rejects.
    /// @param holder Address whose full GNRUS balance is redeemed to itself
    function vaultRedeemFor(address holder) external {
        if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();
        if (sweptAt == 0) revert NotSwept();

        uint256 supply = totalSupply;
        uint256 bal = balanceOf[holder];
        if (bal == 0) revert InsufficientBurn();

        _redeemTo(holder, bal, bal, supply, holder);
    }

    /// @notice Sweep any ETH and stETH still held by GNRUS to the vault, after a long recovery delay.
    /// @dev Vault-owner-only. Recovers charity backing left unredeemed once the game is long over —
    ///      the final-sweep residual pushed when no holders remained, or the share of a holder that
    ///      never redeemed. Gated on gameOver plus RESIDUAL_RECOVERY_DELAY (the 30-day final-sweep
    ///      window plus a 3-year holder grace period), so holders have a multi-year window to redeem
    ///      (directly or via vaultRedeemFor) before the residual is reclaimed.
    function sweepResidualToVault() external {
        if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();
        if (sweptAt == 0) revert NotSwept();
        if (block.timestamp < uint256(sweptAt) + RESIDUAL_RECOVERY_DELAY) revert TooEarly();

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));

        // stETH transfer first (ERC20), ETH transfer last (raw call — CEI)
        if (stethBal != 0) {
            if (!steth.transfer(ContractAddresses.VAULT, stethBal)) revert TransferFailed();
        }
        if (ethBal != 0) {
            (bool ok,) = ContractAddresses.VAULT.call{value: ethBal}("");
            if (!ok) revert TransferFailed();
        }

        emit ResidualSweptToVault(ethBal, stethBal);
    }

    // =====================================================================
    //                    GOVERNANCE -- ADMIN OPS
    // =====================================================================

    /// @notice Vault-owner-only single admin entry point covering charity slate add/replace/remove.
    /// @dev Branches:
    ///      - Instant-apply (writes directly to current slate) when `currentSlate[slot] == address(0)`.
    ///      - Queue (writes to pending edit, applied at next pickCharity flush) when `currentSlate[slot] != address(0)`.
    ///      Pass `recipient == address(0)` to remove a slot. Locked slots (0/1/2) cannot be replaced or
    ///      removed once filled — first fill is an irrevocable commitment.
    /// @param slot Slot index in the current slate (0..19)
    /// @param recipient Charity recipient address; pass address(0) to remove
    function setCharity(uint8 slot, address recipient) external {
        // 1. Vault-owner gate
        if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();

        // 2. InvalidSlot
        if (slot >= MAX_ACTIVE_SLOTS) revert InvalidSlot();

        // 3. Locked-slot guard (BEFORE branch dispatch — slots 0/1/2 cannot be mutated through queue either)
        address current = currentSlate[slot];
        if (slot < LOCKED_SLOTS && current != address(0)) revert SlotLocked();

        uint32 slotMask = uint32(1) << slot;

        // 4. Branch dispatch
        if (current == address(0)) {
            // Instant-apply branch (or removal special case if recipient == 0)
            if (recipient == address(0)) {
                // Removal special case: empty current + zero recipient.
                // SlotAlreadyEmpty fires only when no pending edit exists for this slot.
                // If a pending edit IS set, this call cancels the queued add: clear the bitmap bit
                // (the stale mapping value is never read while the bit is clear).
                if ((pendingEditSet & slotMask) == 0) revert SlotAlreadyEmpty();
                pendingEditSet &= ~slotMask;
                emit CharityQueued(slot, address(0));
                return;
            }
            // Apply. The 20-slot cap is structural: the slot < MAX_ACTIVE_SLOTS guard above bounds
            // every bitmap bit to positions 0..19, so no post-flush slate can exceed the cap.
            currentSlate[slot] = recipient;
            currentActiveBitmap = currentActiveBitmap | slotMask;
            emit CharityApplied(slot, recipient);
        } else {
            // Queue branch (current != 0; locked-slot guard already passed → slot in 3..19)
            // Apply (mapping write + bitmap bit set; if bit already set, this is a pending-overwrite — replace value)
            pendingEdit[slot] = recipient;
            pendingEditSet = pendingEditSet | slotMask;
            emit CharityQueued(slot, recipient);
        }
    }

    /// @dev Compose the future currentActiveBitmap as if all pending edits flushed.
    ///      For each set bit in pendingEditSet: pending value zero  → clear bit (pending-remove);
    ///                                            pending value !zero → set bit (pending-add/replace).
    /// @return future The post-flush currentActiveBitmap
    function _flushedBitmap() private view returns (uint32 future) {
        future = currentActiveBitmap;
        uint32 pSet = pendingEditSet;
        for (uint8 i; i < MAX_ACTIVE_SLOTS;) {
            uint32 mask_i = uint32(1) << i;
            if ((pSet & mask_i) != 0) {
                if (pendingEdit[i] == address(0)) {
                    future = future & ~mask_i;
                } else {
                    future = future | mask_i;
                }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Population count (Hamming weight) of a uint32. Constant-gas via inline-asm.
    /// @param x The 32-bit value to popcount
    /// @return count Number of set bits in `x` (0..32)
    function _popcount32(uint32 x) private pure returns (uint8 count) {
        // Hamming-weight algorithm (parallel bit-counting).
        // Reference: https://en.wikipedia.org/wiki/Hamming_weight (popcount_3)
        assembly {
            let v := and(x, 0xFFFFFFFF)
            v := sub(v, and(shr(1, v), 0x55555555))
            v := add(and(v, 0x33333333), and(shr(2, v), 0x33333333))
            v := and(add(v, shr(4, v)), 0x0F0F0F0F)
            v := mul(v, 0x01010101)
            count := and(shr(24, v), 0xFF)
        }
    }

    // =====================================================================
    //                          VIEW HELPERS
    // =====================================================================

    /// @notice Get the recipient at a given current-slate slot
    /// @param slot The slot index (0..19)
    /// @return recipient The address at the slot, or address(0) if empty
    function getCharity(uint8 slot) external view returns (address recipient) {
        if (slot >= MAX_ACTIVE_SLOTS) revert InvalidSlot();
        return currentSlate[slot];
    }

    /// @notice Enumerate all active charity slots as paired arrays
    /// @return slots The slot indices that hold a non-zero recipient (length = activeCount())
    /// @return recipients The recipients at those slots (recipients[i] is the recipient at slots[i])
    function getActiveSlots() external view returns (uint8[] memory slots, address[] memory recipients) {
        uint32 bitmap = currentActiveBitmap;
        uint8  len    = _popcount32(bitmap);
        slots      = new uint8[](len);
        recipients = new address[](len);
        uint8 j;
        for (uint8 i; i < MAX_ACTIVE_SLOTS;) {
            if ((bitmap & (uint32(1) << i)) != 0) {
                slots[j]      = i;
                recipients[j] = currentSlate[i];
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /// @notice Enumerate all pending charity edits as paired arrays
    /// @dev recipients[i] == address(0) signals a pending-remove for slots[i] (will clear currentSlate[slot] on flush).
    /// @return slots The slot indices with a pending edit (length = popcount of pendingEditSet)
    /// @return recipients The pending recipient values; address(0) means pending-remove
    function getPendingEdits() external view returns (uint8[] memory slots, address[] memory recipients) {
        uint32 bitmap = pendingEditSet;
        uint8  len    = _popcount32(bitmap);
        slots      = new uint8[](len);
        recipients = new address[](len);
        uint8 j;
        for (uint8 i; i < MAX_ACTIVE_SLOTS;) {
            if ((bitmap & (uint32(1) << i)) != 0) {
                slots[j]      = i;
                recipients[j] = pendingEdit[i];
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /// @notice Count of active slots in the current slate
    /// @return count Number of slots with a non-zero recipient (0..20)
    function activeCount() external view returns (uint8 count) {
        return _popcount32(currentActiveBitmap);
    }

    /// @notice Count of active slots after pending edits flush (current ± all pending edits applied)
    /// @return count Number of slots with a non-zero recipient post-flush (0..20)
    function activeCountAfterFlush() external view returns (uint8 count) {
        return _popcount32(_flushedBitmap());
    }

    // =====================================================================
    //                       GOVERNANCE -- VOTE
    // =====================================================================

    /// @notice Cast a vote toward a charity slot in the current level.
    /// @dev Permissionless. Vote weight = `sdgnrs.balanceOf(msg.sender) / 1e18` (no bonus, no threshold).
    ///      Voter may vote on multiple slots independently per level — each (level, voter, slot) tuple
    ///      is tracked separately via `hasVoted[level][voter][slot]`.
    ///      Locked slots (0/1/2) accept votes normally — the locked-slot guard lives exclusively in
    ///      `setCharity`. Voters CAN vote on locked slots once filled.
    ///      CEI-clean: the only external interaction (`sdgnrs.balanceOf`) is a STATICCALL view BEFORE
    ///      state writes; no callback surface.
    /// @param slot The current-slate slot index (0..MAX_ACTIVE_SLOTS-1) to vote for
    function vote(uint8 slot) external {
        // 1. Slot bounds check (cheapest — calldata read + compare; shares the InvalidSlot error)
        if (slot >= MAX_ACTIVE_SLOTS) revert InvalidSlot();

        // 2. Empty-slot rejection (one cold SLOAD)
        if (currentSlate[slot] == address(0)) revert VoteRejected(REJECT_EMPTY_SLOT);

        // 2b. Previous-winner rejection (one cold SLOAD on lastWinningRecipient; reuses the
        //     currentSlate[slot] read from step 2 above — same storage-array slot, no intervening
        //     write, so the optimizer collapses the duplicate SLOAD).
        if (currentSlate[slot] == lastWinningRecipient) revert PreviousWinnerNotVotable();

        // 3. Already-voted rejection (one cold SLOAD on hasVoted[level][voter][slot])
        uint24 level = currentLevel;
        address voter = msg.sender;
        if (hasVoted[level][voter][slot]) revert VoteRejected(REJECT_ALREADY_VOTED);

        // 4. Zero-weight rejection (cross-contract STATICCALL — fires LAST among rejection checks
        //    so sad-path callers don't pay for the indirect call)
        uint256 weight = sdgnrs.balanceOf(voter) / 1e18;
        if (weight == 0) revert VoteRejected(REJECT_ZERO_WEIGHT);

        // 5. State writes — hasVoted bit set, slotApproveWeight accumulator incremented
        hasVoted[level][voter][slot] = true;
        slotApproveWeight[level][slot] += weight;

        // 6. Emit
        emit Voted(level, slot, voter, weight);
    }

    // =====================================================================
    //                     GOVERNANCE -- RESOLVE
    // =====================================================================

    /// @notice Atomically resolve a level: pick winner from CURRENT slate, distribute 2% of unallocated GNRUS, then flush queued edits for next level.
    /// @dev Caller must be the game contract (onlyGame). Operation is atomic per call:
    ///      (1) Argument validation (level matches currentLevel). This alone enforces idempotence:
    ///          currentLevel only ever advances (sole writer is step 2, strictly increasing), so a
    ///          resolved level can never match again.
    ///      (2) currentLevel = level + 1 SET FIRST so state locks before any further work (zero external
    ///          calls in the rest of the function, so re-entrancy is impossible by absence of callable surface).
    ///      (3) Winner phase against CURRENT (pre-flush) slate: iterate slots 0..MAX_ACTIVE_SLOTS-1 with strict `>`
    ///          so ties resolve to lowest active slot index.
    ///      (4) Distribution math: 2% of unallocated GNRUS via BPS.
    ///      (5) Apply distribution iff some active slot has weight AND distribution > 0:
    ///          balanceOf write + Transfer event + LevelResolved event + lastWinningRecipient updated to the
    ///          paid recipient. The lastWinningRecipient write is conditional on the paid branch only — a
    ///          skipped level leaves the prior winner block unchanged.
    ///      (6) Flush phase — apply each pendingEdit to current slate; emit CharityFlushed per-edit; clear
    ///          pendingEditSet. Runs AFTER payout so queued edits cast during level L take effect for level
    ///          L+1, not L. The vault-owner cannot redirect votes already cast for the current level by
    ///          queueing a recipient swap mid-level.
    ///      (7) Terminal LevelSkipped emit when the level was not paid (single emission per call).
    /// @param level The level to resolve (must equal currentLevel).
    function pickCharity(uint24 level) external onlyGame {
        // 1. Argument validation — currentLevel only ever advances (sole writer is step 2 below,
        //    strictly increasing), so this check alone enforces once-per-level resolution.
        if (level != currentLevel) revert PickCharityRejected(REJECT_LEVEL_NOT_ACTIVE);

        // 2. Advance currentLevel FIRST — locks state before winner/distribution/flush.
        currentLevel = level + 1;

        // 3. Winner phase against CURRENT (pre-flush) slate — strict `>` so ties resolve to lowest slot.
        uint32 bitmap = currentActiveBitmap;
        uint8 bestSlot = type(uint8).max;
        uint256 bestWeight = 0;
        uint32 mask = 1;
        for (uint8 i; i < MAX_ACTIVE_SLOTS;) {
            if ((bitmap & mask) != 0) {
                uint256 w = slotApproveWeight[level][i];
                if (w > bestWeight) {
                    bestWeight = w;
                    bestSlot = i;
                }
            }
            unchecked { ++i; mask <<= 1; }
        }

        // 4. Distribution math — 2% of remaining unallocated GNRUS.
        uint256 unallocated = balanceOf[address(this)];
        uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;

        // 5. Apply distribution iff (some active slot has weight) AND (distribution > 0).
        //    bestSlot is only assigned inside the bitmap-gated branch, so bestSlot != max
        //    implies the current slate is non-empty.
        bool paid = (bestSlot != type(uint8).max) && (distribution != 0);
        if (paid) {
            address recipient = currentSlate[bestSlot];
            unchecked { balanceOf[address(this)] = unallocated - distribution; }
            balanceOf[recipient] += distribution;
            lastWinningRecipient = recipient;
            emit Transfer(address(this), recipient, distribution);
            emit LevelResolved(level, bestSlot, recipient, distribution);
        }

        // 6. Flush phase — runs AFTER payout so queued edits during level L apply to L+1, not L.
        //    Invariant: flush MUST NOT revert (setCharity validates every queued edit up front).
        //    Skipped entirely when no edits are pending (the loop would be a no-op and both writes
        //    would rewrite their current values). pendingEdit values are left in place: the
        //    pendingEditSet zeroing below clears every gate atomically, so stale values are
        //    unobservable, and skipping the deletes keeps advance-chain execution gas down
        //    (refunds do not reduce execution counted against the block ceiling).
        uint32 pSet = pendingEditSet;
        if (pSet != 0) {
            uint32 mask_i = 1;
            for (uint8 i; i < MAX_ACTIVE_SLOTS;) {
                if ((pSet & mask_i) != 0) {
                    address pendingValue = pendingEdit[i];
                    currentSlate[i] = pendingValue;
                    if (pendingValue == address(0)) {
                        bitmap = bitmap & ~mask_i;
                    } else {
                        bitmap = bitmap | mask_i;
                    }
                    emit CharityFlushed(i, pendingValue);
                }
                unchecked { ++i; mask_i <<= 1; }
            }
            currentActiveBitmap = bitmap;
            pendingEditSet = 0;
        }

        // 7. Terminal event in the not-paid branch (paid branch already emitted LevelResolved at step 5).
        if (!paid) {
            emit LevelSkipped(level);
        }
    }

    // =====================================================================
    //                         RECEIVE FUNCTION
    // =====================================================================

    /// @notice Accept ETH from game claimWinnings and direct deposits
    receive() external payable {}
}
