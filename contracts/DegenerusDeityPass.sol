// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface IIcons32 {
    function data(uint256 i) external view returns (string memory);
    function symbol(uint256 quadrant, uint8 idx) external view returns (string memory);
}

/// @notice Optional external renderer interface (v1).
/// @dev Calls are bounded and always fallback to internal renderer on failure.
interface IDeityPassRendererV1 {
    function render(
        uint256 tokenId,
        uint8 quadrant,
        uint8 symbolIdx,
        string calldata symbolName,
        string calldata iconPath,
        bool isCrypto,
        string calldata outlineColor,
        string calldata backgroundColor,
        string calldata nonCryptoSymbolColor
    ) external view returns (string memory);
}

/// @title DegenerusDeityPass
/// @notice Minimal ERC721 for deity passes. 32 tokens max (one per symbol).
///         On transfer, calls back to the game contract to burn BURNIE, update storage,
///         and nuke sender stats. tokenId = symbolId (0-23).
contract DegenerusDeityPass {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotAuthorized();
    error InvalidToken();
    error ZeroAddress();
    error InvalidColor();

    // -------------------------------------------------------------------------
    // Events (ERC721)
    // -------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RendererUpdated(address indexed previousRenderer, address indexed newRenderer);
    event RenderColorsUpdated(string outlineColor, string backgroundColor, string nonCryptoSymbolColor);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    address private _contractOwner;
    address public renderer;

    uint16 private constant ICON_VB = 512;
    uint32 private constant SYMBOL_HALF_SIZE = 37;

    string private _outlineColor = "#3f1a82";
    string private _backgroundColor = "#d9d9d9";
    string private _nonCryptoSymbolColor = "#111111";

    modifier onlyOwner() {
        if (msg.sender != _contractOwner) revert NotAuthorized();
        _;
    }

    constructor() {
        _contractOwner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // -------------------------------------------------------------------------
    // ERC721 Metadata
    // -------------------------------------------------------------------------

    function name() external pure returns (string memory) { return "Degenerus Deity Pass"; }
    function symbol() external pure returns (string memory) { return "DEITY"; }
    function owner() external view returns (address) { return _contractOwner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = _contractOwner;
        _contractOwner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }

    /// @notice Set optional external renderer. Set to address(0) to disable.
    function setRenderer(address newRenderer) external onlyOwner {
        address prev = renderer;
        renderer = newRenderer;
        emit RendererUpdated(prev, newRenderer);
    }

    /// @notice Set on-chain render colors.
    /// @param outlineColor Hex color for the card outline (e.g. #3f1a82).
    /// @param backgroundColor Hex color for the card background.
    /// @param nonCryptoSymbolColor Hex color for non-crypto symbols.
    function setRenderColors(
        string calldata outlineColor,
        string calldata backgroundColor,
        string calldata nonCryptoSymbolColor
    ) external onlyOwner {
        if (!_isHexColor(outlineColor) || !_isHexColor(backgroundColor) || !_isHexColor(nonCryptoSymbolColor)) {
            revert InvalidColor();
        }
        _outlineColor = outlineColor;
        _backgroundColor = backgroundColor;
        _nonCryptoSymbolColor = nonCryptoSymbolColor;
        emit RenderColorsUpdated(outlineColor, backgroundColor, nonCryptoSymbolColor);
    }

    /// @notice Read active render colors.
    function renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor) {
        return (_outlineColor, _backgroundColor, _nonCryptoSymbolColor);
    }

    /// @notice On-chain SVG metadata for each deity pass.
    /// @dev Uses internal renderer by default; optional external renderer can override
    ///      but never break tokenURI due to bounded staticcall + fallback.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();

        IIcons32 icons = IIcons32(ContractAddresses.ICONS_32);
        string memory iconPath = icons.data(tokenId);
        uint8 quadrant = uint8(tokenId / 8);
        uint8 symbolIdx = uint8(tokenId % 8);
        string memory symbolName = icons.symbol(quadrant, symbolIdx);
        if (bytes(symbolName).length == 0) {
            symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));
        }
        bool isCrypto = quadrant == 0;

        string memory svg = _renderSvgInternal(
            iconPath,
            quadrant,
            symbolIdx,
            isCrypto
        );
        if (renderer != address(0)) {
            (bool ok, string memory extSvg) = _tryRenderExternal(
                tokenId,
                quadrant,
                symbolIdx,
                symbolName,
                iconPath,
                isCrypto
            );
            if (ok && bytes(extSvg).length != 0) {
                svg = extSvg;
            }
        }

        string memory json = string(abi.encodePacked(
            '{"name":"Deity Pass #', Strings.toString(tokenId), ' - ', symbolName,
            '","description":"Degenerus Deity Pass. Grants divine authority over the ',
            symbolName, ' symbol.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    function _renderSvgInternal(
        string memory iconPath,
        uint8 quadrant,
        uint8 symbolIdx,
        bool isCrypto
    ) private view returns (string memory) {
        uint32 fitSym1e6 = _symbolFitScale(quadrant, symbolIdx);
        uint32 sSym1e6 = uint32((uint256(2) * SYMBOL_HALF_SIZE * fitSym1e6) / ICON_VB);
        (int256 txm, int256 tyn) = _symbolTranslate(ICON_VB, ICON_VB, sSym1e6);

        string memory symbolGroup = string(
            abi.encodePacked(
                "<g transform='",
                _mat6(sSym1e6, txm, tyn),
                isCrypto
                    ? "'><g style='vector-effect:non-scaling-stroke'>"
                    : "'><g class='nonCrypto' style='vector-effect:non-scaling-stroke'>",
                iconPath,
                "</g></g>"
            )
        );

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'
            '<defs>'
            '<style>.nonCrypto *{fill:',
            _nonCryptoSymbolColor,
            '!important;stroke:',
            _nonCryptoSymbolColor,
            '!important;}</style>'
            '</defs>'
            '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',
            _backgroundColor,
            '" stroke="',
            _outlineColor,
            '" stroke-width="2.2"/>',
            symbolGroup,
            "</svg>"
        ));
    }

    function _tryRenderExternal(
        uint256 tokenId,
        uint8 quadrant,
        uint8 symbolIdx,
        string memory symbolName,
        string memory iconPath,
        bool isCrypto
    ) private view returns (bool ok, string memory svg) {
        try IDeityPassRendererV1(renderer).render(
            tokenId,
            quadrant,
            symbolIdx,
            symbolName,
            iconPath,
            isCrypto,
            _outlineColor,
            _backgroundColor,
            _nonCryptoSymbolColor
        ) returns (string memory out) {
            if (bytes(out).length == 0) return (false, "");
            return (true, out);
        } catch {
            return (false, "");
        }
    }

    function _isHexColor(string memory c) private pure returns (bool) {
        bytes memory b = bytes(c);
        if (b.length != 7 || b[0] != "#") return false;
        for (uint256 i = 1; i < 7; ++i) {
            bytes1 ch = b[i];
            bool digit = ch >= "0" && ch <= "9";
            bool lower = ch >= "a" && ch <= "f";
            bool upper = ch >= "A" && ch <= "F";
            if (!(digit || lower || upper)) return false;
        }
        return true;
    }

    function _symbolFitScale(uint8 quadrant, uint8 symbolIdx) private pure returns (uint32) {
        if (quadrant == 0 && (symbolIdx == 1 || symbolIdx == 5)) return 790_000;
        if (quadrant == 2 && (symbolIdx == 1 || symbolIdx == 5)) return 820_000;
        if (quadrant == 1 && symbolIdx == 6) return 820_000;
        if (quadrant == 3 && symbolIdx == 7) return 780_000;
        return 890_000;
    }

    function _symbolTranslate(
        uint16 w,
        uint16 h,
        uint32 sSym1e6
    ) private pure returns (int256 txm, int256 tyn) {
        int256 scale = int256(uint256(sSym1e6));
        int256 w1e6 = int256(uint256(w)) * scale;
        int256 h1e6 = int256(uint256(h)) * scale;
        txm = -w1e6 / 2;
        tyn = -h1e6 / 2;
    }

    function _mat6(
        uint32 s1e6,
        int256 tx1e6,
        int256 ty1e6
    ) private pure returns (string memory) {
        string memory s = _dec6(uint256(s1e6));
        return string(
            abi.encodePacked(
                "matrix(",
                s,
                " 0 0 ",
                s,
                " ",
                _dec6s(tx1e6),
                " ",
                _dec6s(ty1e6),
                ")"
            )
        );
    }

    function _dec6(uint256 x) private pure returns (string memory) {
        uint256 i = x / 1_000_000;
        uint256 f = x % 1_000_000;
        return string(abi.encodePacked(Strings.toString(i), ".", _pad6(uint32(f))));
    }

    function _dec6s(int256 x) private pure returns (string memory) {
        if (x < 0) {
            return string(abi.encodePacked("-", _dec6(uint256(-x))));
        }
        return _dec6(uint256(x));
    }

    function _pad6(uint32 f) private pure returns (string memory) {
        bytes memory b = new bytes(6);
        for (uint256 k; k < 6; ++k) {
            b[5 - k] = bytes1(uint8(48 + (f % 10)));
            f /= 10;
        }
        return string(b);
    }

    // -------------------------------------------------------------------------
    // ERC165
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x80ac58cd  // IERC721
            || id == 0x5b5e139f  // IERC721Metadata
            || id == 0x01ffc9a7; // IERC165
    }

    // -------------------------------------------------------------------------
    // ERC721 Views
    // -------------------------------------------------------------------------

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) external view returns (address ownerAddr) {
        ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0)) revert InvalidToken();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address account, address operator) external view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    // -------------------------------------------------------------------------
    // ERC721 Mutations
    // -------------------------------------------------------------------------

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = _owners[tokenId];
        if (msg.sender != tokenOwner && !_operatorApprovals[tokenOwner][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
        _checkReceiver(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        _transfer(from, to, tokenId);
        _checkReceiver(from, to, tokenId);
    }

    // -------------------------------------------------------------------------
    // Game-Only Mint
    // -------------------------------------------------------------------------

    /// @notice Mint a deity pass. Only callable by the game contract during purchase.
    function mint(address to, uint256 tokenId) external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        if (tokenId >= 32) revert InvalidToken();
        if (_owners[tokenId] != address(0)) revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();

        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    /// @notice Burn a deity pass. Only callable by the game contract (for refunds).
    function burn(uint256 tokenId) external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert InvalidToken();

        delete _tokenApprovals[tokenId];
        unchecked { _balances[tokenOwner]--; }
        delete _owners[tokenId];
        emit Transfer(tokenOwner, address(0), tokenId);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 tokenId) private {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner != from) revert NotAuthorized();
        if (to == address(0)) revert ZeroAddress();

        if (msg.sender != from
            && msg.sender != _tokenApprovals[tokenId]
            && !_operatorApprovals[from][msg.sender]
        ) revert NotAuthorized();

        // Callback to game: burns BURNIE, updates deity storage, nukes sender stats.
        // Reverts propagate back here (e.g., insufficient BURNIE).
        IDeityPassCallback(ContractAddresses.GAME).onDeityPassTransfer(from, to, uint8(tokenId));

        delete _tokenApprovals[tokenId];
        unchecked { _balances[from]--; }
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _checkReceiver(address from, address to, uint256 tokenId) private {
        if (to.code.length != 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "") returns (bytes4 ret) {
                if (ret != IERC721Receiver.onERC721Received.selector) revert NotAuthorized();
            } catch {
                revert NotAuthorized();
            }
        }
    }
}

interface IDeityPassCallback {
    function onDeityPassTransfer(address from, address to, uint8 symbolId) external;
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}
