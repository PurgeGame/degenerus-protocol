// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// Compile-time constants populated by the deploy script.
// The deploy pipeline predicts addresses and patches this file before compilation.
library ContractAddresses {
    uint48 internal constant DEPLOY_DAY_BOUNDARY = 0;
    bytes32 internal constant VRF_KEY_HASH = 0xabababababababababababababababababababababababababababababababab;

    address internal constant ICONS_32 = address(0xa0Cb889707d426A7A386870A03bc70d1b0697598);
    address internal constant GAME_MINT_MODULE = address(0x1d1499e622D69689cdf9004d05Ec547d650Ff211);
    address internal constant GAME_ADVANCE_MODULE = address(0xA4AD4f68d0b91CFD19687c881e50f3A00242828c);
    address internal constant GAME_WHALE_MODULE = address(0x03A6a84cD762D9707A21605b548aaaB891562aAb);
    address internal constant GAME_JACKPOT_MODULE = address(0xD6BbDE9174b1CdAa358d2Cf4D57D1a9F7178FBfF);
    address internal constant GAME_DECIMATOR_MODULE = address(0x15cF58144EF33af1e14b5208015d11F9143E27b9);
    address internal constant GAME_ENDGAME_MODULE = address(0xb4047178973c9d2963c136972f0f572941ebbf51);
    address internal constant GAME_GAMEOVER_MODULE = address(0x212224D2F2d262cd093eE13240ca4873fcCBbA3C);
    address internal constant GAME_LOOTBOX_MODULE = address(0x2a07706473244BC757E10F2a9E86fB532828afe3);
    address internal constant GAME_BOON_MODULE = address(0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7);
    address internal constant GAME_DEGENERETTE_MODULE = address(0xD16d567549A2a2a2005aEACf7fB193851603dd70);
    address internal constant COIN = address(0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758);
    address internal constant COINFLIP = address(0x13aa49bAc059d709dd0a18D6bb63290076a702D7);
    address internal constant VAULT = address(0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da);
    address internal constant AFFILIATE = address(0x756e0562323ADcDA4430d6cb456d9151f605290B);
    address internal constant JACKPOTS = address(0x1aF7f588A501EA2B5bB3feeFA744892aA2CF00e6);
    address internal constant QUESTS = address(0xe8dc788818033232EF9772CB2e6622F1Ec8bc840);
    address internal constant GAME = address(0xDB25A7b768311dE128BBDa7B8426c3f9C74f3240);
    address internal constant SDGNRS = address(0x796f2974e3C1af763252512dd6d521E9E984726C);
    address internal constant DGNRS = address(0x92a6649Fdcc044DA968d94202465578a9371C7b1);
    address internal constant ADMIN = address(0xDA5A5ADC64C8013d334A0DA9e711B364Af7A4C2d);
    address internal constant DEITY_PASS = address(0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E);
    address internal constant WWXRP = address(0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f);
    address internal constant STETH_TOKEN = address(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
    address internal constant LINK_TOKEN = address(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a);
    address internal constant GNRUS = address(0x886D6d1eB8D415b00052828CD6d5B321f072073d);
    address internal constant CREATOR = address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);
    address internal constant VRF_COORDINATOR = address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f);
    address internal constant WXRP = address(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9);
}
