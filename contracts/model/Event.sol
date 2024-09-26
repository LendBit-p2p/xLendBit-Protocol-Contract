// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;



event RequestCreated(
    address indexed _borrower,
    uint96 indexed requestId,
    uint _amount,
    uint8 _interest
);
event OrderCreated(
    address indexed _lender,
    address indexed_tokenAddress,
    uint256 _amount,
    uint96 indexed _requestId
);
event RespondToLendingOffer(
    address indexed sender,
    uint indexed _offerId,
    uint8 _status,
    uint8 _offerStatus
);
event ServiceRequestSuccessful(
    address indexed sender,
    address indexed _borrower,
    uint8 _requestId,
    uint256 amount
);
event CollateralWithdrawn(
    address indexed sender,
    address indexed _tokenCollateralAddress,
    uint256 _amount
);
event UpdatedCollateralTokens(address indexed sender, uint8 newTokensCount);
event AcceptedListedAds(address indexed sender, uint96 indexed id, uint256 indexed amount, uint8 adStatus);
event LoanRepayment(address indexed sender, uint96 id, uint256 amount);
event UpdateLoanableToken(
    address indexed _token,
    address _priceFeed,
    address indexed sender
);
   event CollateralDeposited(
        address indexed _sender,
        address indexed _token,
        uint256 _value
    );

  event  withdrawnAdsToken(
    address indexed sender,
    uint96 indexed _orderId, 
    uint8 indexed orderStatus,
     uint128 _amount);
