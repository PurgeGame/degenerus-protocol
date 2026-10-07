// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {BitPackingLib} from "../../../contracts/libraries/BitPackingLib.sol";
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @title BoxCreationHandler — drives every box-creating entrypoint for the FUZZ-04 box-queue invariant
/// @notice Every box purchase appends ONE complete entry to the write buffer's box queue, which
///         mineFlip()'s human-box stage settles in FIFO order from `boxCursor` once the buffer is
///         sealed and its word published. The creating entrypoints this handler drives:
///           - mint-with-lootbox purchase  (MintModule: one custom box, appended by `_appendBoxOrder`)
///           - whale / lazy / deity pass   (WhaleModule -> LootboxModule.recordCoverBox: one entry,
///                                          one custom box per pass bought)
///           - presale box                 (MintModule._buyPresaleBoxFor: a presale-only entry)
///
///         Each creating call is checked as it lands: the write buffer did not move, its count grew
///         by exactly one, and the entry at the prior count carries the buyer's wallet ID, the
///         purchase level, the box counts/size or presale amount/tier/closing flag the action
///         implies, and matches the purchase event's (buffer, position, amount). Each entry is
///         snapshotted with its buffer generation so the invariant can prove it is never
///         rewritten while its cohort lives. The engine cranks (`openSome`) are observed one
///         mineFlip at a time: the read cursor never moves backwards or past the read count
///         without a seal, completion implies the cursor reached the read count, and every
///         queued-entry resolution event lands in FIFO order, inside [cursor, readCount), at or
///         behind the stored cursor, and to the entry's own wallet.
///
/// @dev The actor base is 0x70000 (disjoint from WhaleHandler's 0xB0000 and the afking handler's
///      0xAF000 / 0xDE17A); even actors are field-isolated-seeded with the HAS_DEITY_PASS score
///      bit. Test-only: ZERO contracts/*.sol mutation.
contract BoxCreationHandler is Test {
    using BoxOrderLib for uint256;

    DegenerusGame public game;
    DegenerusDeityPass public deityPass;
    MockVRFCoordinator public vrf;

    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED;
    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT; // HAS_DEITY_PASS score bit (subscribe/pass gate)
    uint256 private constant PRESALE_BOX_CREDIT_SLOT = GameSlots.PRESALE_BOX_CREDIT; // mapping(uint32 => uint256)
    uint256 private constant PRESALE_BOX_ETH_CAP = 50 ether;

    bytes32 private constant LOOTBOX_BUY = keccak256("LootBoxBuy(uint32,uint48,uint32,uint256)");
    bytes32 private constant PRESALE_BUY = keccak256("PresaleBoxBuy(uint32,uint48,uint32,uint256,bool)");
    bytes32 private constant LOOTBOX_OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant PRESALE_OPENED =
        keccak256("PresaleBoxOpened(uint32,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    uint256 private constant QUEUED_ENTRY_TAG = uint256(1) << 46;
    uint256 private constant REDEMPTION_INDEX_TAG = uint256(1) << 47;

    // -------------------------------------------------------------------------
    // Tracked entries: one per successful creating call, snapshotted at append.
    // -------------------------------------------------------------------------
    struct EntryRef {
        uint48 buffer;
        uint32 position;
        uint32 gen; // the buffer's generation when appended
        uint256 word; // the word as appended
        address owner;
    }

    EntryRef[] private created;
    /// @dev Generation of each physical buffer: bumped when a buffer's write count restarts at
    ///      position 0, i.e. it reopened for a new cohort and its old entries are dead.
    uint32[2] public gen;
    /// @dev (buffer, gen, position) -> owner, for the resolution-event wallet check.
    mapping(bytes32 => address) private ownerAt;

    // --- Ghost violations (asserted zero by the invariants) ---
    uint256 public appendViolations;
    string public lastAppendViolation;
    uint256 public fifoViolations;
    string public lastFifoViolation;
    uint256 public resolutionsObserved;

    // --- Per-path ghost counters (non-vacuity: each box-creating path that fires bumps its own) ---
    uint256 public boxesCreated_mintLootbox;
    uint256 public boxesCreated_whale;
    uint256 public boxesCreated_lazy;
    uint256 public boxesCreated_deity;
    uint256 public boxesCreated_presale;

    // --- Call counters (coverage visibility) ---
    uint256 public calls_mintLootbox;
    uint256 public calls_whale;
    uint256 public calls_lazy;
    uint256 public calls_deity;
    uint256 public calls_presale;
    uint256 public calls_openSome;

    // --- Actors (disjoint 0x70000 base) ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    /// @dev What a creating call must have appended.
    struct Expect {
        uint256 custom; // custom box count (0 for presale-only)
        uint256 sizeWei; // exact custom size; 0 = derive from the LootBoxBuy amount / custom
        uint256 presaleWei; // applied presale wei (0 = no presale leg)
        uint256 tier;
        bool closing;
        uint256 maxAmount; // LootBoxBuy amount ceiling (0 = no ordinary leg). A pass box is a
            // share of the pass price, which claimable/afking may fund beyond msg.value, so
            // passes bound it only through the entry's size.
    }

    /// @dev Write-side state captured just before a creating call.
    struct Pre {
        uint48 wb;
        uint256 count;
        uint24 lvl;
        uint256 priceWei;
    }

    /// @dev Read-side state around one engine call.
    struct ReadState {
        uint48 wb;
        uint48 rb;
        uint256 cursor;
        uint256 readCount;
        bool complete;
    }

    constructor(
        DegenerusGame game_,
        DegenerusDeityPass deityPass_,
        MockVRFCoordinator vrf_,
        uint256 numActors
    ) {
        game = game_;
        deityPass = deityPass_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            // 0x70000 base: disjoint from WhaleHandler (0xB0000) and V61AfkingSpendHandler (0xAF000/0xDE17A).
            address actor = address(uint160(0x70000 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
            // Seed the HAS_DEITY_PASS score bit on EVEN actors only — a deity-pass HOLDER cannot buy a
            // lazy pass NOR a fresh deity pass (both revert), so the un-seeded ODD actors keep those
            // surfaces reachable. The whale pass works for either band.
            if (i % 2 == 0) _grantDeityScoreBit(actor);
        }
    }

    // =========================================================================
    // Views the invariant reads
    // =========================================================================

    function trackedCount() external view returns (uint256) {
        return created.length;
    }

    function trackedEntry(uint256 i) external view returns (EntryRef memory) {
        return created[i];
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Tracked entries whose cohort still lives (buffer generation unchanged) but whose stored
    ///         word differs from the word appended. Zero is the never-rewritten property.
    function rewrittenEntries() public view returns (uint256 n) {
        for (uint256 i; i < created.length; i++) {
            EntryRef memory e = created[i];
            if (e.gen != gen[e.buffer]) continue;
            if (RecyclingState.boxEntry(address(game), e.buffer, e.position) != e.word) n++;
        }
    }

    function totalBoxesCreated() external view returns (uint256) {
        return boxesCreated_mintLootbox + boxesCreated_whale + boxesCreated_lazy + boxesCreated_deity
            + boxesCreated_presale;
    }

    /// @notice Count of DISTINCT box-creating paths that fired at least once (the >=2 non-vacuity gate).
    function pathsExercised() external view returns (uint256 n) {
        if (boxesCreated_mintLootbox != 0) n++;
        if (boxesCreated_whale != 0) n++;
        if (boxesCreated_lazy != 0) n++;
        if (boxesCreated_deity != 0) n++;
        if (boxesCreated_presale != 0) n++;
    }

    /// @notice The read-side state the FIFO invariant checks.
    function readState() public view returns (ReadState memory s) {
        s.wb = RecyclingState.writeBuffer(address(game));
        s.rb = s.wb ^ 1;
        s.cursor = uint48(uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8));
        s.readCount = uint32(uint256(vm.load(address(game), bytes32(GameSlots.BOX_READ_COUNT))) >> (GameSlots.BOX_READ_COUNT_OFFSET * 8));
        s.complete = uint8(uint256(vm.load(address(game), bytes32(GameSlots.HUMAN_READ_COMPLETE))) >> (GameSlots.HUMAN_READ_COMPLETE_OFFSET * 8)) != 0;
    }

    // =========================================================================
    // Action 1: mint-with-lootbox (one custom box appended as one entry)
    // =========================================================================

    function mintWithLootbox(uint256 actorSeed, uint256 lbSeed, uint8 kindSeed) external useActor(actorSeed) {
        calls_mintLootbox++;
        if (game.gameOver()) return;

        uint256 lootboxAmt = bound(lbSeed, 0.01 ether, 2 ether);
        // DirectEth or Combined (skip Claimable here — it sends no fresh ETH and the actor may have none).
        MintPaymentKind kind = (kindSeed & 1) == 0 ? MintPaymentKind.DirectEth : MintPaymentKind.Combined;

        // One whole ticket (400 entries) + the lootbox spend, funded generously with fresh ETH.
        uint256 value = lootboxAmt + 1 ether;
        if (value > currentActor.balance) return;

        uint256 size = (lootboxAmt / 1 gwei) * 1 gwei;
        Pre memory pre = _pre();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.purchase{value: value}(0, 400, BoxOrderLib.boCustomFloor(lootboxAmt), bytes32(0), kind, false) {
            boxesCreated_mintLootbox++;
            _checkAppend(pre, Expect({custom: 1, sizeWei: size, presaleWei: 0, tier: 0, closing: false, maxAmount: size}));
        } catch {
            vm.getRecordedLogs();
        }
    }

    // =========================================================================
    // Action 2: pass bundles (one entry, one custom box per pass bought)
    // =========================================================================

    function buyWhalePass(uint256 actorSeed, uint256 qtySeed) external useActor(actorSeed) {
        calls_whale++;
        if (game.gameOver()) return;

        uint256 qty = bound(qtySeed, 1, 5);
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        Pre memory pre = _pre();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.purchaseWhalePass{value: cost}(0, qty, bytes32(0)) {
            boxesCreated_whale++;
            _checkAppend(pre, Expect({custom: qty, sizeWei: 0, presaleWei: 0, tier: 0, closing: false, maxAmount: type(uint256).max}));
        } catch {
            vm.getRecordedLogs();
        }
    }

    function buyLazyPass(uint256 actorSeed) external useActor(actorSeed) {
        calls_lazy++;
        if (game.gameOver()) return;

        uint256 cost = 0.24 ether;
        if (cost > currentActor.balance) return;

        Pre memory pre = _pre();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.purchaseLazyPass{value: cost}(0, bytes32(0)) {
            boxesCreated_lazy++;
            _checkAppend(pre, Expect({custom: 1, sizeWei: 0, presaleWei: 0, tier: 0, closing: false, maxAmount: type(uint256).max}));
        } catch {
            vm.getRecordedLogs();
        }
    }

    /// @notice Deity pass: base 24 ETH (first pass; subsequent passes cost more and revert on the
    ///         fixed price, which the try/catch swallows).
    function buyDeityPass(uint256 actorSeed, uint256 symbolSeed) external useActor(actorSeed) {
        calls_deity++;
        if (game.gameOver()) return;

        uint8 symbolId = uint8(bound(symbolSeed, 0, 31));
        uint256 cost = 24 ether;
        if (cost > currentActor.balance) return;

        Pre memory pre = _pre();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.purchaseDeityPass{value: cost}(0, symbolId, bytes32(0)) {
            boxesCreated_deity++;
            _checkAppend(pre, Expect({custom: 1, sizeWei: 0, presaleWei: 0, tier: 0, closing: false, maxAmount: type(uint256).max}));
        } catch {
            vm.getRecordedLogs();
        }
    }

    // =========================================================================
    // Action 3: presale box (a presale-only entry)
    // =========================================================================

    /// @notice Buy a presale box. Presale-box credit is normally earned 25% on buys; here it is
    ///         seeded directly (a CREDIT allowance, NOT a box record) so the box is created through
    ///         the REAL buyPresaleBox entrypoint. boxAmount bounded [0.01, 2] ETH.
    function buyPresaleBox(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_presale++;
        if (game.gameOver()) return;
        uint256 remaining = game.presaleBoxEthRemaining();
        if (remaining == 0) return;

        uint256 boxAmount = bound(amtSeed, 0.01 ether, 2 ether);
        if (boxAmount > currentActor.balance) return;

        // Seed enough spendable credit for this buy (credit is consumed 1:1; an over-credit request reverts).
        _grantCredit(currentActor, boxAmount);

        uint256 applied = boxAmount > remaining ? remaining : boxAmount;
        uint256 tier = (PRESALE_BOX_ETH_CAP - remaining) / 10 ether;
        if (tier > 4) tier = 4;
        Pre memory pre = _pre();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.buyPresaleBox{value: boxAmount}(0, boxAmount) {
            boxesCreated_presale++;
            _checkAppend(pre, Expect({custom: 0, sizeWei: 0, presaleWei: applied, tier: tier, closing: applied == remaining, maxAmount: 0}));
        } catch {
            vm.getRecordedLogs();
        }
    }

    // =========================================================================
    // Action 4: open + advance (seal, publish and settle cohorts through the engine)
    // =========================================================================

    /// @notice Crank the permissionless engine, buy one ticket (the daily purchase gate), and
    ///         answer any pending VRF so sealed cohorts publish and settle. Every engine call is
    ///         observed for the FIFO properties.
    function openSome(uint256 actorSeed, uint256 crankSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_openSome++;

        uint256 cranks = bound(crankSeed, 1, 3);
        _crank(cranks);

        if (game.gameOver()) return;

        // Satisfy the daily purchase gate with one whole ticket; a ticket-only buy appends nothing.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= currentActor.balance) {
            uint48 wb = RecyclingState.writeBuffer(address(game));
            uint256 count = RecyclingState.boxCount(address(game), wb);
            vm.prank(currentActor);
            try game.purchase{value: priceWei}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
                if (RecyclingState.writeBuffer(address(game)) != wb || RecyclingState.boxCount(address(game), wb) != count) {
                    _appendViolation("a ticket-only purchase appended a box entry");
                }
            } catch {}
        }

        for (uint256 i; i < 3; i++) {
            _mine();
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(wordSeed, i))) | 1) {} catch {}
                }
            }
        }

        _crank(cranks);
    }

    /// @dev Up to `cranks` observed engine calls; any refusal ends the run.
    function _crank(uint256 cranks) internal {
        for (uint256 i; i < cranks; i++) {
            if (!_mine()) return;
        }
    }

    /// @dev One observed engine call by the current actor.
    function _mine() internal returns (bool ok) {
        ReadState memory pre = readState();
        vm.recordLogs();
        vm.prank(currentActor);
        try game.mineFlip() {
            ok = true;
        } catch {}
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (ok) _checkFifo(pre, readState(), logs);
    }

    // =========================================================================
    // Checks
    // =========================================================================

    function _pre() internal view returns (Pre memory p) {
        p.wb = RecyclingState.writeBuffer(address(game));
        p.count = RecyclingState.boxCount(address(game), p.wb);
        (p.lvl, , , , p.priceWei) = game.purchaseInfo();
    }

    function _appendViolation(string memory why) internal {
        appendViolations++;
        lastAppendViolation = why;
    }

    function _fifoViolation(string memory why) internal {
        fifoViolations++;
        lastFifoViolation = why;
    }

    /// @dev The creating call just succeeded: verify it appended exactly one entry matching `x`
    ///      at the write buffer's prior count, then track it.
    function _checkAppend(Pre memory pre, Expect memory x) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // A first append at position 0 reopens the buffer: its earlier cohort is dead.
        if (pre.count == 0) gen[pre.wb]++;
        string memory why = _appendMismatch(pre, x, logs);
        if (bytes(why).length != 0) {
            _appendViolation(why);
            return;
        }
        created.push(EntryRef({
            buffer: pre.wb,
            position: uint32(pre.count),
            gen: gen[pre.wb],
            word: RecyclingState.boxEntry(address(game), pre.wb, pre.count),
            owner: currentActor
        }));
        ownerAt[keccak256(abi.encode(pre.wb, gen[pre.wb], pre.count))] = currentActor;
    }

    /// @dev Why the creating call's append does not match `x`, or "" when it does.
    function _appendMismatch(Pre memory pre, Expect memory x, Vm.Log[] memory logs)
        internal
        view
        returns (string memory)
    {
        if (RecyclingState.writeBuffer(address(game)) != pre.wb) return "the write buffer moved during a purchase";
        if (RecyclingState.boxCount(address(game), pre.wb) != pre.count + 1) return "a purchase did not append exactly one entry";

        uint256 word = RecyclingState.boxEntry(address(game), pre.wb, pre.count);
        uint32 id = game.walletIdOf(currentActor);
        if (id == 0 || word.boId() != id) return "entry wallet ID is not the buyer's";
        if (word >> 255 != 0) return "entry spare bit set";
        if (word.boCover()) return "a purchase appended a cover entry";
        if (word.boSmall() + word.boMed() + word.boLarge() != 0) return "unexpected preset boxes";
        if (word.boCustomCount() != x.custom) return "entry custom count does not match the action";
        if (word.boPresaleWei() != x.presaleWei) return "entry presale amount does not match the applied amount";
        if (word.boPresaleTier() != x.tier) return "entry presale tier does not match the starting sold amount";
        if (word.boPresaleClosing() != x.closing) return "entry closing flag does not match the sale state";

        (bool sawBuy, uint256 amount) = _purchaseEvent(logs, pre, x.custom != 0 ? LOOTBOX_BUY : PRESALE_BUY);
        if (!sawBuy) return "no purchase event names the appended (buffer, position)";
        if (x.custom != 0) {
            // The ordinary leg: priced at the active ticket level and announced by LootBoxBuy.
            uint24 lvl = word.boLevel();
            if ((lvl != pre.lvl && lvl != pre.lvl + 1) || PriceLookupLib.priceForLevel(lvl) != pre.priceWei) {
                return "entry level is not the active ticket level";
            }
            if (amount == 0 || amount > x.maxAmount) return "box spend outside the action's bound";
            if (x.sizeWei != 0 && amount != x.sizeWei * x.custom) return "LootBoxBuy amount is not the order's cost";
            uint256 size = x.sizeWei != 0 ? x.sizeWei : (amount / (x.custom * 1 gwei)) * 1 gwei;
            if (size == 0 || word.boSizeWei() != size) return "entry box size does not match the spend";
        } else {
            if (word.boLevel() != 0 || word.boSizeWei() != 0) return "presale-only entry carries ordinary lanes";
            if (amount != x.presaleWei) return "PresaleBoxBuy amount is not the applied amount";
        }
        return "";
    }

    /// @dev The buyer's purchase event of `topic` naming (pre.wb, pre.count); returns its amount.
    function _purchaseEvent(Vm.Log[] memory logs, Pre memory pre, bytes32 topic)
        internal
        view
        returns (bool found, uint256 amount)
    {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 3 || logs[i].topics[0] != topic) continue;
            if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf(currentActor)) continue;
            if (uint256(logs[i].topics[2]) != pre.wb) continue;
            uint32 position;
            if (topic == LOOTBOX_BUY) (position, amount) = abi.decode(logs[i].data, (uint32, uint256));
            else (position, amount,) = abi.decode(logs[i].data, (uint32, uint256, bool));
            if (position == pre.count) return (true, amount);
        }
    }

    /// @dev One engine call's read-side transition and its queued-entry resolutions.
    function _checkFifo(ReadState memory pre, ReadState memory post, Vm.Log[] memory logs) internal {
        if (post.cursor > post.readCount) _fifoViolation("cursor beyond the read count");
        if (post.complete && post.cursor != post.readCount) _fifoViolation("completion before the cursor reached the read count");
        bool sealed_ = post.wb != pre.wb;
        if (!sealed_) {
            if (post.readCount != pre.readCount) _fifoViolation("read count moved without a seal");
            if (post.cursor < pre.cursor) _fifoViolation("cursor moved backwards without a seal");
            if (pre.complete && !post.complete) _fifoViolation("completion cleared without a seal");
        }
        uint256 last = pre.cursor;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 3) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 != LOOTBOX_OPENED && t0 != PRESALE_OPENED) continue;
            uint256 tag = uint256(logs[i].topics[2]);
            // Single-box resolvers (0) and redemption orders carry no queue position.
            if (tag & REDEMPTION_INDEX_TAG != 0 || tag & QUEUED_ENTRY_TAG == 0) continue;
            uint48 buffer = uint48(tag & 1);
            uint256 position = (tag & (QUEUED_ENTRY_TAG - 1)) >> 1;
            resolutionsObserved++;
            if (buffer != pre.rb) _fifoViolation("an entry resolved outside the sealed read buffer");
            if (position < last) _fifoViolation("an entry resolved out of FIFO order or behind the cursor");
            if (position >= pre.readCount) _fifoViolation("an entry resolved past the read count");
            if (!sealed_ && position >= post.cursor) _fifoViolation("an entry resolved ahead of the stored cursor");
            last = position;
            address owner = ownerAt[keccak256(abi.encode(buffer, gen[buffer], position))];
            if (owner != address(0) && uint32(uint256(logs[i].topics[1])) != game.walletIdOf(owner)) {
                _fifoViolation("an entry resolved to a wallet other than its buyer");
            }
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Field-isolated HAS_DEITY_PASS score-bit seed in mintPacked_. No balance touched.
    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Seed spendable presale-box credit for `buyer`'s wallet ID — a credit ALLOWANCE, not a
    ///      box record. A buyer without an ID first registers one, as its first paying action would.
    function _grantCredit(address buyer, uint256 amount) internal {
        uint32 id = game.walletIdOf(buyer);
        if (id == 0) {
            vm.prank(ContractAddresses.AFFILIATE);
            id = game.registerWallet(buyer, true);
        }
        bytes32 slot = keccak256(abi.encode(uint256(id), uint256(PRESALE_BOX_CREDIT_SLOT)));
        uint256 existing = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(existing + amount));
    }

    // =========================================================================
    // Falsifiability seam (used ONLY by the BoxEnqueue falsifiability test, never by a fuzzed action)
    // =========================================================================

    /// @dev Overwrite tracked entry `i`'s stored word in place — the shape of a purchase that
    ///      rewrote an earlier entry instead of appending its own.
    function debugRewriteEntry(uint256 i, uint256 word) external {
        EntryRef memory e = created[i];
        bytes32 data = keccak256(abi.encode(keccak256(abi.encode(uint256(e.buffer), GameSlots.BOX_QUEUE))));
        vm.store(address(game), bytes32(uint256(data) + e.position), bytes32(word));
    }
}
