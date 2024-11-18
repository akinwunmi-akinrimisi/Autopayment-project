// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiskToken is ERC20("Lisk", "LSK") {
    constructor() {
        _mint(msg.sender, 100000000e18);
    }

    function mint(uint256 _amount) external {
        require(msg.sender != address(0), "Address zero detected");

        _mint(msg.sender, _amount * 1e18);
    }
}
