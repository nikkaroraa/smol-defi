// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashLoanReceiver} from "../IFlashLoanReceiver.sol";
import {FlashLoanProvider} from "../FlashLoanProvider.sol";
// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ArbitrageBot
 * @notice Example flash loan receiver that performs arbitrage between two exchanges
 */
contract ArbitrageBot is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    // custom errors
    error ArbitrageFailed();
    error UnauthorizedFlashLoan();
    error InsufficientProfit();

    // state variables
    address public immutable flashLoanProvider;
    address public owner;

    // mock exchange interfaces (in real implementation, these would be actual DEX interfaces)
    mapping(address asset => uint256 price) public exchangeA_prices;
    mapping(address asset => uint256 price) public exchangeB_prices;

    // events
    event ArbitrageExecuted(address indexed asset, uint256 amount, uint256 profit);
    event PriceUpdated(address indexed asset, uint256 priceA, uint256 priceB);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _flashLoanProvider) {
        flashLoanProvider = _flashLoanProvider;
        owner = msg.sender;
    }

    /**
     * @notice Execute flash loan callback
     * @param asset The address of the asset being borrowed
     * @param amount The amount of the asset being borrowed
     * @param fee The fee amount that must be paid back
     * @param initiator The address that initiated the flash loan
     * @param params Additional data passed by the initiator
     */
    function executeOperation(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        // ensure the call is from our trusted flash loan provider
        if (msg.sender != flashLoanProvider) revert UnauthorizedFlashLoan();

        // decode parameters (though we don't use them in here)
        (address targetAsset, uint256 expectedProfit) = abi.decode(params, (address, uint256));

        // perform arbitrage logic
        uint256 profit = _performArbitrage(asset, amount);

        // For this example, we need to have the original borrowed amount plus fee
        // The borrowed amount is already in our balance from the flash loan
        // We just need additional tokens to cover the fee
        uint256 totalNeeded = amount + fee;
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));

        require(currentBalance >= totalNeeded, "Insufficient balance for repayment");

        // Transfer the borrowed amount + fee back to the flash loan provider
        IERC20(asset).safeTransfer(flashLoanProvider, totalNeeded);

        emit ArbitrageExecuted(asset, amount, profit);

        return true;
    }

    /**
     * @notice Initiate an arbitrage flash loan
     * @param _asset The asset to arbitrage
     * @param _amount The amount to borrow
     * @param _expectedProfit Minimum expected profit
     */
    function executeArbitrage(address _asset, uint256 _amount, uint256 _expectedProfit) external onlyOwner {
        bytes memory params = abi.encode(_asset, _expectedProfit);

        // Call the flash loan provider directly
        FlashLoanProvider(flashLoanProvider).flashLoan(address(this), _asset, _amount, params);
    }

    /**
     * @notice Perform the actual arbitrage (simplified mock implementation)
     * @param _asset The asset to arbitrage
     * @param _amount The amount borrowed
     * @return profit The profit made from arbitrage
     */
    function _performArbitrage(address _asset, uint256 _amount) internal view returns (uint256 profit) {
        uint256 priceA = exchangeA_prices[_asset];
        uint256 priceB = exchangeB_prices[_asset];

        // simplified arbitrage: buy low, sell high
        if (priceA < priceB) {
            // buy on exchange A, sell on exchange B
            profit = (_amount * (priceB - priceA)) / priceA;
        } else if (priceB < priceA) {
            // buy on exchange B, sell on exchange A
            profit = (_amount * (priceA - priceB)) / priceB;
        }

        // In a real implementation, you would:
        // 1. Swap on the cheaper exchange
        // 2. Swap back on the more expensive exchange
        // 3. Calculate actual profit after slippage and fees
    }

    /**
     * @notice Update mock exchange prices (for testing purposes)
     * @param _asset The asset to update prices for
     * @param _priceA Price on exchange A
     * @param _priceB Price on exchange B
     */
    function updatePrices(address _asset, uint256 _priceA, uint256 _priceB) external onlyOwner {
        exchangeA_prices[_asset] = _priceA;
        exchangeB_prices[_asset] = _priceB;

        emit PriceUpdated(_asset, _priceA, _priceB);
    }

    /**
     * @notice Withdraw any profits (owner only)
     * @param _asset The asset to withdraw
     * @param _amount The amount to withdraw
     */
    function withdrawProfits(address _asset, uint256 _amount) external onlyOwner {
        IERC20(_asset).safeTransfer(owner, _amount);
    }

    /**
     * @notice Get current prices for an asset
     * @param _asset The asset to check
     * @return priceA Price on exchange A
     * @return priceB Price on exchange B
     */
    function getPrices(address _asset) external view returns (uint256 priceA, uint256 priceB) {
        return (exchangeA_prices[_asset], exchangeB_prices[_asset]);
    }

    /**
     * @notice Calculate potential arbitrage profit
     * @param _asset The asset to check
     * @param _amount The amount to arbitrage
     * @return profit Potential profit from arbitrage
     */
    function calculateArbitrageProfit(address _asset, uint256 _amount) external view returns (uint256 profit) {
        uint256 priceA = exchangeA_prices[_asset];
        uint256 priceB = exchangeB_prices[_asset];

        if (priceA < priceB) {
            profit = (_amount * (priceB - priceA)) / priceA;
        } else if (priceB < priceA) {
            profit = (_amount * (priceA - priceB)) / priceB;
        }
    }
}
