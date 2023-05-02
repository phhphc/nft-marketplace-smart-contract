// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenETH is ERC20 {
    constructor() ERC20("TokenETH", "TETH") {}

    function buy() public payable {
        _mint(msg.sender, msg.value);
    }

    function sell(uint256 amount) public {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
