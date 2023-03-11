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
    mapping(address => uint256) sessionBalances;
    mapping(uint256 => Session) sessions;
    mapping(uint256 => uint256) vrfRequestsSessionId;
    uint256 public sessionCounter;
    uint256 public sessionIdCounter = 1;
    uint256 public minSessionPrice = 1000;

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
        
        sessionBalances[msg.sender] += msg.value;
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
        //requestRandomWords(sessionIdCounter);

        emit SessionCreated(msg.sender, sessionIdCounter, 10, 0);
        emit PlayerJoined(msg.sender, sessionIdCounter);
    }

    function startSession() external nonReentrant onlyIfPlayerInSession{
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

        sessions[targetSessionId].randomWord = 0;
        requestRandomWords(sessions[targetSessionId].sessionId);
    }
    
    function dice() external nonReentrant onlyIfPlayerInSession{
        Session memory session = sessions[playerSessionId[msg.sender]];
        if(session.status != SESSION_STARTED) revert TargetSessionIsNotStarted();
        if(session.players[session.whoseTurn] != msg.sender) revert NotYourTurn();
        if(session.randomWord == 0) revert RandomWordIsNotReadyYet();

        uint256 stepCount = (session.randomWord % 6) + 1;
        session.randomWord = 0;
        session.playerPositions[session.whoseTurn] += stepCount;

        // read Appendix A for more details
        if  (session.rngData.lastMiner != block.coinbase) {
            session.rngData.lastBlock = block.number;
            session.rngData.lastMiner = block.coinbase;
            session.randWord = block.prevrandao;

        } else if (session.rngData.lastBlock < block.number - 5){
            session.rngData.lastBlock = block.number;
            session.randWord = block.prevrandao;

        } else {
            
            requestRandomWords(session.sessionId);
        }

        if(session.playerPositions[session.whoseTurn] % 2 == 1){
            uint256 rent = session.sessionPrice / 2;
            if(sessionBalances[msg.sender] > rent) {
                sessionBalances[msg.sender] -= rent;
            }
            else{
                sessionBalances[msg.sender] = 0;
                exitPlayer(msg.sender);
            }
            sessionBalances[session.players[0]] += rent;
        }

        emit DiceRolled(session.sessionId, msg.sender, session.playerPositions[session.whoseTurn] % 24);
        
        if(session.playerCount == 1){
            emit PlayerWon(session.players[0], sessionBalances[session.players[0]]);
            exitPlayer(session.players[0]);
        }
        else{
            ++session.whoseTurn;
            if(session.whoseTurn > session.playerCount)
                session.whoseTurn = 0;
                
            emit WhoseTurnChanged(session.sessionId, session.whoseTurn);
        }
    }

    function enterSession(address player) external payable nonReentrant onlyIfPlayerNotInSession{
        if(playerSessionId[player] == 0) revert TargetPlayerIsNotInSession();
        uint256 targetSessionId = playerSessionId[player];
        if(sessions[targetSessionId].playerCount == sessions[targetSessionId].maxPlayerAmount) revert TargetSessionIsFull();
        if(sessions[targetSessionId].status != SESSION_NOT_STARTED) revert TargetSessionIsStarted();
        if(msg.value != sessions[targetSessionId].sessionPrice) revert SentDifferentSessionPrice();
        sessionBalances[msg.sender] += sessions[targetSessionId].sessionPrice;

        sessions[targetSessionId].players.push(msg.sender);
        ++sessions[targetSessionId].playerCount;
        playerSessionId[msg.sender] = targetSessionId;
        
        emit PlayerJoined(msg.sender, targetSessionId);
    }

    function exitSession() external nonReentrant onlyIfPlayerInSession {
        if(sessions[playerSessionId[msg.sender]].status != SESSION_NOT_STARTED) revert TargetSessionIsStarted();

        exitPlayer(msg.sender);
    }

    function withdrawLinks() external onlyRole(DEFAULT_ADMIN_ROLE){
        IERC20(LINK_TOKEN).safeTransfer(msg.sender, IERC20(LINK_TOKEN).balanceOf(address(this)));
    }

    function exitPlayer(address player) internal {
        uint256 targetSessionId = playerSessionId[player];
        
        if(sessionBalances[player] != 0){
            uint256 sessionBalance = sessionBalances[player];
            sessionBalances[player] = 0;
            payable(player).transfer(sessionBalance);
        }

        if(sessions[targetSessionId].playerCount == 1) {
            delete sessions[targetSessionId];
            --sessionCounter;
        }
        else {
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