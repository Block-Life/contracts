// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";

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

contract BlockdiceManager is VRFV2WrapperConsumerBase, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARD = keccak256("GUARD");
    uint256 private constant SESSION_NOT_STARTED = 1;
    uint256 private constant SESSION_STARTED = 2;
    address private constant LINK_TOKEN = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address private constant VRF_WRAPPER = 0x99aFAf084eBA697E584501b8Ed2c0B37Dd136693;

    mapping(address => uint256) playerSessionId;
    mapping(uint256 => mapping( address => uint256)) sessionBalances;
    mapping(uint256 => Session) sessions;
    mapping(uint256 => uint256) vrfRequestsSessionId;
    uint256 public sessionCounter;
    uint256 public sessionIdCounter = 1;
    uint256 public minSessionPrice = 1000;
    uint256 public collectedFees;

    struct Session { 
        uint256 sessionId;
        address admin;
        uint256 status;
        address[] players;
        uint256 playerCount;
        uint256 maxPlayerAmount;
        uint256 sessionPrice;
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

    constructor() VRFV2WrapperConsumerBase(LINK_TOKEN, VRF_WRAPPER) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GUARD, msg.sender);
        
    }

    function getSession() public view onlyIfPlayerInSession returns(Session memory){
        return sessions[playerSessionId[msg.sender]];
    }

    function getSessionHelper(address sessionCreator) public view returns(Session memory){
        return sessions[playerSessionId[sessionCreator]];
    }

    function createSession() external payable nonReentrant onlyIfPlayerNotInSession{
        if(msg.value < minSessionPrice) revert BelowMinimumSessionPrice();
        
        
        ++sessionCounter;
        while(sessions[sessionIdCounter].playerCount != 0){
            if(sessionIdCounter == type(uint256).max){
                sessionIdCounter = 1;
            }
            else{
                ++sessionIdCounter;
            }
        }
        
        Session memory session;
        session.sessionId = sessionIdCounter;
        session.admin = msg.sender;
        session.status = SESSION_NOT_STARTED;
        session.maxPlayerAmount = 10;
        ++session.playerCount;
        session.sessionPrice = msg.value;
        sessions[sessionIdCounter] = session;
        sessions[sessionIdCounter].players.push(msg.sender);
        playerSessionId[msg.sender] = sessionIdCounter;
        sessions[sessionIdCounter].randomWord = block.prevrandao;

        sessionBalances[sessionIdCounter][msg.sender] += msg.value;

        emit SessionCreated(msg.sender, sessionIdCounter, 10, 0);
        emit PlayerJoined(msg.sender, sessionIdCounter);
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
        
        for(uint256 i; i < sessions[targetSessionId].playerCount; i++){
            sessions[targetSessionId].playerPositions.push(0);
        }

        sessions[targetSessionId].randomWord = block.prevrandao;
    }
    
    function dice() external nonReentrant onlyIfPlayerInSession{
        Session memory session = sessions[playerSessionId[msg.sender]];
        
        address whoseTurn = session.players[session.whoseTurn];
        if(session.status != SESSION_STARTED) revert TargetSessionIsNotStarted();
        if(whoseTurn != msg.sender) revert NotYourTurn();
        if(session.randomWord == 0) revert RandomWordIsNotReadyYet();


        uint256 stepCount = (session.randomWord % 6) + 1;
        session.randomWord = 0;
        session.playerPositions[session.whoseTurn] += stepCount;
        uint256 position = session.playerPositions[session.whoseTurn];
        session.whoseTurn += 1;
        if(session.whoseTurn >= session.playerCount)
            session.whoseTurn = 0;
                
        emit WhoseTurnChanged(session.sessionId, session.whoseTurn);

        uint zone = 0;
        uint convertedPosition = (position % 24);

        if(convertedPosition > 18 || session.playerPositions[session.whoseTurn] == 0){
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

        // checks if player is on a special square
        if(position % 3 == 0){
            // if yellow square
            if (position % 6 == 0){
                sessionBalances[session.sessionId][msg.sender] += session.treasury[zone - 1];
                session.treasury[zone - 1] = 0;
                
            } else {  // if red square
                uint payTax = zone * session.sessionPrice / 10;

                if ( payTax > sessionBalances[session.sessionId][msg.sender] ){
                    
                    session.treasury[zone - 1] += sessionBalances[session.sessionId][msg.sender];
                    sessionBalances[session.sessionId][msg.sender] = 0;
                    exitPlayer(msg.sender);
                } else {
                    session.treasury[zone - 1] += payTax;
                    sessionBalances[session.sessionId][msg.sender] -= payTax;
                }
            }
        } else{
            // checks if square already owned
            address squareOwner = session.squareOwners[zone - 1];
            if (squareOwner != address(0)){
                if (squareOwner != msg.sender){
                // pay rent
                uint payRent = zone * session.sessionPrice / 10;

                sessionBalances[session.sessionId][msg.sender] -= payRent;
                sessionBalances[session.sessionId][squareOwner] += payRent;
                }
            }
            else{
                // earn square
                session.squareOwners[zone - 1] = msg.sender;
            }
        }

        if(session.playerCount == 1){
            uint fees = 5 * sessionBalances[session.sessionId][session.players[0]] / 100;
            collectedFees += fees;
            sessionBalances[session.sessionId][session.players[0]] -= fees;
            emit PlayerWon(session.players[0], sessionBalances[session.sessionId][session.players[0]]);
            exitPlayer(session.players[0]);
            return;
        }

        // read Appendix A for more details
        if  (session.rngData.lastMiner != block.coinbase) {
            session.rngData.lastBlock = block.number;
            session.rngData.lastMiner = block.coinbase;
            session.randomWord = block.prevrandao;

        } else if (session.rngData.lastBlock < block.number - 5){
            session.rngData.lastBlock = block.number;
            session.randomWord = block.prevrandao;

        } else {
            revert();
            //requestRandomWords(session.sessionId);
        }

        emit DiceRolled(session.sessionId, msg.sender, position % 24);

        // push memory session to storage
        sessions[playerSessionId[msg.sender]] = session;
        
    }

    function enterSession(address player) external payable nonReentrant {
        uint256 targetSessionId = playerSessionId[player];
        if(targetSessionId == 0) revert TargetPlayerIsNotInSession();
        
        
        if(sessions[targetSessionId].playerCount == sessions[targetSessionId].maxPlayerAmount) revert TargetSessionIsFull();
        if(sessions[targetSessionId].status != SESSION_NOT_STARTED) revert TargetSessionIsStarted();
        if(msg.value != sessions[targetSessionId].sessionPrice) revert SentDifferentSessionPrice(); 
        sessionBalances[targetSessionId][msg.sender] += sessions[targetSessionId].sessionPrice;

        sessions[targetSessionId].players.push(msg.sender);
        ++sessions[targetSessionId].playerCount;
        playerSessionId[msg.sender] = targetSessionId;
        
        emit PlayerJoined(msg.sender, targetSessionId);
    }

    function exitSession() external nonReentrant onlyIfPlayerInSession {
        uint256 targetSessionId = playerSessionId[msg.sender];

        if(sessions[targetSessionId].status == SESSION_STARTED){
            if(sessions[targetSessionId].playerCount == 2){
                uint256 sessionBalance = sessionBalances[targetSessionId][msg.sender];
                sessionBalances[targetSessionId][msg.sender] = 0;
                exitPlayer(msg.sender);
                
                sessionBalances[targetSessionId][sessions[targetSessionId].players[0]] += sessionBalance;

                uint fees = 5 * sessionBalances[targetSessionId][sessions[targetSessionId].players[0]] / 100;
                collectedFees += fees;
                sessionBalances[targetSessionId][sessions[targetSessionId].players[0]] -= fees;
                emit PlayerWon(sessions[targetSessionId].players[0], sessionBalances[targetSessionId][sessions[targetSessionId].players[0]]);
                exitPlayer(sessions[targetSessionId].players[0]);
            }
            else{
                uint256 sessionBalance = sessionBalances[targetSessionId][msg.sender];
                sessions[targetSessionId].treasury[0] += sessionBalance / 4;
                sessions[targetSessionId].treasury[1] += sessionBalance / 4;
                sessions[targetSessionId].treasury[2] += sessionBalance / 4;
                sessions[targetSessionId].treasury[3] += sessionBalance - sessionBalance * 3 / 4;
                sessionBalances[targetSessionId][msg.sender] = 0;
            
                exitPlayer(msg.sender);
            }
        }
        else{
            exitPlayer(msg.sender);
        }
    }

    function withdrawLinks() external onlyRole(DEFAULT_ADMIN_ROLE){
        IERC20(LINK_TOKEN).safeTransfer(msg.sender, IERC20(LINK_TOKEN).balanceOf(address(this)));
    }

    function exitPlayer(address player) internal {
        uint256 targetSessionId = playerSessionId[player];

        if(sessionBalances[targetSessionId][player] != 0){
            uint256 sessionBalance = sessionBalances[targetSessionId][player];
            sessionBalances[targetSessionId][player] = 0;
           
            require(payable(player).send(sessionBalance));
        }

        if(sessions[targetSessionId].playerCount == 1) {
            delete sessions[targetSessionId];
            --sessionCounter;
        }
        else {
            // remove player from the array and reorder the array
            bool indexFound = false;
            for (uint256 i; i < sessions[targetSessionId].playerCount - 1; i++){
                if(!indexFound && sessions[targetSessionId].players[i] == player) {
                    indexFound = true;
                }
                if(indexFound) {
                    sessions[targetSessionId].players[i] = sessions[targetSessionId].players[i + 1];
                }
            }
            if(sessions[targetSessionId].admin == player){
                sessions[targetSessionId].admin = sessions[targetSessionId].players[0];
            }
            sessions[targetSessionId].players.pop();
            --sessions[targetSessionId].playerCount;
        }
        playerSessionId[player] = 0;

        emit PlayerLeaved(player, targetSessionId);
    }

    function requestRandomWords(uint256 sessionId) internal {
        if(sessions[sessionId].randomWord == 0){
            uint256 requestId = requestRandomness(
                1000000,        //_callbackGasLimit is the gas limit that should be used when calling the consumer's fulfillRandomWords function.
                3,              //_requestConfirmations is the number of confirmations to wait before fulfilling the request. A higher number of confirmations increases security by reducing the likelihood that a chain re-org changes a published randomness outcome.
                1               //_numWords is the number of random words to request.
            );
        
            vrfRequestsSessionId[requestId] = sessionId;
        }
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override{
        uint256 sessionId = vrfRequestsSessionId[requestId];
        sessions[sessionId].randomWord = randomWords[0];
    }

    function withdraw () external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = collectedFees;
        require(payable(msg.sender).send(balance));
    }

    // function getSessionAddress() external view returns(address){
    //     return playerSession[msg.sender];
    // }

    // function createSession() external nonReentrant {
    //     if(playerSession[msg.sender] != address(0)) revert PlayerAlreadyInSession();
    //     playerSession[msg.sender] = address(new GameSession(msg.sender));
    //     GameSession(playerSession[msg.sender]).enterSession(msg.sender);
    // }

    // function exitSession() external nonReentrant {
    //     if(playerSession[msg.sender] == address(0)) revert PlayerNotInSession();
    //     playerSession[msg.sender] = address(0);
    //     GameSession(playerSession[msg.sender]).exitSession(msg.sender);
    // }
}