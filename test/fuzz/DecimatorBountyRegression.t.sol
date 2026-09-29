// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DecimatorBountyRegression — mineFlip's decimator-leg bounty (MINER_BOUNTY_DECIMATOR)
/// @notice Pins the FLIP flip-credit a mineFlip call earns for settling decimator winners through
///         its decimator leg:
///           bounty = unit * min(unitsUsed / 15, 5) / 5, unit = BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mintPrice
///         and the rules around it:
///           1. LIVE      — a live-game mineFlip call that settles winning entries credits the
///                          keeper exactly one MinerBounty of kind 5; the credit lands as a
///                          next-day coinflip STAKE (creditFlip -> _addDailyFlip), surfaced by
///                          coinflipAmount.
///           2. SCALES    — the bounty pro-rates with the leg's walk-unit spend up to a 5-credit
///                          knee: a settle that stays under the saturation threshold pays less
///                          than a settle that clears it, which pays the flat per-call unit.
///           3. GAME-OVER — the leg settles nothing after game over (its own gate, alongside the
///                          RNG lock and liveness): mineFlip finds no work and the keeper earns
///                          no bounty; the winners still settle through the individual claim.
///           4. ETH-VALUE — the FLIP credit holds its ETH-reimbursement value across the price
///                          curve at saturation: credit == BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mintPrice.
///           5. FAUCET    — the bounty is far below the FLIP a winner had to burn to exist, so a
///                          keeper cannot manufacture winners to farm it.
///
/// @dev Winners are real decEntry list records, created through the real burn path
///      (recordDecBurn via COIN) and drawn through the real runDecimatorJackpot, then settled by
///      mineFlip's decimator leg with the box/advance/craps legs left quiet — the same harness
///      shape DecimatorListRecord.t.sol uses to pin the leg itself.
contract DecimatorBountyRegression is DeployProtocol {
    uint256 internal constant SLOT_HEADER = 0; // packed flags incl. gameOver @ byte 21
    uint256 internal constant SLOT_POOLS_1 = 1; // currentPrizePool[0:128] | claimablePool[128:256]

    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;
    uint256 internal constant BOUNTY_ETH_TARGET = 885_000_000_000_000; // mirror of the module constant

    uint256 internal constant MULT_1X = 10_000;
    uint8 internal constant KIND_DECIMATOR = 5;

    bytes32 internal constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");
    bytes32 internal constant DEC_CLAIMED_SIG =
        keccak256("DecimatorClaimed(address,uint24,uint256,uint256,uint256)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private _lastFulfilledReqId;

    address internal keeper;

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("dec_bounty_keeper");
        // mineFlip's decimator leg only runs once the advance leg is not due and the box legs
        // find nothing pending — drain both so every mine() below reaches the leg cleanly.
        _settleGame(uint256(keccak256("dec-bounty-settle")));
        game.openBoxes(1_000);
        _quietCrapsTable();
    }

    // ------------------------------------------------------------------
    //                              harness
    // ------------------------------------------------------------------

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _burn(address player, uint24 lvl, uint8 bucket, uint256 base) internal {
        vm.prank(ContractAddresses.COIN);
        game.recordDecBurn(player, lvl, bucket, base, MULT_1X);
    }

    function _subOf(address player, uint24 lvl, uint8 bucket) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(player, lvl, bucket))) % bucket);
    }

    function _winningSub(uint256 rngWord, uint8 denom) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(rngWord, denom))) % denom);
    }

    /// @dev A fresh address whose subbucket for (lvl, bucket) is `sub` (or is not, when `want` is false).
    function _playerIn(string memory tag, uint256 i, uint24 lvl, uint8 bucket, uint8 sub, bool want)
        internal
        returns (address p)
    {
        for (uint256 n; ; ++n) {
            p = makeAddr(string(abi.encodePacked(tag, vm.toString(i), "-", vm.toString(n))));
            if ((_subOf(p, lvl, bucket) == sub) == want) return p;
        }
    }

    /// @dev Run the real draw for `lvl`, then book the spend into claimablePool as the advance does.
    function _draw(uint24 lvl, uint256 poolWei, uint256 rngWord) internal {
        vm.prank(address(game));
        uint256 returned = game.runDecimatorJackpot(poolWei, lvl, rngWord);
        uint256 spend = poolWei - returned;
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_POOLS_1)));
        uint256 claimable = (w >> 128) + spend;
        w = (w & ((uint256(1) << 128) - 1)) | (claimable << 128);
        vm.store(address(game), bytes32(SLOT_POOLS_1), bytes32(w));
    }

    /// @dev Install `n` winners at `denom` on `lvl`, plus one loser in the same denom so the
    ///      winning total is not the whole level, and draw.
    function _installWinners(uint24 lvl, uint8 denom, uint256 n, uint256 rngWord, uint256 poolWei)
        internal
        returns (address[] memory winners)
    {
        winners = new address[](n);
        uint8 wsub = _winningSub(rngWord, denom);
        _burn(_playerIn("lose", lvl, lvl, denom, wsub, false), lvl, denom, 2_000 ether);
        for (uint256 i; i < n; ++i) {
            address p = _playerIn(string(abi.encodePacked("win", vm.toString(lvl))), i, lvl, denom, wsub, true);
            _burn(p, lvl, denom, 1_000 ether + i * 7 ether);
            winners[i] = p;
        }
        _draw(lvl, poolWei, rngWord);
    }

    function _mine() internal {
        vm.prank(keeper);
        game.mineFlip();
    }

    function _bounty(Vm.Log[] memory logs) internal pure returns (uint256 count, uint8 kind, uint256 amount) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 2 && logs[i].topics[0] == MINER_BOUNTY_SIG) {
                ++count;
                (kind, amount) = abi.decode(logs[i].data, (uint8, uint256));
            }
        }
    }

    function _claimedCount(Vm.Log[] memory logs) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == DEC_CLAIMED_SIG) ++n;
        }
    }

    /// @dev Set the gameOver flag (slot 0, byte 21).
    function _setGameOver() internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        w |= (uint256(1) << (21 * 8));
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(w));
    }

    /// @dev The bounty's per-credit unit, priced the same way the module prices it.
    function _unit() internal view returns (uint256) {
        return (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice();
    }

    // ------------------------------------------------------------------
    //                              tests
    // ------------------------------------------------------------------

    /// @notice LIVE — one settling call credits the keeper exactly one kind-5 bounty, as a
    ///         coinflip stake.
    function test_LiveCallCreditsExactlyOneDecimatorBounty() public {
        _installWinners(5, 6, 1, uint256(keccak256("live")), 1 ether);

        uint256 before = coinflip.coinflipAmount(keeper);
        vm.recordLogs();
        _mine();
        (uint256 count, uint8 kind, uint256 amount) = _bounty(vm.getRecordedLogs());

        assertEq(count, 1, "exactly one bounty per settling call");
        assertEq(kind, KIND_DECIMATOR);
        assertGt(amount, 0, "nonzero bounty");
        assertEq(coinflip.coinflipAmount(keeper) - before, amount, "credited as a coinflip stake");
    }

    /// @notice SCALES — a settle under the saturation knee pays less than the flat per-call unit;
    ///         a settle that clears the knee (well past 75 walk units, guaranteed by 4 real
    ///         settles at DEC_SETTLE_WEIGHT=42 each) pays exactly the unit, saturated.
    function test_BountyScalesToTheKneeThenSaturates() public {
        _installWinners(5, 6, 1, uint256(keccak256("scales-small")), 1 ether);
        vm.recordLogs();
        _mine();
        (, , uint256 small) = _bounty(vm.getRecordedLogs());

        _installWinners(15, 6, 4, uint256(keccak256("scales-big")), 4 ether);
        vm.recordLogs();
        _mine();
        (, , uint256 saturated) = _bounty(vm.getRecordedLogs());

        uint256 unit = _unit();
        assertLt(small, saturated, "a smaller settle earns less than a saturating one");
        assertEq(saturated, unit, "a saturating settle earns the flat per-call unit");
    }

    /// @notice GAME-OVER — the leg settles nothing after game over: mineFlip finds no work and
    ///         pays no bounty; the winners still settle through the individual claim.
    function test_LegSettlesNothingAfterGameOverAndPaysNoBounty() public {
        address[] memory winners = _installWinners(5, 6, 1, uint256(keccak256("over")), 1 ether);
        _setGameOver();

        uint256 before = coinflip.coinflipAmount(keeper);
        vm.recordLogs();
        vm.prank(keeper);
        try game.mineFlip() {} catch {}
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 count, , ) = _bounty(logs);
        assertEq(count, 0, "no bounty once the game is over");
        assertEq(_claimedCount(logs), 0, "the leg settles nothing after game over");
        assertEq(coinflip.coinflipAmount(keeper), before, "keeper earns nothing");

        uint256 claimBefore = game.claimableWinningsOf(winners[0]);
        game.claimDecimatorJackpot(5, 6, 0);
        assertGt(game.claimableWinningsOf(winners[0]), claimBefore, "the claim still pays after game over");
    }

    /// @notice ETH-VALUE — at saturation the FLIP credit holds its ETH-reimbursement value
    ///         exactly: credit == BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mintPrice.
    function test_SaturatedBountyHoldsItsEthReimbursementValue() public {
        _installWinners(5, 6, 4, uint256(keccak256("eth-value")), 4 ether);
        vm.recordLogs();
        _mine();
        (, , uint256 amount) = _bounty(vm.getRecordedLogs());
        assertEq(amount, _unit(), "saturated bounty equals the priced unit exactly");
    }

    /// @notice FAUCET — even a saturated bounty is far below the FLIP a single winner had to
    ///         burn to exist, so a keeper cannot manufacture winners to farm it.
    function test_BountyFarBelowBurnCostToManufactureAWinner() public {
        _installWinners(5, 6, 4, uint256(keccak256("faucet")), 4 ether);
        vm.recordLogs();
        _mine();
        (, , uint256 amount) = _bounty(vm.getRecordedLogs());
        assertLt(amount, 1_000 ether, "bounty << burn cost to manufacture a single winning entry");
    }
}
