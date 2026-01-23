// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "../ContractAddresses.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

enum PurchaseKind {
    Player,
    Ticket
}

struct PurchaseParams {
    uint256 quantity;
    PurchaseKind kind;
    MintPaymentKind payKind;
    bool payInCoin;
    bytes32 affiliateCode;
}

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
    function burnTokens(address player, uint256[] calldata tokenIds) external;
    function claimWinnings(address player) external;
    function claimWhalePass(address player) external;
    function setAutoRebuy(address player, bool enabled) external;
    function setAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external;
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external;
    function setOperatorApproval(address operator, bool approved) external;
}

interface IDegenerusGamepiecesPlayer {
    function purchase(PurchaseParams calldata params) external payable;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
    function placeAsk(address seller, uint256 tokenId, uint256 price, uint40 expiry) external;
    function cancelAsk(uint256 tokenId) external;
}

interface IDegenerusCoinPlayer {
    function decimatorBurn(address player, uint256 amount) external;
}

interface IBurnieCoinflipPlayer {
    function depositCoinflip(address player, uint256 amount) external;
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function claimCoinflipsKeepMultiple(address player, uint256 multiples) external returns (uint256 claimed);
    function setCoinflipAutoRebuy(address player, bool enabled, uint256 keepMultiple) external;
    function setCoinflipAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external;
}

interface IDegenerusAffiliatePlayer {
    function createAffiliateCode(bytes32 code_, uint8 rakebackPct) external;
}

interface IDegenerusJackpotsPlayer {
    function claimDecimatorJackpot(uint24 lvl) external;
}

interface IDegenerusStonkPlayer {
    function burn(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}

/// @notice Owner-controlled player wrapper for full Degenerus gameplay.
contract DegenerusGamePlayerFull {
    error OnlyOwner();

    address public owner;

    IDegenerusGamePlayer public game;
    IDegenerusGamepiecesPlayer public gamepieces;
    IDegenerusCoinPlayer public coin;
    IBurnieCoinflipPlayer public coinflip;
    IDegenerusAffiliatePlayer public affiliate;
    IDegenerusJackpotsPlayer public jackpots;
    IDegenerusStonkPlayer public dgnrs;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        address game_,
        address gamepieces_,
        address coin_,
        address coinflip_,
        address affiliate_,
        address jackpots_,
        address dgnrs_
    ) {
        owner = msg.sender;
        game = IDegenerusGamePlayer(game_ == address(0) ? ContractAddresses.GAME : game_);
        gamepieces = IDegenerusGamepiecesPlayer(
            gamepieces_ == address(0) ? ContractAddresses.GAMEPIECES : gamepieces_
        );
        coin = IDegenerusCoinPlayer(coin_ == address(0) ? ContractAddresses.COIN : coin_);
        coinflip = IBurnieCoinflipPlayer(
            coinflip_ == address(0) ? ContractAddresses.COINFLIP : coinflip_
        );
        affiliate = IDegenerusAffiliatePlayer(
            affiliate_ == address(0) ? ContractAddresses.AFFILIATE : affiliate_
        );
        jackpots = IDegenerusJackpotsPlayer(
            jackpots_ == address(0) ? ContractAddresses.JACKPOTS : jackpots_
        );
        dgnrs = IDegenerusStonkPlayer(dgnrs_ == address(0) ? ContractAddresses.DGNRS : dgnrs_);
    }

    receive() external payable {}

    // =============================== Game ==================================
    function gameAdvance(uint32 cap) external onlyOwner {
        game.advanceGame(cap);
    }

    function gamePurchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable onlyOwner {
        game.purchase{value: msg.value}(
            buyer,
            gamepieceQuantity,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function gameOpenLootBox(address player, uint48 lootboxIndex) external onlyOwner {
        game.openLootBox(player, lootboxIndex);
    }

    function gameBurnTokens(address player, uint256[] calldata tokenIds) external onlyOwner {
        game.burnTokens(player, tokenIds);
    }

    function gameClaimWinnings(address player) external onlyOwner {
        game.claimWinnings(player);
    }

    function gameClaimWhalePass(address player) external onlyOwner {
        game.claimWhalePass(player);
    }

    function gameSetAutoRebuy(address player, bool enabled) external onlyOwner {
        game.setAutoRebuy(player, enabled);
    }

    function gameSetAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external onlyOwner {
        game.setAutoRebuyKeepMultiple(player, keepMultiple);
    }

    function gameSetAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external onlyOwner {
        game.setAfKingMode(player, enabled, ethKeepMultiple, coinKeepMultiple);
    }

    function gameSetOperatorApproval(address operator, bool approved) external onlyOwner {
        game.setOperatorApproval(operator, approved);
    }

    // ============================ Gamepieces ===============================
    function gamepiecesPurchase(PurchaseParams calldata params) external payable onlyOwner {
        gamepieces.purchase{value: msg.value}(params);
    }

    function gamepiecesApprove(address to, uint256 tokenId) external onlyOwner {
        gamepieces.approve(to, tokenId);
    }

    function gamepiecesSetApprovalForAll(address operator, bool approved) external onlyOwner {
        gamepieces.setApprovalForAll(operator, approved);
    }

    function gamepiecesTransferFrom(address from, address to, uint256 tokenId) external onlyOwner {
        gamepieces.transferFrom(from, to, tokenId);
    }

    function gamepiecesSafeTransferFrom(address from, address to, uint256 tokenId) external onlyOwner {
        gamepieces.safeTransferFrom(from, to, tokenId);
    }

    function gamepiecesSafeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external onlyOwner {
        gamepieces.safeTransferFrom(from, to, tokenId, data);
    }

    function gamepiecesPlaceAsk(
        address seller,
        uint256 tokenId,
        uint256 price,
        uint40 expiry
    ) external onlyOwner {
        gamepieces.placeAsk(seller, tokenId, price, expiry);
    }

    function gamepiecesCancelAsk(uint256 tokenId) external onlyOwner {
        gamepieces.cancelAsk(tokenId);
    }

    // =============================== Coin ==================================
    function coinDepositCoinflip(address player, uint256 amount) external onlyOwner {
        coinflip.depositCoinflip(player, amount);
    }

    function coinClaimCoinflips(
        address player,
        uint256 amount
    ) external onlyOwner returns (uint256 claimed) {
        return coinflip.claimCoinflips(player, amount);
    }

    function coinClaimCoinflipsKeepMultiple(
        address player,
        uint256 multiples
    ) external onlyOwner returns (uint256 claimed) {
        return coinflip.claimCoinflipsKeepMultiple(player, multiples);
    }

    function coinDecimatorBurn(address player, uint256 amount) external onlyOwner {
        coin.decimatorBurn(player, amount);
    }

    function coinSetAutoRebuy(
        address player,
        bool enabled,
        uint256 keepMultiple
    ) external onlyOwner {
        coinflip.setCoinflipAutoRebuy(player, enabled, keepMultiple);
    }

    function coinSetAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external onlyOwner {
        coinflip.setCoinflipAutoRebuyKeepMultiple(player, keepMultiple);
    }

    // ============================= Affiliate ===============================
    function affiliateCreateCode(bytes32 code_, uint8 rakebackPct) external onlyOwner {
        affiliate.createAffiliateCode(code_, rakebackPct);
    }

    // ============================== Jackpots ===============================
    function jackpotsClaimDecimator(uint24 lvl) external onlyOwner {
        jackpots.claimDecimatorJackpot(lvl);
    }

    // ================================ DGNRS =================================
    function dgnrsBurn(
        address player,
        uint256 amount
    ) external onlyOwner returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        return dgnrs.burn(player, amount);
    }
}
