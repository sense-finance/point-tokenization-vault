// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PToken is ERC20, Ownable {
    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
        Ownable(msg.sender)
    {}

    function mint(address to, uint256 value) public virtual onlyOwner {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual onlyOwner {
        _burn(from, value);
    }
}
