// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

/**
 * @title Restaking Protocol
 * @notice a minimal implementation of a restaking mechanism inspired by protocols like EigenLayer
 * @dev allows users to stake ETH and restake it to secure additional protocols
 */
contract Restaking {
    /**
     * @notice structure to track cooldown status for unstaking
     * @param cooldownStart timestamp when cooldown period started
     * @param amount amount of ETH in cooldown
     */
    struct CooldownStatus {
        uint256 cooldownStart;
        uint256 amount;
    }

    // events
    /**
     * @notice emitted when a user stakes ETH
     * @param user address of the user who staked
     * @param amount amount of ETH staked
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice emitted when a user restakes ETH to a protocol
     * @param user address of the user who restaked
     * @param protocol address of the protocol being secured
     * @param amount amount of ETH restaked
     */
    event Restaked(address indexed user, address indexed protocol, uint256 amount);

    /**
     * @notice emitted when a user initiates unstaking from a protocol
     * @param user address of the user who initiated unstaking
     * @param protocol address of the protocol being unstaked from
     * @param amount amount of ETH being unstaked
     */
    event UnstakeInitiated(address indexed user, address indexed protocol, uint256 amount);

    /**
     * @notice emitted when a user withdraws their ETH after cooldown
     * @param user address of the user who withdrew
     * @param amount amount of ETH withdrawn
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice emitted when a user's ETH is slashed
     * @param user address of the user who was slashed
     * @param amount amount of ETH slashed
     */
    event Slashed(address indexed user, uint256 amount);

    /// @notice address of the contract owner
    address public immutable owner;
    /// @notice duration of the cooldown period in seconds
    uint256 public immutable cooldownDuration;
    /// @notice mapping of user addresses to their staked ETH balance
    mapping(address user => uint256 stakedBalance) public stakedBalances;
    /// @notice mapping of user addresses to their restaked protocol addresses
    mapping(address user => address[] restakedProtocolAddresses) public restakedProtocols;
    /// @notice mapping of user addresses to their restaked balances per protocol
    mapping(address user => mapping(address targetProtocol => uint256 restakedBalance)) public restakedBalances;
    /// @notice mapping of user addresses to their slashed balances
    mapping(address user => uint256 slashedBalance) public slashedBalances;
    /// @notice mapping of user addresses to their cooldown status
    mapping(address user => CooldownStatus cooldownStatus) public cooldownStatuses;

    // custom errors
    error ZeroAmount();
    error ZeroBalance();
    error AnotherCooldownInProgress();
    error CooldownNotOver();
    error WithdrawFailed();
    error OnlyOwner();
    error NothingToSlash();
    error InvalidProtocol();
    error CooldownNotStarted();
    error FullySlashed();

    /// @notice modifier to restrict function access to owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /**
     * @notice constructor to initialize the contract
     * @param _cooldownDuration duration of the cooldown period in seconds
     */
    constructor(uint256 _cooldownDuration) {
        owner = msg.sender;
        cooldownDuration = _cooldownDuration;
    }

    /**
     * @notice allows users to stake ETH
     * @dev emits Staked event on successful stake
     * @dev reverts if amount is zero
     */
    function stake() external payable {
        if (msg.value == 0) revert ZeroAmount();
        stakedBalances[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    /**
     * @notice allows users to restake their ETH to secure another protocol
     * @param targetProtocol address of the protocol to restake to
     * @dev emits Restaked event on successful restake
     * @dev reverts if protocol address is zero or user has no staked balance
     */
    function restake(address targetProtocol) external {
        if (targetProtocol == address(0)) revert InvalidProtocol();
        if (stakedBalances[msg.sender] == 0) revert ZeroBalance();

        uint256 amount = stakedBalances[msg.sender];
        restakedBalances[msg.sender][targetProtocol] += amount;
        restakedProtocols[msg.sender].push(targetProtocol);
        stakedBalances[msg.sender] = 0;

        emit Restaked(msg.sender, targetProtocol, amount);
    }

    /**
     * @notice allows users to initiate unstaking from a protocol
     * @param targetProtocol address of the protocol to unstake from
     * @dev emits UnstakeInitiated event and starts cooldown period
     * @dev reverts if user has no restaked balance or another cooldown is in progress
     */
    function unstake(address targetProtocol) external {
        uint256 unstakeAmount = restakedBalances[msg.sender][targetProtocol];
        if (unstakeAmount == 0) revert ZeroBalance();
        if (cooldownStatuses[msg.sender].cooldownStart != 0) revert AnotherCooldownInProgress();

        stakedBalances[msg.sender] += unstakeAmount;
        cooldownStatuses[msg.sender] = CooldownStatus({cooldownStart: block.timestamp, amount: unstakeAmount});

        // remove protocol from user's restaked protocols
        _removeProtocolIfEmpty(msg.sender, targetProtocol);

        emit UnstakeInitiated(msg.sender, targetProtocol, unstakeAmount);
    }

    /**
     * @notice allows users to withdraw their ETH after cooldown period
     * @dev emits Withdrawn event on successful withdrawal
     * @dev reverts if cooldown hasn't started, isn't over, or user has no balance
     * @dev applies any slashing penalties before withdrawal
     */
    function withdraw() external {
        CooldownStatus storage status = cooldownStatuses[msg.sender];
        if (status.cooldownStart == 0) revert CooldownNotStarted();
        if (block.timestamp < status.cooldownStart + cooldownDuration) revert CooldownNotOver();
        if (stakedBalances[msg.sender] == 0) revert ZeroBalance();

        uint256 withdrawAmount = stakedBalances[msg.sender];
        uint256 penalty = slashedBalances[msg.sender];
        if (withdrawAmount <= penalty) revert FullySlashed();

        uint256 finalAmount = withdrawAmount - penalty;
        stakedBalances[msg.sender] = 0;
        slashedBalances[msg.sender] = 0; // reset after withdrawal
        delete cooldownStatuses[msg.sender];

        (bool success,) = msg.sender.call{value: finalAmount}("");
        if (!success) revert WithdrawFailed();

        emit Withdrawn(msg.sender, finalAmount);
    }

    /**
     * @notice allows owner to slash a user's restaked ETH for misbehavior
     * @param user address of the user to slash
     * @param targetProtocol address of the protocol to slash
     * @param amount amount of ETH to slash
     * @dev only callable by owner, emits Slashed event
     * @dev reverts if user has no restaked balance in the protocol
     * @dev caps slash amount to what's actually restaked
     */
    function slash(address user, address targetProtocol, uint256 amount) external onlyOwner {
        uint256 currentRestaked = restakedBalances[user][targetProtocol];
        if (currentRestaked == 0) revert NothingToSlash();

        // cap slash amount to what's actually restaked
        if (amount > currentRestaked) {
            amount = currentRestaked;
        }

        restakedBalances[user][targetProtocol] -= amount;
        slashedBalances[user] += amount;

        // remove protocol from restakedProtocols if balance is now zero
        _removeProtocolIfEmpty(user, targetProtocol);

        emit Slashed(user, amount);
    }

    /**
     * @notice internal function to remove a protocol from user's restaked protocols if balance is zero
     * @param user address of the user
     * @param protocol address of the protocol to check
     * @dev removes protocol from array and deletes mapping entry if balance is zero
     */
    function _removeProtocolIfEmpty(address user, address protocol) internal {
        if (restakedBalances[user][protocol] > 0) return;

        delete restakedBalances[user][protocol]; // free up storage

        address[] storage protocols = restakedProtocols[user];
        for (uint256 i = 0; i < protocols.length; i++) {
            if (protocols[i] == protocol) {
                protocols[i] = protocols[protocols.length - 1];
                protocols.pop();
                break;
            }
        }
    }
}
