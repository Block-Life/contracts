import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-truffle5";
import dotenv from "dotenv";
dotenv.config();



// add mumbai testnet 
// take accounts from accounts.csv file


const config: HardhatUserConfig = {
  networks: {
    mumbai: {
      url: "https://rpc-mumbai.maticvigil.com",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
  },
  solidity: {
    compilers: [
        {
            version: "0.8.19",
            settings: {
              viaIR: true,
              metadata: {
                appendCBOR: false,
                bytecodeHash: "none"
              },
              optimizer: {
                enabled: true,
                runs: 1,
              }
            }
          }
    ]
  }

};

export default config;