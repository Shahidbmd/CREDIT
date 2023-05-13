// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "../interfaces/ICREDIT.sol";
import "../interfaces/IUniswap.sol";
import "./PlantProsperityPool.sol";
import "../Tree/Types.sol";

contract PlantNFT is Ownable, ReentrancyGuard {
  uint16 public maxMonths = 6;
  uint16 public maxNFTsPerMinter = 96;
  uint256 public gracePeriod = 30 days;
  uint256 public gammaPeriod = 72 days;
  uint256 public StakeWaitPeriod = 30 days;

  uint256 public totalNFTs = 0;
  mapping(uint256 => Types.NFT) public plantNfts;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(uint256 => uint256)) public ownedNfts;
  mapping(uint256 => uint256) public ownedNftsIndex;

  mapping(Types.StakePeriod => uint256) public StakeLockDurations;
  mapping(Types.StakePeriod => PlantProsperityPool) public stakingPools;
  mapping(Types.StakePeriod => uint256) public boosts;

  uint256 public nftSeedingFee = 0;
  uint256 public renewalFee = 0.006 ether;
  uint256 public stakeFee = 0.007 ether;
  uint256 public seedPrice = 20e18;
  string public constant name = "Plant NFT";
  string public constant symbol = "PNFT";

  uint256[20] public rates = [
    700000000000,
    595000000000,
    505750000000,
    429887500000,
    365404375000,
    310593718750,
    264004660937,
    224403961797,
    190743367527,
    162131862398,
    137812083039,
    117140270583,
    99569229995,
    84633845496,
    71938768672,
    61147953371,
    51975760365,
    44179396311,
    37552486864,
    31919613834
  ];

  ICREDIT public immutable credit;
  IUniswapV2Router02 public immutable router;
  IERC20 public immutable USDC;

  Types.NFTFeeRecipients public feeRecipients;

  uint16 public claimFee = 600;
  // Basis for above fee values
  uint16 public constant bps = 10_000;

  constructor(
    ICREDIT _credit,
    IUniswapV2Router02 _router,
    IERC20 _usdc,
    address _owner
  ) {
    transferOwnership(_owner);
    credit = _credit;
    router = IUniswapV2Router02(_router);
    USDC = _usdc;

    feeRecipients = Types.NFTFeeRecipients(
      0xc766B8c9741BC804FCc378FdE75560229CA3AB1E, // operation
      0x682Ce32507D2825A540Ad31dC4C2B18432E0e5Bd, // development
      0x454cD1e89df17cDB61D868C6D3dBC02bC2c38a17 // validators
    );

    StakeLockDurations[Types.StakePeriod.OneYear] = 365 days;
    StakeLockDurations[Types.StakePeriod.ThreeYears] = 365 days * 3;
    StakeLockDurations[Types.StakePeriod.FiveYears] = 365 days * 5;

    stakingPools[Types.StakePeriod.OneYear] = new PlantProsperityPool(
      _owner,
      365 days
    );
    stakingPools[Types.StakePeriod.ThreeYears] = new PlantProsperityPool(
      _owner,
      365 days * 3
    );
    stakingPools[Types.StakePeriod.FiveYears] = new PlantProsperityPool(
      _owner,
      365 days * 5
    );

    boosts[Types.StakePeriod.OneYear] = 2e18;
    boosts[Types.StakePeriod.ThreeYears] = 12e18;
    boosts[Types.StakePeriod.FiveYears] = 36e18;
  }

  function seedPlantNFT(
    uint256 _months
  ) external payable nonReentrant returns (uint256) {
    require(
      msg.value == getRenewalFeeForMonths(_months) + nftSeedingFee,
      "Invalid Ether value provided"
    );
    return _seedPlantNFT(_months);
  }

  function seedNFTBatch(
    uint256 _amount,
    uint256 _months
  ) external payable nonReentrant returns (uint256[] memory ids) {
    require(
      msg.value == (getRenewalFeeForMonths(_months) + nftSeedingFee) * _amount,
      "Invalid Ether value provided"
    );
    ids = new uint256[](_amount);
    for (uint256 i = 0; i < _amount; ) {
      ids[i] = _seedPlantNFT(_months);
      unchecked {
        ++i;
      }
    }
    return ids;
  }

  function _seedPlantNFT(uint256 _months) internal returns (uint256) {
    require(balanceOf[msg.sender] < maxNFTsPerMinter, "Too many NFTs");
    require(_months > 0 && _months <= maxMonths, "Must be 1-6 months");

    require(
      credit.burnForseedPlantNFT(msg.sender, seedPrice),
      "Not able to burn"
    );

    (bool success, ) = feeRecipients.validators.call{
      value: getRenewalFeeForMonths(_months) + nftSeedingFee
    }("");
    require(success, "Could not send ETH");

    uint256 id;
    uint256 length;
    unchecked {
      id = totalNFTs++;
      length = balanceOf[msg.sender]++;
    }

    plantNfts[id] = Types.NFT(
      Types.StakePeriod.None,
      msg.sender,
      block.timestamp,
      block.timestamp + 30 days * _months,
      0,
      0,
      0,
      0,
      0
    );
    ownedNfts[msg.sender][length] = id;
    ownedNftsIndex[id] = length;

    return id;
  }

  function renewPlantNFT(
    uint256 _id,
    uint256 _months
  ) external payable nonReentrant {
    require(
      msg.value == getRenewalFeeForMonths(_months),
      "Invalid Ether value provided"
    );
    _renewPlantNFT(_id, _months);
  }

  function renewPlantNFTBatch(
    uint256[] calldata _ids,
    uint256 _months
  ) external payable nonReentrant {
    uint256 length = _ids.length;
    require(
      msg.value == (getRenewalFeeForMonths(_months)) * length,
      "Invalid Ether value provided"
    );
    for (uint256 i = 0; i < length; ) {
      _renewPlantNFT(_ids[i], _months);
      unchecked {
        ++i;
      }
    }
  }

  function _renewPlantNFT(uint256 _id, uint256 _months) internal {
    Types.NFT storage nft = plantNfts[_id];

    require(nft.minter == msg.sender, "Invalid ownership");
    require(
      nft.expires + gracePeriod >= block.timestamp,
      "Grace period expired"
    );

    uint256 monthsLeft = 0;
    if (block.timestamp > nft.expires) {
      monthsLeft = (block.timestamp - nft.created) / 30 days;
    }
    require(_months + monthsLeft <= maxMonths, "Too many months");

    (bool success, ) = feeRecipients.validators.call{
      value: getRenewalFeeForMonths(_months)
    }("");
    require(success, "Could not send ETH");

    nft.expires += 30 days * _months;
  }

  function stakeNFT(
    uint256 _id,
    Types.StakePeriod _stakePeriod
  ) external payable nonReentrant {
    Types.NFT storage nft = plantNfts[_id];

    require(nft.minter == msg.sender, "Invalid ownership");
    require(nft.stakePeriod == Types.StakePeriod.None, "Already Staked");
    require(nft.expires > block.timestamp, "NFT expired");

    require(msg.value == stakeFee, "Invalid Ether value provided");

    (bool success, ) = feeRecipients.validators.call{ value: msg.value }("");
    require(success, "Could not send ETH");

    INetwork network = stakingPools[_stakePeriod];
    network.increaseShare(
      msg.sender,
      block.timestamp + StakeLockDurations[_stakePeriod]
    );

    nft.stakePeriod = _stakePeriod;
    nft.staked = block.timestamp;
    nft.unlocks = block.timestamp + StakeLockDurations[_stakePeriod];
  }

  function claimCREDIT(uint256 _id) external nonReentrant {
    _claimCREDIT(_id);
  }

  function claimCREDITBatch(uint256[] calldata _ids) external nonReentrant {
    uint256 length = _ids.length;
    for (uint256 i = 0; i < length; ) {
      _claimCREDIT(_ids[i]);
      unchecked {
        ++i;
      }
    }
  }

  function _claimCREDIT(uint256 _id) internal {
    Types.NFT storage nft = plantNfts[_id];
    require(nft.minter == msg.sender, "Invalid ownership");
    require(nft.stakePeriod == Types.StakePeriod.None, "Must be Unstaked");
    require(nft.expires > block.timestamp, "NFT expired");

    uint256 amount = getPendingCREDIT(_id);
    amount = takeClaimFee(amount);
    credit.transfer(msg.sender, amount);

    nft.numClaims++;
    nft.lastClaimed = block.timestamp;
  }

  function claimETH(uint256 _id) external nonReentrant {
    _claimETH(_id);
  }

  function claimETHBatch(uint256[] calldata _ids) external nonReentrant {
    uint256 length = _ids.length;
    for (uint256 i = 0; i < length; ) {
      _claimETH(_ids[i]);
      unchecked {
        ++i;
      }
    }
  }

  function _claimETH(uint256 _id) internal {
    Types.NFT storage nft = plantNfts[_id];
    require(nft.minter == msg.sender, "Invalid ownership");
    require(nft.stakePeriod != Types.StakePeriod.None, "Must be Staked");
    require(nft.expires > block.timestamp, "NFT expired");
    require(
      block.timestamp - nft.staked > StakeWaitPeriod,
      "Cannot claim ETH yet"
    );

    stakingPools[nft.stakePeriod].distributeDividend(msg.sender);

    if (nft.unlocks <= block.timestamp) {
      require(credit.transfer(msg.sender, boosts[nft.stakePeriod]));
      stakingPools[nft.stakePeriod].decreaseShare(nft.minter);
      nft.stakePeriod = Types.StakePeriod.None;
      nft.staked = 0;
      nft.unlocks = 0;
    }
  }

  function getPendingCREDIT(uint256 _id) public view returns (uint256) {
    Types.NFT memory nft = plantNfts[_id];

    uint256 rate = nft.numClaims >= rates.length
      ? rates[rates.length - 1]
      : rates[nft.numClaims];
    uint256 amount = (block.timestamp -
      (nft.numClaims > 0 ? nft.lastClaimed : nft.created)) * (rate);
    if (nft.created < block.timestamp + gammaPeriod) {
      uint256 _seconds = (block.timestamp + gammaPeriod) - nft.created;
      uint256 _percent = 100;
      if (_seconds >= 4838400) {
        _percent = 900;
      } else if (_seconds >= 4233600) {
        _percent = 800;
      } else if (_seconds >= 3628800) {
        _percent = 700;
      } else if (_seconds >= 3024000) {
        _percent = 600;
      } else if (_seconds >= 2419200) {
        _percent = 500;
      } else if (_seconds >= 1814400) {
        _percent = 400;
      } else if (_seconds >= 1209600) {
        _percent = 300;
      } else if (_seconds >= 604800) {
        _percent = 200;
      }
      uint256 _divisor = amount * _percent;
      (, uint256 result) = tryDiv(_divisor, 10000);
      amount -= result;
    }

    return amount;
  }

  function takeClaimFee(uint256 amount) internal returns (uint256) {
    uint256 fee = (amount * claimFee) / bps;

    address[] memory path = new address[](2);
    path[0] = address(credit);
    path[1] = address(USDC);
    credit.approve(address(router), fee);
    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      fee,
      0,
      path,
      address(this),
      block.timestamp
    );

    uint256 usdcToSend = USDC.balanceOf(address(this)) / 3;
    USDC.transfer(feeRecipients.operations, usdcToSend);
    USDC.transfer(feeRecipients.developments, usdcToSend);
    USDC.transfer(feeRecipients.validators, usdcToSend);

    return amount - fee;
  }

  function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      if (b == 0) {
        return (false, 0);
      }
      return (true, a / b);
    }
  }

  function getRenewalFeeForMonths(
    uint256 _months
  ) public view returns (uint256) {
    return renewalFee * _months;
  }

  function removeNft(uint256 _id) external onlyOwner {
    uint256 lastNFTIndex = balanceOf[plantNfts[_id].minter]; //7
    uint256 nftIndex = ownedNftsIndex[_id]; //5

    if (nftIndex != lastNFTIndex) {
      uint256 lastNFTId = ownedNfts[plantNfts[_id].minter][lastNFTIndex]; //7

      ownedNfts[plantNfts[_id].minter][nftIndex] = lastNFTId; // Move the last NFTto the slot of the to-delete token
      ownedNftsIndex[lastNFTId] = nftIndex; // Update the moved NFT's index
    }

    // This also deletes the contents at the last position of the array
    delete ownedNftsIndex[_id];
    delete ownedNfts[plantNfts[_id].minter][lastNFTIndex];

    balanceOf[plantNfts[_id].minter]--;
    totalNFTs--;

    delete plantNfts[_id];
  }

  function setRates(uint256[] calldata _rates) external onlyOwner {
    require(_rates.length == rates.length, "Invalid length");

    uint256 length = _rates.length;
    for (uint256 i = 0; i < length; ) {
      rates[i] = _rates[i];
      unchecked {
        ++i;
      }
    }
  }

  function setSeedingPrice(uint256 _seedPrice) external onlyOwner {
    seedPrice = _seedPrice;
  }

  function setMaxMonths(uint16 _maxMonths) external onlyOwner {
    maxMonths = _maxMonths;
  }

  function setFees(
    uint256 _nftSeedingFee,
    uint256 _renewalFee,
    uint256 _stakeFee,
    uint16 _claimFee
  ) external onlyOwner {
    nftSeedingFee = _nftSeedingFee;
    renewalFee = _renewalFee;
    stakeFee = _stakeFee;
    claimFee = _claimFee;
  }

  function setStakeLockDurations(
    Types.StakePeriod _stakePeriod,
    uint256 _duration
  ) external onlyOwner {
    StakeLockDurations[_stakePeriod] = _duration;
  }

  function setStakePool(
    Types.StakePeriod _stakePeriod,
    PlantProsperityPool _stakePool
  ) external onlyOwner {
    stakingPools[_stakePeriod] = _stakePool;
  }

  function setBoosts(
    Types.StakePeriod _stakePeriod,
    uint256 _boost
  ) external onlyOwner {
    boosts[_stakePeriod] = _boost;
  }

  function setFeeRecipients(
    Types.NFTFeeRecipients calldata _feeRecipients
  ) external onlyOwner {
    feeRecipients = _feeRecipients;
  }

  function setPeriods(
    uint256 _gracePeriod,
    uint256 _gammaPeriod,
    uint256 _stakeWaitPeriod
  ) external onlyOwner {
    gracePeriod = _gracePeriod;
    gammaPeriod = _gammaPeriod;
    StakeWaitPeriod = _stakeWaitPeriod;
  }

  function approveRouter() external onlyOwner {
    credit.approve(address(router), type(uint256).max);
  }

  function withdrawETH(address _recipient) external onlyOwner {
    (bool success, ) = _recipient.call{ value: address(this).balance }("");
    require(success, "Could not send ETH");
  }

  function withdrawToken(IERC20 _token, address _recipient) external onlyOwner {
    _token.transfer(_recipient, _token.balanceOf(address(this)));
  }

  receive() external payable {}
}
