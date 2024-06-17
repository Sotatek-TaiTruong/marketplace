// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Types {
    enum SaleType {
        FixedPrice,
        Auction
    }

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        address paymentToken;
        uint256 price;
        SaleType saleType;
        uint256 auctionEndTime;
        bool sold;
    }

    struct Bid {
        address bidder;
        uint256 amount;
    }
}
