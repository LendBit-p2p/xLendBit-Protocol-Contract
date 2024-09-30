// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

struct User {
    address userAddr;
    uint gitCoinPoint;
    uint totalLoanCollected;
}

struct Request {
    uint96 requestId;
    address author;
    uint128 amount;
    uint16 interest;
    uint256 totalRepayment;
    uint256 returnDate;
    address lender;
    address loanRequestAddr;
    Status status;
}

struct Order {
    uint256 orderId;
    address loanAddress;
    address author;
    uint128 amount;
    uint16 interest;
    uint256 totalRepayment;
    uint256 returnDate;
    OrderStatus orderStatus;
}

enum Status {
    OPEN,
    SERVICED,
    CLOSED
}

enum OrderStatus {
    OPEN,
    ACCEPTED,
    CLOSED
}
