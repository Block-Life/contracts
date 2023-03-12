# BlockDice SmartContracts Repo - The Bucharest Hackathon

<img style="display: block;-webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);" src="https://bafkreieybqtgdeu2fafk5h3bx5m5stpeqwn7ovdfxmaxohoidhtst6io7u.ipfs.w3s.link/" width="200" height="200">

## Introduction
BlockDice is an on-chain turn-based game. It is a decentralized version of popular diced-table games. 

## Summary

[Rules](#rules)

[Game Flow](#game-flow)

[Blocks Placement](#blocks-placement)

[To Do](#to-do)

[Appendix](#appendix)

[🚢 Deployment](#🚢-deployment)


## Rules
* The game is played between two and ten players, each of which has a wallet. 
* The game is played in rounds

    * each round consists of a number of turns equivalent to the amount of players at the game session. 
    * In each turn, each player rolls a dice using RANDAO if it's the first dice roll in a single block and using Chainlink's VRF in all other cases. 

    * The dice rolled value determines the amount of spaces a player gets to walk forward at the table. 

    <img style="display: block; max-width: 70%; -webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);transition: background-color 300ms;" src="https://bafybeibqborpiy3p7osrnimqti4evo6hvd7z4oxhpitonmruaanswr4j7q.ipfs.w3s.link/" >

* Special blocks
    
    The game has four different zones and four types of blocks that determine the smart contract interaction's result. 

    <img style="display: block;-webkit-user-select: none;max-width: 70%;margin: auto;background-color: hsl(0, 0%, 90%);transition: background-color 300ms;" src="https://bafkreig2uoye6m42rchwea7a4f7qtiyk2hx5itdovz6czki5hx3nrkbbj4.ipfs.w3s.link/">

    Zones act as effect multipliers. Zone 1 is the starting zone and interactions are multiplied by 1. Zone 2's interactions are multiplied by 2 and so on up to zone 4 which is the last one and interactions are multiplied by 4.

    Some blocks are owned by players and some are not. The blocks are placed in a sequence of 24. Starting from the 0th block up to the 23rd block. The blocks are placed as follows:

    | Block Type | Purpose | Description |
    | --- | --- | --- |
    | Yellow | Treasury | If a player lands on a yellow block, he receives the amount of taxes cumulated in the corresponding zone. | 
    | Red | Tax | If a player lands on a red block, he pays taxes to the zone's treasury. |
    | Not owned | Vacant Property | If a player lands on a not owned block, he gets ownership of it for free. |
    | Owned | Property | If a player lands on an owned block, he pays rent to the block owner. |

* Game end condition
    * The game ends when there's one player left.
    * This player is declared winner and receives 95% of the game's treasury.
    * The remaining 5% is sent to the developers.



## Game Flow
0. All these steps are integrated to the client side and users don't really have to consider them, but they are important for the game to work. Users click the buttons and the whole logic is handled by the client and the smart contracts.
1. The game is started by a player by calling the `createSession` function.
2. Other players can join the game by calling the `enterSession` function with the game starter's address as the function call argument.
3. The game starter can start the game by calling the `startSession` function.
4. The game starter can call the `requestRandomWords` function to roll the dice for the first time. 
5. The turns are determined by arrival order. The first player to arrive will be the first to roll the dice. The second player to arrive will be the second to roll the dice and so on.
5. The `dice` function will decide whether a random number was already figured out from the last valid proposed block's RANDAO and if not it will use this random number. Else it will call the `requestRandomWords` to figure out the amount of space walked. 
6. The turn ends when all players have rolled the dice and finished their smart contract interactions.
7. A new round starts when all players have finished their turns. Player 1 can roll the dice again.


## Blocks Placement
The blocks are a sequence of 24. Starting from the 0th block up to the 23rd block.

### Yellow blocks positions:
* 0
* 6
* 12	
* 18
### Red blocks positions:
* 3
* 9
* 15
* 21

### Other blocks:
All other blocks are not owned. And can be earned for free by stopping on them after a dice roll.


## To Do
- [x] Treasury logic
- [x] Blocks placement
- [x] Add the game end condition
- [x] Add the game winner determination
- [x] Add the special blocks logic
    - [x] Add the yellow block logic
    - [x] Add the red block logic
    - [x] Add the not owned block logic
    - [x] Add the owned block logic
- [x] Add the RANDAO / Chainlink VRF logic to the `dice` function
- [x] Add fee collection logic to the end of a game
- [x] Beautiful documentation
- [ ] Unit tests
- [x] Deployment script
- [ ] Static analysis 
- [ ] Code refactor

## Appendix

### A - Dice RNG Logic
The dice roll is determined by the following logic:
- If the last valid RANDAO was proposed by block's a different miner, use it to determine the dice roll.
- Else, if the last valid RANDAO was proposed by the same miner, but the block was more than 5 blocks ago, use it to determine the dice roll.
- Else, use Chainlink VRF to determine the dice roll.

## 🚢 Deployment
To deploy the contract at Mumbai testnet,make sure you have a funded account with Testnet Matic tokens. Then
fill the .env file with your private key and your Alchemy API key.

Run the following command:
```
npx hardhat run scripts/deploy.js --network mumbai
```
Voila! You have deployed the contract. 

