/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-ethers')
require("dotenv").config()


const SEPOLIA_API_KEY_URL = process.env.SEPOLIA_API_KEY_URL
const BASE_API_KEY_URL = process.env.BASE_API_KEY_URL
const ACCOUNT_PRIVATE_KEY = process.env.ACCOUNT_PRIVATE_KEY
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.4',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: true,
        },
      },
      {
        version: '0.8.20',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: true,
        },
      },
      {
        version: '0.8.9',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: true,
        },
      },
    ]
  },
  networks: {
    mainnet: {
      url: BASE_API_KEY_URL,
      accounts: [ACCOUNT_PRIVATE_KEY],
      // gas: 20044273,
    },
    sepolia: {
      url: SEPOLIA_API_KEY_URL,
      accounts: [ACCOUNT_PRIVATE_KEY],
      // gas: 20044273,
    },
  },
}

