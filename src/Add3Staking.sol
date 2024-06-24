// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { OwnableUpgradeable } from "@upgradeable/openzeppelin/access/OwnableUpgradeable.sol";
import { Initializable } from "@upgradeable/openzeppelin/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@upgradeable/openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @author Juan Xavier Valverde M.
 * @title
 * @notice An upgradeable Staking contract that once initialized can be set to be Dynamic or Static,
 * performing or not Autocompound.
 * Dynamic: Users are able to stake dynamically and everytime they stake, the available rewards up to that moment (if any)
 * are autocompounded
 * Static: Users are not able to stake dynamically and ionce they stake, they would need to unstake their tokens
 * in order to restake and get new rewards
 */
contract Add3Staking is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    /* ----------------------- ERRORS ----------------------- */
    error ZeroAmount();
    error NotInitialized();
    error AlreadyStaked();
    error StakingHasEnded();
    error InsufficientBalance();
    error SomethingWentWrong();
    error ContractAlreadyInitialized();
    error InsufficientStakingBalance();
    error UnwantedTransfer();
    error MinimumLockTimeUnfinished();
    error InsufficientBalanceToCoverRewards();
    error MaximumCapExceeded();

    /* ----------------------- EVENTS ----------------------- */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /* -------------------- CUSTOM TYPES -------------------- */
    enum StakingType {
        Static,
        Dynamic
    }

    /* --------------------- STATE VARS --------------------- */
    IERC20 internal stakingToken;
    StakingType public stakingType;

    uint256 public rewardRate;
    uint256 public stakingDuration;
    uint256 public minimumLockTime;
    uint256 public maxTotalSupply;
    uint256 public totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public lastStakedTime;
    mapping(address => uint256) public initialStakedTime;
    mapping(address => uint256) public lastClaimedRewards;

    /* ---------------------- FUNCTIONS --------------------- */
    /// @dev This function should be called immediately after deploying the contract
    function initialize(
        address _stakingToken,
        StakingType _stakingType,
        uint256 _rewardRate,
        uint256 _stakingDuration,
        uint256 _minimumLockTime,
        uint256 _maxTotalSupply
    ) public initializer {
        if (_getInitializedVersion() > 1) revert ContractAlreadyInitialized();
        __Ownable_init();
        __UUPSUpgradeable_init();
        stakingType = _stakingType;
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;
        stakingDuration = _stakingDuration;
        minimumLockTime = _minimumLockTime;
        maxTotalSupply = _maxTotalSupply;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Warning: Possible attack vector due to centralization via access control on this function
    function changeStakingType(StakingType _stakingType) external onlyOwner {
        if (_getInitializedVersion() == 0) revert NotInitialized();
        stakingType = _stakingType;
    }

    function _compoundRewards(address user) internal {
        uint256 rewards = _calculateRewards(user, balances[user]);
        balances[user] += rewards;
        totalSupply += rewards;
        lastStakedTime[user] = block.timestamp;
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount + totalSupply > maxTotalSupply) revert MaximumCapExceeded();
        bool transfer = stakingToken.transferFrom(msg.sender, address(this), amount);
        if (!transfer) revert SomethingWentWrong();

        if (stakingType == StakingType.Dynamic) {
            _compoundRewards(msg.sender);
            _stake(amount);
        } else if (stakingType == StakingType.Static) {
            if (balances[msg.sender] > 0) revert AlreadyStaked();
            else _stake(amount);
        }
    }

    /// @dev If user unstakes less than the total staked when Dynamic is on, the rewards of the withdrawm amount
    /// are compounded and not transferred back to the user. On the other hand, if Static is set, the rewards are
    /// transferred alongside the requested amount
    function unstake(uint256 amount) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > balances[msg.sender]) revert InsufficientStakingBalance();
        _ensureLockTime();
        uint256 rewards = _calculateRewards(msg.sender, amount);
        if ((amount + rewards) > stakingToken.balanceOf(address(this))) revert InsufficientBalanceToCoverRewards();

        bool transfer;

        if (stakingType == StakingType.Dynamic) {
            balances[msg.sender] += rewards;
            totalSupply += rewards;
            transfer = stakingToken.transfer(msg.sender, amount);
        } else transfer = stakingToken.transfer(msg.sender, (amount + rewards));

        if (!transfer) revert SomethingWentWrong();

        /// @dev this balance update is not following the CEI pattern because
        // balances get updated when Dynamic is on before transferring
        // `nonReentrant` takes care of possible re-rentrancy attacks
        balances[msg.sender] -= amount;
        totalSupply -= amount;

        emit Withdrawn(msg.sender, amount);
    }

    function _ensureLockTime() internal view {
        if (initialStakedTime[msg.sender] + minimumLockTime > block.timestamp) revert MinimumLockTimeUnfinished();
    }

    function withdrawAll() external nonReentrant {
        uint256 rewards = _calculateRewards(msg.sender, balances[msg.sender]);
        uint256 total = balances[msg.sender] + rewards;
        totalSupply -= balances[msg.sender];
        balances[msg.sender] = 0;

        if (total > 0) {
            _ensureLockTime();
            bool transfer = stakingToken.transfer(msg.sender, total);
            if (!transfer) revert SomethingWentWrong();
            emit Withdrawn(msg.sender, total);
        }
    }

    function claimRewards() external nonReentrant {
        uint256 rewards = (_calculateRewards(msg.sender, balances[msg.sender]));

        if (rewards > 0) {
            _ensureLockTime();
            lastClaimedRewards[msg.sender] = block.timestamp;
            bool transfer = stakingToken.transfer(msg.sender, rewards);
            if (!transfer) revert SomethingWentWrong();
        }
    }

    function availableRewards(address user) external view returns (uint256) {
        return _calculateRewards(user, balances[user]);
    }

    /* ****************************************************** */
    /*                        INTERNAL                        */
    /* ****************************************************** */

    function _calculateRewards(address user, uint256 amount) internal view returns (uint256) {
        uint256 timeSinceLastStaking = block.timestamp - lastStakedTime[user];
        if (lastStakedTime[user] == 0 || timeSinceLastStaking == 0) return 0;
        uint256 _lastClaimedRewards = lastClaimedRewards[user]; // memory read only

        uint256 timeSinceLastClaim = _lastClaimedRewards == 0
            ? timeSinceLastStaking
            : block.timestamp - _lastClaimedRewards;

        uint256 lastUpdate = _min(timeSinceLastClaim, timeSinceLastStaking);
        // This is to avoid overcompensating for when users withdraw after Max Staking duration has ended
        if (lastUpdate > stakingDuration) lastUpdate = stakingDuration;
        uint256 reward = (amount * rewardRate * lastUpdate) / (stakingDuration * 100);
        return reward;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _stake(uint256 amount) internal {
        if (
            block.timestamp > lastStakedTime[msg.sender] + stakingDuration ||
            initialStakedTime[msg.sender] + stakingDuration < block.timestamp
        ) revert StakingHasEnded();
        if (balances[msg.sender] == 0) initialStakedTime[msg.sender] = block.timestamp;

        balances[msg.sender] += amount;
        lastStakedTime[msg.sender] = block.timestamp;
        totalSupply += amount;
        emit Staked(msg.sender, amount);
    }

    receive() external payable {
        revert UnwantedTransfer();
    }

    fallback() external payable {
        revert UnwantedTransfer();
    }

    function rescueTokens(address _token) external onlyOwner {
        if (_token != address(stakingToken)) {
            uint256 balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).transfer(msg.sender, balance);
        }
    }
}
