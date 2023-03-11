# BlockDice SmartContracts Repo - The Bucharest Hackathon

## Introduction
BlockDice is an on-chain turn-based game. It is a decentralized version of popular diced-table games. 

## Rules
The game is played between two and ten players, each of which has a wallet. 
The game is played in rounds, and each round consists of a number of turns equivalent to the amount of players at the game session. 
In each turn, each player rolls a dice using RANDAO if it's the first dice roll in a single block and using Chainlink's VRF in all other cases. 
The dice rolled value determines the amount of spaces a player gets to walk forward at the table. 
Special blocks?
Game end condition?
Game winner determination?

## Game Flow
0. All these steps are integrated to the client side and users don't really have to consider them, but they are important for the game to work. Users click the buttons and the whole logic is handled by the client and the smart contracts.
1. The game is started by a player by calling the `createSession` function.
2. Other players can join the game by calling the `enterSession` function with the game starter's address as the function call argument.
3. The game starter can start the game by calling the `startSession` function.
4. The game starter can call the `requestRandomWords` function to roll the dice for the first time. 
5. Whose turn?
5. The `dice` function will decide whether a random number was already figured out from the last valid proposed block's RANDAO and if not it will use this random number. Else it will call the `requestRandomWords` to figure out the amount of space walked. 
6. The turn ends when all players have rolled the dice.
7. Game end condition?
8. Game winner determination?

## Blocks Placement
The blocks are a sequence of 24. Starting from the 0th block up to the 23rd block.
Yellow blocks - 0, 6, 12, 18
Red blocks - 3, 9, 15, 21

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
- [ ] Beautiful documentation
- [ ] Unit tests
- [ ] Deployment script
- [ ] Static analysis 
- [ ] Code refactor

## Appendix

### A - Dice RNG Logic
The dice roll is determined by the following logic:
- If the last valid RANDAO was proposed by block's a different miner, use it to determine the dice roll.
- Else, if the last valid RANDAO was proposed by the same miner, but the block was more than 5 blocks ago, use it to determine the dice roll.
- Else, use Chainlink VRF to determine the dice roll.
