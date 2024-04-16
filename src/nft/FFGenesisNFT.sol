// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

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

contract FFGenesisNFT is ERC721 {
    error InvalidId(uint256 id);
    error Minted(address owner);

    mapping(address => uint256) public minted;

    constructor() ERC721("FFGenesisNFT", "FFG") {}

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string.concat("FFGenesisNFT", "-", uint2str(id));
    }

    function mint() public {
        if (minted[msg.sender] > 0) {
            revert Minted(msg.sender);
        }

        // 2 ** 21 - 1
        uint256 id = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.number))) % 2097151;
        if (id == 0 || _ownerOf[id] != address(0)) {
            revert InvalidId(id);
        }

        minted[msg.sender] = id;
        _safeMint(msg.sender, id);
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }

        return string(bstr);
    }
}