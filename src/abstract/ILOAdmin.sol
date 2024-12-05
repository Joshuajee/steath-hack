// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


abstract contract ILOAdmin { 

    uint constant internal BASE_BPS = 10000;
    uint public PROTOCOL_FEE = 500;

    mapping(address => uint) public protocolFee;



    //Todo only owner
    function claimFees(address token) external {

    }





}