// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {AccountFactory} from "src/AccountFactory.sol";
import {Script} from "forge-std/Script.sol";

contract DeployAccountFactory is Script {
    function run() external  returns(AccountFactory ) {
        AccountFactory factory=new AccountFactory();
        return factory;
    }
}