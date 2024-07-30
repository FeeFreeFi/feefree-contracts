// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }
}

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
}

library TransferHelper {
    error NativeTransferFailed();

    function safeTransferNative(address to, uint256 amount) internal {
        bool success;

        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert NativeTransferFailed();
        }
    }
}

/// @notice Simple single owner authorization mixin.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol)
abstract contract Owned {
    error Unauthorized();
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}


abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

abstract contract ERC721 {
    error ERC721InvalidOwner(address owner);
    error ERC721NonexistentToken(uint256 id);
    error ERC721IncorrectOwner(address sender, uint256 id, address owner);
    error ERC721InvalidSender(address sender);
    error ERC721InvalidReceiver(address receiver);
    error ERC721InsufficientApproval(address operator, uint256 id);
    error ERC721InvalidApprover(address approver);
    error ERC721InvalidOperator(address operator);

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    string public name;
    string public symbol;

    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function tokenURI(uint256 id) public view virtual returns (string memory);

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _ownerOf[id];
        if (owner == address(0)) {
            revert ERC721NonexistentToken(id);
        }
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }

        return _balanceOf[owner];
    }

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
            revert ERC721InvalidApprover(msg.sender);
        }

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        if (from != _ownerOf[id]) {
            revert ERC721IncorrectOwner(from, id, _ownerOf[id]);
        }

        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }

        if (msg.sender != from && !isApprovedForAll[from][msg.sender] && msg.sender != getApproved[id]) {
            revert ERC721InvalidApprover(msg.sender);
        }

        unchecked {
            _balanceOf[from]--;
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);
        _checkOnERC721Received(msg.sender, from, id, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);
        _checkOnERC721Received(msg.sender, from, id, data);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function _mint(address to, uint256 id) internal virtual {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }

        if (_ownerOf[id] != address(0)) {
            revert ERC721InvalidSender(address(0));
        }

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];
        if (owner == address(0)) {
            revert ERC721NonexistentToken(id);
        }

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];
        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        _checkOnERC721Received(msg.sender, address(0), id, "");
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        _checkOnERC721Received(msg.sender, address(0), id, data);
    }

    function _checkOnERC721Received(address from, address to, uint256 id, bytes memory data) private {
        if (to.code.length > 0) {
            try ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) returns (bytes4 retval) {
                if (retval != ERC721TokenReceiver.onERC721Received.selector) {
                    revert ERC721InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert ERC721InvalidReceiver(to);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }
}

contract FFGenesisNFT is Owned, ERC721 {
    using Strings for uint256;

    error InvalidPrice(uint256 expected, uint256 actual);
    error ExceededCap();
    error NonexistentToken(uint256 id);

    uint256 public constant cap = 10000;
    uint256 public totalSupply;

    string public baseURI;
    uint256 public immutable price;
    address public fund;
    mapping(address => uint256) private _nonces;

    constructor(string memory baseURI_, uint256 price_) Owned(msg.sender) ERC721("FFGenesisNFT", "FFG") {
        baseURI = baseURI_;
        price = price_;
    }

    function mint(address to) public payable returns (uint256 id) {
        if (totalSupply == cap) {
            revert ExceededCap();
        }

        uint256 _price = price;
        if (_price > 0) {
            if (msg.value != _price) {
                revert InvalidPrice(_price, msg.value);
            }

            if (fund != address(0)) {
                TransferHelper.safeTransferNative(fund, msg.value);
            }
        }

        id = _generateId();
        _safeMint(to, id);

        unchecked {
            totalSupply += 1;
        }
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    function setFund(address fund_) external onlyOwner {
        fund = fund_;

        uint256 amount = address(this).balance;
        if (amount > 0) {
            TransferHelper.safeTransferNative(fund, amount);
        }
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _checkExist(id);

        return bytes(baseURI).length > 0 ? string.concat(baseURI, id.toString()) : "";
    }

    function _generateId() internal returns (uint256 id) {
        uint256 total = totalSupply;
        uint256 nonce = _nonces[msg.sender];
        do {
            unchecked {
                nonce += 1;
            }
            id = _calcId(total, nonce);
        } while (id > 0 && _ownerOf[id] != address(0));

        _nonces[msg.sender] = nonce;
    }

    function _calcId(uint256 total, uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(msg.sender, address(this), total, nonce))) >> 233;
    }

    function _checkExist(uint256 id) internal view {
        if (_ownerOf[id] == address(0)) {
            revert NonexistentToken(id);
        }
    }
}