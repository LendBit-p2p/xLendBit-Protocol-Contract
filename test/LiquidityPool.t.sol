// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "forge-std/Test.sol";
import "../contracts/Diamond.sol";
import "../contracts/facets/ProtocolFacet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/model/Event.sol";
import "../contracts/utils/constants/Constant.sol";
import "../contracts/utils/validators/Validator.sol";

// MOCK Contracts
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ProtocolTest is Test, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    ProtocolFacet protocolFacet;

    address USDT_USD;
    address DAI_USD;
    address LINK_USD;
    address WETH_USD;
    address ETH_USD;

    address USDT_CONTRACT_ADDRESS;
    address WETH_CONTRACT_ADDRESS;
    address DAI_CONTRACT_ADDRESS;
    address LINK_CONTRACT_ADDRESS;
    address ETH_CONTRACT_ADDRESS = address(1);

    address owner;
    address B;
    address C;

    address botAddress = address(0x0beaf0BfC5D1f3f3F8d3a6b0F1B6E3f2b0f1b6e3);
    address swapRouterAddress = 0x1689E7B1F10000AE47eBfE339a4f69dECd19F602;

    address[] tokens;
    address[] priceFeed;

    function setUp() public {
        owner = mkaddr("owner");
        B = mkaddr("B address");
        C = mkaddr("C address");

        switchSigner(owner);
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(owner, address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        protocolFacet = new ProtocolFacet();

        //deploy mock tokens
        (USDT_CONTRACT_ADDRESS, USDT_USD) = deployERC20ContractAndAddPriceFeed(
            "USDT",
            6,
            1
        );
        (DAI_CONTRACT_ADDRESS, DAI_USD) = deployERC20ContractAndAddPriceFeed(
            "DAI",
            18,
            1
        );
        (LINK_CONTRACT_ADDRESS, LINK_USD) = deployERC20ContractAndAddPriceFeed(
            "LINK",
            18,
            10
        );
        (WETH_CONTRACT_ADDRESS, WETH_USD) = deployERC20ContractAndAddPriceFeed(
            "WETH",
            18,
            2000
        );

        tokens.push(USDT_CONTRACT_ADDRESS);
        tokens.push(DAI_CONTRACT_ADDRESS);
        tokens.push(LINK_CONTRACT_ADDRESS);
        tokens.push(WETH_CONTRACT_ADDRESS);
        tokens.push(ETH_CONTRACT_ADDRESS);

        priceFeed.push(USDT_USD);
        priceFeed.push(DAI_USD);
        priceFeed.push(LINK_USD);
        priceFeed.push(WETH_USD);
        priceFeed.push(WETH_USD);

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](3);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        cut[2] = (
            FacetCut({
                facetAddress: address(protocolFacet),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("ProtocolFacet")
            })
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        //call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();

        ///@notice set protocol constructor by the diamond
        diamond.initialize(tokens, priceFeed);

        protocolFacet = ProtocolFacet(address(diamond));
        // protocolFacet.setBotAddress(botAddress);
        // protocolFacet.setSwapRouter(swapRouterAddress);

        ProtocolFacet(address(diamond)).setFeeRate(100);

        transferTokenToOwner();
    }

    function transferTokenToOwner() public {
        ERC20Mock(USDT_CONTRACT_ADDRESS).mint(owner, 1000E18);
        ERC20Mock(DAI_CONTRACT_ADDRESS).mint(owner, 500 ether);
        ERC20Mock(WETH_CONTRACT_ADDRESS).mint(owner, 500 ether);
        ERC20Mock(LINK_CONTRACT_ADDRESS).mint(owner, 500 ether);
    }

    function testOnlyWhitelistedUserCanRequestLoan() public {
        _depositCollateral(C, ETH_CONTRACT_ADDRESS, 1E18);
        switchSigner(owner);
        IERC20(DAI_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint256).max
        );
        address[] memory whitelist = new address[](1);
        whitelist[0] = B;
        protocolFacet.createLoanListing(
            10E10,
            2E10,
            10E10,
            block.timestamp + 365 days,
            500,
            DAI_CONTRACT_ADDRESS,
            whitelist
        );

        switchSigner(C);
        vm.expectRevert(
            abi.encodeWithSelector(Protocol__NotWhitelisted.selector)
        );
        protocolFacet.requestLoanFromListing(1, 5E10);
    }

    function testListingWithZeroWhitelistAddressIsOpenForAllAddress() public {
        _depositCollateral(C, ETH_CONTRACT_ADDRESS, 1E18);
        _depositCollateral(B, ETH_CONTRACT_ADDRESS, 1E18);
        switchSigner(owner);
        IERC20(DAI_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint256).max
        );
        address[] memory whitelist = new address[](0);
        protocolFacet.createLoanListing(
            10E10,
            2E10,
            10E10,
            block.timestamp + 365 days,
            500,
            DAI_CONTRACT_ADDRESS,
            whitelist
        );

        switchSigner(C);
        vm.expectEmit(true, true, true, true);
        emit RequestCreated(C, 1, 5E10, 500);
        protocolFacet.requestLoanFromListing(1, 5E10);

        switchSigner(B);
        vm.expectEmit(true, true, true, true);
        emit RequestCreated(B, 2, 5E10, 500);
        protocolFacet.requestLoanFromListing(1, 5E10);
    }

    function _mintTokenToAddress(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        ERC20Mock(_token).mint(_to, _amount);
    }

    function _depositCollateral(
        address user,
        address token,
        uint256 amount
    ) internal {
        switchSigner(user);
        if (token == ETH_CONTRACT_ADDRESS) {
            vm.deal(user, amount);
            protocolFacet.depositCollateral{value: amount}(token, amount);
            return;
        }
        IERC20(token).approve(address(protocolFacet), type(uint).max);
        protocolFacet.depositCollateral(token, amount);
    }

    function deployERC20ContractAndAddPriceFeed(
        string memory _name,
        uint8 _decimals,
        int256 _initialAnswer
    ) internal returns (address, address) {
        ERC20Mock _erc20 = new ERC20Mock();
        MockV3Aggregator _priceFeed = new MockV3Aggregator(
            _decimals,
            _initialAnswer * 1e8
        );
        vm.label(address(_priceFeed), "Price Feed");
        vm.label(address(_erc20), _name);
        return (address(_erc20), address(_priceFeed));
    }

    function generateSelectors(
        string memory _facetName
    ) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "scripts/genSelectors.js";
        cmd[2] = _facetName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }

    function mkaddr(string memory name) public returns (address) {
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(name))))
        );
        vm.label(addr, name);
        return addr;
    }

    function switchSigner(address _newSigner) public {
        address foundrySigner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        if (msg.sender == foundrySigner) {
            vm.startPrank(_newSigner);
        } else {
            vm.stopPrank();
            vm.startPrank(_newSigner);
        }
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}
}
