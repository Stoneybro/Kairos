// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {SimpleAccount} from "src/SimpleAccount.sol";

contract SimpleAccountTest is Test {
    SimpleAccount account;
    address owner = address(1);
    address attacker = address(2);

    function setUp() public {
        account = new SimpleAccount();
        account.initialize(owner);
        vm.deal(address(account), 10 ether); // Fund the contract for task creation
    }

    function testOnlyOwnerCanCreateTask() public {
        vm.startPrank(attacker);
        vm.expectRevert(SimpleAccount.SimpleAccount__OnlyOwnerCanCallThisFunction.selector);
        account.createTask("Test task", 1 ether, 1 days);
        vm.stopPrank();
    }

    function testCreateTaskStoresCorrectData() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        SimpleAccount.Task memory task = account.getTask(0);
        vm.stopPrank();

        assertEq(task.id, 0);
        assertEq(task.description, "Test task");
        assertEq(task.rewardAmount, 1 ether);
        assertEq(task.completed, false);
        assertEq(task.canceled, false);
        assertEq(task.expired, false);
    }

    function testCreateTaskEmitsEvent() public {
        vm.startPrank(owner);
        vm.expectEmit();
        emit SimpleAccount.TaskCreated(0, "Test task", 1 ether);
        account.createTask("Test task", 1 ether, 1 days);
        vm.stopPrank();
    }

    function testCannotCreateTaskIfInsufficientFunds() public {
        vm.startPrank(owner);
        vm.expectRevert(SimpleAccount.SimpleAccount__AddMoreFunds.selector);
        account.createTask("Expensive task", 20 ether, 1 days);
        vm.stopPrank();
    }

    function testCompleteTask() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        uint256 ownerBalanceBefore = owner.balance;

        vm.expectEmit();
        emit SimpleAccount.TaskCompleted(0);
        account.completeTask(0);
        vm.stopPrank();

        SimpleAccount.Task memory task = account.getTask(0);
        assertTrue(task.completed);
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
    }

    function testCannotCompleteTaskTwice() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        account.completeTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskAlreadyCompleted.selector);
        account.completeTask(0);
        vm.stopPrank();
    }

    function testCannotCompleteTaskIfCanceled() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        account.cancelTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasBeenCanceled.selector);
        account.completeTask(0);
        vm.stopPrank();
    }

    function testCannotCompleteTaskIfExpired() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 seconds);
        vm.warp(block.timestamp + 2);
        account.expireTask(0);
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        account.completeTask(0);
        vm.stopPrank();
    }

    function testCancelTask() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);

        vm.expectEmit();
        emit SimpleAccount.TaskCanceled(0);
        account.cancelTask(0);

        SimpleAccount.Task memory task = account.getTask(0);
        assertTrue(task.canceled);
        vm.stopPrank();
    }

    function testCannotCancelTaskTwice() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        account.cancelTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasBeenCanceled.selector);
        account.cancelTask(0);
        vm.stopPrank();
    }

    function testCannotCancelTaskIfCompleted() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        account.completeTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskAlreadyCompleted.selector);
        account.cancelTask(0);
        vm.stopPrank();
    }

    function testRevertIfTaskDoesNotExistOnComplete() public {
        vm.startPrank(owner);
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskDoesntExist.selector);
        account.completeTask(0);
        vm.stopPrank();
    }

    function testRevertIfTaskDoesNotExistOnCancel() public {
        vm.startPrank(owner);
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskDoesntExist.selector);
        account.cancelTask(0);
        vm.stopPrank();
    }

    function testOnlyOwnerCanCompleteTask() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        vm.stopPrank();
        vm.prank(attacker);
        vm.expectRevert(SimpleAccount.SimpleAccount__OnlyOwnerCanCallThisFunction.selector);
        account.completeTask(0);
    }

    function testOnlyOwnerCanCancelTask() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        vm.stopPrank();
        vm.prank(attacker);
        vm.expectRevert(SimpleAccount.SimpleAccount__OnlyOwnerCanCallThisFunction.selector);
        account.cancelTask(0);
    }

    function testFuzz_MultipleTasksCanBeCreatedAndCompletedIndependently(
        uint256 rewards,
        uint256 durations,
        uint256 taskId
    ) public {
        rewards = bound(rewards, 1, 1e18);
        durations = bound(durations, 1, 30 days);
        taskId = bound(taskId, 0, 30); // We'll create at least taskId + 1 tasks

        uint256 totalReward = rewards * (taskId + 1);

        vm.deal(address(account), totalReward);

        vm.startPrank(owner);

        for (uint256 i = 0; i <= taskId; i++) {
            account.createTask("Fuzzed Task", rewards, durations);
        }

        account.completeTask(taskId);
        assertTrue(account.getTask(taskId).completed);

        vm.stopPrank();
    }

    function testFuzz_CancelTaskDoesNotAffectOtherTasks(uint256[] memory rewards, uint256 cancelIndex) public {
        vm.startPrank(owner);
        vm.assume(rewards.length > 1 && cancelIndex < rewards.length);

        uint256 totalReward = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            rewards[i] = bound(rewards[i], 1, 1e18);
            totalReward += rewards[i];
        }
        vm.deal(address(account), totalReward);

        for (uint256 i = 0; i < rewards.length; i++) {
            account.createTask("Fuzzed Task", rewards[i], 1000);
        }

        account.cancelTask(cancelIndex);
        assertTrue(account.getTask(cancelIndex).canceled);

        for (uint256 i = 0; i < rewards.length; i++) {
            if (i != cancelIndex) {
                assertFalse(account.getTask(i).canceled);
            }
        }

        vm.stopPrank();
    }

    function test_CreateTaskRevertsWhenInsufficientFunds() public {
        uint256 reward = 1 ether;

        // Send less than the reward to the contract
        vm.deal(address(account), reward - 1);

        vm.startPrank(owner);
        vm.expectRevert(SimpleAccount.SimpleAccount__AddMoreFunds.selector);
        account.createTask("Insufficient Funds", reward, 100);

        vm.stopPrank();
    }

    function test_CancelCompletedTaskReverts() public {
        uint256 reward = 1 ether;
        uint256 duration = 100;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Cancel", reward, duration);
        account.completeTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskAlreadyCompleted.selector);
        account.cancelTask(0);

        vm.stopPrank();
    }

    function test_CancelTaskWorks() public {
        uint256 reward = 1 ether;
        uint256 duration = 100;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Cancel", reward, duration);

        account.cancelTask(0);
        assertTrue(account.getTask(0).canceled);

        vm.stopPrank();
    }

    function test_CompleteTaskRevertsWhenExpired() public {
        uint256 reward = 1 ether;
        uint256 duration = 1; // 1 second

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Expiry", reward, duration);

        // Fast forward past the deadline
        vm.warp(block.timestamp + 2);
        account.expireTask(0);
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        account.completeTask(0);

        vm.stopPrank();
    }

    function testTaskExpiredFlagIsSetWhenExpired() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 seconds);
        vm.warp(block.timestamp + 2);
        account.expireTask(0);
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        account.completeTask(0);

        assert(account.getTask(0).expired);
        vm.stopPrank();
    }

    // function testOverflowProtection() public {
    //     vm.startPrank(owner);

    //     // Directly manipulate storage to simulate near-overflow
    //     vm.store(address(account), bytes32(uint256(2)), bytes32(type(uint256).max - 1 ether + 1)); // s_totalCommitedReward slot

    //     vm.expectRevert();
    //     account.createTask("Overflow test", 1 ether, 1 days);

    //     vm.stopPrank();
    // }
    function testTotalCommittedRewardDecreasesOnCancel() public {
        vm.startPrank(owner);
        account.createTask("Test task", 1 ether, 1 days);
        uint256 committedBefore = account.s_totalCommitedReward();

        account.cancelTask(0);
        uint256 committedAfter = account.s_totalCommitedReward();

        assertEq(committedAfter, committedBefore - 1 ether);
        vm.stopPrank();
    }

    function testCreateTaskWithZeroDuration() public {
        vm.startPrank(owner);
        account.createTask("Instant Expire Task", 1 ether, 0);

        SimpleAccount.Task memory task = account.getTask(0);
        assertEq(task.deadline, block.timestamp); // Should expire immediately if allowed.

        vm.stopPrank();
    }

    function testExpireTask_Succeeds_WhenDeadlineHasPassed() public {
        uint256 reward = 1 ether;
        uint256 duration = 1 days;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Task", reward, duration);

        // Fast forward time past the deadline
        vm.warp(block.timestamp + duration + 1);

        account.expireTask(0);
        assertTrue(account.getTask(0).expired);
        vm.stopPrank();
    }

    function testExpireTask_Reverts_WhenTaskNotYetExpired() public {
        uint256 reward = 1 ether;
        uint256 duration = 1 days;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Task", reward, duration);

        // Try expiring the task before the deadline
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskNotYetExpired.selector);
        account.expireTask(0);

        vm.stopPrank();
    }

    function testExpireTask_Reverts_WhenTaskAlreadyExpired() public {
        uint256 reward = 1 ether;
        uint256 duration = 1 days;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Task", reward, duration);

        // Fast forward time past the deadline
        vm.warp(block.timestamp + duration + 1);

        account.expireTask(0);

        // Try to expire the task again
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        account.expireTask(0);

        vm.stopPrank();
    }

    function testExpireTask_EmitsEvent() public {
        uint256 reward = 1 ether;
        uint256 duration = 1 days;

        vm.deal(address(account), reward);

        vm.startPrank(owner);
        account.createTask("Test Task", reward, duration);

        vm.warp(block.timestamp + duration + 1);

        vm.expectEmit(true, false, false, true);
        emit SimpleAccount.TaskExpired(0);

        account.expireTask(0);

        vm.stopPrank();
    }

    function test_RevertIfTaskNotYetExpired() public {
        vm.startPrank(owner);
        account.createTask("Test Task", 1 ether, 10 days);
        // Do NOT warp time
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskNotYetExpired.selector);
        account.expireTask(0);
        vm.stopPrank();
    }

    function test_RevertIfTaskAlreadyExpired() public {
        vm.startPrank(owner);
        account.createTask("Test Task", 1 ether, 10 days);
        vm.warp(block.timestamp + 11 days);
        account.expireTask(0); // First call succeeds
        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        account.expireTask(0); // Second call should revert
        vm.stopPrank();
    }

    function test_CompleteTask_WithZeroAmount() public {
        vm.startPrank(owner);
        account.createTask("Test Task", 0 ether, 10 days);

        // Should not revert, just skip the transfer
        account.completeTask(0);
        vm.stopPrank();
    }

    function testTaskCreationSetsNextExpiringTask() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 100);
        assertEq(account.nextExpiringTaskId(), 0);
        assertApproxEqAbs(account.nextDeadline(), block.timestamp + 100, 1);
    }

    function testExpireTaskSuccessfully() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 1);
        vm.warp(block.timestamp + 2);

        vm.prank(attacker);
        account.expireTask(0);
        assertTrue(account.getTask(0).expired);
        assertFalse(account.getTask(0).pending);
    }

    function testExpireTaskRevertsIfNotExpired() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 100);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskNotYetExpired.selector);
        vm.prank(attacker);
        account.expireTask(0);
    }

    function testExpireTaskRevertsIfAlreadyExpired() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 1);
        vm.warp(block.timestamp + 2);

        vm.prank(attacker);
        account.expireTask(0);

        vm.expectRevert(SimpleAccount.SimpleAccount__TaskHasExpired.selector);
        vm.prank(attacker);
        account.expireTask(0);
    }

    function testCheckUpkeepDetectsExpiredTask() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 1);
        vm.warp(block.timestamp + 2);

        (bool upkeepNeeded, bytes memory performData) = account.checkUpkeep("");

        assertTrue(upkeepNeeded);
        uint256 taskId = abi.decode(performData, (uint256));
        assertEq(taskId, 0);
    }

    function testPerformUpkeepExpiresTask() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 1);
        vm.warp(block.timestamp + 2);

        (, bytes memory performData) = account.checkUpkeep("");

        account.performUpkeep(performData);

        assertTrue(account.getTask(0).expired);
        assertFalse(account.getTask(0).pending);
    }

    function testUpdateNextExpiringTaskCorrectly() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 50);
        vm.prank(owner);
        account.createTask("Task 2", 1 ether, 100);

        // Expire first task
        vm.warp(block.timestamp + 60);
        (, bytes memory performData) = account.checkUpkeep("");
        account.performUpkeep(performData);

        // nextExpiringTaskId should now be task 1
        assertEq(account.nextExpiringTaskId(), 1);
    }

    function testResetNextExpiringTaskIfNoPendingTasks() public {
        vm.prank(owner);
        account.createTask("Task 1", 1 ether, 1);

        vm.warp(block.timestamp + 2);
        (, bytes memory performData) = account.checkUpkeep("");
        account.performUpkeep(performData);

        // Should reset to defaults
        assertEq(account.nextDeadline(), type(uint256).max);
    }
}
