require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      blockGasLimit: 9000000000,
      allowUnlimitedContractSize: true,
    },
  },
  solidity: {
    version: "0.8.13", // Note that this only has the version number
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
};
