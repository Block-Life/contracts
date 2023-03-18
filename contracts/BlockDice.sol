// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

error SentDifferentSessionPrice();
error PlayerAlreadyInSession();
error PlayerNotInSession();
error PlayerIsNotAdmin();
error TargetPlayerIsNotInSession();
error TargetSessionIsFull();
error TargetSessionIsNotStarted();
error TargetSessionIsStarted();
error BelowMinimumSessionPrice();
error Minimum2PlayersNeeded();
error NotYourTurn();
error RandomWordIsNotReadyYet();

contract BlockdiceManager is VRFConsumerBaseV2, ConfirmedOwner, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARD = keccak256("GUARD");
    uint256 private constant SESSION_NOT_STARTED = 1;
    uint256 private constant SESSION_STARTED = 2;
    address private constant LINK_TOKEN = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    VRFCoordinatorV2Interface COORDINATOR;

    mapping(address => uint256) playerSessionId;
    mapping(uint256 => Session) sessions;
    mapping(uint256 => uint256) vrfRequestsSessionId;
    uint256 public sessionCounter;
    uint256 public sessionIdCounter = 1;
    uint256 public minSessionPrice = 1000;
    uint256 public collectedFees;
    uint256 public feePerThousand = 50;
    uint64 s_subscriptionId;

    struct Session { 
        uint256 sessionId;
        address admin;
        uint256 status;
        address[] players;
        uint256 playerCount;
        uint256 maxPlayerAmount;
        uint256 sessionPrice;
        uint256[] playerBalances;
        uint256[] playerPositions;
        uint256 whoseTurn;
        uint256 randomWord;
        RNGHelper rngData;
        uint256[4] treasury;
        address[24] squareOwners;
    }

    struct RNGHelper{
        uint256 lastBlock;
        address lastMiner; // make sure to convert block.coinbase (address payable) to address
    }
    
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    event SessionCreated(address indexed admin, uint256 indexed sessionId, uint256 maxPlayerAmount, uint256 sessionPrice);
    event PlayerJoined(address indexed player, uint256 indexed sessionId);
    event PlayerLeaved(address indexed player, uint256 indexed sessionId);
    event PlayerWon(address indexed player, uint256 reward);
    event DiceRolled(uint256 indexed sessionId, address player, uint256 newPosition);
    event WhoseTurnChanged(uint256 indexed sessionId, uint256 newTurn);

    modifier onlyIfPlayerInSession{
        if(playerSessionId[msg.sender] == 0) revert PlayerNotInSession();
        _;
    }
    
    modifier onlyIfPlayerNotInSession{
        if(playerSessionId[msg.sender] != 0) revert PlayerAlreadyInSession();
        _;
    }

    constructor(
        uint64 subscriptionId,
        address vrfCoordinator
    )
        VRFConsumerBaseV2(vrfCoordinator) // this is for sepolia
        ConfirmedOwner(msg.sender)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            vrfCoordinator
        );
        s_subscriptionId = subscriptionId;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GUARD, msg.sender);
    }

    function getSession() public view onlyIfPlayerInSession returns(Session memory){
        return sessions[playerSessionId[msg.sender]];
    }
    
    function getPlayerBalance() public view onlyIfPlayerInSession returns(uint256){
        return sessions[playerSessionId[msg.sender]].playerBalances[findPlayerIndexInArray(playerSessionId[msg.sender], msg.sender)];
    }

    function getSessionHelper(address sessionCreator) public view returns(Session memory){
        return sessions[playerSessionId[sessionCreator]];
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = collectedFees;
        require(payable(msg.sender).send(balance));
        collectedFees = 0;
    }
    
    function withdrawLinks() external onlyRole(DEFAULT_ADMIN_ROLE){
        IERC20(LINK_TOKEN).safeTransfer(msg.sender, IERC20(LINK_TOKEN).balanceOf(address(this)));
    }

    function changeFeePerThousand(uint256 feePerThousand_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feePerThousand = feePerThousand_;
    }

    function createSession() external payable nonReentrant onlyIfPlayerNotInSession{
        if(msg.value < minSessionPrice) revert BelowMinimumSessionPrice();
        
        ++sessionCounter;
        // Search until empty sessionId is found
        while(sessions[sessionIdCounter].playerCount != 0){
            if(sessionIdCounter == type(uint256).max){
                sessionIdCounter = 1;
            }
            else{
                ++sessionIdCounter;
            }
        }
        
        // Initialize the session
        Session memory session;
        session.sessionId = sessionIdCounter;
        session.admin = msg.sender;
        session.status = SESSION_NOT_STARTED;
        session.maxPlayerAmount = 10;
        ++session.playerCount;
        session.sessionPrice = msg.value;
        sessions[sessionIdCounter] = session;
        sessions[sessionIdCounter].players.push(msg.sender);
        sessions[sessionIdCounter].playerBalances.push(msg.value);
        sessions[sessionIdCounter].playerPositions.push(0);
        playerSessionId[msg.sender] = sessionIdCounter;
        
        requestRandomWordsHelper(sessionIdCounter);

        emit SessionCreated(msg.sender, sessionIdCounter, 10, 0);
        emit PlayerJoined(msg.sender, sessionIdCounter);
    }

    function enterSession(address player) external payable nonReentrant {
        uint256 targetSessionId = playerSessionId[player];
        if(targetSessionId == 0) revert TargetPlayerIsNotInSession();
        if(sessions[targetSessionId].playerCount == sessions[targetSessionId].maxPlayerAmount) revert TargetSessionIsFull();
        if(sessions[targetSessionId].status != SESSION_NOT_STARTED) revert TargetSessionIsStarted();
        if(msg.value != sessions[targetSessionId].sessionPrice) revert SentDifferentSessionPrice(); 

        sessions[targetSessionId].players.push(msg.sender);
        sessions[targetSessionId].playerBalances.push(sessions[targetSessionId].sessionPrice);
        sessions[sessionIdCounter].playerPositions.push(0);
        ++sessions[targetSessionId].playerCount;
        playerSessionId[msg.sender] = targetSessionId;
        
        emit PlayerJoined(msg.sender, targetSessionId);
    }

    function startSession() external nonReentrant {
        uint256 targetSessionId = playerSessionId[msg.sender];
        if(sessions[targetSessionId].admin != msg.sender) revert PlayerIsNotAdmin();
        if(sessions[targetSessionId].playerCount == 1) revert Minimum2PlayersNeeded();
        if(sessions[targetSessionId].randomWord == 0) revert RandomWordIsNotReadyYet();

        sessions[targetSessionId].status = SESSION_STARTED;
        uint256 firstPlayerIndex = sessions[targetSessionId].randomWord % sessions[targetSessionId].playerCount;
        sessions[targetSessionId].whoseTurn = firstPlayerIndex;
        emit WhoseTurnChanged(targetSessionId, firstPlayerIndex);

        //sessions[targetSessionId].randomWord = block.prevrandao;
        requestRandomWordsHelper(sessions[targetSessionId].sessionId);

    }
    
        function dice() external nonReentrant onlyIfPlayerInSession{
        uint256 targetSessionId = playerSessionId[msg.sender];
        if(sessions[targetSessionId].status != SESSION_STARTED) revert TargetSessionIsNotStarted();
        address whoseTurn = sessions[targetSessionId].players[sessions[targetSessionId].whoseTurn];
        if(whoseTurn != msg.sender) revert NotYourTurn();
        if(sessions[targetSessionId].randomWord == 0) revert RandomWordIsNotReadyYet();

        uint256 stepCount = (sessions[targetSessionId].randomWord % 6) + 1;
        sessions[targetSessionId].randomWord = 0;
        sessions[targetSessionId].playerPositions[sessions[targetSessionId].whoseTurn] += stepCount;
        uint256 position = sessions[targetSessionId].playerPositions[sessions[targetSessionId].whoseTurn];

        uint zone = 0;
        uint convertedPosition = (position % 24);

        if(convertedPosition > 18 || sessions[targetSessionId].playerPositions[sessions[targetSessionId].whoseTurn] == 0){
            zone = 4;
        }
        else if(convertedPosition > 12){
            zone = 3;
        }
        else if(convertedPosition > 6){
            zone = 2;
        }
        else{
            zone = 1;
        }

        // Checks if player is on a special square
        if(position % 3 == 0){
            if (position % 6 == 0){
                // If yellow square
                sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] += sessions[targetSessionId].treasury[zone - 1];
                sessions[targetSessionId].treasury[zone - 1] = 0;
            } 
            else {  
                // If red square
                uint payTax = zone * sessions[targetSessionId].sessionPrice / 10;

                if ( payTax > sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn]){
                    
                    sessions[targetSessionId].treasury[zone - 1] += sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn];
                    sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] = 0;
                    exitPlayer(msg.sender);
                } else {
                    sessions[targetSessionId].treasury[zone - 1] += payTax;
                    sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] -= payTax;
                }
            }
        } else{
            // Checks if square already owned
            address squareOwner = sessions[targetSessionId].squareOwners[convertedPosition];
            if (squareOwner != address(0)){
                // Square is already owned
                if (squareOwner != msg.sender){
                    // pay rent
                    uint payRent = zone * sessions[targetSessionId].sessionPrice / 10;
                    uint256 squareOwnerIndex = findPlayerIndexInArray(targetSessionId, squareOwner);
                    if (payRent > sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] ){
                        sessions[targetSessionId].playerBalances[squareOwnerIndex] += sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn];
                        sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] = 0;
                        exitPlayer(msg.sender);
                    } 
                    else {
                        sessions[targetSessionId].playerBalances[sessions[targetSessionId].whoseTurn] -= payRent;
                        sessions[targetSessionId].playerBalances[squareOwnerIndex] += payRent;
                    }
                }
            }
            else{
                // Square is empty
                sessions[targetSessionId].squareOwners[convertedPosition] = msg.sender;
            }
        }

        emit DiceRolled(targetSessionId, msg.sender, position % 24);

        if(sessions[targetSessionId].playerCount == 1){
            for (uint256 i; i < 4; i++) {
                sessions[targetSessionId].playerBalances[0] += sessions[targetSessionId].treasury[i];
            }

            uint fees = feePerThousand * sessions[targetSessionId].playerBalances[0] / 1000;
            collectedFees += fees;
            sessions[targetSessionId].playerBalances[0] -= fees;
            emit PlayerWon(sessions[targetSessionId].players[0], sessions[targetSessionId].playerBalances[0]);
            exitPlayer(sessions[targetSessionId].players[0]);
        }
        else{
            sessions[targetSessionId].whoseTurn += 1;
            if(sessions[targetSessionId].whoseTurn >= sessions[targetSessionId].playerCount)
                sessions[targetSessionId].whoseTurn = 0;
                
            emit WhoseTurnChanged(targetSessionId, sessions[targetSessionId].whoseTurn);

            requestRandomWordsHelper(sessions[targetSessionId].sessionId);
            /*
            Only works on post-merge chains (e.g. Goerli, Sepolia & Mainnet)
            Read Appendix A for more details.
            if  (sessions[targetSessionId].rngData.lastMiner != block.coinbase) {
                sessions[targetSessionId].rngData.lastBlock = block.number;
                sessions[targetSessionId].rngData.lastMiner = block.coinbase;
                sessions[targetSessionId].randomWord = block.prevrandao;

            }   else if (sessions[targetSessionId].rngData.lastBlock < block.number - 5){
                sessions[targetSessionId].rngData.lastBlock = block.number;
                sessions[targetSessionId].randomWord = block.prevrandao;

            } else {
                revert();
                //requestRandomWordsHelper(sessions[targetSessionId].sessionId);
            }

            */
        }
    }

    function exitSession() external nonReentrant onlyIfPlayerInSession {
        uint256 targetSessionId = playerSessionId[msg.sender];

        if(sessions[targetSessionId].status == SESSION_STARTED){
            uint256 playerIndex = findPlayerIndexInArray(targetSessionId, msg.sender);
            uint256 sessionBalance = sessions[targetSessionId].playerBalances[playerIndex];
            sessions[targetSessionId].treasury[0] += sessionBalance / 4;
            sessions[targetSessionId].treasury[1] += sessionBalance / 4;
            sessions[targetSessionId].treasury[2] += sessionBalance / 4;
            sessions[targetSessionId].treasury[3] += sessionBalance - sessionBalance * 3 / 4;
            sessions[targetSessionId].playerBalances[playerIndex] = 0;
            
            exitPlayer(msg.sender);

            if(sessions[targetSessionId].playerCount == 1){
                for (uint256 i; i < 4; i++) {
                    sessions[targetSessionId].playerBalances[0] += sessions[targetSessionId].treasury[i];
                }

                uint fees = feePerThousand * sessions[targetSessionId].playerBalances[0] / 1000;
                collectedFees += fees;
                sessions[targetSessionId].playerBalances[0] -= fees;
                emit PlayerWon(sessions[targetSessionId].players[0], sessions[targetSessionId].playerBalances[0]);
                exitPlayer(sessions[targetSessionId].players[0]);
            }
        }
        else{
            exitPlayer(msg.sender);
        }
    }

    function exitPlayer(address player) internal {
        uint256 targetSessionId = playerSessionId[player];
        uint256 playerIndex = findPlayerIndexInArray(targetSessionId, player);
        if(sessions[targetSessionId].playerBalances[playerIndex] != 0){
            uint256 sessionBalance = sessions[targetSessionId].playerBalances[playerIndex];
            sessions[targetSessionId].playerBalances[playerIndex] = 0;
           
            require(payable(player).send(sessionBalance));
        }

        if(sessions[targetSessionId].playerCount == 1) {
            delete sessions[targetSessionId];
            --sessionCounter;
        }
        else {
            // If the player has squares, make them ownable
            for (uint256 i; i < 24; i++) {
                if(sessions[targetSessionId].squareOwners[i] == player){
                    sessions[targetSessionId].squareOwners[i] = address(0);
                }
            }

            // Remove player from the array and reorder the array
            bool indexFound = false;
            for (uint256 i; i < sessions[targetSessionId].playerCount - 1; i++){
                if(!indexFound && sessions[targetSessionId].players[i] == player) {
                    indexFound = true;
                }
                if(indexFound) {
                    sessions[targetSessionId].players[i] = sessions[targetSessionId].players[i + 1];
                    sessions[targetSessionId].playerBalances[i] = sessions[targetSessionId].playerBalances[i + 1];
                    sessions[targetSessionId].playerPositions[i] = sessions[targetSessionId].playerPositions[i + 1];
                }
            }
            if(sessions[targetSessionId].admin == player){
                sessions[targetSessionId].admin = sessions[targetSessionId].players[0];
            }
            sessions[targetSessionId].players.pop();
            sessions[targetSessionId].playerBalances.pop();
            sessions[targetSessionId].playerPositions.pop();
            --sessions[targetSessionId].playerCount;
        }
        playerSessionId[player] = 0;

        emit PlayerLeaved(player, targetSessionId);
    }

    function requestRandomWordsHelper(uint256 sessionId) public {
        
            uint256 requestId = COORDINATOR.requestRandomWords(
                0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f,        // keyHash is the keyHash of the Chainlink gaslane (hardcoded for Mumbai)
                s_subscriptionId, // subscriptionId is the ID of the Chainlink subscription
                3,              //_requestConfirmations is the number of confirmations to wait before fulfilling the request. A higher number of confirmations increases security by reducing the likelihood that a chain re-org changes a published randomness outcome.
                1000000,        //_callbackGasLimit is the gas limit that should be used when calling the consumer's fulfillRandomWords function.
                1               //_numWords is the number of random words to request.
            );
        
            vrfRequestsSessionId[requestId] = sessionId;

    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override{
        uint256 sessionId = vrfRequestsSessionId[requestId];
        sessions[sessionId].randomWord = randomWords[0];
    }

    function findPlayerIndexInArray(uint256 targetSessionId, address playerAddress) internal view returns(uint256) {
        for (uint256 i; i < sessions[targetSessionId].players.length; i++) {
            if (sessions[targetSessionId].players[i] == playerAddress) {
                return i;
            }
        }
        revert();
    }
}