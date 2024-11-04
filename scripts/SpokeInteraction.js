const { ethers } = require("ethers");

const sourceProvider = new ethers.JsonRpcProvider(sourceChain.rpc);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, sourceProvider);
