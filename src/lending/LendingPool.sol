// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// contracts
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

/**
 * @title lending pool
 * @notice implements a simple lending pool with deposit, borrow, and interest accrual
 * @dev uses a single asset (WETH) for both collateral and borrowing
 */
contract LendingPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // custom errors
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientCollateral();
    error InvalidCollateralRatio();
    error LiquidationThresholdReached();

    // constants
    uint256 public constant COLLATERAL_RATIO = 15_000; // 150% in basis points
    uint256 public constant LIQUIDATION_THRESHOLD = 12_500; // 125% in basis points
    uint256 public constant LIQUIDATION_PENALTY = 500; // 5% in basis points

    // state variables
    IERC20 public immutable asset; // WETH
    InterestRateModel public immutable interestRateModel;

    // user balances
    mapping(address user => uint256 depositAmount) public deposits;
    mapping(address user => uint256 borrowAmount) public borrows;

    // global state
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    uint256 public lastUpdateTimestamp;
    uint256 public protocolFees; // track protocol revenue

    // events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed user, address indexed liquidator, uint256 amount);
    event InterestAccrued(uint256 timestamp, uint256 borrowRate, uint256 supplyRate);
    event ProtocolFeesCollected(uint256 amount);

    constructor(address _asset, address _interestRateModel) Ownable(msg.sender) {
        asset = IERC20(_asset);
        interestRateModel = InterestRateModel(_interestRateModel);
        lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice deposit assets into the pool
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external nonReentrant whenNotPaused {
        accrueInterest();
        if (_amount == 0) revert InvalidAmount();

        // transfer tokens from user
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        // update state
        deposits[msg.sender] += _amount;
        totalDeposits += _amount;

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice withdraw assets from the pool
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _amount) external nonReentrant whenNotPaused {
        accrueInterest();
        if (_amount == 0) revert InvalidAmount();

        uint256 userDeposit = deposits[msg.sender];
        uint256 interestEarned = getInterestEarned(msg.sender);
        uint256 totalWithdrawable = userDeposit + interestEarned;

        if (_amount > totalWithdrawable) revert InsufficientBalance();

        // update state
        deposits[msg.sender] = userDeposit - _amount;
        totalDeposits -= _amount;

        // transfer tokens to user
        asset.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice borrow assets from the pool
     * @param _amount amount to borrow
     */
    function borrow(uint256 _amount) external nonReentrant whenNotPaused {
        accrueInterest();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalDeposits - totalBorrows) revert InsufficientBalance();

        // check collateral ratio
        uint256 collateralValue = deposits[msg.sender];
        uint256 borrowValue = borrows[msg.sender] + _amount;

        if (collateralValue * 10000 < borrowValue * COLLATERAL_RATIO) {
            revert InvalidCollateralRatio();
        }

        // update state
        borrows[msg.sender] += _amount;
        totalBorrows += _amount;

        // transfer tokens to user
        asset.safeTransfer(msg.sender, _amount);

        emit Borrow(msg.sender, _amount);
    }

    /**
     * @notice repay borrowed assets
     * @param _amount amount to repay
     */
    function repay(uint256 _amount) external nonReentrant whenNotPaused {
        accrueInterest();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > borrows[msg.sender]) revert InsufficientBalance();

        // transfer tokens from user
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        // update state
        borrows[msg.sender] -= _amount;
        totalBorrows -= _amount;

        emit Repay(msg.sender, _amount);
    }

    /**
     * @notice calculate the health factor of a position
     * @param _user address of the user
     * @return health factor in basis points (10000 = 100%)
     */
    function getHealthFactor(address _user) public view returns (uint256) {
        uint256 collateralValue = deposits[_user];
        uint256 borrowValue = borrows[_user];

        if (borrowValue == 0) return type(uint256).max;

        return (collateralValue * 10000) / borrowValue;
    }

    /**
     * @notice liquidate an undercollateralized position
     * @param _user address of the user to liquidate
     * @param _amount amount to liquidate
     */
    function liquidate(address _user, uint256 _amount) external nonReentrant whenNotPaused {
        accrueInterest();
        uint256 healthFactor = getHealthFactor(_user);

        // allow liquidation if health factor is below liquidation threshold
        if (healthFactor > LIQUIDATION_THRESHOLD) {
            revert LiquidationThresholdReached();
        }

        uint256 borrowValue = borrows[_user];

        // ensure we're not trying to liquidate more than the borrow amount
        if (_amount > borrowValue) {
            _amount = borrowValue;
        }

        // transfer tokens from liquidator
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        // calculate liquidation bonus
        uint256 bonus = (_amount * LIQUIDATION_PENALTY) / 10000;
        uint256 totalRepaid = _amount + bonus;

        // update state
        borrows[_user] -= _amount;
        totalBorrows -= _amount;
        deposits[_user] -= totalRepaid;
        totalDeposits -= totalRepaid;

        // transfer collateral to liquidator
        asset.safeTransfer(msg.sender, totalRepaid);

        emit Liquidate(_user, msg.sender, _amount);
    }

    /**
     * @notice accrue interest to the pool
     */
    function accrueInterest() public {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastUpdateTimestamp) return;

        uint256 borrowRate = interestRateModel.getInterestRate(totalBorrows, totalDeposits);
        uint256 timeElapsed = currentTimestamp - lastUpdateTimestamp;

        // calculate interest
        uint256 borrowInterest = (totalBorrows * borrowRate * timeElapsed) / (365 days * 10000);

        // split interest between protocol and suppliers
        uint256 protocolInterest = (borrowInterest * 1000) / 10000; // 10% to protocol
        uint256 supplyInterest = borrowInterest - protocolInterest; // 90% to suppliers

        // update state
        totalBorrows += borrowInterest;
        totalDeposits += supplyInterest;
        protocolFees += protocolInterest;
        lastUpdateTimestamp = currentTimestamp;

        emit InterestAccrued(currentTimestamp, borrowRate, (supplyInterest * 10000) / totalDeposits);
        emit ProtocolFeesCollected(protocolInterest);
    }

    /**
     * @notice withdraw protocol fees
     */
    function withdrawProtocolFees() external onlyOwner {
        uint256 amount = protocolFees;
        protocolFees = 0;
        asset.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice calculate user's share of interest
     * @param _user address of the user
     * @return amount of interest earned
     */
    function getInterestEarned(address _user) public view returns (uint256) {
        uint256 userDeposit = deposits[_user];
        if (userDeposit == 0) return 0;

        // calculate user's share of total deposits
        uint256 userShare = (userDeposit * 10000) / totalDeposits;
        // calculate interest based on user's share
        return (userShare * (totalDeposits - totalBorrows)) / 10000;
    }

    /**
     * @notice pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
