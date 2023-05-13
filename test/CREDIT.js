const { expect, asssert } = require("chai");
const { ethers } = require("hardhat");
const chai = require("chai");

describe("CREDIT", function () {
  let USDC;
  let usdcInstance;
  let CREDIT;
  let creditInstance;
  let owner;
  let account1;
  let account2;
  beforeEach(async function () {
    USDC = await ethers.getContractFactory("USDC");
    usdcInstance = await USDC.deploy();
    await usdcInstance.deployed();
    CREDIT = await ethers.getContractFactory("CREDIT");
    creditInstance = await CREDIT.deploy(usdcInstance.address);
    creditInstance.wait();
    await creditInstance.deployed();

    [owner, account1, account2] = await ethers.getSigners();
  });
  describe("Afer Deployment Credit", function () {
    it("only owner can mints credits", async function () {
      await creditInstance.mintCredits(400);
      expect(creditInstance.balanceOf(owner.address)).to.equal(1000);
    });
    it("only account1 cannot  mints credits", async function () {
      await creditInstance
        .connect(account1.address)
        .mintCredits(400)
        .should.be.revertedWith("Ownable: caller is not the owner");
      expect(creditInstance.balanceOf(owner.address)).to.equal(400);
    });
  });
});
