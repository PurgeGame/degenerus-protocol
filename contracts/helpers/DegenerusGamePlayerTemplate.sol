// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "../ContractAddresses.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

interface IDegenerusGamePlayer {
    function advanceGame(uint32 cap) external;
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    function openLootBox(address player, uint48 lootboxIndex) external;
    function claimWinnings(address player) external;
    function claimWhalePass(address player) external;
}

interface IDegenerusCoinPlayer {
    function depositCoinflip(address player, uint256 amount) external;
    function decimatorBurn(address player, uint256 amount) external;
}

interface IDegenerusAffiliatePlayer {
    function createAffiliateCode(bytes32 code_, uint8 rakebackPct) external;
    function referPlayer(bytes32 code_) external;
}

interface IDegenerusStonkPlayer {
    function burn(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}

/// @notice Template player contract that wraps user-facing Degenerus actions.
contract DegenerusGamePlayerTemplate {
    error OnlyOwner();

    address public owner;

    IDegenerusGamePlayer public game;
    IDegenerusCoinPlayer public coin;
    IDegenerusAffiliatePlayer public affiliate;
    IDegenerusStonkPlayer public dgnrs;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        address game_,
        address coin_,
        address affiliate_,
        address dgnrs_
    ) {
        owner = msg.sender;
        game = IDegenerusGamePlayer(
            game_ == address(0) ? ContractAddresses.GAME : game_
        );
        coin = IDegenerusCoinPlayer(
            coin_ == address(0) ? ContractAddresses.COIN : coin_
        );
        affiliate = IDegenerusAffiliatePlayer(
            affiliate_ == address(0) ? ContractAddresses.AFFILIATE : affiliate_
        );
        dgnrs = IDegenerusStonkPlayer(
            dgnrs_ == address(0) ? ContractAddresses.DGNRS : dgnrs_
        );
    }

    receive() external payable {}

    function gameAdvance(uint32 cap) external onlyOwner {
        game.advanceGame(cap);
    }

    function gamePurchase(
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable onlyOwner {
        game.purchase{value: msg.value}(
            address(0),
            gamepieceQuantity,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function gameOpenLootBox(uint48 lootboxIndex) external onlyOwner {
        game.openLootBox(address(0), lootboxIndex);
    }

    function gameClaimWinnings() external onlyOwner {
        game.claimWinnings(address(0));
    }

    function gameClaimWhalePass() external onlyOwner {
        game.claimWhalePass(address(0));
    }

    function coinDepositCoinflip(uint256 amount) external onlyOwner {
        coin.depositCoinflip(address(0), amount);
    }

    function coinDecimatorBurn(uint256 amount) external onlyOwner {
        coin.decimatorBurn(address(0), amount);
    }

    function affiliateCreateCode(
        bytes32 code_,
        uint8 rakebackPct
    ) external onlyOwner {
        affiliate.createAffiliateCode(code_, rakebackPct);
    }

    function affiliateRefer(bytes32 code_) external onlyOwner {
        affiliate.referPlayer(code_);
    }

    function dgnrsBurn(
        uint256 amount
    ) external onlyOwner returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        return dgnrs.burn(address(0), amount);
    }
}
