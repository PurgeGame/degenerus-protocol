// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ContractAddresses {
    // Network Constants
    address internal constant CREATOR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant STETH_TOKEN = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Sepolia stETH
    address internal constant LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // Sepolia LINK
    address internal constant VRF_COORDINATOR = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; // Sepolia VRF V2.5
    bytes32 internal constant VRF_KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; // 100 gwei
    address internal constant WXRP = 0x0000000000000000000000000000000000000000; // TODO: Update with wXRP address

    // Cost divisor for testnet (divide all ETH amounts by 1,000,000)
    uint256 internal constant COST_DIVISOR = 1_000_000;

    // Deploy day boundary (0-indexed from Unix epoch, with JACKPOT_RESET_TIME offset)
    // IMPORTANT: Set by deployment script before deploying contracts
    // Day windows run from 22:57 UTC to 22:57 UTC (82620 second offset)
    // Example: For Jan 16, 2026 as "day 1": (1737072000 - 82620) / 86400 = 20104
    uint48 internal constant DEPLOY_DAY_BOUNDARY = 20104; // TODO: Update in deploy script

    // Contract Addresses (Precomputed)
    address internal constant ICONS_32 = 0x8B2f93c5dbF41739a19C9a75BAd0D35420A8f370;
    address internal constant TROPHY_SVG_ASSETS = 0x6dc9D20D47226Af9b76bA1Bc20Cf8443C5Ddc3b6;
    address internal constant GAME_MINT_MODULE = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address internal constant GAME_ADVANCE_MODULE = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // TODO: Update after deployment
    address internal constant GAME_WHALE_MODULE = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9; // TODO: Update after deployment
    address internal constant GAME_JACKPOT_MODULE = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address internal constant GAME_DECIMATOR_MODULE = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707; // TODO: Update after deployment
    address internal constant GAME_ENDGAME_MODULE = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address internal constant GAME_GAMEOVER_MODULE = 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853;
    address internal constant LOOTBOX = 0x0000000000000000000000000000000000000000; // TODO: Update after deployment
    address internal constant COIN = 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6;
    address internal constant COINFLIP = 0x0000000000000000000000000000000000000000; // TODO: Update after deployment
    address internal constant VAULT = 0x4cF98E2b067D05f22b569d8a37f38E8Ec9D9e52A;
    address internal constant DGNRS = 0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e; // TODO: Update after deployment
    address internal constant AFFILIATE = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
    address internal constant JACKPOTS = 0x0B306BF915C4d645ff596e518fAf3F9669b97016;
    address internal constant QUESTS = 0x610178dA211FEF7D417bC0e6FeD39F05609AD788;
    address internal constant ICON_COLOR_REGISTRY = 0xdD09Fb5B508f13218aAf22f41C9C8eAF86b9a4De;
    address internal constant RENDERER_REGULAR = 0x9A3C4439528C216cb16A49851430A8602D352B59;
    address internal constant RENDERER_REGULAR_ASSETS = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // TODO: Update after deployment
    address internal constant RENDERER_TROPHY_SVG = 0xDA9ADf339C9C85763B18A40c73daf107DD9b7D70;
    address internal constant RENDERER_TROPHY = 0x24798fa853c4b4C64944a33Ff7896cE09b2f1616;
    address internal constant GAMEPIECE_RENDERER_ROUTER = 0xF8cA8AD503FFf9cf717487bb9aCa62b185Bce5f5;
    address internal constant TROPHY_RENDERER_ROUTER = 0x97c71595906fFb8ea59F97198EcD7bE889Fe2ae9;
    address internal constant TROPHIES = 0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82;
    address internal constant GAMEPIECES = 0x9A676e781A523b5d0C0e43731313A708CB607508;
    address internal constant GAME = 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1;
    address internal constant LAZY_PASS = 0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE;
    address internal constant ADMIN = 0x8a41ff68A3Da66E9d9fed4bC6d8d857F0cD23DFD;
    address internal constant WWXRP = 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0; // TODO: Update after deployment
}
