// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Types {
    struct FeeRecipients {
        address operationTeam;
        address developmentTeam;
        address marketingTeam;
        
    }

    struct Fees {
        uint16 operations;
        uint16 development;
        uint16 marketing;
    }

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
        uint256 started;
        uint256 unlocks;
    }

    enum StakePeriod {
        None,
        OneYear,
        ThreeYears,
        FiveYears
    }

    struct NFT {
        StakePeriod stakePeriod;
        address minter;
        uint256 created;
        uint256 expires;
        uint256 numClaims;
        uint256 lastClaimed;
        uint256 staked;
        uint256 unlocks;
        uint256 lastStakeClaimed;
    }

    struct NFTFeeRecipients {
        address operations;
        address developments;
        address validators;
    }
}
