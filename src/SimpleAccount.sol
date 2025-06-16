// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
/**
 * @title Account model for users.
 * @author Livingstone zion
 * @notice This is the initial account model deployed by the Account Factory
 */

contract SimpleAccount is Initializable, AutomationCompatibleInterface {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct Task {
        uint256 id;
        string description;
        uint256 rewardAmount;
        uint256 deadline;
        bool pending;
        bool completed;
        bool canceled;
        bool expired;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public s_owner;
    mapping(uint256 => Task) private s_tasks;
    uint256 private s_taskId;
    uint256 public s_totalCommitedReward;
    uint256 public nextExpiringTaskId;
    uint256 public nextDeadline = type(uint256).max;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TaskCreated(uint256 indexed taskId, string description, uint256 rewardAmount);
    event TaskCompleted(uint256 indexed taskId);
    event TaskCanceled(uint256 indexed taskId);
    event TaskExpired(uint256 indexed taskId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error SimpleAccount__OnlyOwnerCanCallThisFunction();
    error SimpleAccount__TaskRewardPaymentFailed();
    error SimpleAccount__TaskAlreadyCompleted();
    error SimpleAccount__AddMoreFunds();
    error SimpleAccount__TaskHasBeenCanceled();
    error SimpleAccount__TaskDoesntExist();
    error SimpleAccount__TaskHasExpired();
    error SimpleAccount__TaskNotYetExpired();
    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(address _owner) external initializer {
        s_owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyOwner() {
        if (msg.sender != s_owner) {
            revert SimpleAccount__OnlyOwnerCanCallThisFunction();
        }
        _;
    }

    modifier contractFundedForTasks(uint256 rewardAmount) {
        if (address(this).balance < s_totalCommitedReward + rewardAmount) {
            revert SimpleAccount__AddMoreFunds();
        }
        _;
    }

    modifier taskExist(uint256 taskId) {
        if (taskId >= s_taskId) {
            revert SimpleAccount__TaskDoesntExist();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}

    function createTask(string calldata description, uint256 rewardAmount, uint256 durationInSeconds)
        external
        contractFundedForTasks(rewardAmount)
        onlyOwner
    {
        s_tasks[s_taskId] = Task({
            id: s_taskId,
            description: description,
            rewardAmount: rewardAmount,
            deadline: block.timestamp + durationInSeconds,
            pending: true,
            completed: false,
            canceled: false,
            expired: false
        });
        if (block.timestamp + durationInSeconds < nextDeadline) {
            nextExpiringTaskId = s_taskId;
            nextDeadline = block.timestamp + durationInSeconds;
        }
        emit TaskCreated(s_taskId, description, rewardAmount);
        s_taskId++;
        s_totalCommitedReward += rewardAmount;
    }

    function checkUpkeep(bytes calldata) public view override returns (bool upkeepNeeded, bytes memory performData) {
        Task storage task = s_tasks[nextExpiringTaskId];
        if (task.pending && block.timestamp > task.deadline) {
            upkeepNeeded = true;
            performData = abi.encode(nextExpiringTaskId);
        } else {
            upkeepNeeded = false;
            performData = "";
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 taskId = abi.decode(performData, (uint256));
        Task storage task = s_tasks[taskId];
        if (block.timestamp > task.deadline && task.pending) {
            task.pending = false;
            task.expired = true;
            s_totalCommitedReward -= task.rewardAmount;
            if (taskId == nextExpiringTaskId) {
                _updateNextExpiringTask();
            }
            emit TaskExpired(taskId);
        }
    }

    function expireTask(uint256 taskId) external {
        Task storage task = s_tasks[taskId];
        if (block.timestamp < task.deadline) {
            revert SimpleAccount__TaskNotYetExpired();
        }
        if (task.expired) {
            revert SimpleAccount__TaskHasExpired();
        }
        task.pending = false;
        task.expired = true;
        emit TaskExpired(taskId);
    }

    function completeTask(uint256 taskId) external taskExist(taskId) onlyOwner {
        Task storage task = s_tasks[taskId];
        if (task.expired) {
            revert SimpleAccount__TaskHasExpired();
        }
        if (task.completed) {
            revert SimpleAccount__TaskAlreadyCompleted();
        }
        if (task.canceled) {
            revert SimpleAccount__TaskHasBeenCanceled();
        }
        task.pending = false;
        task.completed = true;

        emit TaskCompleted(taskId);

        if (task.rewardAmount > 0) {
            (bool success,) = payable(s_owner).call{value: task.rewardAmount}("");
            if (!success) {
                revert SimpleAccount__TaskRewardPaymentFailed();
            }
        }
        s_totalCommitedReward -= task.rewardAmount;
        if (taskId == nextExpiringTaskId) {
            _updateNextExpiringTask();
        }
    }

    function cancelTask(uint256 taskId) external taskExist(taskId) onlyOwner {
        Task storage task = s_tasks[taskId];
        if (task.completed) {
            revert SimpleAccount__TaskAlreadyCompleted();
        }
        if (task.canceled) {
            revert SimpleAccount__TaskHasBeenCanceled();
        }
        task.pending = false;
        task.canceled = true;
        s_totalCommitedReward -= task.rewardAmount;
        if (taskId == nextExpiringTaskId) {
            _updateNextExpiringTask();
        }
        emit TaskCanceled(taskId);
    }

    function _updateNextExpiringTask() internal {
        uint256 soonestDeadline = type(uint256).max;
        uint256 soonestTaskId;
        for (uint256 i = 0; i < s_taskId; i++) {
            Task storage t = s_tasks[i];
            if (t.pending && t.deadline < soonestDeadline) {
                soonestDeadline = t.deadline;
                soonestTaskId = i;
            }
        }
        if (soonestDeadline == type(uint256).max) {
            nextExpiringTaskId = 0; // Or any safe default
            nextDeadline = type(uint256).max;
        } else {
            nextExpiringTaskId = soonestTaskId;
            nextDeadline = soonestDeadline;
        }

        nextExpiringTaskId = soonestTaskId;
        nextDeadline = soonestDeadline;
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        return s_tasks[taskId];
    }
}
