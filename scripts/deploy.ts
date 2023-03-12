// This script deploys the BlockDice contract to Mumbai Testnet

const hre = require("hardhat");
import { ContractFactory } from "ethers";
import { Contract } from "ethers";
import { Signer } from "ethers";
const dotenv = require("dotenv");

dotenv.config();

async function main() {
console.log("🚀 Mumbai Testnet BlockDiceManager Deployment Script 🚀");
// connect to alchemy mumbai api
const provider = new hre.ethers.providers.AlchemyProvider("maticmum", process.env.ALCHEMY_API_KEY);
console.log("Connected to Alchemy Mumbai API");

const latestBlockNumber = await provider.getBlockNumber();
    console.log({latestBlockNumber});

    // get account 0 from hre
    const accounts = await hre.ethers.getSigners();
    console.log("Deployer account: ", accounts[0].address);

// deploy the ERC1155 contract using the marketPlaceOwner account
const gameFactory: ContractFactory = await hre.ethers.getContractFactory("BlockdiceManager");

// deploy the contract  
console.log("Beginning BlockDiceManager contract deployment... 🚀")

const blockDiceManagerContract: Contract = await gameFactory.connect(accounts[0]).deploy();
console.log("Awaiting BlockDiceManager contract to be mined... 🚀\n")
await blockDiceManagerContract.deployed();

console.log("🚢 BlockDiceManager contract succesfully shipped at: ", blockDiceManagerContract.address, " 🚢 \n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});



