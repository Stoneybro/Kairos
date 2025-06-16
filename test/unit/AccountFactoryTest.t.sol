// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployAccountFactory} from "script/DeployAccountFactory.s.sol";
import {AccountFactory} from "src/AccountFactory.sol";
import {SimpleAccount} from "src/SimpleAccount.sol";
import {Test} from "forge-std/Test.sol";

contract AccountFactoryTest is Test {
    DeployAccountFactory deployFactory;
    AccountFactory factory;
    address user;

    function setUp() public {
        deployFactory = new DeployAccountFactory();
        factory = deployFactory.run();
        user = makeAddr("user");
    }

    function testCreateAccount() external {
        vm.startPrank(user);
        address  accountAddress = factory.createAccount(1);
        vm.stopPrank();
        address storedCloneAddress = factory.userClones(user);
        assertEq(storedCloneAddress, accountAddress);
        SimpleAccount account = SimpleAccount(payable(accountAddress));
        assertEq(account.s_owner(), user);
    }

    function testCreateAccountAddressIsTheSameAsPredictedAddress() external {
        vm.startPrank(user);
        address accountAddress = factory.createAccount(1);
        address predictedAddress = factory.getAddress(1);
        vm.stopPrank();
        assertEq(accountAddress, predictedAddress);
    }

    function testAccountAlreadyCreated() external {
        vm.startPrank(user);
        address accountAddress = factory.createAccount(1);
        vm.expectRevert(AccountFactory.AccountFactory__contractAlreadyDeployed.selector);
        address secondAccountAddress = factory.createAccount(1);
        vm.stopPrank();
    }

    function testCreateAccountEvent() external {
        uint256 userNonce = 1;
        bytes32 salt = keccak256(abi.encodePacked(user, userNonce));
        vm.startPrank(user);
        vm.expectEmit();
        emit AccountFactory.cloneCreated(factory.getAddress(1), user, salt);
        address accountAddress = factory.createAccount(1);
        vm.stopPrank();
    }

    function testNewUserCanCreateAccount() external {
         vm.startPrank(user);
        address accountAddress = factory.createAccount(1);
        vm.stopPrank();
        address newUser = makeAddr("newUser");
        vm.startPrank(newUser);
        address newAccountAddress = factory.createAccount(1);
        vm.stopPrank();
        address storedCloneAddress = factory.userClones(newUser);
        assertEq(storedCloneAddress, newAccountAddress);
        SimpleAccount account = SimpleAccount(payable(newAccountAddress));
        assertEq(account.s_owner(), newUser);
    }

    function testRevertOnDoubleInitialize() external {
        vm.startPrank(user);
        address accountAddress = factory.createAccount(1);
        vm.expectRevert();
        SimpleAccount(payable(accountAddress)).initialize(user); // Should revert
        vm.stopPrank();
    }

    function testCreateAccountWithDifferentNonces() external {
        vm.startPrank(user);
        address firstAccount = factory.createAccount(1);
        address secondAccount = factory.createAccount(2);
        vm.stopPrank();

        assertTrue(firstAccount != secondAccount);
    }

    function testPredictedAddressChangesWithNonce() external {
        address predictedFirst = factory.getAddress(1);
        address predictedSecond = factory.getAddress(2);

        assertTrue(predictedFirst != predictedSecond);
    }

    function testMultipleUsersCreateAccounts() external {
        address secondUser = makeAddr("secondUser");

        vm.startPrank(user);
        address firstAccount = factory.createAccount(1);
        vm.stopPrank();

        vm.startPrank(secondUser);
        address secondAccount = factory.createAccount(1);
        vm.stopPrank();

        assertTrue(firstAccount != secondAccount);
        assertEq(factory.userClones(user), firstAccount);
        assertEq(factory.userClones(secondUser), secondAccount);
    }

    function testUserClonePersistsCorrectly() external {
        vm.startPrank(user);
        address accountAddress = factory.createAccount(1);
        vm.stopPrank();

        // Simulate multiple lookups
        address lookup1 = factory.userClones(user);
        address lookup2 = factory.userClones(user);

        assertEq(lookup1, accountAddress);
        assertEq(lookup2, accountAddress);
    }
}
