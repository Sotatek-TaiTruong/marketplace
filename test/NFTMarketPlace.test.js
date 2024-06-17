const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFTMarketplace", function () {
  let Marketplace, marketplace;
  let erc721Mock;
  let erc1155Mock;
  let ERC20Mock, erc20Mock;
  let owner, seller, buyer, bidder1, bidder2, treasury;

  beforeEach(async function () {
    [owner, seller, buyer, bidder1, bidder2, treasury] =
      await ethers.getSigners();

    // Deploy MyNFT721 contract
    const ERC721Mock = await ethers.getContractFactory("MyNFT721");
    const erc721Mock = await ERC721Mock.deploy();

    // Deploy MyNFT1155 contract
    const ERC1155Mock = await ethers.getContractFactory("MyNFT1155");
    const erc1155Mock = await ERC1155Mock.deploy();

    ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    erc20Mock = await ERC20Mock.deploy(
      "Mock20",
      "M20",
      18,
      ethers.utils.parseEther("1000")
    );
    await erc20Mock.deployed();

    Marketplace = await ethers.getContractFactory("NFTMarketplace");
    marketplace = await Marketplace.deploy(
      treasury.address,
      25,
      25,
      ethers.utils.parseUnits("0.01", "ether")
    );
    await marketplace.deployed();

    // Mint and approve NFTs and tokens
    await erc721Mock.mint(seller.address, 1);
    await erc1155Mock.mint(seller.address, 1, 10, "0x");

    await erc721Mock
      .connect(seller)
      .setApprovalForAll(marketplace.address, true);
    await erc1155Mock
      .connect(seller)
      .setApprovalForAll(marketplace.address, true);
    await erc20Mock.transfer(buyer.address, ethers.utils.parseEther("100"));
    await erc20Mock
      .connect(buyer)
      .approve(marketplace.address, ethers.utils.parseEther("100"));
  });

  it("Should list and buy an ERC721 NFT with ETH", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc721Mock.address,
        1,
        1,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("1"),
        0,
        0
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc721Mock.address,
      1,
      0
    );

    await marketplace
      .connect(buyer)
      .buyNFT(listingId, { value: ethers.utils.parseEther("1.0025") });

    expect(await erc721Mock.ownerOf(1)).to.equal(buyer.address);
  });

  it("Should list and buy an ERC1155 NFT with ERC20", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc1155Mock.address,
        1,
        5,
        erc20Mock.address,
        ethers.utils.parseEther("5"),
        0,
        0
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc1155Mock.address,
      1,
      0
    );

    await marketplace.connect(buyer).buyNFT(listingId);

    expect(await erc1155Mock.balanceOf(buyer.address, 1)).to.equal(5);
  });

  it("Should handle auction correctly", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc721Mock.address,
        1,
        1,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("1"),
        1,
        86400
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc721Mock.address,
      1,
      1
    );

    await marketplace
      .connect(bidder1)
      .placeBid(listingId, { value: ethers.utils.parseEther("1.01") });
    await marketplace
      .connect(bidder2)
      .placeBid(listingId, { value: ethers.utils.parseEther("1.02") });

    await ethers.provider.send("evm_increaseTime", [86400]);
    await marketplace.finalizeAuction(listingId);

    expect(await erc721Mock.ownerOf(1)).to.equal(bidder2.address);
  });

  it("Should cancel listing correctly", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc721Mock.address,
        1,
        1,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("1"),
        0,
        0
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc721Mock.address,
      1,
      0
    );

    await marketplace.connect(seller).cancelListing(listingId);

    const listing = await marketplace.listings(listingId);
    expect(listing.sold).to.equal(true);
  });

  it("Should blacklist and prevent blacklisted user from listing", async function () {
    await marketplace.blacklistUser(seller.address, true);

    await expect(
      marketplace
        .connect(seller)
        .listNFT(
          erc721Mock.address,
          1,
          1,
          ethers.constants.AddressZero,
          ethers.utils.parseEther("1"),
          0,
          0
        )
    ).to.be.revertedWith("You are blacklisted");
  });

  it("Should blacklist and prevent blacklisted user from buying", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc721Mock.address,
        1,
        1,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("1"),
        0,
        0
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc721Mock.address,
      1,
      0
    );

    await marketplace.blacklistUser(buyer.address, true);

    await expect(
      marketplace
        .connect(buyer)
        .buyNFT(listingId, { value: ethers.utils.parseEther("1.0025") })
    ).to.be.revertedWith("You are blacklisted");
  });

  it("Should blacklist and prevent blacklisted user from bidding", async function () {
    await marketplace
      .connect(seller)
      .listNFT(
        erc721Mock.address,
        1,
        1,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("1"),
        1,
        86400
      );
    const listingId = await marketplace.getListingId(
      seller.address,
      erc721Mock.address,
      1,
      1
    );

    await marketplace.blacklistUser(bidder1.address, true);

    await expect(
      marketplace
        .connect(bidder1)
        .placeBid(listingId, { value: ethers.utils.parseEther("1.01") })
    ).to.be.revertedWith("You are blacklisted");
  });
});
