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

## To Do
- [ ] Add the game end condition
- [ ] Add the game winner determination
- [ ] Add the special blocks logic
- [X] Add the RANDAO / Chainlink VRF logic to the `dice` function
- [ ] Unit tests
- [ ] Deployment script
- [ ] Static analysis 

## Appendix

### A - Dice RNG Logic
The dice roll is determined by the following logic:
- If the last valid RANDAO was proposed by block's a different miner, use it to determine the dice roll.
- Else, if the last valid RANDAO was proposed by the same miner, but the block was more than 5 blocks ago, use it to determine the dice roll.
- Else, use Chainlink VRF to determine the dice roll.
