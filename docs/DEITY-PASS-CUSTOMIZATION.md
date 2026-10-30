# Deity pass display dependencies

The renderer and icon data receive dependency review only under [scope.txt](../scope.txt). Cosmetic
appearance is outside the contest target; authorization and effects on in-scope contracts remain
relevant.

[DeityPassCustomizationRenderer](../contracts/DeityPassCustomizationRenderer.sol) stores colors and
geometry independently of gameplay. Its setters require the NFT's owner. Game operators and ERC-721
approved addresses do not gain customization authority. Geometry setters enforce bounds, including
the combined size/position constraints.

[DegenerusDeityPass](../contracts/DegenerusDeityPass.sol) selects the renderer through its owner
control. `tokenURI` calls the selected renderer and retains its default rendering fallback if that
call reverts or returns empty. Selecting a renderer does not erase another renderer's stored
settings.

[Icons32Data](../contracts/Icons32Data.sol) permits bounded creator initialization and governance
writes until finalization. [Owner governance](OWNER_GOVERNANCE.md) describes those authorities.
Neither artwork nor a suffix in a selector supplies authorization.

The source-level ABI is available through the contract's public/external functions. Compiled
artifacts supply the machine-readable ABI; a second checked-in ABI copy is unnecessary.

## Verification

Use the grouped runner from [Testing](TESTING.md):

```sh
python3 scripts/test-hardhat-groups.py --file test/unit/DeityPassCustomizationRenderer.test.js \
  --file test/unit/DegenerusDeityPass.test.js --file test/unit/GoldDice6Badge.test.js
```
