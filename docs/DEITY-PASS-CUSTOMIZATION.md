# Deity pass cosmetics

`DeityPassCustomizationRenderer` adds per-token artwork settings to an **existing**
`DegenerusDeityPass`. No NFT redeployment, migration, remint, proxy upgrade, pass
storage change, or gameplay change is required. The inspected pass already calls
`IDeityPassRendererV1.render(...)` with the token ID, canonical symbol path and
collection colors. The extension implements that exact hook and stores overrides
in its own contract.

Only the current `pass.ownerOf(tokenId)` can write or clear overrides. Game
operator approval, Vault majority ownership, and the renderer deployer convey no
additional editing permission. `pass.setRenderer(address)` and
`pass.setRenderColors(string,string,string)` retain their existing Vault-majority
authorization. Passes remain soulbound.

## Frontend contract

Full generated ABI: [`abi/DeityPassCustomizationRenderer.json`](abi/DeityPassCustomizationRenderer.json).
Send customization transactions to the **renderer address**, not the NFT address.
Read the active address using `pass.renderer()` and verify it against the supported
deployment on the selected chain. The existing champion picker can continue reading
`pass.tokenURI(tokenId)`; it receives the customized SVG automatically after activation.

Struct fields, in ABI order:

```solidity
struct Colors {
    string rimColor;
    string badgeBackgroundColor;
    string symbolColor;
    string backgroundColor;
    string outlineColor;
}
struct Geometry {
    uint16 radius;
    int16 centerX;
    int16 centerY;
}
struct Customization {
    Colors colors;
    Geometry geometry;
    uint8 overrideMask;
}
```

| Field | Artwork | Inherited default | Override bit |
| --- | --- | --- | --- |
| `rimColor` | Outer champion badge ring; present this picker first | Collection outline; XRP `#ed0e11`, Ethereum `#30d100` | 1 |
| `badgeBackgroundColor` | Inner circle immediately behind the symbol | `#ffffff`; legacy collection-gold Dice 6 uses `#111111` | 2 |
| `symbolColor` | Inherited non-crypto fill/stroke; explicit cutouts/pips retain their authored treatment | Collection non-crypto ink | 4 |
| `backgroundColor` | NFT card fill | Collection background | 8 |
| `outlineColor` | NFT card border | Collection outline | 16 |
| `geometry` | Size and center of the whole badge, including all rings and the icon | Radius 4600, center `(0,0)` | 32 |

Hex colors must be exactly `#RRGGBB` (case insensitive). In **setter/raw override**
values, `""` means inherit that one field. A nonempty value remains an override even
if it currently equals the default. In **effective** values, all supported colors
are resolved; crypto tokens 0–7 return `symbolColor == ""`, meaning original
multicolor artwork. Disable their ink picker: a nonempty crypto ink override reverts
with `UnsupportedSymbolInk`. Crypto icon paths, fills, gradients and artwork are
passed through verbatim; their surrounding rings and backgrounds are customizable.

The fixed decorative middle ring remains dark. The legacy collection-gold Dice 6
template has a white middle ring and dark pips. That template follows the
**collection defaults**, independently of holder overrides: changing the holder's
rim or ink never silently changes another color picker. An explicit badge background
always wins over the template's default inner fill.

### Read and write signatures

```solidity
function pass() external view returns (address);
function tokenCustomization(uint256 tokenId) external view returns (Customization memory);
function effectiveTokenStyle(uint256 tokenId)
    external view returns (Colors memory colors, Geometry memory geometry, uint8 overrideMask);

function setTokenColors(uint256 tokenId, Colors calldata colors) external;
function clearTokenColors(uint256 tokenId) external;
function setTokenGeometry(uint256 tokenId, Geometry calldata geometry) external;
function clearTokenGeometry(uint256 tokenId) external;
function clearTokenCustomization(uint256 tokenId) external;

function geometryBounds() external pure returns (
    uint16 unitsPerSvgUnit, uint16 minRadius, uint16 maxRadius,
    uint16 defaultRadius, uint16 innerHalfExtent, uint16 innerCornerRadius
);
function positionBounds(uint16 radius) external pure returns (int16 minCenter, int16 maxCenter);
function isValidGeometry(uint16 radius, int16 centerX, int16 centerY) external pure returns (bool);
```

Canonical transaction signatures (tuples, not struct names):

```text
setTokenColors(uint256,(string,string,string,string,string))
clearTokenColors(uint256)
setTokenGeometry(uint256,(uint16,int16,int16))
clearTokenGeometry(uint256)
clearTokenCustomization(uint256)
```

`setTokenColors` replaces all five color overrides and leaves geometry unchanged.
For a single-picker edit, read `tokenCustomization`, retain the other **raw**
values, and replace the selected field. Do not submit the effective defaults as
overrides unless the owner wants to lock those colors. Setting a field to `""`
clears that field. `clearTokenColors` clears all five colors without changing
geometry; `clearTokenGeometry` restores the default radius and centered position
without changing colors; `clearTokenCustomization` clears everything. Resets use
the current collection defaults and continue following future default changes.

`overrideMask != 0` means at least one override exists. Test each bit to mark
individual pickers as inherited/custom. Raw geometry is zeroed when absent; use
effective geometry for previews and sliders. Every token-specific read/write
requires an already minted ID in `[0,31]` and reverts `InvalidToken` otherwise.
Writes from anyone other than the NFT owner revert `NotTokenOwner`; malformed
colors revert `InvalidColor`; invalid geometry reverts `InvalidGeometry`.

Example: Aries (ID 8) gets a pink ring, retaining existing independent overrides:

```js
const raw = await renderer.tokenCustomization(8);
await renderer.connect(owner).setTokenColors(8, {
  rimColor: "#ff69b4",
  badgeBackgroundColor: raw.colors.badgeBackgroundColor,
  symbolColor: raw.colors.symbolColor,
  backgroundColor: raw.colors.backgroundColor,
  outlineColor: raw.colors.outlineColor,
});
// Taurus (ID 9) is unchanged. Refetch pass.tokenURI(8) after confirmation.
```

## Badge geometry and preview coordinates

All geometry fields use **hundredths of one SVG unit**, not percentages or pixels.
The card is 100 units wide, centered at `(0,0)`; positive X moves right and positive Y
moves down. The SVG `viewBox` is `-52 -52 104 104`, including the card's full outline
(the original internal renderer's 102-unit viewBox cuts off 0.1 unit of that stroke).

`geometryBounds()` returns `(100, 1200, 4890, 4600, 4890, 1090)`:

- Radius: 1200–4890 inclusive (12–48.9 SVG units); default 4600 (46 units).
- At radius `r`, each coordinate must independently satisfy
  `-(4890-r) <= center <= 4890-r`. `positionBounds(r)` returns these inclusive bounds.
- The slider step is 1 (0.01 SVG unit). Its valid position range changes with size.
  Submit size and both coordinates together. A larger offset badge is rejected
  unless the same transaction also brings its center within the new bounds.
- `isValidGeometry` reports validity without changing state; `positionBounds`
  reverts for an invalid radius. Frontends should clamp/recenter the proposed
  position before submitting a resize and show the resulting preview.

The badge transform is `matrix(s 0 0 s x y)`, where
`s = floor(radius * 1_000_000 / 4600) / 1_000_000`,
`x = centerX / 100`, and `y = centerY / 100`. It encloses all three circles and the
symbol. The base ring radii are 46, 35 and 28, with the existing per-symbol fit
table. Strokes scale with the badge; there are no non-scaling strokes. For exact
previews use the returned SVG; local previews should apply this transform and the
same source paths, rather than changing a gameplay ticket's colors or geometry.

The bound includes the card stroke: its inner edge is at `50 - 2.2/2 = 48.9`,
and its inner corner radius is `12 - 2.2/2 = 10.9`. The minimum badge radius 12 is
larger than 10.9. For circles at least that large, the axis bounds above also keep
the entire circle within every rounded corner (not just its center or a square
card). Rings have no strokes; the fitted canonical icon artwork and its scaling
strokes stay within the outer ring. This relies on the production Icons32 artwork,
as does the original renderer; arbitrary replacement SVGs in an unfinalized Icons32
contract are trusted collection data, not holder-controlled input.

## Events and cache refresh

```solidity
event TokenColorsUpdated(uint256 indexed tokenId, Colors overrides, uint8 overrideMask);
event TokenGeometryUpdated(uint256 indexed tokenId, Geometry geometry, bool overridden);
event TokenCustomizationCleared(uint256 indexed tokenId);
event MetadataUpdate(uint256 indexed tokenId);
```

Every successful setting/reset emits its specific event plus `MetadataUpdate`.
`TokenColorsUpdated.overrideMask` is the complete post-write mask, including any
geometry bit. Geometry reset emits the effective `(4600,0,0)` and `overridden=false`.
Complete reset emits `TokenCustomizationCleared` rather than separate color and
geometry events. Events originate at the **renderer**. The unchanged NFT does not
emit ERC-4906 events or advertise that interface, so marketplaces listening only
to the NFT may require their usual explicit metadata refresh.

Subscribe to this renderer's `MetadataUpdate` and the pass's `RenderColorsUpdated`
and `RendererUpdated`. Invalidate the affected champion/NFT preview, or all previews
for a collection-level change. Key customization caches by chain, pass, renderer,
and token ID; overrides belong to a particular renderer instance.

## Exact deployment and activation requirements

No live deployment or transactions were performed for this change. Deployment is
an explicit future operation:

1. Select the target chain and existing pass address. Verify that the deployed pass
   has the inspected V1 hook and Vault-controlled `setRenderer`; confirm its
   `ownerOf`, `renderColors`, `renderer`, and `tokenURI` views. Confirm the expected
   production Icons32 paths are installed (normally finalized by deployment).
   This source-based compatibility result does not attest an unspecified live address.
2. Compile `contracts/DeityPassCustomizationRenderer.sol` with the repository's
   Solidity **0.8.34**, optimizer **1000 runs**, **viaIR=true**, EVM **osaka** settings.
   The target network must support that EVM target. Deploy **one**
   `DeityPassCustomizationRenderer(existingPassAddress)` after the pass exists.
   The constructor rejects addresses with no code; the binding is immutable.
   Do not insert this deployment into the existing predicted nonce sequence or
   change `ContractAddresses.sol`; it is a separate, optional deployment.
3. Verify the extension's source/constructor argument, and that `renderer.pass()`
   equals the existing NFT address. Record the chain, pass and renderer addresses
   for the frontend. The extension has no administrator or initialization call.
4. From an account satisfying the existing pass's `vault.isVaultOwner(msg.sender)`
   check, call **`existingPass.setRenderer(newRendererAddress)`**. Only this
   Vault-authorized transaction activates customization in the existing `tokenURI`.
   No owner approvals, collection-color transaction or NFT migration are required.
5. Configure frontend writes and event subscriptions with the new renderer ABI and
   address. Confirm a minted token's `tokenURI` contains the `id='badge'` group and
   matches `effectiveTokenStyle`. Existing holders can now submit their own settings.

Holders may save settings before activation, but they appear in `tokenURI` only
while this renderer is selected. Setting `pass.setRenderer(address(0))` restores
the internal renderer; selecting another renderer delegates artwork to it. Neither
action deletes settings here. Selecting this same instance again restores them;
deploying a fresh instance starts with no overrides. If the hook reverts or returns
empty, the pass retains its existing internal-default fallback behavior.

Contract-owned NFTs have the same strict owner rule. In particular, the genesis
XRP and Ethereum passes are owned by protocol contracts: a Vault majority holder
or game operator cannot edit on their behalf. Such a token can only be customized
if its actual owning contract has a suitable call path; this extension adds no
forwarder to those existing owners.

## Validation

```sh
npx hardhat test test/unit/DeityPassCustomizationRenderer.test.js \
  test/unit/DegenerusDeityPass.test.js test/unit/GoldDice6Badge.test.js
```

The focused suite covers owner success, all unauthorized write/reset paths,
approved game operators, unminted/out-of-range IDs, malformed colors in every
field, independently inherited colors, resets, crypto preservation, SVG output,
token isolation, min/max sizes, every edge/corner combination, one-unit-outside
rejections, and atomic resize/recenter checks. A separate geometric oracle samples
the rendered circle boundary against the inner rounded card. Transaction traces
verify the mutation paths use only external `STATICCALL` and write only renderer
storage. Symbol metadata stays unchanged; no gameplay contract imports or reads
this extension, and no scoring, roll, odds, ticket-color or boon logic is modified.

Validation completed: 14 customization tests and 69 existing pass/gold-dice
regressions passed. All 32 production symbols were also rendered through the
compiled extension and raster-checked for badge-envelope overflow; none exceeded
the outer ring. The published ABI matches the compiled artifact. Renderer runtime
bytecode is 11,048 bytes with the stated compiler settings.
