// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Events {
    event Listed(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        address paymentToken,
        uint256 price,
        uint8 saleType,
        uint256 auctionEndTime
    );

    event Sale(bytes32 indexed listingId, address indexed buyer, uint256 price);

    event BidPlaced(
        bytes32 indexed listingId,
        address indexed bidder,
        uint256 amount
    );

    event Withdrawn(
        bytes32 indexed listingId,
        address indexed bidder,
        uint256 amount
    );

    event AuctionEnded(
        bytes32 indexed listingId,
        address indexed winner,
        uint256 amount
    );

    event ListingCancelled(bytes32 indexed listingId);
}
