// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface ICREDIT is IERC20 {
    function burnForseedPlantNFT(address _burnee, uint256 _amount) external returns (bool);
    function burnForseedTreeNFT(address _burnee, uint256 _amount) external returns (bool);
}
