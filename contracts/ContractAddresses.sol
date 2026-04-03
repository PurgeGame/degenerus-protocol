// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// Compile-time constants populated by the deploy script.
// The deploy pipeline predicts addresses and patches this file before compilation.
library ContractAddresses {
    uint48 internal constant DEPLOY_DAY_BOUNDARY = 20545;
    bytes32 internal constant VRF_KEY_HASH = 0xabababababababababababababababababababababababababababababababab;

    address internal constant ICONS_32 = address(0x1d52eEe60b9386572cF1BC8326Bc1B9BC00a5636);
    address internal constant GAME_MINT_MODULE = address(0xC20DEdd58a9E664C2126822AA34Bdb670F268b28);
    address internal constant GAME_ADVANCE_MODULE = address(0xffdFbC4Ce7f64d61938DFde1e2e8A2917fDA9ADd);
    address internal constant GAME_WHALE_MODULE = address(0x4eD5a1E9AeC37258cf6388b0232E813d5c8BEBF1);
    address internal constant GAME_JACKPOT_MODULE = address(0x1fCcC463806434a21Ee4c5525eEEcCd8a9628Ec0);
    address internal constant GAME_DECIMATOR_MODULE = address(0x2a3a0bE7e650D4f3522E00764510f05cDdb59d44);
    address internal constant GAME_ENDGAME_MODULE = address(0xb4047178973c9d2963c136972f0f572941ebbf51);
    address internal constant GAME_GAMEOVER_MODULE = address(0x1d5D425bBC009A7eb04e8bEf007B3F13EaB963E7);
    address internal constant GAME_LOOTBOX_MODULE = address(0xE9304B70AFc81eD2067C15E1b1c1Ff2d4C6c5Ef8);
    address internal constant GAME_BOON_MODULE = address(0xa05F1B28e5b4964A2D3df7cdbe32C9bb536aCf99);
    address internal constant GAME_DEGENERETTE_MODULE = address(0x91B73475fAfABdD3a8173F5ac7C45a3eEF2B9e2B);
    address internal constant COIN = address(0x3b1b6E83D35F5f81FEc095d5993B1E3F85877614);
    address internal constant COINFLIP = address(0xd0D551BfD1F5e7025c2Aade42EEfFa9912319b68);
    address internal constant VAULT = address(0x0aE8889f40A72f47d6A2F2585d98fC0385B0926D);
    address internal constant AFFILIATE = address(0x8b2A70708382F5799421A590881Bc3AAc8cdEB28);
    address internal constant JACKPOTS = address(0xF023Ef65Ab8b9900f68A718A7117DD412682d385);
    address internal constant QUESTS = address(0xEEAEE162B565D22Fb1BEDCcc6E17909a4112Bf7b);
    address internal constant GAME = address(0x452aafC41D6dB51708B25D03a6A4FAB41E3a725D);
    address internal constant SDGNRS = address(0x3dC2d6DA9FDfed2f55AedFa16C8BFf9acd0e0bE4);
    address internal constant DGNRS = address(0xc3C3E6591e52B80D2C20df513EaC1BD2095Df3A2);
    address internal constant ADMIN = address(0xf0645259e5235d6360380973458d42d71AB0A7a0);
    address internal constant DEITY_PASS = address(0x14f497aDa44B5885595eE0D9Ee7B8e5129fE8a9B);
    address internal constant WWXRP = address(0xD54B9b2597562F757D0d333fa4D54668E35FD0dA);
    address internal constant STETH_TOKEN = address(0x8bE408cd73734fe96b35BD6C2f5Fcd6210dFE0F4);
    address internal constant LINK_TOKEN = address(0x60631bD5D174f28a9FE0a9b7eD2328b34546A34d);
    address internal constant GNRUS = address(0x1bc9A2754D84Df5de340D2a580bBcdD69F6f7891);
    address internal constant CREATOR = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address internal constant VRF_COORDINATOR = address(0xb0221109c6871aB9ca29C1E32DBa30488e8e7690);
    address internal constant WXRP = address(0x08E29584e89A05a7301b5f999DBE58Cc68A28Ace);
}
