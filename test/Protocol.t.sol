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

contract ProtocolTest is Test, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    ProtocolFacet protocolFacet;

    address USDTHolders = 0xCEFc1C9af894a9dFBF763A394E6588b0b4D9a5a8;
    address DAIHolders = 0xCEFc1C9af894a9dFBF763A394E6588b0b4D9a5a8;
    address LINKHolders = 0x4281eCF07378Ee595C564a59048801330f3084eE;
    address WETHHolders = 0x0a4CAA57ac414f6B936261ff7CB1d6883bBF7264;

    address USDT_USD = 0x3ec8593F930EA45ea58c968260e6e9FF53FC934f;
    address DIA_USD = 0xD1092a65338d049DB68D7Be6bD89d17a0929945e;
    address LINK_USD = 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61;
    address WETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    address USDT_CONTRACT_ADDRESS = 0x00D1C02E008D594ebEFe3F3b7fd175850f96AEa0;
    address WETH_CONTRACT_ADDRESS = 0x7fEa3ea63433a35e8516777171D7d0e038804716;
    address DIA_CONTRACT_ADDRESS = 0x5caF98bf477CBE96d5CA56039FE7beec457bA653;
    address LINK_CONTRACT_ADDRESS = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address ETH_CONTRACT_ADDRESS = address(1);

    address owner = address(0xa);
    address B = address(0xb);
    address C = address(0xc);

    address botAddress = address(0x0beaf0BfC5D1f3f3F8d3a6b0F1B6E3f2b0f1b6e3);
    address swapRouterAddress = 0x1689E7B1F10000AE47eBfE339a4f69dECd19F602;
    address wormhole = 0x79A1027a6A159502049F10906D333EC57E95F083;
    address tokenBridge = 0x86F55A04690fd7815A3D802bD587e83eA888B239;
    address wormholeRelayer = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
    address circleTM = 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5;
    address circleMT = 0x7865fAfC2db2093669d92c0F33AeEF291086BEFD;
    uint16 chainId = 10004;

    address[] tokens;
    address[] priceFeed;
    uint16[] chainIds;
    address[] spokeProtocols;
    uint32[] cctpDomain;

    function setUp() public {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        protocolFacet = new ProtocolFacet();

        owner = mkaddr("owner");
        B = mkaddr("B address");
        C = mkaddr("C address");

        tokens.push(USDT_CONTRACT_ADDRESS);
        tokens.push(DIA_CONTRACT_ADDRESS);
        tokens.push(LINK_CONTRACT_ADDRESS);
        tokens.push(WETH_CONTRACT_ADDRESS);
        tokens.push(ETH_CONTRACT_ADDRESS);

        priceFeed.push(USDT_USD);
        priceFeed.push(DIA_USD);
        priceFeed.push(LINK_USD);
        priceFeed.push(WETH_USD);
        priceFeed.push(ETH_USD);

        chainIds.push(1005);
        chainIds.push(1003);

        spokeProtocols.push(0xc5520369a974AEB437a34F5ef15D8F408A2e7588);
        spokeProtocols.push(0xd556b9e2c661eFEbf8775cb538ff696621edD353);

        cctpDomain.push(2);
        cctpDomain.push(3);

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
        diamond.initialize(
            tokens,
            priceFeed,
            chainIds,
            spokeProtocols,
            wormhole,
            wormholeRelayer,
            tokenBridge,
            circleTM,
            circleMT,
            chainId,
            cctpDomain
        );

        protocolFacet = ProtocolFacet(payable(address(diamond)));
        protocolFacet.setBotAddress(botAddress);
        protocolFacet.setSwapRouter(swapRouterAddress);

        // protocolFacet.approveUserToSpendTokens(DIA_CONTRACT_ADDRESS, B, type(uint).max);

        switchSigner(owner);
        IERC20(USDT_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint).max
        );
        IERC20(DIA_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint).max
        );
        IERC20(WETH_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint).max
        );

        // switchSigner(address(protocolFacet));
        // IERC20(DIA_CONTRACT_ADDRESS).approve(B, type(uint).max);
        // IERC20(USDT_CONTRACT_ADDRESS).approve(B, type(uint).max);
        // IERC20(WETH_CONTRACT_ADDRESS).approve(B, type(uint).max);

        transferTokenToOwner();
    }

    function testDepositTCollateral() public {
        switchSigner(owner);
        protocolFacet.depositCollateral(USDT_CONTRACT_ADDRESS, 100 * (10 ** 6));
        uint256 _amountQualaterized = protocolFacet
            .getAddressToCollateralDeposited(owner, USDT_CONTRACT_ADDRESS);
        assertEq(_amountQualaterized, (100 * 10 ** 6));
    }

    function testDepositNativeCollateral() public {
        switchSigner(owner);
        vm.deal(owner, 500 ether);
        protocolFacet.depositCollateral{value: 100 ether}(
            ETH_CONTRACT_ADDRESS,
            100 ether
        );
        uint256 _amountQualaterized = protocolFacet
            .getAddressToCollateralDeposited(owner, ETH_CONTRACT_ADDRESS);
        assertEq(_amountQualaterized, 100 ether);
    }

    function testGetUsdValue() public view {
        uint256 value = protocolFacet.getUsdValue(
            ETH_CONTRACT_ADDRESS,
            0.1 ether,
            18
        );
        assert(value > 0);
    }

    function testGetAccountAvailableValue() public {
        testDepositTCollateral();
        uint256 _avaiable = protocolFacet.getAccountAvailableValue(owner);
        uint256 value = protocolFacet.getUsdValue(
            USDT_CONTRACT_ADDRESS,
            100E6,
            6
        );

        assertEq(_avaiable, value);
    }

    function testServiceNativeRequest() public {
        switchSigner(owner);
        protocolFacet.depositCollateral(USDT_CONTRACT_ADDRESS, 1000000000);

        uint128 requestAmount = 0.01 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            ETH_CONTRACT_ADDRESS
        );

        switchSigner(B);
        vm.deal(B, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit RequestServiced(1, B, owner, 0.01 ether, uint16(11155));
        protocolFacet.serviceRequest{value: 0.01 ether}(
            1,
            ETH_CONTRACT_ADDRESS
        );
    }

    function testGetServicedRequestByLender() public {
        testServiceNativeRequest();
        Request[] memory _requests = protocolFacet.getServicedRequestByLender(
            B
        );

        assertEq(_requests.length, 1);
    }

    function testCloseRequest() public {
        switchSigner(owner);
        protocolFacet.depositCollateral(USDT_CONTRACT_ADDRESS, 1000000000);

        uint128 requestAmount = 0.01 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            ETH_CONTRACT_ADDRESS
        );

        protocolFacet.closeRequest(1);

        Request[] memory requests = protocolFacet.getUserActiveRequests(owner);

        assertEq(requests.length, 0);
    }

    function testGetConvertValue() external view {
        uint256 value = protocolFacet.getConvertValue(
            ETH_CONTRACT_ADDRESS,
            USDT_CONTRACT_ADDRESS,
            1 ether
        );
        console.log(value);
        assert(value > 2200E6);
    }

    function testWithdrawCollateral() public {
        switchSigner(owner);
        vm.deal(owner, 500 ether);
        protocolFacet.depositCollateral{value: 100 ether}(
            ETH_CONTRACT_ADDRESS,
            100 ether
        );

        uint128 requestAmount = 1 ether;
        uint16 interestRate = 1000;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            ETH_CONTRACT_ADDRESS
        );

        switchSigner(B);
        vm.deal(B, 10 ether);

        protocolFacet.serviceRequest{value: 1 ether}(1, ETH_CONTRACT_ADDRESS);

        switchSigner(owner);
        protocolFacet.withdrawCollateral(ETH_CONTRACT_ADDRESS, 90 ether);
        uint256 _amountQualaterized = protocolFacet
            .getAddressToCollateralDeposited(owner, ETH_CONTRACT_ADDRESS);
        assertEq(_amountQualaterized, 10 ether);
    }

    function testGetUserCollateralToken() external {
        switchSigner(owner);
        vm.deal(owner, 500 ether);
        protocolFacet.depositCollateral{value: 100 ether}(
            ETH_CONTRACT_ADDRESS,
            100 ether
        );

        address[] memory userTokens = protocolFacet.getUserCollateralTokens(
            owner
        );
        assertEq(userTokens.length, 1);
    }

    function testWithdrawNativeCollateral() public {
        switchSigner(owner);
        vm.deal(owner, 500 ether);
        protocolFacet.depositCollateral{value: 400 ether}(
            ETH_CONTRACT_ADDRESS,
            1
        );

        protocolFacet.withdrawCollateral(ETH_CONTRACT_ADDRESS, 250 ether);
        uint256 _amountCollaterized = protocolFacet
            .getAddressToCollateralDeposited(owner, ETH_CONTRACT_ADDRESS);
        assertEq(_amountCollaterized, 150 ether);
        assertEq(address(owner).balance, 350 ether);
    }

    function testGetHealthFactorBeforeDeposit() public view {
        uint256 value = protocolFacet.getHealthFactor(owner);
        assertEq(value, 0);
    }

    function testGetHealthFactorAfterDeposit() public {
        testDepositTCollateral();
        switchSigner(owner);
        uint256 value = protocolFacet.getHealthFactor(owner);
        assert(value != 0);
    }

    function testNativeListingAds() external {
        switchSigner(owner);

        vm.deal(owner, 500 ether);

        uint256 _amount = 100 ether;
        uint16 _interestRate = 500;
        uint256 _returnDate = 365 days;
        uint256 _min_amount = 2E10;
        uint256 _max_amount = 10E10;
        protocolFacet.createLoanListing{value: 100 ether}(
            _amount,
            _min_amount,
            _max_amount,
            _returnDate,
            _interestRate,
            ETH_CONTRACT_ADDRESS
        );

        LoanListing memory _listing = protocolFacet.getLoanListing(1);
        assertEq(_listing.author, owner);
        assertEq(_listing.tokenAddress, ETH_CONTRACT_ADDRESS);
        assertEq(_listing.amount, _amount);
        assertEq(_listing.interest, _interestRate);
        assertEq(_listing.min_amount, _min_amount);
        assertEq(_listing.max_amount, _max_amount);
        assertEq(_listing.returnDate, _returnDate);
        assertEq(uint8(_listing.listingStatus), uint8(ListingStatus.OPEN));
    }

    function testUserCanCreateTwoRequest() public {
        testDepositTCollateral();

        switchSigner(owner);

        uint128 requestAmount = 30 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            DIA_CONTRACT_ADDRESS
        );
        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            DIA_CONTRACT_ADDRESS
        );

        // Verify that the request is correctly added

        Request[] memory requests = protocolFacet.getAllRequest();
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, requestAmount);
    }

    function testExcessiveBorrowing() public {
        testDepositTCollateral();
        switchSigner(owner);

        uint128 requestAmount = 100 ether;

        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days; // 1 year later
        vm.expectRevert(
            abi.encodeWithSelector(Protocol__InsufficientCollateral.selector)
        );
        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            DIA_CONTRACT_ADDRESS
        );
    }

    function testServiceRequest() public {
        // IERC20 daiContract = IERC20(WETHHolders);
        // switchSigner(WETHHolders);
        switchSigner(owner);
        IERC20(LINK_CONTRACT_ADDRESS).transfer(B, 2 ether);
        testDepositTCollateral();

        uint128 requestAmount = 2 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days; // 1 year later

        uint256 borrowerDAIStartBalance = IERC20(LINK_CONTRACT_ADDRESS)
            .balanceOf(owner);
        switchSigner(owner);
        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            LINK_CONTRACT_ADDRESS
        );

        uint256 bal = protocolFacet.getAddressToAvailableBalance(
            owner,
            USDT_CONTRACT_ADDRESS
        );
        console.log("Available Balance", bal);

        switchSigner(B);
        IERC20(LINK_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            requestAmount
        );
        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);
        assertEq(
            IERC20(LINK_CONTRACT_ADDRESS).balanceOf(owner),
            borrowerDAIStartBalance + requestAmount
        );
        Request memory _borrowRequest = protocolFacet.getUserRequest(owner, 1);

        assertEq(_borrowRequest.lender, B);
        assertEq(uint8(_borrowRequest.status), uint8(1));
    }

    function testServiceRequestAvailable() public {
        // IERC20 daiContract = IERC20(WETHHolders);
        // switchSigner(WETHHolders);
        switchSigner(owner);
        IERC20(LINK_CONTRACT_ADDRESS).transfer(B, 2 ether);
        IERC20(LINK_CONTRACT_ADDRESS).approve(address(protocolFacet), 1 ether);

        protocolFacet.depositCollateral(LINK_CONTRACT_ADDRESS, 1 ether);
        // uint256 _amountQualaterized = protocolFacet
        //     .getAddressToCollateralDeposited(owner, LINK_CONTRACT_ADDRESS);

        uint128 requestAmount = 0.5 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days; // 1 year later

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            LINK_CONTRACT_ADDRESS
        );

        uint256 tokenBal = protocolFacet.getRequestToCollateral(
            1,
            LINK_CONTRACT_ADDRESS
        );
        switchSigner(B);

        IERC20(LINK_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            requestAmount
        );
        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);
        uint256 bal = protocolFacet.getAddressToAvailableBalance(
            owner,
            LINK_CONTRACT_ADDRESS
        );

        console.log("Token Balance", tokenBal);
        console.log("Available Balance", bal);

        assert(bal < 0.5 ether);
    }

    function testServiceRequestFailsAfterFirstService() public {
        switchSigner(owner);
        IERC20(LINK_CONTRACT_ADDRESS).transfer(B, 2 ether);
        testDepositTCollateral();

        uint128 requestAmount = 2 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days; // 1 year later

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            LINK_CONTRACT_ADDRESS
        );

        switchSigner(B);
        IERC20(LINK_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            requestAmount
        );
        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(Protocol__RequestNotOpen.selector)
        );

        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);

        // NOTE to ensure it is not just the first person to service the request it fails for
        switchSigner(C);
        vm.expectRevert(
            abi.encodeWithSelector(Protocol__RequestNotOpen.selector)
        );

        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);
    }

    function testServiceRequestFailsWithoutTokenAllowance() public {
        switchSigner(owner);
        IERC20(LINK_CONTRACT_ADDRESS).transfer(B, 2 ether);
        testDepositTCollateral();

        uint128 requestAmount = 2 ether;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days; // 1 year later

        protocolFacet.createLendingRequest(
            requestAmount,
            interestRate,
            returnDate,
            LINK_CONTRACT_ADDRESS
        );
        switchSigner(B);

        // daiContract.approve(address(protocol), requestAmount);
        vm.expectRevert(
            abi.encodeWithSelector(Protocol__InsufficientAllowance.selector)
        );

        protocolFacet.serviceRequest(1, LINK_CONTRACT_ADDRESS);
    }

    function testUserCannotRequestLoanFromListingWithoutDepositingCollateral()
        public
    {
        switchSigner(owner);

        IERC20(USDT_CONTRACT_ADDRESS).transfer(B, 1000000);

        uint256 requestAmount = 1000;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLoanListing(
            requestAmount,
            0,
            requestAmount,
            returnDate,
            interestRate,
            DIA_CONTRACT_ADDRESS
        );
        protocolFacet.createLoanListing(
            requestAmount,
            0,
            requestAmount,
            returnDate,
            interestRate,
            DIA_CONTRACT_ADDRESS
        );

        switchSigner(B);

        vm.expectRevert(
            abi.encodeWithSelector(Protocol__InsufficientCollateral.selector)
        );
        protocolFacet.requestLoanFromListing(1, requestAmount);
    }

    function testCloseListingAd() public {
        switchSigner(owner);

        uint128 requestAmount = 10000;
        uint16 interestRate = 500;
        uint256 returnDate = block.timestamp + 365 days;

        protocolFacet.createLoanListing(
            requestAmount,
            0,
            requestAmount,
            returnDate,
            interestRate,
            DIA_CONTRACT_ADDRESS
        );
        protocolFacet.createLoanListing(
            requestAmount,
            0,
            requestAmount,
            returnDate,
            interestRate,
            DIA_CONTRACT_ADDRESS
        );

        uint256 _balanceBeforeClosingListing = IERC20(DIA_CONTRACT_ADDRESS)
            .balanceOf(owner);

        protocolFacet.closeListingAd(1);

        uint256 _balanceAfterClosingListing = IERC20(DIA_CONTRACT_ADDRESS)
            .balanceOf(owner);
        LoanListing memory _listing = protocolFacet.getLoanListing(1);

        assertEq(
            _balanceAfterClosingListing,
            _balanceBeforeClosingListing + requestAmount
        );
        assertEq(_listing.amount, 0);
        assertEq(uint8(_listing.listingStatus), uint8(ListingStatus.CLOSED));
    }

    function testRepayLoan() public {
        testServiceRequest();
        switchSigner(owner);
        Request memory _request = protocolFacet.getRequest(1);

        IERC20(_request.loanRequestAddr).approve(
            address(protocolFacet),
            _request.totalRepayment
        );

        protocolFacet.repayLoan(1, _request.totalRepayment);

        Request memory _requestAfterRepay = protocolFacet.getRequest(1);
        assertEq(uint8(_requestAfterRepay.status), uint8(Status.CLOSED));
        assertEq(_requestAfterRepay.totalRepayment, 0);
    }

    function testRepayLoanAvailable() public {
        testServiceRequestAvailable();
        switchSigner(owner);

        Request memory _request = protocolFacet.getRequest(1);

        IERC20(_request.loanRequestAddr).approve(
            address(protocolFacet),
            _request.totalRepayment
        );
        uint256 totalRepayment = _request.totalRepayment;
        protocolFacet.repayLoan(1, totalRepayment);

        Request[] memory _requestAfterRepay = protocolFacet
            .getUserActiveRequests(owner);

        uint256 loanerCA = protocolFacet.getAddressToCollateralDeposited(
            _request.lender,
            _request.loanRequestAddr
        );
        uint256 loanerAB = protocolFacet.getAddressToAvailableBalance(
            _request.lender,
            _request.loanRequestAddr
        );

        Request memory _request1 = protocolFacet.getRequest(1);

        uint256 conbal = IERC20(_request.loanRequestAddr).balanceOf(
            address(protocolFacet)
        );

        assertEq(uint8(_requestAfterRepay.length), uint8(0));
        assertEq(_request1.totalRepayment, 0);
        assertEq(uint8(_request1.status), uint8(2));
        assertEq(loanerCA, totalRepayment);
        assertEq(loanerAB, totalRepayment);
        assertEq(conbal, loanerAB + 1 ether);
    }

    function testRepayLoanFailsWithoutAllowance() public {
        testServiceRequest();
        switchSigner(owner);
        Request memory _request = protocolFacet.getRequest(1);

        vm.expectRevert(
            abi.encodeWithSelector(Protocol__InsufficientAllowance.selector)
        );

        protocolFacet.repayLoan(1, _request.totalRepayment);
    }

    function testSwapEthToToken() external {
        switchSigner(owner);

        vm.deal(address(protocolFacet), 50 ether);

        uint256 linkBalanceBeforeSwap = IERC20(LINK_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );

        uint[] memory amountsOut = protocolFacet.swapToLoanCurrency(
            address(1),
            0.01 ether,
            LINK_CONTRACT_ADDRESS
        );

        uint256 linkBalanceAfterSwap = IERC20(LINK_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );

        assertGt(amountsOut[1], 0);

        assertGt(linkBalanceAfterSwap, linkBalanceBeforeSwap);

        uint256 linkReceived = linkBalanceAfterSwap - linkBalanceBeforeSwap;

        assertEq(linkReceived, amountsOut[1]);
    }

    function testSwapTokenForEth() external {
        switchSigner(owner);

        IERC20(LINK_CONTRACT_ADDRESS).transfer(
            address(protocolFacet),
            200 ether
        );

        switchSigner(B);

        vm.deal(B, 50 ether);

        uint256 ethBalanceBeforeSwap = address(protocolFacet).balance;

        uint[] memory amountsOut = protocolFacet.swapToLoanCurrency(
            LINK_CONTRACT_ADDRESS,
            0.01 ether,
            Constants.NATIVE_TOKEN
        );

        uint256 ethBalanceAfterSwap = address(protocolFacet).balance;

        //  Assert that some ETH was received from the swap
        assertGt(amountsOut[1], 0);
        // Assert that the ETH balance of protocolFacet increased
        assertGt(ethBalanceAfterSwap, ethBalanceBeforeSwap);

        //  Calculate how much ETH was received
        uint256 ethReceived = ethBalanceAfterSwap - ethBalanceBeforeSwap;

        // Assert that the received ETH matches the output amount from the swap
        assertEq(ethReceived, amountsOut[1]);
    }

    function testswapExactTokensForTokens() external {
        switchSigner(owner);

        IERC20(LINK_CONTRACT_ADDRESS).transfer(
            address(protocolFacet),
            200 ether
        );

        switchSigner(B);

        vm.deal(B, 50 ether);

        // Get the balance of LINK (collateral token) and DAI (loan currency) before the swap
        uint256 linkBalanceBeforeSwap = IERC20(LINK_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );
        uint256 daiBalanceBeforeSwap = IERC20(DIA_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );

        // Perform the swap: swap 10 LINK tokens for DAI
        uint[] memory amountsOut = protocolFacet.swapToLoanCurrency(
            LINK_CONTRACT_ADDRESS,
            10 ether,
            DIA_CONTRACT_ADDRESS
        );

        // Get the balance of LINK and DAI after the swap
        uint256 linkBalanceAfterSwap = IERC20(LINK_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );
        uint256 daiBalanceAfterSwap = IERC20(DIA_CONTRACT_ADDRESS).balanceOf(
            address(protocolFacet)
        );

        // Assert that LINK balance decreased after the swap
        assertLt(linkBalanceAfterSwap, linkBalanceBeforeSwap);

        // Assert that DAI balance increased after the swap
        assertGt(daiBalanceAfterSwap, daiBalanceBeforeSwap);

        // Optionally, check how much DAI was received
        uint256 daiReceived = daiBalanceAfterSwap - daiBalanceBeforeSwap;

        // Assert that the DAI received matches the output amount in `amountsOut`
        assertEq(daiReceived, amountsOut[1]); // Ensure DAI received matches amountsOut[1].
    }

    function testProgressiveLoanRepayment() public {
        testServiceRequest();
        switchSigner(owner);
        Request memory _request = protocolFacet.getRequest(1);
        uint256 firstHalf = _request.totalRepayment / 2;
        uint256 secondHalf = _request.totalRepayment - firstHalf;

        IERC20(_request.loanRequestAddr).approve(
            address(protocolFacet),
            _request.totalRepayment
        );

        protocolFacet.repayLoan(1, firstHalf);
        Request memory _requestAfterRepay = protocolFacet.getRequest(1);
        assertEq(
            _requestAfterRepay.totalRepayment,
            _request.totalRepayment - (_request.totalRepayment / 2)
        );

        protocolFacet.repayLoan(1, secondHalf);
        Request memory _requestAfterRepay2 = protocolFacet.getRequest(1);
        assertEq(_requestAfterRepay2.totalRepayment, 0);
    }

    function testCreateLoanListing() public {
        switchSigner(owner);
        IERC20(DIA_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint256).max
        );
        uint256 _amount = 10E10;
        uint16 _interestRate = 500;
        uint256 _returnDate = 365 days;
        uint256 _min_amount = 2E10;
        uint256 _max_amount = 10E10;
        protocolFacet.createLoanListing(
            _amount,
            _min_amount,
            _max_amount,
            _returnDate,
            _interestRate,
            DIA_CONTRACT_ADDRESS
        );

        LoanListing memory _listing = protocolFacet.getLoanListing(1);
        assertEq(_listing.author, owner);
        assertEq(_listing.tokenAddress, DIA_CONTRACT_ADDRESS);
        assertEq(_listing.amount, _amount);
        assertEq(_listing.interest, _interestRate);
        assertEq(_listing.min_amount, _min_amount);
        assertEq(_listing.max_amount, _max_amount);
        assertEq(_listing.returnDate, _returnDate);
        assertEq(uint8(_listing.listingStatus), uint8(ListingStatus.OPEN));
    }

    function testRequestLoanFromListing() public {
        createLoanListing();
        IERC20(LINK_CONTRACT_ADDRESS).transfer(B, 250 ether);
        _depositCollateral(B, LINK_CONTRACT_ADDRESS, 200 ether);

        protocolFacet.requestLoanFromListing(1, 5E10);

        Request memory _request = protocolFacet.getRequest(1);
        LoanListing memory _listing = protocolFacet.getLoanListing(1);

        assertEq(_request.amount, 5E10);
        assertEq(_request.interest, _listing.interest);
        assertEq(_request.returnDate, _listing.returnDate);
        assertEq(uint8(_request.status), uint8(Status.SERVICED));
        assertEq(_listing.amount, 5E10);
    }

    function testLiquidateUser() external {
        testRequestLoanFromListing();
        uint256 _balance = IERC20(DIA_CONTRACT_ADDRESS).balanceOf(
            address(diamond)
        );
        console.log("Balance", _balance);
        switchSigner(botAddress);
        protocolFacet.liquidateUserRequest(1);
    }

    function createLoanListing() public {
        switchSigner(owner);
        IERC20(DIA_CONTRACT_ADDRESS).approve(
            address(protocolFacet),
            type(uint256).max
        );
        protocolFacet.createLoanListing(
            10E10,
            2E10,
            10E10,
            block.timestamp + 365 days,
            500,
            DIA_CONTRACT_ADDRESS
        );
    }

    function testGetHealthFactor() public {
        uint256 _healthfactorBeforeDeposit = protocolFacet.getHealthFactor(
            owner
        );
        _depositCollateral(owner, LINK_CONTRACT_ADDRESS, 5E18);

        uint256 _healthfactorAfterDeposit = protocolFacet.getHealthFactor(
            owner
        );

        assertEq(_healthfactorBeforeDeposit, 0);
        assert(_healthfactorAfterDeposit > 1);
    }

    function testSendingEtherDirectlyToContractReverts() public {
        vm.deal(owner, 100 ether);
        switchSigner(owner);

        vm.expectRevert("ProtocolFacet: fallback");
        (bool _success, ) = payable(address(protocolFacet)).call{
            value: 100 ether
        }("");
        assertFalse(_success);
    }

    function transferTokenToOwner() public {
        switchSigner(USDTHolders);
        IERC20(USDT_CONTRACT_ADDRESS).transfer(owner, 1000 * (10 ** 6));
        switchSigner(DAIHolders);
        IERC20(DIA_CONTRACT_ADDRESS).transfer(owner, 500 ether);
        switchSigner(WETHHolders);
        IERC20(WETH_CONTRACT_ADDRESS).transfer(owner, 500 ether);
        switchSigner(LINKHolders);
        IERC20(LINK_CONTRACT_ADDRESS).transfer(owner, 500 ether);
    }

    function _depositCollateral(
        address user,
        address token,
        uint256 amount
    ) internal {
        switchSigner(user);
        IERC20(token).approve(address(protocolFacet), type(uint).max);
        protocolFacet.depositCollateral(token, amount);
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
