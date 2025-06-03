// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
// contracts
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FlashLoanProvider
 * @notice Provides uncollateralized flash loans that must be repaid within the same transaction
 * @dev Implements a simple flash loan mechanism with configurable fees
 */
contract FlashLoanProvider is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // custom errors
    error InvalidAmount();
    error InsufficientLiquidity();
    error FlashLoanFailed();
    error RepaymentFailed();
    error InvalidReceiver();

    // constants
    uint256 public constant MAX_FLASH_LOAN_FEE = 1000; // 10% max fee in basis points

    // state variables
    mapping(address asset => bool supported) public supportedAssets;
    mapping(address asset => uint256 fee) public flashLoanFees; // fee in basis points
    mapping(address asset => uint256 available) public availableLiquidity;

    uint256 public totalFeesCollected;

    // events
    event FlashLoan(address indexed receiver, address indexed asset, uint256 amount, uint256 fee);
    event AssetAdded(address indexed asset, uint256 fee);
    event AssetRemoved(address indexed asset);
    event FeeUpdated(address indexed asset, uint256 oldFee, uint256 newFee);
    event LiquidityDeposited(address indexed asset, uint256 amount);
    event LiquidityWithdrawn(address indexed asset, uint256 amount);
    event FeesCollected(uint256 amount);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Execute a flash loan
     * @param _receiver The contract that will receive the loan and execute the callback
     * @param _asset The address of the asset to borrow
     * @param _amount The amount to borrow
     * @param _params Additional data to pass to the receiver
     */
    function flashLoan(address _receiver, address _asset, uint256 _amount, bytes calldata _params)
        external
        nonReentrant
        whenNotPaused
    {
        if (_amount == 0) revert InvalidAmount();
        if (_receiver == address(0)) revert InvalidReceiver();
        if (!supportedAssets[_asset]) revert InvalidAmount();
        if (_amount > availableLiquidity[_asset]) revert InsufficientLiquidity();

        IERC20 asset = IERC20(_asset);
        uint256 balanceBefore = asset.balanceOf(address(this));

        // calculate fee
        uint256 fee = (_amount * flashLoanFees[_asset]) / 10000;
        uint256 amountPlusFee = _amount + fee;

        // update available liquidity
        availableLiquidity[_asset] -= _amount;

        // send the loan amount to the receiver
        asset.safeTransfer(_receiver, _amount);

        // execute the receiver's callback
        bool success = IFlashLoanReceiver(_receiver).executeOperation(_asset, _amount, fee, msg.sender, _params);

        if (!success) revert FlashLoanFailed();

        // check that the loan + fee has been repaid
        uint256 balanceAfter = asset.balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert RepaymentFailed();

        // update liquidity and fees
        availableLiquidity[_asset] += _amount;
        totalFeesCollected += fee;

        emit FlashLoan(_receiver, _asset, _amount, fee);
    }

    /**
     * @notice Add a new asset for flash loans
     * @param _asset The address of the asset to add
     * @param _fee The fee in basis points (e.g., 30 = 0.3%)
     */
    function addAsset(address _asset, uint256 _fee) external onlyOwner {
        if (_fee > MAX_FLASH_LOAN_FEE) revert InvalidAmount();

        supportedAssets[_asset] = true;
        flashLoanFees[_asset] = _fee;

        emit AssetAdded(_asset, _fee);
    }

    /**
     * @notice Remove an asset from flash loans
     * @param _asset The address of the asset to remove
     */
    function removeAsset(address _asset) external onlyOwner {
        supportedAssets[_asset] = false;
        flashLoanFees[_asset] = 0;

        emit AssetRemoved(_asset);
    }

    /**
     * @notice Update the flash loan fee for an asset
     * @param _asset The address of the asset
     * @param _newFee The new fee in basis points
     */
    function updateFee(address _asset, uint256 _newFee) external onlyOwner {
        if (!supportedAssets[_asset]) revert InvalidAmount();
        if (_newFee > MAX_FLASH_LOAN_FEE) revert InvalidAmount();

        uint256 oldFee = flashLoanFees[_asset];
        flashLoanFees[_asset] = _newFee;

        emit FeeUpdated(_asset, oldFee, _newFee);
    }

    /**
     * @notice Deposit liquidity to enable flash loans
     * @param _asset The address of the asset to deposit
     * @param _amount The amount to deposit
     */
    function depositLiquidity(address _asset, uint256 _amount) external {
        if (_amount == 0) revert InvalidAmount();
        if (!supportedAssets[_asset]) revert InvalidAmount();

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        availableLiquidity[_asset] += _amount;

        emit LiquidityDeposited(_asset, _amount);
    }

    /**
     * @notice Withdraw liquidity (owner only for simplicity)
     * @param _asset The address of the asset to withdraw
     * @param _amount The amount to withdraw
     */
    function withdrawLiquidity(address _asset, uint256 _amount) external onlyOwner {
        if (_amount == 0) revert InvalidAmount();
        if (_amount > availableLiquidity[_asset]) revert InsufficientLiquidity();

        availableLiquidity[_asset] -= _amount;
        IERC20(_asset).safeTransfer(msg.sender, _amount);

        emit LiquidityWithdrawn(_asset, _amount);
    }

    /**
     * @notice Get the maximum amount available for flash loan
     * @param _asset The address of the asset
     * @return The maximum borrowable amount
     */
    function getMaxFlashLoan(address _asset) external view returns (uint256) {
        if (!supportedAssets[_asset]) return 0;
        return availableLiquidity[_asset];
    }

    /**
     * @notice Calculate the flash loan fee for a given amount
     * @param _asset The address of the asset
     * @param _amount The amount to borrow
     * @return The fee amount
     */
    function getFlashLoanFee(address _asset, uint256 _amount) external view returns (uint256) {
        if (!supportedAssets[_asset]) return 0;
        return (_amount * flashLoanFees[_asset]) / 10000;
    }

    /**
     * @notice Collect accumulated fees (owner only)
     */
    function collectFees() external onlyOwner {
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;

        emit FeesCollected(amount);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
