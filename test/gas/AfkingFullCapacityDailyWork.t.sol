// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AfkingFullCapacityDailyWork -- one game day of AFKing work at the largest reachable set.
/// @notice Fills the subscriber set through real seat mints and real subscribes until the seat cap
///         admits no more, then drives one game day through `mineRun` only: the pre-RNG subscriber
///         preparation up to the daily VRF request, then everything after the word up to session
///         completion, AFKing box opening included. Each call runs against cooled protocol
///         accounts so its storage access is priced like a fresh transaction.
/// @dev Per-call gas is the caller-side execution gas of one `mineRun{gas: allowance}`; intrinsic
///      transaction gas is excluded. Results are logged as `DW,...` rows.
contract AfkingFullCapacityDailyWork is DeployProtocol {
    address internal constant MINER = address(uint160(0x5EED_A11CE));
    uint256 internal constant ALLOWANCE_12M = 12_000_000;
    uint256 internal constant ALLOWANCE_TX_CAP = 16_777_216;
    uint256 internal constant MAX_CALLS = 4_000;

    uint8 internal constant ACTION_TICKETS = 4;
    uint8 internal constant ACTION_AFKING = 8;
    uint8 internal constant ACTION_PREPARE = 14;
    uint8 internal constant ACTION_REQUEST_DAILY = 16;

    bytes32 internal constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");

    struct Fill {
        uint256 players;
        uint256 tickets;
        uint256 boxes;
        uint256 unfunded;
        uint256 seized;
    }

    struct Phase {
        uint256 calls;
        uint256 total;
        uint256 max;
        uint256[] gas;
        uint256 prepCalls;
        uint256 openCalls;
        uint256 openGas;
        uint256 openMax;
        uint256 ticketCalls;
        uint256 boxesOpened;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        _finishSubscriptionWindow();
        _giveWalletId(MINER);
    }

    function test_DailyWork_Mix() public { _scenario(2, "mix"); }

    function test_DailyWork_AllTickets() public { _scenario(0, "tickets"); }

    function test_DailyWork_AllBoxes() public { _scenario(1, "boxes"); }

    /// @param mode 0 = every player in ticket mode at quantity 8, 1 = every player in box mode at
    ///        quantity 8, 2 = half tickets / half boxes at quantities 1-3 with 2% unfunded and 1%
    ///        seized runs, each spread over both modes.
    function _scenario(uint8 mode, string memory tag) internal {
        Fill memory f = _fill(mode);
        uint256 setLength = game.subscriberSetLength();
        emit log_named_uint(string.concat(tag, "_set_length"), setLength);
        emit log_named_uint(string.concat(tag, "_players"), f.players);
        emit log_named_uint(string.concat(tag, "_ticket_members"), f.tickets);
        emit log_named_uint(string.concat(tag, "_box_members"), f.boxes);
        emit log_named_uint(string.concat(tag, "_unfunded"), f.unfunded);
        emit log_named_uint(string.concat(tag, "_seized"), f.seized);
        assertEq(setLength + afkingSubToken.totalSupply(), afkingSubToken.SEAT_CAP(), "the seat cap is full");

        uint256 snap = vm.snapshotState();
        _day(tag, ALLOWANCE_12M);
        vm.revertToState(snap);
        _day(tag, ALLOWANCE_TX_CAP);
    }

    function _fill(uint8 mode) internal returns (Fill memory f) {
        vm.pauseGasMetering();
        uint256 cap = afkingSubToken.SEAT_CAP();
        uint256 tranche = afkingSubToken.FREE_TRANCHE();
        for (uint256 i; ; ++i) {
            bool free = afkingSubToken.freeClaims() < tranche;
            if (!free && afkingSubToken.totalSupply() + game.subscriberSetLength() + 1 > cap) break;
            address owner = address(uint160(0xA0000000 + i));
            vm.deal(owner, 2 ether);
            uint32 id = _giveWalletId(owner);
            if (free) {
                vm.prank(ContractAddresses.GAME);
                afkingSubToken.mintSeatFor(owner);
            } else {
                vm.prank(ContractAddresses.VAULT);
                afkingSubToken.vaultMintSeats(owner, 1);
            }
            uint256 seat = uint256(afkingSubToken.nextSerial()) - 1;
            bool tickets = mode == 0 || (mode == 2 && i % 2 == 1);
            uint8 qty = mode == 2 ? uint8(1 + i % 3) : 8;
            bool unfunded = mode == 2 && (i % 100 == 7 || i % 100 == 32);
            vm.prank(owner);
            game.subscribe{value: unfunded ? 0 : 1 ether}(0, tickets, qty, seat);
            if (mode == 2 && (i % 200 == 13 || i % 200 == 64)) {
                _markSeized(id);
                ++f.seized;
            } else if (unfunded) {
                ++f.unfunded;
            }
            ++f.players;
            if (tickets) ++f.tickets;
            else ++f.boxes;
        }
        vm.resumeGasMetering();
    }

    /// @dev A loan seizure's state for a run: its lane marked for removal by the next preparation.
    function _markSeized(uint32 id) internal {
        (, uint256 position1) = GameSlotKeys.subLane(address(game), id);
        uint256 position = position1 - 1;
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS))) + position / 3);
        uint256 word = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(word | (uint256(1) << ((position % 3) * 85 + 68))));
    }

    function _day(string memory tag, uint256 allowance) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 request = mockVRF.lastRequestId();
        Phase memory pre = _newPhase();
        while (mockVRF.lastRequestId() == request) {
            require(pre.calls < MAX_CALLS, "pre-RNG did not reach the daily request");
            _step(pre, allowance);
        }
        assertTrue(game.rngLocked(), "the daily request locked the day");

        uint256 word = uint256(keccak256(abi.encode("afking-capacity", tag, allowance))) | 1;
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), word);
        Phase memory post = _newPhase();
        for (;;) {
            (bool complete,,) = game.dailySessionState();
            if (complete) break;
            require(post.calls < MAX_CALLS, "post-RNG did not complete the session");
            _step(post, allowance);
        }
        assertEq(_pendingBoxes(), 0, "every stamped box opened");

        _report(tag, allowance, "pre", pre);
        _report(tag, allowance, "post", post);
    }

    function _newPhase() internal pure returns (Phase memory p) {
        p.gas = new uint256[](MAX_CALLS);
    }

    function _step(Phase memory p, uint256 allowance) internal {
        _coolProtocol();
        uint256 pendingBefore = _pendingBoxes();
        vm.recordLogs();
        vm.prank(MINER);
        uint256 before = gasleft();
        game.mineRun{gas: allowance}(0);
        uint256 used = before - gasleft();
        uint8 first = _firstAction(vm.getRecordedLogs());
        uint256 pendingAfter = _pendingBoxes();
        p.gas[p.calls] = used;
        ++p.calls;
        p.total += used;
        if (used > p.max) p.max = used;
        if (first == ACTION_PREPARE) ++p.prepCalls;
        if (first == ACTION_TICKETS) ++p.ticketCalls;
        if (pendingAfter < pendingBefore) {
            ++p.openCalls;
            p.openGas += used;
            if (used > p.openMax) p.openMax = used;
            p.boxesOpened += pendingBefore - pendingAfter;
        }
    }

    function _firstAction(Vm.Log[] memory logs) internal pure returns (uint8 first) {
        first = type(uint8).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (first,,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
            }
        }
    }

    function _report(string memory tag, uint256 allowance, string memory phase, Phase memory p) internal {
        uint256 median = _median(p.gas, p.calls);
        emit log(string.concat(
            "DW,", tag, ",", vm.toString(allowance), ",", phase,
            ",calls=", vm.toString(p.calls),
            ",total=", vm.toString(p.total),
            ",max=", vm.toString(p.max),
            ",median=", vm.toString(median),
            ",prepFirst=", vm.toString(p.prepCalls),
            ",ticketFirst=", vm.toString(p.ticketCalls)
        ));
        emit log(string.concat(
            "DW,", tag, ",", vm.toString(allowance), ",", phase,
            ",openCalls=", vm.toString(p.openCalls),
            ",openGas=", vm.toString(p.openGas),
            ",openMax=", vm.toString(p.openMax),
            ",boxesOpened=", vm.toString(p.boxesOpened)
        ));
    }

    function _median(uint256[] memory values, uint256 n) internal pure returns (uint256) {
        if (n == 0) return 0;
        uint256[] memory sorted = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            uint256 v = values[i];
            uint256 j = i;
            while (j != 0 && sorted[j - 1] > v) {
                sorted[j] = sorted[j - 1];
                --j;
            }
            sorted[j] = v;
        }
        return sorted[n / 2];
    }

    function _pendingBoxes() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PENDING_BOX_COUNT)));
        return uint16(packed >> (8 * GameSlots.PENDING_BOX_COUNT_OFFSET));
    }

    function _coolProtocol() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.COIN);
        vm.cool(ContractAddresses.COINFLIP);
        vm.cool(ContractAddresses.QUESTS);
        vm.cool(ContractAddresses.AFFILIATE);
        vm.cool(ContractAddresses.SDGNRS);
        vm.cool(ContractAddresses.DGNRS);
        vm.cool(ContractAddresses.VAULT);
        vm.cool(ContractAddresses.JACKPOTS);
        vm.cool(ContractAddresses.GNRUS);
        vm.cool(ContractAddresses.WWXRP);
        vm.cool(ContractAddresses.CRAPS);
        vm.cool(ContractAddresses.CRAPS_ENGINE);
        vm.cool(ContractAddresses.JACKPOT_BATTLE);
        vm.cool(ContractAddresses.PARIMUTUEL);
        vm.cool(ContractAddresses.STETH_TOKEN);
        vm.cool(ContractAddresses.DEITY_PASS);
        vm.cool(ContractAddresses.AFKING_SUB_TOKEN);
        vm.cool(ContractAddresses.ADMIN);
        vm.cool(ContractAddresses.VRF_COORDINATOR);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_RNG_MODULE);
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENESIS_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_DECIMATOR_MODULE);
    }
}
