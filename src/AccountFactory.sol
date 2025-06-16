// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SimpleAccount} from "./SimpleAccount.sol";

contract AccountFactory {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable implementation;
    mapping (address user => address clone) public userClones;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event cloneCreated(address indexed clone,address indexed user,bytes32 indexed salt);
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AccountFactory__contractAlreadyDeployed();

    /*CONSTRUCTOR*/
    constructor() {
        implementation=address(new SimpleAccount());
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createAccount(uint256 userNonce) external returns (address) {
        bytes32 salt=keccak256(abi.encodePacked(msg.sender,userNonce));
        address predictedAddress =
            Clones.predictDeterministicAddress(implementation, salt);

        if (predictedAddress.code.length != 0) {
            revert AccountFactory__contractAlreadyDeployed();
        }
        address account = Clones.cloneDeterministic(implementation, salt);
        userClones[msg.sender]=account;
        emit cloneCreated(account,msg.sender,salt);
        SimpleAccount(payable(account)).initialize(msg.sender);

        return account;
    }
    function getAddress(uint256 userNonce) external view  returns (address predictedAddress) {
        bytes32 salt=keccak256(abi.encodePacked(msg.sender,userNonce));
        predictedAddress=Clones.predictDeterministicAddress(implementation,salt);
    }
}
