// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Helpers} from "contracts/libraries/Helpers.sol";
import {Events} from "contracts/libraries/Events.sol";
import {Types} from "contracts/libraries/Types.sol";

contract NFTMarketplace is
   Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver
{
    using Address for address payable;
    using Types for Types.Listing;
    using Types for Types.Bid;

    mapping(bytes32 => Types.Listing) public listings;
    mapping(bytes32 => Types.Bid) public highestBids;
    mapping(bytes32 => mapping(address => uint256)) public pendingReturns;

    address public treasury;
    uint256 public buyerFee;
    uint256 public sellerFee;
    uint256 public auctionStep;

    mapping(address => bool) public blacklist;

    function initialize(
        address _treasury,
        uint256 _buyerFee,
        uint256 _sellerFee,
        uint256 _auctionStep
    ) public initializer {
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();

        treasury = _treasury;
        buyerFee = _buyerFee;
        sellerFee = _sellerFee;
        auctionStep = _auctionStep;
    }

    modifier notBlacklisted() {
        require(!blacklist[msg.sender], "You are blacklisted");
        _;
    }

    function listNFT(
        address _nftContract,
        uint256 _tokenId,
        uint256 _amount,
        address _paymentToken,
        uint256 _price,
        Types.SaleType _saleType,
        uint256 _auctionDuration
    ) external notBlacklisted {
        require(
            _saleType == Types.SaleType.FixedPrice || _auctionDuration > 0,
            "Invalid sale type or auction duration"
        );

        bytes32 listingId = keccak256(
            abi.encodePacked(
                msg.sender,
                _nftContract,
                _tokenId,
                block.timestamp
            )
        );
        listings[listingId] = Types.Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            amount: _amount,
            paymentToken: _paymentToken,
            price: _price,
            saleType: _saleType,
            auctionEndTime: block.timestamp + _auctionDuration,
            sold: false
        });

        emit Events.Listed(
            listingId,
            msg.sender,
            _nftContract,
            _tokenId,
            _amount,
            _paymentToken,
            _price,
            uint8(_saleType),
            block.timestamp + _auctionDuration
        );
    }

    function buyNFT(
        bytes32 _listingId
    ) external payable notBlacklisted nonReentrant {
        Types.Listing storage listing = listings[_listingId];
        require(!listing.sold, "NFT already sold");
        require(
            listing.saleType == Types.SaleType.FixedPrice,
            "Not a fixed price sale"
        );
        uint256 totalPrice = listing.price +
            ((listing.price * buyerFee) / 10000);

        if (listing.paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient funds");
        } else {
            IERC20(listing.paymentToken).transferFrom(
                msg.sender,
                address(this),
                totalPrice
            );
        }

        _transferNFT(
            listing.nftContract,
            listing.seller,
            msg.sender,
            listing.tokenId,
            listing.amount
        );

        uint256 sellerProceeds = listing.price -
            ((listing.price * sellerFee) / 10000);
        _sendFunds(listing.seller, sellerProceeds, listing.paymentToken);

        uint256 treasuryFee = totalPrice - sellerProceeds;
        _sendFunds(treasury, treasuryFee, listing.paymentToken);

        listing.sold = true;
        emit Events.Sale(_listingId, msg.sender, listing.price);
    }

    function placeBid(
        bytes32 _listingId
    ) external payable notBlacklisted nonReentrant {
        Types.Listing storage listing = listings[_listingId];
        require(
            listing.saleType == Types.SaleType.Auction,
            "Not an auction sale"
        );
        require(block.timestamp < listing.auctionEndTime, "Auction ended");

        uint256 bidAmount = msg.value;
        Types.Bid storage highestBid = highestBids[_listingId];
        require(
            bidAmount >= highestBid.amount + auctionStep,
            "Bid amount too low"
        );

        if (highestBid.amount > 0) {
            pendingReturns[_listingId][highestBid.bidder] += highestBid.amount;
        }

        highestBids[_listingId] = Types.Bid({
            bidder: msg.sender,
            amount: bidAmount
        });

        emit Events.BidPlaced(_listingId, msg.sender, bidAmount);
    }

    function withdrawBid(bytes32 _listingId) external nonReentrant {
        uint256 amount = pendingReturns[_listingId][msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingReturns[_listingId][msg.sender] = 0;
        payable(msg.sender).sendValue(amount);

        emit Events.Withdrawn(_listingId, msg.sender, amount);
    }

    function finalizeAuction(bytes32 _listingId) external nonReentrant {
        Types.Listing storage listing = listings[_listingId];
        require(
            block.timestamp >= listing.auctionEndTime,
            "Auction not ended yet"
        );
        require(!listing.sold, "NFT already sold");

        Types.Bid storage highestBid = highestBids[_listingId];
        require(
            highestBid.amount >= listing.price,
            "Highest bid below reserve price"
        );

        _transferNFT(
            listing.nftContract,
            listing.seller,
            highestBid.bidder,
            listing.tokenId,
            listing.amount
        );

        uint256 sellerProceeds = highestBid.amount -
            ((highestBid.amount * sellerFee) / 10000);
        _sendFunds(listing.seller, sellerProceeds, address(0));

        uint256 treasuryFee = (highestBid.amount * sellerFee) / 10000;
        _sendFunds(treasury, treasuryFee, address(0));

        listing.sold = true;
        emit Events.AuctionEnded(
            _listingId,
            highestBid.bidder,
            highestBid.amount
        );
    }

    function cancelListing(bytes32 _listingId) external nonReentrant {
        Types.Listing storage listing = listings[_listingId];
        require(msg.sender == listing.seller, "Only seller can cancel listing");
        require(!listing.sold, "Cannot cancel sold listing");

        if (listing.saleType == Types.SaleType.Auction) {
            require(
                block.timestamp < listing.auctionEndTime,
                "Cannot cancel ended auction"
            );
            require(
                highestBids[_listingId].amount == 0,
                "Cannot cancel auction with bids"
            );
        }

        listing.sold = true;
        emit Events.ListingCancelled(_listingId);
    }

    function blacklistUser(address _user, bool _blacklist) external onlyOwner {
        blacklist[_user] = _blacklist;
    }

    function _transferNFT(
        address _nftContract,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) internal {
        if (
            IERC165(_nftContract).supportsInterface(type(IERC721).interfaceId)
        ) {
            IERC721(_nftContract).safeTransferFrom(_from, _to, _tokenId);
        } else if (
            IERC165(_nftContract).supportsInterface(type(IERC1155).interfaceId)
        ) {
            IERC1155(_nftContract).safeTransferFrom(
                _from,
                _to,
                _tokenId,
                _amount,
                ""
            );
        } else {
            revert("Unsupported NFT standard");
        }
    }

    function _sendFunds(
        address _recipient,
        uint256 _amount,
        address _paymentToken
    ) internal {
        if (_paymentToken == address(0)) {
            payable(_recipient).sendValue(_amount);
        } else {
            IERC20(_paymentToken).transfer(_recipient, _amount);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
