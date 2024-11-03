const fs = require("fs");
const { getSelectors, FacetCutAction } = require('./libraries/diamond.js')
const { ethers } = require('hardhat')
async function deployDiamond() {
  const accounts = await ethers.getSigners()
  const contractOwner = accounts[0]


  const assets = [
    "0x00D1C02E008D594ebEFe3F3b7fd175850f96AEa0",
    "0x7fEa3ea63433a35e8516777171D7d0e038804716",
    "0x5caF98bf477CBE96d5CA56039FE7beec457bA653",
    "0xE4aB69C077896252FAFBD49EFD26B5D171A32410",
    "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    "0x0000000000000000000000000000000000000001"
  ]
  const priceFeeds = [
    "0x3ec8593F930EA45ea58c968260e6e9FF53FC934f",
    "0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1",
    "0xD1092a65338d049DB68D7Be6bD89d17a0929945e",
    "0xb113F5A928BCfF189C998ab20d753a47F9dE5A61",
    "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165",
    "0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1"
  ]

  const botAddress = "0x0beaf0BfC5D1f3f3F8d3a6b0F1B6E3f2b0f1b6e3"
  const swapRouterAddress = "0x1689E7B1F10000AE47eBfE339a4f69dECd19F602";
  const wormhole = "0x79A1027a6A159502049F10906D333EC57E95F083";
  const tokenBridge = "0x86F55A04690fd7815A3D802bD587e83eA888B239";
  const wormholeRelayer = "0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE";
  const circleTM = "0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5";
  const circleMT = "0x7865fAfC2db2093669d92c0F33AeEF291086BEFD";
  const chainId = 10004;

  const chainIds = [1005, 1003]
  const spokeProtocols = [
    "0xc5520369a974AEB437a34F5ef15D8F408A2e7588",
    "0xd556b9e2c661eFEbf8775cb538ff696621edD353"
  ]
  const cctpDomain = [2, 3]

  // BASE Mainnet addresses
  // const assets = [
  //   "0x0000000000000000000000000000000000000001",
  //   "0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196",
  //   "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  //   "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
  //   "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb"
  // ]
  // const priceFeeds = [
  //   "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70", //ETHUSD
  //   "0x17CAb8FE31E32f08326e5E27412894e49B0f9D65", //LINKUSD
  //   "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B", //USDCUSD
  //   "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9", //USDTUSD
  //   "0x591e79239a7d679378eC8c847e5038150364C78F" //DAIUSD
  // ]

  // deploy DiamondCutFacet
  const DiamondCutFacet = await ethers.getContractFactory('DiamondCutFacet')
  const diamondCutFacet = await DiamondCutFacet.deploy()
  await diamondCutFacet.deployed()
  console.log('DiamondCutFacet deployed:', diamondCutFacet.address)

  const LibXGetters = await ethers.getContractFactory('LibXGetters')
  const libXGetters = await LibXGetters.deploy()

  // deploy Diamond
  const Diamond = await ethers.getContractFactory('Diamond')
  const diamond = await Diamond.deploy(
    contractOwner.address,
    diamondCutFacet.address,
  )
  await diamond.deployed()
  console.log('Diamond deployed:', diamond.address)

  // deploy DiamondInit
  // DiamondInit provides a function that is called when the diamond is upgraded to initialize state variables
  // Read about how the diamondCut function works here: https://eips.ethereum.org/EIPS/eip-2535#addingreplacingremoving-functions
  const DiamondInit = await ethers.getContractFactory('DiamondInit')
  const diamondInit = await DiamondInit.deploy()
  await diamondInit.deployed()
  console.log('DiamondInit deployed:', diamondInit.address)

  // deploy facets
  console.log('')
  console.log('Deploying facets')
  const FacetNames = ['DiamondLoupeFacet', 'OwnershipFacet', 'ProtocolFacet', 'XProtocolFacet']
  const cut = []
  for (const FacetName of FacetNames) {
    const Facet = await ethers.getContractFactory(FacetName, (
      FacetName === 'XProtocolFacet') || (FacetName === 'ProtocolFacet') ?
      { libraries: { LibXGetters: libXGetters.address } } : {})
    const facet = await Facet.deploy()
    await facet.deployed()

    fs.writeFile(`./scripts/abi/${FacetName}.json`, JSON.stringify(Facet.interface, null, 2), { flag: "w" }, (err) => {
      if (err) {
        console.error(err)
        return
      }
    })
    console.log(`${FacetName} deployed: ${facet.address}`)
    cut.push({
      facetAddress: facet.address,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(facet),
    })
  }


  // upgrade diamond with facets
  console.log('')
  console.log('Diamond Cut:', cut)
  const diamondCut = await ethers.getContractAt('IDiamondCut', diamond.address)
  let tx
  let receipt
  // call to init function
  let functionCall = diamondInit.interface.encodeFunctionData('init')
  tx = await diamondCut.diamondCut(cut, diamondInit.address, functionCall)
  console.log('Diamond cut tx: ', tx.hash)
  receipt = await tx.wait()
  if (!receipt.status) {
    throw Error(`Diamond upgrade failed: ${tx.hash}`)
  }
  console.log('Completed diamond cut')

  const initTx = await diamond.initialize(
    assets, priceFeeds, chainIds, spokeProtocols,
    wormhole, wormholeRelayer, tokenBridge, circleTM,
    circleMT, chainId, cctpDomain
  )
  initTx.wait()
  console.log('Diamond initialized')

  await setAddresses(diamond.address, botAddress, swapRouterAddress)

  return diamond.address
}

async function setAddresses(address, botAddress, swapRouterAddress) {
  const signer = await ethers.getSigners()[0]
  const protocol = await ethers.getContractAt('ProtocolFacet', address, signer)
  const btTx = await protocol.setBotAddress(botAddress)
  const srTx = await protocol.setSwapRouter(swapRouterAddress)

  btTx.wait()
  srTx.wait()
  console.log('Bot address and swap router set')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
if (require.main === module) {
  deployDiamond()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error)
      process.exit(1)
    })
}

exports.deployDiamond = deployDiamond
