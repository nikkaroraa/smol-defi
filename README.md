# smol-defi

A collection of minimal, production-influenced DeFi smart contracts — designed for learning, experimentation, and mastery.

This repository implements foundational concepts from decentralized finance, focusing on clarity over complexity. Each module captures the essence of a DeFi primitive or protocol mechanism in a compact, self-contained way — perfect for engineers exploring smart contract internals or building intuition from first principles.

## 📦 Modules Included

- **Restaking** – Shared security mechanism inspired by EigenLayer (Currently Implemented)
- **Lending Pool** – Simple lending protocol with deposits, borrows, and liquidations (Currently Implemented)
- **Flash Loans** – Uncollateralized borrowing within one transaction (Currently Implemented)
- Perpetuals – Leveraged trading logic and funding rate math
- Options – European and American-style options settlement
- AMMs – Constant product market makers and variants
- Liquid Staking – Derivatives like stETH / rETH
- Stablecoins – Overcollateralized and algorithmic models
- Vaults – Yield optimization and strategy execution
- Governance – Token voting and proposal lifecycle
- Interest Rate Models – Compound-style utilization-based rates

## 🧰 Why Use smol-defi?

- 🔍 **Minimal**: No unnecessary boilerplate. Focuses only on what matters.
- 🧠 **Educational**: Designed to help you grok DeFi from the ground up.
- 💡 **Extensible**: Use as a base for hackathons, prototypes, or deeper dives.
- 🧪 **Well-Commented**: Every contract comes with inline explanations and events.

## 📚 Ideal For

- Smart contract developers
- DeFi curious engineers
- Protocol designers
- Audit learners

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
