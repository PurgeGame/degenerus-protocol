# DegenerusDeityPass.sol + DeityBoonViewer.sol -- Function-Level Audit

**Contracts:** DegenerusDeityPass, DeityBoonViewer
**Files:** contracts/DegenerusDeityPass.sol (455 lines), contracts/DeityBoonViewer.sol (171 lines)
**Solidity:** 0.8.34
**Audit date:** 2026-03-07

## Summary

ERC-721 deity pass NFT (max 32 tokens, tokenId = symbolId 0-31) with on-chain SVG rendering and optional external renderer fallback. Mint/burn gated exclusively by the Game contract via address check against `ContractAddresses.GAME`. On every ERC-721 transfer, a callback to `IDegenerusGame.onDeityPassTransfer` fires to burn BURNIE, update deity storage, and nuke sender stats. Ownership management uses a minimal Ownable pattern (not OpenZeppelin). DeityBoonViewer is a stateless view contract that reads raw deity boon state from Game and applies weighted random boon type selection across 3 daily slots.

---

## Function Audit

### DegenerusDeityPass -- Metadata & Admin

---

### `name()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function name() external pure returns (string memory)` |
| **Visibility** | external |
| **Mutability** | pure |
| **Parameters** | None |
| **Returns** | `string memory`: The token collection name `"Degenerus Deity Pass"` |

**State Reads:** None
**State Writes:** None

**Callers:** External only (ERC-721 metadata queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Always returns the same string.
**NatSpec Accuracy:** No NatSpec. Acceptable for trivial pure getter.
**Gas Flags:** None -- pure, no computation.
**Verdict:** CORRECT

---

### `symbol()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function symbol() external pure returns (string memory)` |
| **Visibility** | external |
| **Mutability** | pure |
| **Parameters** | None |
| **Returns** | `string memory`: The token symbol `"DEITY"` |

**State Reads:** None
**State Writes:** None

**Callers:** External only (ERC-721 metadata queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Always returns the same string.
**NatSpec Accuracy:** No NatSpec. Acceptable for trivial pure getter.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `owner()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function owner() external view returns (address)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `address`: The current contract owner |

**State Reads:** `_contractOwner`
**State Writes:** None

**Callers:** External only (admin queries, UI display)
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns the address that can call onlyOwner functions.
**NatSpec Accuracy:** No NatSpec. Standard ownership pattern.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferOwnership(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferOwnership(address newOwner) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newOwner` (address): New owner address |
| **Returns** | None |

**State Reads:** `_contractOwner` (via onlyOwner modifier)
**State Writes:** `_contractOwner` = newOwner

**Callers:** External only (current owner)
**Callees:** None (emits OwnershipTransferred event)

**ETH Flow:** No
**Invariants:** Only the current `_contractOwner` can call. `newOwner` must not be address(0). After execution, `_contractOwner == newOwner`.
**NatSpec Accuracy:** No NatSpec. Behavior is standard Ownable pattern.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setRenderer(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setRenderer(address newRenderer) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newRenderer` (address): New external renderer address (address(0) to disable) |
| **Returns** | None |

**State Reads:** `renderer` (for prev event param), `_contractOwner` (via onlyOwner)
**State Writes:** `renderer` = newRenderer

**Callers:** External only (owner)
**Callees:** None (emits RendererUpdated event)

**ETH Flow:** No
**Invariants:** Only owner can call. address(0) is valid (disables external rendering). After execution, `renderer == newRenderer`.
**NatSpec Accuracy:** `@notice Set optional external renderer. Set to address(0) to disable.` -- Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setRenderColors(string,string,string)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setRenderColors(string calldata outlineColor, string calldata backgroundColor, string calldata nonCryptoSymbolColor) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `outlineColor` (string): Hex color for card outline; `backgroundColor` (string): Hex color for card background; `nonCryptoSymbolColor` (string): Hex color for non-crypto symbols |
| **Returns** | None |

**State Reads:** `_contractOwner` (via onlyOwner)
**State Writes:** `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor`

**Callers:** External only (owner)
**Callees:** `_isHexColor` (private, called 3 times for validation)

**ETH Flow:** No
**Invariants:** Only owner can call. All three color params must pass `_isHexColor` validation (7 chars, `#` prefix, hex digits). After execution, all three storage colors are updated.
**NatSpec Accuracy:** `@notice Set on-chain render colors.` with param descriptions -- Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `renderColors()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `outlineColor` (string): current outline color; `backgroundColor` (string): current background color; `nonCryptoSymbolColor` (string): current non-crypto symbol color |

**State Reads:** `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor`
**State Writes:** None

**Callers:** External only (UI queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns current stored colors. Defaults: `#3f1a82`, `#d9d9d9`, `#111111`.
**NatSpec Accuracy:** `@notice Read active render colors.` -- Accurate.
**Gas Flags:** Returns 3 dynamic strings from storage -- necessary for the use case.
**Verdict:** CORRECT

---

### DegenerusDeityPass -- ERC-721 Core

---

### `supportsInterface(bytes4)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function supportsInterface(bytes4 id) external pure returns (bool)` |
| **Visibility** | external |
| **Mutability** | pure |
| **Parameters** | `id` (bytes4): Interface identifier to check |
| **Returns** | `bool`: True if the interface is supported |

**State Reads:** None
**State Writes:** None

**Callers:** External only (ERC-165 introspection)
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns true for IERC721 (`0x80ac58cd`), IERC721Metadata (`0x5b5e139f`), and IERC165 (`0x01ffc9a7`). Returns false for all others.
**NatSpec Accuracy:** No NatSpec. Standard ERC-165 pattern.
**Gas Flags:** None -- pure comparison.
**Verdict:** CORRECT -- Interface IDs are correct per EIP-165, EIP-721.

---

### `balanceOf(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function balanceOf(address account) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `account` (address): Address to query |
| **Returns** | `uint256`: Number of tokens owned by `account` |

**State Reads:** `_balances[account]`
**State Writes:** None

**Callers:** External only (ERC-721 queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Reverts with `ZeroAddress` if `account == address(0)`. Returns the tracked balance count.
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `ownerOf(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function ownerOf(uint256 tokenId) external view returns (address ownerAddr)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `tokenId` (uint256): Token to query |
| **Returns** | `address ownerAddr`: Owner of the token |

**State Reads:** `_owners[tokenId]`
**State Writes:** None

**Callers:** External only (ERC-721 queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Reverts with `InvalidToken` if token does not exist (owner == address(0)).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `getApproved(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function getApproved(uint256 tokenId) external view returns (address)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `tokenId` (uint256): Token to query |
| **Returns** | `address`: Approved address for the token (address(0) if none) |

**State Reads:** `_owners[tokenId]`, `_tokenApprovals[tokenId]`
**State Writes:** None

**Callers:** External only (ERC-721 queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** Reverts with `InvalidToken` if token does not exist.
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `isApprovedForAll(address,address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function isApprovedForAll(address account, address operator) external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `account` (address): Token owner; `operator` (address): Operator to check |
| **Returns** | `bool`: True if `operator` is approved for all of `account`'s tokens |

**State Reads:** `_operatorApprovals[account][operator]`
**State Writes:** None

**Callers:** External only (ERC-721 queries)
**Callees:** None

**ETH Flow:** No
**Invariants:** No zero-address check (per ERC-721 spec, this is acceptable).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `approve(address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): Address to approve; `tokenId` (uint256): Token to approve |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`, `_operatorApprovals[tokenOwner][msg.sender]`
**State Writes:** `_tokenApprovals[tokenId]` = to

**Callers:** External only (token owner or approved operator)
**Callees:** None (emits Approval event)

**ETH Flow:** No
**Invariants:** Only the token owner or an approved operator for the owner can call. Reverts with `NotAuthorized` otherwise. Does not check if token exists first -- but if `_owners[tokenId] == address(0)`, then `msg.sender != address(0)` is always true (since EOAs cannot be address(0)), so the operator check runs against `_operatorApprovals[address(0)][msg.sender]` which defaults to false, causing `NotAuthorized` revert. This is safe -- non-existent tokens cannot be approved.
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setApprovalForAll(address,bool)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setApprovalForAll(address operator, bool approved) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): Operator to set approval for; `approved` (bool): Whether to approve |
| **Returns** | None |

**State Reads:** None
**State Writes:** `_operatorApprovals[msg.sender][operator]` = approved

**Callers:** External only
**Callees:** None (emits ApprovalForAll event)

**ETH Flow:** No
**Invariants:** Any address can call to set operator approval for themselves. No zero-address check on operator (per ERC-721 spec).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFrom(address,address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** (delegated to `_transfer`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** All invariants enforced by `_transfer`. No receiver check (per ERC-721 transferFrom spec).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `safeTransferFrom(address,address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function safeTransferFrom(address from, address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** (delegated to `_transfer` and `_checkReceiver`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`, `_checkReceiver(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** All `_transfer` invariants plus `_checkReceiver` invariant (contract recipients must implement IERC721Receiver).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `safeTransferFrom(address,address,uint256,bytes)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer; `bytes calldata`: Additional data (unused) |
| **Returns** | None |

**State Reads:** (delegated to `_transfer` and `_checkReceiver`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`, `_checkReceiver(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** Same as 3-param `safeTransferFrom`. Note: the `data` parameter is accepted but ignored -- the `_checkReceiver` call passes empty bytes `""` to `onERC721Received` regardless of the `data` argument. This is a minor deviation from ERC-721 spec which expects `data` to be forwarded.
**NatSpec Accuracy:** No NatSpec.
**Gas Flags:** The `data` parameter is declared but never used -- minimal gas overhead (calldata is read-only, just costs calldatacopy).
**Verdict:** CONCERN -- The `data` bytes parameter in the 4-argument `safeTransferFrom` is silently ignored rather than forwarded to `onERC721Received`. Per ERC-721, the data should be passed through. In practice this is low-risk since the onDeityPassTransfer callback is the primary transfer hook, and most receivers don't use the data parameter, but it is technically non-compliant.

---

### DegenerusDeityPass -- Mint/Burn

---

### `mint(address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mint(address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): Recipient of the minted token; `tokenId` (uint256): Symbol ID (0-31) |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`
**State Writes:** `_balances[to]` (incremented), `_owners[tokenId]` = to

**Callers:** External only -- DegenerusGame contract (via `purchaseDeityPass`)
**Callees:** None (emits Transfer event with from=address(0))

**ETH Flow:** No
**Invariants:**
- Only `ContractAddresses.GAME` can call (reverts `NotAuthorized` otherwise)
- `tokenId < 32` (reverts `InvalidToken` otherwise)
- Token must not already exist: `_owners[tokenId] == address(0)` (reverts `InvalidToken` otherwise)
- `to != address(0)` (reverts `ZeroAddress` otherwise)
- After execution: `_owners[tokenId] == to`, `_balances[to]` incremented by 1

**NatSpec Accuracy:** `@notice Mint a deity pass. Only callable by the game contract during purchase.` -- Accurate. The "during purchase" clarification is contextually correct (Game calls this from purchaseDeityPass).
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `burn(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burn(uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `tokenId` (uint256): Token to burn |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`
**State Writes:** `_tokenApprovals[tokenId]` (deleted), `_balances[tokenOwner]` (decremented via unchecked), `_owners[tokenId]` (deleted)

**Callers:** External only -- DegenerusGame contract (for deity pass refunds during game over)
**Callees:** None (emits Transfer event with to=address(0))

**ETH Flow:** No
**Invariants:**
- Only `ContractAddresses.GAME` can call (reverts `NotAuthorized` otherwise)
- Token must exist: `_owners[tokenId] != address(0)` (reverts `InvalidToken` otherwise)
- After execution: `_owners[tokenId] == address(0)`, `_balances[tokenOwner]` decremented by 1, approval cleared
- `unchecked` balance decrement is safe because if the token exists, the owner's balance is >= 1

**NatSpec Accuracy:** `@notice Burn a deity pass. Only callable by the game contract (for refunds).` -- Accurate.
**Gas Flags:** `unchecked` decrement is safe (owner's balance guaranteed >= 1 since they own the token being burned).
**Verdict:** CORRECT

---

### DegenerusDeityPass -- Transfer Internals

---

### `_transfer(address,address,uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 tokenId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Claimed current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`, `_tokenApprovals[tokenId]`, `_operatorApprovals[from][msg.sender]`
**State Writes:** `_tokenApprovals[tokenId]` (deleted), `_balances[from]` (decremented, unchecked), `_balances[to]` (incremented), `_owners[tokenId]` = to

**Callers:** `transferFrom`, `safeTransferFrom` (both overloads)
**Callees:** `IDeityPassCallback(ContractAddresses.GAME).onDeityPassTransfer(from, to, uint8(tokenId))` -- cross-contract callback

**ETH Flow:** No direct ETH flow. The Game callback may perform internal ETH accounting (burns BURNIE, updates deity storage, nukes sender stats) but no ETH is transferred in this function.
**Invariants:**
- `_owners[tokenId] == from` (reverts `NotAuthorized` otherwise -- ownership verification)
- `to != address(0)` (reverts `ZeroAddress` -- cannot transfer to zero)
- `msg.sender` must be `from`, or `_tokenApprovals[tokenId]`, or an approved operator for `from` (reverts `NotAuthorized` otherwise)
- Game callback is called BEFORE state mutation (callback-first pattern). If Game callback reverts, entire transfer reverts.
- `unchecked` balance decrement is safe (from owns the token, so balance >= 1)
- After execution: `_owners[tokenId] == to`, `_balances[from]` decremented, `_balances[to]` incremented, approval cleared
- The `uint8(tokenId)` cast is safe because tokenId is guaranteed to be < 32 (only minted 0-31)

**NatSpec Accuracy:** No NatSpec on the function itself. Inline comment: `// Callback to game: burns BURNIE, updates deity storage, nukes sender stats.` -- Accurate description of what the Game contract does.
**Gas Flags:** None. The callback-first pattern (calling Game before mutating state) is intentional for correctness -- Game needs to know the transfer is happening to update its state, and if Game reverts, the transfer should fail.
**Verdict:** CORRECT -- Note: The callback-before-mutation pattern means this is NOT strictly CEI (Checks-Effects-Interactions), but it is intentional. The Game contract is a trusted fixed address, not an arbitrary external call, so reentrancy is not a concern.

---

### `_checkReceiver(address,address,uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _checkReceiver(address from, address to, uint256 tokenId) private` |
| **Visibility** | private |
| **Mutability** | state-changing (makes external call) |
| **Parameters** | `from` (address): Previous owner; `to` (address): Recipient; `tokenId` (uint256): Token transferred |
| **Returns** | None |

**State Reads:** `to.code.length` (extcodesize check)
**State Writes:** None

**Callers:** `safeTransferFrom` (both overloads)
**Callees:** `IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "")` -- external call to receiver contract

**ETH Flow:** No
**Invariants:**
- Only called if `to` is a contract (`to.code.length != 0`)
- If `to` is a contract, it must return `IERC721Receiver.onERC721Received.selector` (reverts `NotAuthorized` otherwise)
- If the call reverts, the entire safeTransferFrom reverts with `NotAuthorized`
- Always passes empty bytes `""` as data (see concern on 4-param safeTransferFrom)

**NatSpec Accuracy:** No NatSpec. Standard ERC-721 receiver check pattern.
**Gas Flags:** None.
**Verdict:** CORRECT -- Standard ERC-721 safe transfer receiver check. The empty data forwarding is noted in the safeTransferFrom entry.

---

### DegenerusDeityPass -- SVG Rendering

---

### `tokenURI(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function tokenURI(uint256 tokenId) external view returns (string memory)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `tokenId` (uint256): Token to get URI for |
| **Returns** | `string memory`: Base64-encoded JSON metadata with embedded SVG image |

**State Reads:** `_owners[tokenId]`, `renderer`, `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor` (via `_renderSvgInternal` and `_tryRenderExternal`)
**State Writes:** None

**Callers:** External only (marketplaces, wallets, UIs)
**Callees:**
- `IIcons32(ContractAddresses.ICONS_32).data(tokenId)` -- external view call to get icon SVG path data
- `IIcons32(ContractAddresses.ICONS_32).symbol(quadrant, symbolIdx)` -- external view call to get symbol name
- `_renderSvgInternal(iconPath, quadrant, symbolIdx, isCrypto)` -- internal SVG generation
- `_tryRenderExternal(tokenId, quadrant, symbolIdx, symbolName, iconPath, isCrypto)` -- conditional external renderer
- `Strings.toString()` -- OpenZeppelin uint-to-string
- `Base64.encode()` -- OpenZeppelin base64 encoding

**ETH Flow:** No
**Invariants:**
- Reverts `InvalidToken` if token does not exist
- `quadrant = tokenId / 8` (0-3), `symbolIdx = tokenId % 8` (0-7)
- `isCrypto = (quadrant == 0)` -- first quadrant is crypto symbols
- If `symbolName` is empty (no named symbol), generates fallback `"Dice N"`
- Always generates internal SVG first; if external renderer is set and succeeds with non-empty output, uses external SVG instead
- Output is always `data:application/json;base64,...` with embedded `data:image/svg+xml;base64,...`

**NatSpec Accuracy:** `@notice On-chain SVG metadata for each deity pass.` with `@dev Uses internal renderer by default; optional external renderer can override but never break tokenURI due to bounded staticcall + fallback.` -- Accurate. The try/catch in `_tryRenderExternal` ensures external renderer failures fall back gracefully.
**Gas Flags:** Multiple string concatenations via `abi.encodePacked` -- gas-heavy for on-chain view, but acceptable for view function (no state cost). Double Base64 encoding (SVG into JSON, JSON into URI) is standard for fully on-chain NFTs.
**Verdict:** CORRECT

---

### `_renderSvgInternal(string,uint8,uint8,bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _renderSvgInternal(string memory iconPath, uint8 quadrant, uint8 symbolIdx, bool isCrypto) private view returns (string memory)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `iconPath` (string): SVG path data from Icons32; `quadrant` (uint8): Symbol quadrant (0-3); `symbolIdx` (uint8): Symbol index within quadrant (0-7); `isCrypto` (bool): Whether this is a crypto symbol |
| **Returns** | `string memory`: Complete SVG string |

**State Reads:** `_nonCryptoSymbolColor`, `_backgroundColor`, `_outlineColor`
**State Writes:** None

**Callers:** `tokenURI`
**Callees:** `_symbolFitScale(quadrant, symbolIdx)`, `_symbolTranslate(ICON_VB, ICON_VB, sSym1e6)`, `_mat6(sSym1e6, txm, tyn)`

**ETH Flow:** No
**Invariants:**
- `fitSym1e6` is the scaling factor (fixed-point 1e6) for the symbol within the card
- `sSym1e6 = (2 * SYMBOL_HALF_SIZE * fitSym1e6) / ICON_VB` -- scales the symbol to fit within the card
- Non-crypto symbols get the `.nonCrypto` CSS class which overrides fill/stroke colors
- SVG viewBox is `-51 -51 102 102` (centered origin with 1px margin for stroke)
- Card is a 100x100 rounded rect with rx=12

**NatSpec Accuracy:** No NatSpec. Internal rendering helper.
**Gas Flags:** Multiple `abi.encodePacked` concatenations. Acceptable for view function.
**Verdict:** CORRECT

---

### `_tryRenderExternal(uint256,uint8,uint8,string,string,bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _tryRenderExternal(uint256 tokenId, uint8 quadrant, uint8 symbolIdx, string memory symbolName, string memory iconPath, bool isCrypto) private view returns (bool ok, string memory svg)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `tokenId` (uint256): Token ID; `quadrant` (uint8): Symbol quadrant; `symbolIdx` (uint8): Symbol index; `symbolName` (string): Symbol name; `iconPath` (string): SVG path data; `isCrypto` (bool): Whether crypto symbol |
| **Returns** | `ok` (bool): Whether external render succeeded; `svg` (string): Rendered SVG or empty |

**State Reads:** `renderer` (implicitly, caller checks `renderer != address(0)` before calling), `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor`
**State Writes:** None

**Callers:** `tokenURI` (only when `renderer != address(0)`)
**Callees:** `IDeityPassRendererV1(renderer).render(...)` -- external view call wrapped in try/catch

**ETH Flow:** No
**Invariants:**
- Uses try/catch to safely call external renderer
- If the external call reverts, returns `(false, "")`
- If the external call returns empty string, returns `(false, "")`
- Only returns `(true, svg)` if the external renderer returns a non-empty string
- The NatSpec on `IDeityPassRendererV1` says "Calls are bounded and always fallback to internal renderer on failure" -- this is enforced by this try/catch pattern

**NatSpec Accuracy:** No NatSpec on this function itself. The interface NatSpec is accurate.
**Gas Flags:** The `try` block uses a regular external call (not staticcall with gas limit), so a malicious renderer could consume all gas. However, since `renderer` is set by the owner (trusted), this is acceptable. The `view` context means this is a staticcall at the EVM level anyway.
**Verdict:** CORRECT

---

### `_isHexColor(string)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _isHexColor(string memory c) private pure returns (bool)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `c` (string): Color string to validate |
| **Returns** | `bool`: True if valid hex color (e.g. `#3f1a82`) |

**State Reads:** None
**State Writes:** None

**Callers:** `setRenderColors` (called 3 times)
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Must be exactly 7 bytes
- First byte must be `#`
- Remaining 6 bytes must be hex digits (0-9, a-f, A-F)

**NatSpec Accuracy:** No NatSpec. Behavior is self-evident from the name and logic.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_symbolFitScale(uint8,uint8)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _symbolFitScale(uint8 quadrant, uint8 symbolIdx) private pure returns (uint32)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `quadrant` (uint8): Symbol quadrant (0-3); `symbolIdx` (uint8): Symbol index within quadrant (0-7) |
| **Returns** | `uint32`: Scale factor in 1e6 fixed-point |

**State Reads:** None
**State Writes:** None

**Callers:** `_renderSvgInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Special cases for specific symbols that need tighter fit:
  - Quadrant 0, indices 1,5: 790,000 (79% scale)
  - Quadrant 2, indices 1,5: 820,000 (82% scale)
  - Quadrant 1, index 6: 820,000 (82% scale)
  - Quadrant 3, index 7: 780,000 (78% scale)
  - All others: 890,000 (89% scale)
- These are hand-tuned visual scaling factors for each icon

**NatSpec Accuracy:** No NatSpec. Internal rendering helper.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_symbolTranslate(uint16,uint16,uint32)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _symbolTranslate(uint16 w, uint16 h, uint32 sSym1e6) private pure returns (int256 txm, int256 tyn)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `w` (uint16): Icon viewbox width; `h` (uint16): Icon viewbox height; `sSym1e6` (uint32): Scale factor in 1e6 |
| **Returns** | `txm` (int256): X translation in 1e6; `tyn` (int256): Y translation in 1e6 |

**State Reads:** None
**State Writes:** None

**Callers:** `_renderSvgInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Centers the symbol by computing `txm = -(w * scale) / 2` and `tyn = -(h * scale) / 2`
- Always called with `w = h = ICON_VB = 512`

**NatSpec Accuracy:** No NatSpec. Internal rendering math.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_mat6(uint32,int256,int256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _mat6(uint32 s1e6, int256 tx1e6, int256 ty1e6) private pure returns (string memory)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `s1e6` (uint32): Scale factor in 1e6; `tx1e6` (int256): X translation in 1e6; `ty1e6` (int256): Y translation in 1e6 |
| **Returns** | `string memory`: SVG matrix transform string `"matrix(s 0 0 s tx ty)"` |

**State Reads:** None
**State Writes:** None

**Callers:** `_renderSvgInternal`
**Callees:** `_dec6(uint256(s1e6))`, `_dec6s(tx1e6)`, `_dec6s(ty1e6)`

**ETH Flow:** No
**Invariants:**
- Produces SVG `matrix(a 0 0 d e f)` transform (uniform scale + translate)
- `a = d = scale`, `b = c = 0` (no skew/rotation), `e = tx`, `f = ty`

**NatSpec Accuracy:** No NatSpec. Internal rendering helper.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_dec6(uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _dec6(uint256 x) private pure returns (string memory)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `x` (uint256): Fixed-point 1e6 value |
| **Returns** | `string memory`: Decimal string representation (e.g. 890000 -> "0.890000") |

**State Reads:** None
**State Writes:** None

**Callers:** `_mat6`, `_dec6s`
**Callees:** `Strings.toString(i)`, `_pad6(uint32(f))`

**ETH Flow:** No
**Invariants:** Splits into integer part (x / 1_000_000) and fractional part (x % 1_000_000). Always produces 6 decimal places.
**NatSpec Accuracy:** No NatSpec. Internal formatting helper.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_dec6s(int256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _dec6s(int256 x) private pure returns (string memory)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `x` (int256): Signed fixed-point 1e6 value |
| **Returns** | `string memory`: Signed decimal string representation |

**State Reads:** None
**State Writes:** None

**Callers:** `_mat6`
**Callees:** `_dec6(uint256(-x))` or `_dec6(uint256(x))`

**ETH Flow:** No
**Invariants:** Prepends `-` for negative values, delegates to `_dec6` for magnitude.
**NatSpec Accuracy:** No NatSpec. Internal formatting helper.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_pad6(uint32)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _pad6(uint32 f) private pure returns (string memory)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `f` (uint32): Fractional part (0-999999) |
| **Returns** | `string memory`: Zero-padded 6-digit string |

**State Reads:** None
**State Writes:** None

**Callers:** `_dec6`
**Callees:** None

**ETH Flow:** No
**Invariants:** Always produces exactly 6 ASCII digit characters. Fills from right to left using modulo arithmetic. E.g. `f=42` produces `"000042"`.
**NatSpec Accuracy:** No NatSpec. Internal formatting helper.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### DegenerusDeityPass -- Constructor

---

### `constructor()` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | N/A (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** None
**State Writes:** `_contractOwner` = msg.sender

**Callers:** Deploy transaction
**Callees:** None (emits OwnershipTransferred event with from=address(0))

**ETH Flow:** No
**Invariants:** Sets deployer as initial owner. Emits OwnershipTransferred(address(0), msg.sender).
**NatSpec Accuracy:** No NatSpec on constructor.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### DegenerusDeityPass -- Modifier

---

### `onlyOwner` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyOwner()` |
| **Visibility** | N/A (modifier) |
| **Mutability** | view (reads storage) |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `_contractOwner`
**State Writes:** None

**Callers:** `transferOwnership`, `setRenderer`, `setRenderColors`
**Callees:** None

**ETH Flow:** No
**Invariants:** Reverts with `NotAuthorized` if `msg.sender != _contractOwner`.
**NatSpec Accuracy:** No NatSpec.
**Gas Flags:** None.
**Verdict:** CORRECT

---

## DeityBoonViewer

---

### `deityBoonSlots(address,address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function deityBoonSlots(address game, address deity) external view returns (uint8[3] memory slots, uint8 usedMask, uint48 day)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `game` (address): DegenerusGame contract address; `deity` (address): Deity address to query |
| **Returns** | `slots` (uint8[3]): Array of 3 boon type IDs; `usedMask` (uint8): Bitmask of used slots; `day` (uint48): Current day index |

**State Reads:** None (stateless contract)
**State Writes:** None

**Callers:** External only (UI/frontends to display deity boon options)
**Callees:**
- `IDeityBoonDataSource(game).deityBoonData(deity)` -- external view call to Game contract
- `_boonFromRoll(seed % total, decimatorOpen, deityPassAvailable)` -- internal, called 3 times

**ETH Flow:** No
**Invariants:**
- Reads raw boon state from Game contract: `dailySeed`, `day`, `usedMask`, `decimatorOpen`, `deityPassAvailable`
- For each of 3 slots, deterministically computes a boon type from: `keccak256(abi.encode(dailySeed, deity, day, slotIndex))`
- Total weight pool: `W_TOTAL = 1298` (with decimator), `W_TOTAL_NO_DECIMATOR = 1248` (without), minus `W_DEITY_PASS_ALL = 40` if no deity pass available
- Each slot's seed is modulo total weight, then mapped to boon type via `_boonFromRoll`

**NatSpec Accuracy:** `@notice Compute deity boon slots for a given deity.` with param/return descriptions -- Accurate.
**Gas Flags:** None. Clean view function.
**Verdict:** CORRECT

---

### `_boonFromRoll(uint256,bool,bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _boonFromRoll(uint256 roll, bool decimatorAllowed, bool deityEligible) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `roll` (uint256): Random roll value (0 to total-1); `decimatorAllowed` (bool): Whether decimator boons are in the pool; `deityEligible` (bool): Whether deity pass boons are in the pool |
| **Returns** | `uint8`: Boon type ID |

**State Reads:** None
**State Writes:** None

**Callers:** `deityBoonSlots` (called 3 times per query)
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Implements weighted random selection using cursor accumulation pattern
- Weight distribution (all boons, full pool = 1298):
  - Coinflip: 5% (200), 10% (40), 25% (8) = 248
  - Lootbox: 5% (200), 15% (30), 25% (8) = 238
  - Purchase: 5% (400), 15% (80), 25% (16) = 496
  - Decimator: 10% (40), 25% (8), 50% (2) = 50 [conditional]
  - Whale: 10% (28), 25% (10), 50% (2) = 40
  - Deity Pass: 10% (28), 25% (10), 50% (2) = 40 [conditional]
  - Activity: 10% (100), 25% (30), 50% (8) = 138
  - Whale Pass: (8) = 8
  - Lazy Pass: 10% (30), 25% (8), 50% (2) = 40
- Weight verification: 248 + 238 + 496 + 50 + 40 + 40 + 138 + 8 + 40 = 1298 = W_TOTAL. Correct.
- Without decimator: 1298 - 50 = 1248 = W_TOTAL_NO_DECIMATOR. Correct.
- Without deity pass: subtracts 40 = W_DEITY_PASS_ALL. Correct.
- Fallback: returns `DEITY_BOON_ACTIVITY_50` if roll exceeds all cursors (should not happen with correct total, but provides safety)
- When `decimatorAllowed == false`, the decimator section is skipped entirely (cursor doesn't advance for those weights)
- When `deityEligible == false`, the deity pass section is skipped entirely

**NatSpec Accuracy:** No NatSpec. Internal helper.
**Gas Flags:** Linear scan through all weight buckets. With ~24 comparisons max, this is cheap and acceptable.
**Verdict:** CORRECT -- Weight sums verified, conditional sections correctly skip weights, fallback is safe.

---

## Access Control Matrix

| Modifier / Check | Functions | Who Can Call |
|-------------------|-----------|-------------|
| `onlyOwner` | `transferOwnership`, `setRenderer`, `setRenderColors` | Contract owner (deployer initially) |
| `msg.sender == ContractAddresses.GAME` | `mint`, `burn` | DegenerusGame contract only |
| ERC-721 ownership/approval rules | `approve`, `transferFrom`, `safeTransferFrom` (both) | Token owner or approved address/operator |
| (none) | `setApprovalForAll` | Any address (for their own approvals) |
| (none - view/pure) | `name`, `symbol`, `owner`, `renderColors`, `supportsInterface`, `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `tokenURI` | Anyone |
| (none - view) | `deityBoonSlots` | Anyone |
| (none - pure) | `_boonFromRoll` | Internal only |

## Storage Mutation Map

| Function | Variables Written | Write Type |
|----------|------------------|------------|
| `constructor` | `_contractOwner` | Initialize |
| `transferOwnership` | `_contractOwner` | Overwrite |
| `setRenderer` | `renderer` | Overwrite |
| `setRenderColors` | `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor` | Overwrite |
| `approve` | `_tokenApprovals[tokenId]` | Overwrite |
| `setApprovalForAll` | `_operatorApprovals[msg.sender][operator]` | Overwrite |
| `mint` | `_balances[to]` (increment), `_owners[tokenId]` | Increment, Initialize |
| `burn` | `_tokenApprovals[tokenId]` (delete), `_balances[tokenOwner]` (decrement), `_owners[tokenId]` (delete) | Delete, Decrement, Delete |
| `_transfer` | `_tokenApprovals[tokenId]` (delete), `_balances[from]` (decrement), `_balances[to]` (increment), `_owners[tokenId]` | Delete, Decrement, Increment, Overwrite |

**DeityBoonViewer:** No storage mutations. Entirely stateless (no constructor, no state variables, all constants are `private constant`).

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| (none) | N/A | N/A | N/A | N/A |

DegenerusDeityPass has no `payable` functions, no `receive()`, no `fallback()`. It never holds, receives, or transfers ETH. DeityBoonViewer is similarly ETH-free. All ETH flows related to deity passes (purchase price, refunds) occur in the DegenerusGame contract, not in the NFT contract itself.

## Cross-Contract Call Graph

| Caller Function | Target Contract | Target Method | Call Type | Purpose |
|-----------------|----------------|---------------|-----------|---------|
| `tokenURI` | `IIcons32` (ContractAddresses.ICONS_32) | `data(tokenId)` | view call | Get SVG path data for icon |
| `tokenURI` | `IIcons32` (ContractAddresses.ICONS_32) | `symbol(quadrant, symbolIdx)` | view call | Get symbol name |
| `_tryRenderExternal` | `IDeityPassRendererV1` (renderer) | `render(...)` | try/catch view call | Optional external SVG rendering |
| `_transfer` | `IDeityPassCallback` (ContractAddresses.GAME) | `onDeityPassTransfer(from, to, symbolId)` | state-changing call | Notify Game of deity pass transfer; Game burns BURNIE, updates deity storage, nukes sender stats |
| `_checkReceiver` | `IERC721Receiver` (to) | `onERC721Received(operator, from, tokenId, "")` | call | ERC-721 safe transfer receiver check |
| `deityBoonSlots` | `IDeityBoonDataSource` (game param) | `deityBoonData(deity)` | view call | Read raw deity boon state from Game |

**Inbound calls (from other contracts to DegenerusDeityPass):**

| Source Contract | Method Called | Purpose |
|-----------------|-------------|---------|
| DegenerusGame | `mint(to, tokenId)` | Mint deity pass during purchase |
| DegenerusGame | `burn(tokenId)` | Burn deity pass during game-over refund |
| Marketplaces/Users | `transferFrom`, `safeTransferFrom`, `approve`, etc. | Standard ERC-721 operations |

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 1 | `safeTransferFrom(from,to,tokenId,data)` silently ignores `data` parameter instead of forwarding to `onERC721Received`. Minor ERC-721 spec deviation. |
| GAS | 0 | No gas inefficiencies found (all heavy computation is in view functions) |
| INFO | 0 | N/A |
| CORRECT | 30 | All other functions verified correct |

### Detailed Concern

**CONCERN-01: safeTransferFrom data parameter not forwarded**

The 4-argument `safeTransferFrom(address,address,uint256,bytes)` accepts a `data` parameter but the internal `_checkReceiver` always passes empty bytes `""` to `onERC721Received`. Per ERC-721 spec (EIP-721), the data should be forwarded to the receiver. This is a minor spec deviation.

**Impact:** Low. The `onDeityPassTransfer` callback in `_transfer` is the primary transfer hook mechanism. Most ERC-721 receivers do not use the data parameter. No known receiver in the Degenerus protocol depends on this data.

**Recommendation:** Informational only. If strict ERC-721 compliance is desired, `_checkReceiver` could accept and forward the data parameter.
