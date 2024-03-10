/*
Layout of Contract Elements:
- License
- Pragma statements
- Import statements
- Events
- Errors
- Interfaces
- Libraries
- Contracts
*/

/*
Inside each Contract, Library or Interface:
- Type declarations (eg: Enums)
- State variables
- Events
- Modifiers
- Function
*/

/*
Layout of Functions:
- constructor
- receive function (if exists)
- fallback function (if exists)
- external
- public
- internal
- private
- view & pure functions
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contrac
 * @author Andrew Henry
 * @notice This contract is a simple raffle contract
 * @dev Implements Chaninlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
    // error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, RaffleState raffleState);

    /// Type declarations

    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    /// State Variables

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMBER_OF_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /// @dev duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    /// @dev s_players is a storage variable not immutable as the array will change each time a user enters the raffle
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /// Events
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestesRaffleWinner(uint256 indexed requestId);

    /// @dev Anything that is network specific should be passed in as an argument to the constructor
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    /// Enter The Raffle
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /// When the raffle is supposed to be drawn and a winner selected
    /*
    * @dev This function that the Chainlink Automation nodes will call to see if it's time to perform an upkeep
    * The following shou ld be true for this to return true:
    * - The raffle is in the OPEN state
    * - The time since the last raffle is greater than the interval
    * - The contract has ETH (aka players have entered the raffle)
    * - (Implicit) The subscription has enough LINK to make a request to the Chainlink VRF
    */
    function checkUpKeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        /// Check to see if the raffle is open
        bool isOpen = RaffleState.OPEN == s_raffleState;

        /// Check to see if enough time has passed
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);

        /// Check to see if there are enough players and thus enough ETH in the contract
        bool enoughPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;

        upkeepNeeded = (isOpen && timeHasPassed && enoughPlayers && hasBalance);
        return (upkeepNeeded, "0x0"); // '0x0' is a blank bytes object
    }

    /// Pick a winner
    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        /// Make a request to the Chainlink Node for a random number/s
        /// It will then call the VRFConsumerBaseV2 contract's rawFulfillRandomWords function
        /// Which then will call the fulfillRandomWords function in this contract (which we have marked as 'overide' - to override the VRFConsumerBaseV2 contract)
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, i_subscriptionId, REQUEST_CONFIRMATIONS, i_callbackGasLimit, NUMBER_OF_WORDS
        );
        emit RequestesRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] memory randomWords) internal override {
        // Checks
        // Effects (OUR own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        /// Reset the raffle
        s_players = new address payable[](0);

        /// Set the last time stamp to the current block time
        s_lastTimeStamp = block.timestamp;

        emit PickedWinner(winner);

        // Interactions (Other contracts)
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
