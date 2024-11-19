// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Owned} from "solmate/src/auth/Owned.sol";
import {LibString} from "solmate/src/utils/LibString.sol";
import {ERC721} from "solmate/src/tokens/ERC721.sol";

contract FFWeekNFT is Owned, ERC721 {
    using LibString for uint256;

    error ExceededCap();
    error NonexistentToken(uint256 id);

    uint256 public constant cap = 1000000;
    uint256 public totalSupply;

    string public baseURI;
    uint256 public immutable week;
    mapping(address => uint256) private _nonces;

    constructor(string memory baseURI_, uint256 week_) Owned(msg.sender) ERC721("FFWeekNFT", "FFW") {
        baseURI = baseURI_;
        week = week_;
    }

    function mint(address to) public payable returns (uint256 id) {
        if (totalSupply == cap) {
            revert ExceededCap();
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