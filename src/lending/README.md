# Lending Pool

A simple lending protocol that allows users to deposit assets as collateral and borrow against them. The protocol uses a single asset (WETH) for both collateral and borrowing.

## Architecture

### Core Components

1. **LendingPool.sol**

   - Main contract that handles deposits, borrows, and liquidations
   - Uses a single asset (WETH) for both collateral and borrowing
   - Implements interest accrual and distribution

2. **InterestRateModel.sol**
   - Calculates interest rates based on utilization ratio
   - Used by LendingPool to determine borrow and supply rates

### Key Features

1. **Deposits and Withdrawals**

   - Users can deposit WETH to earn interest
   - Interest accrues continuously and is distributed to depositors
   - Users can withdraw their deposits plus earned interest

2. **Borrowing**

   - Users can borrow WETH against their deposits
   - Minimum collateral ratio of 150% required
   - Interest accrues on borrowed amounts

3. **Liquidation**

   - Positions can be liquidated when health factor falls below 125%
   - Liquidators receive a 5% bonus on liquidated amounts
   - Helps maintain protocol solvency

4. **Interest Mechanism**
   - Interest accrues continuously based on time elapsed
   - 90% of borrow interest goes to depositors
   - 10% goes to protocol as revenue
   - Interest rates are determined by the InterestRateModel

### Key Parameters

- **Collateral Ratio**: 150% (15,000 basis points)
- **Liquidation Threshold**: 125% (12,500 basis points)
- **Liquidation Penalty**: 5% (500 basis points)
- **Protocol Fee**: 10% of borrow interest

### Security Features

1. **Reentrancy Protection**

   - Uses OpenZeppelin's ReentrancyGuard
   - Prevents reentrancy attacks on state-changing functions

2. **Pausable**

   - Contract can be paused by owner in case of emergencies
   - All state-changing functions are paused when contract is paused

3. **Safe Token Transfers**
   - Uses OpenZeppelin's SafeERC20 for token transfers
   - Handles non-standard ERC20 tokens safely

### Events

- `Deposit`: Emitted when a user deposits assets
- `Withdraw`: Emitted when a user withdraws assets
- `Borrow`: Emitted when a user borrows assets
- `Repay`: Emitted when a user repays borrowed assets
- `Liquidate`: Emitted when a position is liquidated
- `InterestAccrued`: Emitted when interest is accrued
- `ProtocolFeesCollected`: Emitted when protocol fees are collected

## Usage

### Depositing

```solidity
// Deposit 1 WETH
lendingPool.deposit(1e18);
```

### Borrowing

```solidity
// Borrow 0.5 WETH (requires 0.75 WETH collateral)
lendingPool.borrow(0.5e18);
```

### Withdrawing

```solidity
// Withdraw deposit plus interest
lendingPool.withdraw(amount);
```

### Repaying

```solidity
// Repay borrowed amount plus interest
lendingPool.repay(amount);
```

### Liquidating

```solidity
// Liquidate an undercollateralized position
lendingPool.liquidate(user, amount);
```

## Interest Calculation

Interest accrues continuously based on:

1. Time elapsed since last update
2. Current borrow rate from InterestRateModel
3. Total borrows and deposits

Interest is split:

- 90% to depositors
- 10% to protocol

## Security Considerations

1. **Collateral Ratio**

   - Minimum 150% required to open position
   - Liquidation at 125% to prevent bad debt

2. **Liquidation**

   - Positions can be liquidated before becoming undercollateralized
   - 5% bonus incentivizes quick liquidation

3. **Interest Accrual**
   - Interest accrues on every state-changing operation
   - Prevents interest manipulation

## Future Improvements

1. **Multiple Assets**

   - Support for multiple collateral and borrow assets
   - Price feeds for different assets

2. **Flash Loans**

   - Add flash loan functionality
   - Allow borrowing without collateral for one transaction

3. **Governance**

   - Add governance for parameter updates
   - Allow community to vote on protocol changes

4. **Insurance**

   - Add protocol insurance mechanism
   - Protect against bad debt

5. **Oracles**
   - Add price feed oracles
   - More accurate liquidation triggers
