// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IESM} from "./interfaces/IESM.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {INFTOracle} from "./interfaces/INFTOracle.sol";
import {IReserveOracleGetter} from "./interfaces/IReserveOracleGetter.sol";
import {IConfigurator} from "./interfaces/IConfigurator.sol";
import {ICapitalPool} from "./interfaces/ICapitalPool.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ICNFTRegistry} from "./interfaces/ICNFTRegistry.sol";
import {IIncentivesController} from "./interfaces/IIncentivesController.sol";
import {ICTokensAndCNFTsHelper} from "./interfaces/ICTokensAndCNFTsHelper.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Manage is Initializable {
    using SafeMath for uint256;

    /**
     * @notice vote struct
     * @param  id ID of the parameter to operate on
     * @param typeNum the vote num type 0 indicates the delay and 1 indicates the immediate effect
     * @param blockTime Record number of Seconds
     * @param voteNumber Number of valVotes passed
     * @param val Parameter values
     * @param status  Current status (0 initial status, failed to vote 1 Passed unconfirmed 2 Confirmed)
     */
    struct ValVote {
        uint256 id;
        uint256 typeNum;
        uint256 blockTime;
        uint256 voteNumber;
        uint256 val;
        uint256 status;
    }

    struct AddrVote {
        uint256 id;
        uint256 typeNum;
        uint256 blockTime;
        uint256 voteNumber;
        address val;
        uint256 status;
    }

    struct Voter {
        bool isVoted;
    }

    struct Manager {
        bool isManager;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => Voter)))public voters;
    /// @notice All staker-instances state
    ValVote[] public valVotes;
    /// @notice All addr vote state
    AddrVote[] public addrVotes;

    /// @notice Users with permissions
    mapping(address => Manager) public manager;
    ///@notice Total Number of Current Administrators
    uint256 public ManagerNumber;
    ///@notice Sets how many Seconds expire after
    uint256 public Seconds;
    ///@notice Current through the scaling factor
    uint256 public ByScalingFactor;
    IAddressesProvider public _addressProvider;

    event AddValVote(uint256 id, uint256 typeNum, uint256 val);
    event AddAddrVotes(uint256 id, uint256 typeNum, address val);

    event ValSignature(uint256 serialNumber);
    event AddrSignature(uint256 serialNumber);
    event ConfirmValSignature(uint256 serialNumber);
    event ConfirmAddrSignature(uint256 serialNumber);
    event DeleteValVote(uint256 serialNumber);
    event DeleteAddrVote(uint256 serialNumber);

    function initialize(address[] memory managers)
    public
    initializer
    {
        for (uint256 i = 0; i < managers.length; i++) {
            manager[managers[i]].isManager = true;
        }
        ManagerNumber = managers.length;
        Seconds = 600;
        ByScalingFactor = 60;
    }

    /**
     * @notice Add a vote
     * @param id ID of the parameter to operate on
     * @param typeNum the type of vote
     * @param val Parameter values
     */
    function addValVote(
        uint256 id,
        uint256 typeNum,
        uint256 val
    ) external onlyManager {
        uint256 blockTime = getBlockTime();
        uint256 voteNumber = 1;
        uint256 status = 0;
        valVotes.push(ValVote(id, typeNum, blockTime, voteNumber, val, status));
        voters[msg.sender][0][valVotes.length - 1].isVoted = true;
        emit AddValVote(id, typeNum, val);
    }

    /**
     * @notice Add a vote
     * @param id ID of the parameter to operate on
     * @param typeNum the type of vote
     * @param val Parameter address
     */
    function addAddrVotes(
        uint256 id,
        uint256 typeNum,
        address val
    ) external onlyManager {
        uint256 blockTime = getBlockTime();
        uint256 voteNumber = 1;
        uint256 status = 0;
        addrVotes.push(
            AddrVote(id, typeNum, blockTime, voteNumber, val, status)
        );
        voters[msg.sender][2][addrVotes.length - 1].isVoted = true;
        emit AddAddrVotes(id, typeNum, val);
    }

    /**
     * @notice Signature to vote
     * @param serialNumber Select voting ID
     */
    function valSignature(uint256 serialNumber) external onlyManager {
        uint256 blockTime = getBlockTime();
        if (valVotes[serialNumber].typeNum != 0) {
            require(
                blockTime.sub(valVotes[serialNumber].blockTime) <= Seconds,
                "The current vote has expired"
            );
        }
        require(
            valVotes[serialNumber].status == 0,
            "The current status does not allow voting"
        );
        require(
            voters[msg.sender][0][serialNumber].isVoted == false,
            "The current administrator has voted"
        );
        valVotes[serialNumber].voteNumber = valVotes[serialNumber]
        .voteNumber
        .add(1);
        voters[msg.sender][0][serialNumber].isVoted = true;
        if (
            valVotes[serialNumber].voteNumber.mul(100).div(ManagerNumber) >=
            ByScalingFactor
        ) {
            valVotes[serialNumber].status = 1;
            valVotes[serialNumber].blockTime = blockTime;
        }
        emit ValSignature(serialNumber);
    }

    /**
     * @notice Signature to vote
     * @param serialNumber Select voting ID
     */
    function addrSignature(uint256 serialNumber) external onlyManager {
        uint256 blockTime = getBlockTime();
        if (addrVotes[serialNumber].typeNum != 0) {
            require(
                blockTime.sub(addrVotes[serialNumber].blockTime) <= Seconds,
                "The current vote has expired"
            );
        }
        require(
            addrVotes[serialNumber].status == 0,
            "The current status does not allow voting"
        );
        require(
            voters[msg.sender][2][serialNumber].isVoted == false,
            "The current administrator has voted"
        );
        addrVotes[serialNumber].voteNumber = addrVotes[serialNumber]
        .voteNumber
        .add(1);
        voters[msg.sender][2][serialNumber].isVoted = true;
        if (
            addrVotes[serialNumber].voteNumber.mul(100).div(ManagerNumber) >=
            ByScalingFactor
        ) {
            addrVotes[serialNumber].status = 1;
            addrVotes[serialNumber].blockTime = blockTime;
        }
        emit AddrSignature(serialNumber);
    }

    /**
     * @notice Confirmation vote
     * @param serialNumber Select voting ID
     */
    function confirmValSignature(uint256 serialNumber) external onlyManager {
        uint256 blockTime = getBlockTime();
        require(
            valVotes[serialNumber].status == 1,
            "The vote has not passed yet"
        );
        if (valVotes[serialNumber].typeNum == 1) {
            require(
                blockTime.sub(valVotes[serialNumber].blockTime) >= Seconds,
                "The voting time has not yet expired"
            );
        }
        uint256 id = valVotes[serialNumber].id;
        uint256 val = valVotes[serialNumber].val;
        IESM esm = IESM(_addressProvider.getESM());
        IConfigurator configurator = IConfigurator(_addressProvider.getConfigurator());
        IIncentivesController incentivesController = IIncentivesController(_addressProvider.getIncentivesController());
        if (id == 0) {
            esm.open(val);
        } else if (id == 1) {
            esm.pause(val);
        } else if (id == 2) {
            ///Pass ratio coefficient
            require(
                val >= 50 && val <= 100,
                "The pass rate should be between 50% and 100%"
            );
            ByScalingFactor = val;
        } else if (id == 3) {
            ///pass number of Seconds
            require(val > 0, "The current value cannot be set to 0");
            require(
                val >= 300 && val <= 604800,
                "The current value cannot be set to 0"
            );
            Seconds = val;
        } else if (id == 4) {
            ///minBidDelta
            configurator.setMinBidDeltaEvent(val);
        } else if (id == 5) {
            ///set Min Lend
            configurator.setMinLendEvent(val);
        } else if (id == 6) {
            ///Set hard top
            configurator.setBufferTimeEvent(val);
        } else if (id == 7) {
            ///Set the minimum pledge amount
            configurator.setCountdownTimeEvent(val);
        } else if (id == 8) {
            ///set BidReward Rate Event
            configurator.setBidRewardRateEvent(val);
        } else if (id == 9) {
            ///withdrawReward
            incentivesController.withdrawReward(val);
        }

        valVotes[serialNumber].status = 2;
        valVotes[serialNumber].blockTime = blockTime;

        emit ConfirmValSignature(serialNumber);
    }

    /**
     * @notice Confirmation vote
     * @param serialNumber Select voting ID
     */
    function confirmAddrSignature(uint256 serialNumber) external onlyManager {
        uint256 blockTime = getBlockTime();
        require(
            addrVotes[serialNumber].status == 1,
            "The vote has not passed yet"
        );
        if (addrVotes[serialNumber].typeNum == 1) {
            require(
                blockTime.sub(addrVotes[serialNumber].blockTime) >= Seconds,
                "The voting time has not yet expired"
            );
        }
        uint256 id = addrVotes[serialNumber].id;
        address val = addrVotes[serialNumber].val;
        if (id == 0) {
            require(
                !isManager(val),
                "Manager: the account is already registered on the Manager"
            );
            manager[val].isManager = true;
            ManagerNumber = ManagerNumber.add(1);
        } else if (id == 1) {
            require(isManager(val), "Manager: account is not a manager");
            manager[val].isManager = false;
            ManagerNumber = ManagerNumber.sub(1);
        } else if (id == 2) {
            _addressProvider = IAddressesProvider(val);
        } else if (id == 3) {
            INFTOracle nftOracle = INFTOracle(_addressProvider.getNFTOracle());
            nftOracle.setPriceFeedAdmin(val);
        } else if (id == 4) {
            IReserveOracleGetter reserveOracle = IReserveOracleGetter(_addressProvider.getReserveOracle());
            reserveOracle.setAdmin(val);
        } else if (id == 5) {
            IConfigurator configurator = IConfigurator(_addressProvider.getConfigurator());
            configurator.updateVaultAddress(val);
        } else if (id == 6) {
            ICapitalPool capitalPool = ICapitalPool(_addressProvider.getCapitalPool());
            capitalPool.setAdmin(val);
        } else if (id == 7) {
            IVault vault = IVault(_addressProvider.getVault());
            vault.approve(val, 1e26);
        } else if (id == 8) {
            ICNFTRegistry cNFTRegistry = ICNFTRegistry(_addressProvider.getCNFTRegistry());
            cNFTRegistry.setAdmin(val);
        } else if (id == 9) {
            IIncentivesController incentivesController = IIncentivesController(_addressProvider.getIncentivesController());
            incentivesController.setAdmin(val);
        } else if (id == 10) {
            ICTokensAndCNFTsHelper cTokensAndCNFTsHelper = ICTokensAndCNFTsHelper(_addressProvider.getCTokensAndCNFTsHelper());
            cTokensAndCNFTsHelper.setAdmin(val);
        } else if (id == 11) {
            _addressProvider.setPoolAdmin(val);
        } else if (id == 12) {
            _addressProvider.setManage(val);
        } else if (id == 13) {
            IIncentivesController incentivesController = IIncentivesController(_addressProvider.getIncentivesController());
            incentivesController.updateRewardVault(val);
        }
        addrVotes[serialNumber].status = 2;
        addrVotes[serialNumber].blockTime = blockTime;
        emit ConfirmAddrSignature(serialNumber);
    }

    /**
     * @notice Viewing voting Status
     * @param serialNumber Select voting ID
     */
    function getValVoteStatus(uint256 serialNumber)
    public
    view
    returns (uint256)
    {
        return valVotes[serialNumber].status;
    }

    /**
     * @notice Viewing voting Status
     * @param serialNumber Select voting ID
     */
    function getAddrVoteStatus(uint256 serialNumber)
    public
    view
    returns (uint256)
    {
        return addrVotes[serialNumber].status;
    }

    /**
     * @notice Delete a vote. Only the contract owner can delete a vote
     * @param serialNumber Select voting ID
     */
    function deleteValVote(uint256 serialNumber) external onlyManager {
        require(
            valVotes[serialNumber].status < 2,
            "The vote has passed and cannot be deleted"
        );
        valVotes[serialNumber].status = 3;
        emit DeleteValVote(serialNumber);
    }

    /**
     * @notice Delete a vote. Only the contract owner can delete a vote
     * @param serialNumber Select voting ID
     */
    function deleteAddrVotes(uint256 serialNumber) external onlyManager {
        require(
            addrVotes[serialNumber].status < 2,
            "The vote has passed and cannot be deleted"
        );
        addrVotes[serialNumber].status = 3;
        emit DeleteAddrVote(serialNumber);
    }

    function getValVotes() public view returns (ValVote[] memory) {
        return valVotes;
    }

    function getAddrVotes() public view returns (AddrVote[] memory) {
        return addrVotes;
    }

    /**
     *  Get block number now
     */
    function getBlockTime() public view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Check whether acccount in whitelist
     * @param account Any address
     */
    function isManager(address account) public view returns (bool) {
        return manager[account].isManager == true;
    }

    /**
     * @notice Check whether msg.sender in whitelist overrides.
     */
    function isManager() public view returns (bool) {
        return isManager(msg.sender);
    }

    modifier onlyManager() {
        require(isManager(), "Manager: msg.sender not is manager");
        _;
    }
}
