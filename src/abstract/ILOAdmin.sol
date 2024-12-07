// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


abstract contract ILOAdmin { 

    error  NotTokenOwner();
    int24 MAX_TICK = 887272;
    uint128 constant PRECISION = 1e18; //wad
    uint constant internal BASE_BPS = 10000;
    uint public PROTOCOL_FEE = 500;

    mapping(address => uint) public protocolFee;



    //Todo only owner and fee collection
    function claimFees(address token, address to) external {

    }





}