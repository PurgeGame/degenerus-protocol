// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface ILazyPassGame {
    function activateLazyPass(address player) external returns (uint24 passLevel);
    function activateLazyPassAtLevel(address player, uint24 passLevel) external;
    function level() external view returns (uint24);
}

/// @notice Transferable lazy pass that activates and burns on use.
contract DegenerusLazyPass {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotGame();
    error InvalidToken();
    error InvalidPassLevel();
    error PassLevelCapReached();
    error ZeroAddress();
    error Unauthorized();
    error UnsafeRecipient();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event PassActivated(uint256 indexed tokenId, address indexed owner, uint24 passLevel);

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    string public constant name = "Degenerus Lazy Pass";
    string public constant symbol = "LAZYPASS";

    uint32 private constant PASS_LEVEL_MASK = (1 << 24) - 1;
    uint32 private constant AUTO_ACTIVATION_BATCH = 20;
    uint16 private constant MAX_PER_LEVEL = 1000;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => uint32) private _passData;
    mapping(address => uint256) private _inactiveBalance;
    mapping(uint24 => uint16) private _mintedPerLevel;
    mapping(uint24 => uint16) private _activationCursor;

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert NotGame();
        _;
    }

    // ---------------------------------------------------------------------
    // Minting
    // ---------------------------------------------------------------------

    function mintPasses(
        address to,
        uint256 quantity,
        uint24 passLevel_
    ) external onlyGame {
        if (to == address(0)) revert ZeroAddress();
        if (quantity == 0) revert InvalidToken();
        if (passLevel_ == 0 || (passLevel_ % 10) != 1) revert InvalidPassLevel();
        if (passLevel_ < ILazyPassGame(ContractAddresses.GAME).level()) {
            revert InvalidPassLevel();
        }

        uint16 minted = _mintedPerLevel[passLevel_];
        if (quantity > MAX_PER_LEVEL) revert PassLevelCapReached();
        if (uint256(minted) + quantity > MAX_PER_LEVEL) revert PassLevelCapReached();

        _balances[to] += quantity;
        _inactiveBalance[to] += quantity;

        uint256 baseId = uint256(passLevel_) * uint256(MAX_PER_LEVEL) + uint256(minted);
        for (uint256 i = 0; i < quantity; ) {
            uint256 tokenId = baseId + i;
            _owners[tokenId] = to;
            _passData[tokenId] = passLevel_;
            emit Transfer(address(0), to, tokenId);
            unchecked {
                ++i;
            }
        }
        _mintedPerLevel[passLevel_] = minted + uint16(quantity);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function inactiveBalanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _inactiveBalance[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert InvalidToken();
        return owner;
    }

    function isActivated(uint256 tokenId) public view returns (bool) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return false;
    }

    function passLevel(uint256 tokenId) external view returns (uint24) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return uint24(_passData[tokenId] & PASS_LEVEL_MASK);
    }

    // ---------------------------------------------------------------------
    // Approvals
    // ---------------------------------------------------------------------

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) {
            revert Unauthorized();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == address(0)) revert ZeroAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // ---------------------------------------------------------------------
    // Transfers (activate on transfer)
    // ---------------------------------------------------------------------

    function transferFrom(address from, address to, uint256 tokenId) public {
        _transferAndActivate(from, to, tokenId, false, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        _transferAndActivate(from, to, tokenId, true, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        _transferAndActivate(from, to, tokenId, true, data);
    }

    // ---------------------------------------------------------------------
    // Activation
    // ---------------------------------------------------------------------

    function activate(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) {
            revert Unauthorized();
        }
        _consumeInactive(owner);
        _activateCurrentAndBurn(owner, tokenId);
    }

    /// @notice Batch auto-activate unactivated passes.
    /// @dev Access: GAME contract only.
    /// @param limit Max tokens to scan this call (0 = default).
    /// @param level Current game level.
    /// @return worked True if any tokens were scanned.
    /// @return finished True if cursor reached the current end.
    function processAutoActivation(
        uint32 limit,
        uint24 level
    ) external onlyGame returns (bool worked, bool finished) {
        uint256 cursor = _activationCursor[level];
        uint256 end = _mintedPerLevel[level];
        if (cursor >= end) return (false, true);

        uint256 maxCount = limit == 0
            ? uint256(AUTO_ACTIVATION_BATCH)
            : uint256(limit);
        uint256 startCursor = cursor;
        uint256 stop = cursor + maxCount;
        if (stop > end) stop = end;
        uint256 baseId = uint256(level) * uint256(MAX_PER_LEVEL);

        while (cursor < stop) {
            uint256 tokenId = baseId + cursor;
            address owner = _owners[tokenId];
            if (owner != address(0)) {
                _consumeInactive(owner);
                _activateScheduledAndBurn(owner, tokenId, level);
            }
            unchecked {
                ++cursor;
            }
        }

        _activationCursor[level] = uint16(cursor);
        worked = cursor != startCursor;
        finished = cursor >= end;
    }

    // ---------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert InvalidToken();

        uint24 level = uint24(_passData[tokenId] & PASS_LEVEL_MASK);
        string memory status = "inactive";
        string memory levelStr = _toString(level);

        return string(
            abi.encodePacked(
                "data:application/json,{\"name\":\"Lazy Pass #",
                _toString(tokenId),
                "\",\"description\":\"Degenerus 10-level lazy pass.\",\"attributes\":[{\"trait_type\":\"Status\",\"value\":\"",
                status,
                "\"},{\"trait_type\":\"Start Level\",\"value\":\"",
                levelStr,
                "\"}]}"
            )
        );
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _consumeInactive(address owner) private {
        uint256 balance = _inactiveBalance[owner];
        if (balance == 0) revert InvalidToken();
        unchecked {
            _inactiveBalance[owner] = balance - 1;
        }
    }

    function _transferAndActivate(
        address from,
        address to,
        uint256 tokenId,
        bool safe,
        bytes memory data
    ) private {
        if (to == address(0)) revert ZeroAddress();
        address owner = ownerOf(tokenId);
        if (owner != from) revert Unauthorized();
        if (
            msg.sender != owner &&
            msg.sender != _tokenApprovals[tokenId] &&
            !_operatorApprovals[owner][msg.sender]
        ) {
            revert Unauthorized();
        }

        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);

        if (safe && to.code.length != 0) {
            bytes4 selector = IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            );
            if (selector != IERC721Receiver.onERC721Received.selector) {
                revert UnsafeRecipient();
            }
        }

        _consumeInactive(from);
        _activateCurrentAndBurn(to, tokenId);
    }

    function _activateCurrentAndBurn(address owner, uint256 tokenId) private {
        uint24 passLevel_ = ILazyPassGame(ContractAddresses.GAME).activateLazyPass(
            owner
        );
        emit PassActivated(tokenId, owner, passLevel_);
        _burn(owner, tokenId);
    }

    function _activateScheduledAndBurn(
        address owner,
        uint256 tokenId,
        uint24 passLevel_
    ) private {
        ILazyPassGame(ContractAddresses.GAME).activateLazyPassAtLevel(
            owner,
            passLevel_
        );
        emit PassActivated(tokenId, owner, passLevel_);
        _burn(owner, tokenId);
    }

    function _burn(address owner, uint256 tokenId) private {
        _tokenApprovals[tokenId] = address(0);
        _balances[owner] -= 1;
        delete _owners[tokenId];
        delete _passData[tokenId];
        emit Transfer(owner, address(0), tokenId);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
