🧱 Minimal Restaking Protocol
This project implements a simplified version of a restaking mechanism, inspired by protocols like EigenLayer. The goal is to understand how restaking works at a fundamental level by recreating its basic logic using Ethereum smart contracts.

🧠 Concept
Restaking allows users to reuse their staked ETH (or other tokens) to secure additional protocols beyond Ethereum — enabling a shared security model. In this minimal protocol:

- Users stake ETH into a contract.
- They can restake their ETH to a specific external protocol (represented by an address).
- A cooldown period ensures that users can't instantly withdraw after restaking.
- The contract can optionally support slashing, allowing restaked ETH to be partially penalized for misbehavior in external protocols.

⚙️ Features

- stake(): Deposit ETH and track user balances.
- restake(address targetProtocol): Commit staked ETH to secure another protocol.
- unstake(): Initiate cooldown after restaking.
- withdraw(): Withdraw ETH after the cooldown period ends.
- slash(address user, uint256 amount): (Optional) Slash a portion of restaked ETH for misbehavior.
- Cooldown logic to simulate unstaking delays.

🔒 Assumptions

- ETH is restaked virtually (i.e., no actual transfer to the external protocol).
- Target protocols are represented by mock addresses or contracts.

This is a learning-oriented prototype, not production-safe.

🧪 Goals
This repo is meant to:

- Explore shared security and slashing mechanics.
- Simulate how protocols like EigenLayer manage opt-in restaking.
- Serve as a base to extend into operator delegation, LST restaking, or off-chain slashing conditions.
