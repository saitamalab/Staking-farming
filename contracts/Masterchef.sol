// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/ISaitama.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MasterChef is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeBEP20 for IBEP20;

  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    uint256 rewardLockedUp; // Reward locked up.
    uint256 nextHarvestUntil; // When can the user harvest again.
    //
    // We do some fancy math here. Basically, any point in time, the amount of Saitamas
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accSaitamaPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    //   1. The pool's `accSaitamaPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
  }

  // Info of each pool.
  struct PoolInfo {
    IBEP20 lpToken; // Address of LP token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. Saitamas to distribute per block.
    uint256 lastRewardBlock; // Last block number that Saitamas distribution occurs.
    uint256 accSaitamaPerShare; // Accumulated Saitamas per share, times 1e12. See below.
    uint16 depositFeeBP; // Deposit fee in basis points
    uint256 harvestInterval; // Harvest interval in seconds
  }

  // The Saitama TOKEN!
  ISaitama public immutable Saitama;
  // Reward Wallet address
  address public RewardWalletAddress;
  // Dev address.
  address public devAddress;
  // Deposit Fee address
  address public feeAddress;
  // Saitama tokens created per block.
  uint256 public SaitamaPerBlock;
  // Bonus muliplier for early Saitama makers.
  uint256 public constant BONUS_MULTIPLIER = 1;
  // Max harvest interval: 14 days.
  uint256 public constant MAXIMUM_HARVEST_INTERVAL = 14 days;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  //Checks if the LPToken exists in the pool
  mapping(IBEP20 => bool) public LpPool;
  // Total allocation points. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;
  // The block number when Saitama mining starts.
  uint256 public startBlock;
  // Total locked up rewards
  uint256 public totalLockedUpRewards;

  event addPool(
    uint256 _allocPoint,
    IBEP20 _lpToken,
    uint16 _depositFeeBP,
    uint256 _harvestInterval,
    bool _withUpdate
  );
  event setPool(
    uint256 _pid,
    uint256 _allocPoint,
    uint16 _depositFeeBP,
    uint256 _harvestInterval,
    bool _withUpdate
  );

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );
  event EmissionRateUpdated(
    address indexed caller,
    uint256 previousAmount,
    uint256 newAmount
  );

  event RewardLockedUp(
    address indexed user,
    uint256 indexed pid,
    uint256 amountLockedUp
  );

  constructor(
    ISaitama _Saitama,
    address _RewardWalletAddress,
    uint256 _startBlock,
    uint256 _SaitamaPerBlock
  ) public {
    Saitama = _Saitama;
    startBlock = _startBlock;
    SaitamaPerBlock = _SaitamaPerBlock;
    RewardWalletAddress = _RewardWalletAddress;
    devAddress = msg.sender;
    feeAddress = msg.sender;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Add a new lp to the pool. Can only be called by the owner.
  // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(
    uint256 _allocPoint,
    IBEP20 _lpToken,
    uint16 _depositFeeBP,
    uint256 _harvestInterval,
    bool _withUpdate
  ) external onlyOwner {
    require(
      LpPool[_lpToken] == false,
      "Can't add more than one pool for the same token"
    );
    require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
    require(
      _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
      "add: invalid harvest interval"
    );

    LpPool[_lpToken] = true;

    if (_withUpdate) {
      massUpdatePools();
    }
    uint256 lastRewardBlock = block.number > startBlock
      ? block.number
      : startBlock;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(
      PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accSaitamaPerShare: 0,
        depositFeeBP: _depositFeeBP,
        harvestInterval: _harvestInterval
      })
    );
    emit addPool(
      _allocPoint,
      _lpToken,
      _depositFeeBP,
      _harvestInterval,
      _withUpdate
    );
  }

  //Update the Reward Wallet Address
  function updateRewardWallet(address _rewardWalletAddress) external onlyOwner {
    require(
      _rewardWalletAddress != address(0),
      "Reward Wallet Address Can't be Zero"
    );
    RewardWalletAddress = _rewardWalletAddress;
  }

  // Update the given pool's Saitama allocation point and deposit fee. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    uint16 _depositFeeBP,
    uint256 _harvestInterval,
    bool _withUpdate
  ) external onlyOwner {
    require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
    require(
      _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
      "set: invalid harvest interval"
    );
    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
      _allocPoint
    );
    poolInfo[_pid].allocPoint = _allocPoint;
    poolInfo[_pid].depositFeeBP = _depositFeeBP;
    poolInfo[_pid].harvestInterval = _harvestInterval;

    emit setPool(
      _pid,
      _allocPoint,
      _depositFeeBP,
      _harvestInterval,
      _withUpdate
    );
  }

  // Return reward multiplier over the given _from to _to block.
  function getMultiplier(uint256 _from, uint256 _to)
    public
    pure
    returns (uint256)
  {
    return _to.sub(_from).mul(BONUS_MULTIPLIER);
  }

  // View function to see pending Saitamas on frontend.
  function pendingSaitama(uint256 _pid, address _user)
    external
    view
    returns (uint256)
  {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accSaitamaPerShare = pool.accSaitamaPerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
      uint256 SaitamaReward = multiplier
        .mul(SaitamaPerBlock)
        .mul(pool.allocPoint)
        .div(totalAllocPoint);
      accSaitamaPerShare = accSaitamaPerShare.add(
        SaitamaReward.mul(1e12).div(lpSupply)
      );
    }
    uint256 pending = user.amount.mul(accSaitamaPerShare).div(1e12).sub(
      user.rewardDebt
    );
    return pending.add(user.rewardLockedUp);
  }

  // View function to see if user can harvest Saitamas.
  function canHarvest(uint256 _pid, address _user) public view returns (bool) {
    UserInfo storage user = userInfo[_pid][_user];
    return block.timestamp >= user.nextHarvestUntil;
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
      return;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0 || pool.allocPoint == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }
    uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
    uint256 SaitamaReward = multiplier
      .mul(SaitamaPerBlock)
      .mul(pool.allocPoint)
      .div(totalAllocPoint);

    Saitama.transferFrom(
      RewardWalletAddress,
      devAddress,
      SaitamaReward.div(10)
    );

    Saitama.transferFrom(RewardWalletAddress, address(this), SaitamaReward);

    pool.accSaitamaPerShare = pool.accSaitamaPerShare.add(
      SaitamaReward.mul(1e12).div(lpSupply)
    );
    pool.lastRewardBlock = block.number;
  }

  // Deposit LP tokens to MasterChef for Saitama allocation.
  function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    payOrLockupPendingSaitama(_pid);
    if (_amount > 0) {
      pool.lpToken.safeTransferFrom(
        address(msg.sender),
        address(this),
        _amount
      );
      if (address(pool.lpToken) == address(Saitama)) {
        // SaitamaTax in basis points
        uint256 SaitamaTax = (Saitama._reflectionFee() +
          Saitama._burnFee() +
          Saitama._marketingTokenFee() +
          Saitama._marketingETHFee()).mul(100);
        uint256 transferTax = _amount.mul(SaitamaTax).div(10000);
        _amount = _amount.sub(transferTax);
      }
      if (pool.depositFeeBP > 0) {
        uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
        pool.lpToken.safeTransfer(feeAddress, depositFee);
        user.amount = user.amount.add(_amount).sub(depositFee);
      } else {
        user.amount = user.amount.add(_amount);
      }
    }
    user.rewardDebt = user.amount.mul(pool.accSaitamaPerShare).div(1e12);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw LP tokens from MasterChef.
  function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "withdraw: not good");
    updatePool(_pid);
    payOrLockupPendingSaitama(_pid);
    if (_amount > 0) {
      user.amount = user.amount.sub(_amount);
      pool.lpToken.safeTransfer(address(msg.sender), _amount);
    }
    user.rewardDebt = user.amount.mul(pool.accSaitamaPerShare).div(1e12);
    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    uint256 amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;
    user.rewardLockedUp = 0;
    user.nextHarvestUntil = 0;
    pool.lpToken.safeTransfer(address(msg.sender), amount);
    emit EmergencyWithdraw(msg.sender, _pid, amount);
  }

  // Pay or lockup pending Saitamas.
  function payOrLockupPendingSaitama(uint256 _pid) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    if (user.nextHarvestUntil == 0) {
      user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
    }

    uint256 pending = user.amount.mul(pool.accSaitamaPerShare).div(1e12).sub(
      user.rewardDebt
    );
    if (canHarvest(_pid, msg.sender)) {
      if (pending > 0 || user.rewardLockedUp > 0) {
        uint256 totalRewards = pending.add(user.rewardLockedUp);

        // reset lockup
        totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);

        // send rewards
        safeSaitamaTransfer(msg.sender, totalRewards);
      }
    } else if (pending > 0) {
      user.rewardLockedUp = user.rewardLockedUp.add(pending);
      totalLockedUpRewards = totalLockedUpRewards.add(pending);
      emit RewardLockedUp(msg.sender, _pid, pending);
    }
  }

  // Safe Saitama transfer function, just in case if rounding error causes pool to not have enough Saitamas.
  function safeSaitamaTransfer(address _to, uint256 _amount) internal {
    uint256 SaitamaBal = Saitama.balanceOf(address(this));
    if (_amount > SaitamaBal) {
      Saitama.transfer(_to, SaitamaBal);
    } else {
      Saitama.transfer(_to, _amount);
    }
  }

  // Update dev address by the previous dev.
  function setDevAddress(address _devAddress) external {
    require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
    require(_devAddress != address(0), "setDevAddress: ZERO");
    devAddress = _devAddress;
  }

  function setFeeAddress(address _feeAddress) external {
    require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
    require(_feeAddress != address(0), "setFeeAddress: ZERO");
    feeAddress = _feeAddress;
  }

  // Saita has to add hidden dummy pools in order to alter the emission, here we make it simple and transparent to all.
  function updateEmissionRate(uint256 _SaitamaPerBlock) external onlyOwner {
    massUpdatePools();
    emit EmissionRateUpdated(msg.sender, SaitamaPerBlock, _SaitamaPerBlock);
    SaitamaPerBlock = _SaitamaPerBlock;
  }
}
