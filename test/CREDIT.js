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
    console.log("USDC Contract", usdcInstance?.address);
    CREDIT = await ethers.getContractFactory("CREDIT");
    creditInstance = await CREDIT.deploy(usdcInstance.address);
    await creditInstance.deployed();
    console.log("CREDIT Contract", creditInstance?.address);
    [owner, account1, account2] = await ethers.getSigners();
  });
  describe("Afer Deployment Credit", function () {
    it("only owner can mints credits", async function () {
      const balanceBefore = await usdcInstance.balanceOf(owner.address);
      console.log("Balance Before", balanceBefore);
      const amount = ethers.utils.parseEther("0.5");
      await usdcInstance.transfer(account1.address, amount);
      const balanceAfter = await usdcInstance.balanceOf(owner.address);
      console.log("Balance After", balanceAfter);
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
