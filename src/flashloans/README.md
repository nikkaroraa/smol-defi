# Flash Loans

Flash loans are uncollateralized loans that must be borrowed and repaid within the same transaction. They enable powerful DeFi strategies like arbitrage, liquidations, and complex trading without requiring upfront capital.

## 📁 Components

### Core Contracts

- **`FlashLoanProvider.sol`** - Main flash loan provider that manages liquidity and executes loans
- **`IFlashLoanReceiver.sol`** - Interface that borrowers must implement to receive flash loans

### Examples

- **`ArbitrageBot.sol`** - Example flash loan receiver demonstrating arbitrage between exchanges

## 🔧 How It Works

### 1. Flash Loan Process

```
1. User calls flashLoan() on FlashLoanProvider
2. Provider sends tokens to receiver contract
3. Provider calls executeOperation() on receiver
4. Receiver performs arbitrary logic (arbitrage, liquidation, etc.)
5. Receiver approves provider to take back loan + fee
6. Provider checks that loan + fee was repaid
7. Transaction reverts if repayment failed
```

### 2. Key Features

- **Instant Liquidity**: Borrow large amounts without collateral
- **Atomic Transactions**: Everything happens in one transaction
- **Configurable Fees**: Per-asset fee structure (basis points)
- **Multi-Asset Support**: Support for any ERC20 token
- **Safety Checks**: Comprehensive validation and reentrancy protection

## 🚀 Usage

### For Liquidity Providers

```solidity
// 1. Add asset support (owner only)
flashLoanProvider.addAsset(address(token), 30); // 0.3% fee

// 2. Deposit liquidity
token.approve(address(flashLoanProvider), amount);
flashLoanProvider.depositLiquidity(address(token), amount);
```

### For Borrowers

```solidity
// 1. Implement IFlashLoanReceiver
contract MyBot is IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Your logic here (arbitrage, liquidation, etc.)

        // Approve repayment
        IERC20(asset).forceApprove(msg.sender, amount + fee);
        return true;
    }
}

// 2. Execute flash loan
flashLoanProvider.flashLoan(
    address(myBot),
    address(token),
    amount,
    customParams
);
```

## 💡 Use Cases

### 1. Arbitrage

- Exploit price differences between DEXes
- Example: Buy low on Uniswap, sell high on SushiSwap

### 2. Liquidations

- Liquidate undercollateralized positions
- Use flash loan to pay debt, claim collateral, profit from bonus

### 3. Collateral Swapping

- Change collateral type without closing position
- Flash loan → repay debt → withdraw collateral → swap → redeposit → reborrow

### 4. Debt Refinancing

- Move debt between protocols for better rates
- Flash loan → repay old debt → open new debt → repay flash loan

## 🧮 Fee Structure

- **Flash Loan Fee**: Configurable per asset (0-10% max)
- **Fee Calculation**: `fee = (amount * feeRate) / 10000`
- **Example**: 10,000 USDC at 0.3% = 30 USDC fee

## ⚠️ Risks & Considerations

### For Users

- **Transaction Failure**: Entire transaction reverts if logic fails
- **Gas Costs**: Complex operations can be expensive
- **MEV**: Vulnerable to Maximum Extractable Value attacks
- **Smart Contract Risk**: Bugs in receiver logic can cause losses

### For Liquidity Providers

- **Smart Contract Risk**: Provider contract could have vulnerabilities
- **Liquidity Lock**: Funds temporarily unavailable during loans
- **Fee Dependency**: Returns depend on flash loan demand

## 🧪 Testing

Run the test suite:

```bash
forge test --match-path test/flashloans/
```

Key test scenarios:

- ✅ Basic flash loan execution
- ✅ Fee calculations
- ✅ Liquidity management
- ✅ Error conditions
- ✅ Arbitrage bot example

## 🛠️ Advanced Features

### Gas Optimization

- Uses OpenZeppelin's `forceApprove` for safer approval handling
- Minimal state changes during flash loan execution
- Efficient balance checking

### Security

- Reentrancy protection on all external functions
- Comprehensive input validation
- Safe ERC20 token handling
- Owner-only administrative functions

### Extensibility

- Modular design for easy integration
- Configurable fee structure
- Support for any ERC20 token
- Pausable for emergency situations

## 📈 Integration Ideas

1. **With Lending Pools**: Use lending pool liquidity for flash loans
2. **With DEX Aggregators**: Optimize arbitrage execution
3. **With Yield Farms**: Flash loan for position management
4. **With Options**: Delta hedging strategies
5. **With Perps**: Funding rate arbitrage

## 🔗 Next Steps

After mastering flash loans, consider building:

- **AMMs** - To provide liquidity sources for arbitrage
- **Liquidation Bots** - Using flash loans for risk-free liquidations
- **Yield Strategies** - Complex multi-protocol yield optimization
- **MEV Bots** - Maximum extractable value capture
