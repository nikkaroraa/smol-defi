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
     */
    function unstake(address targetProtocol) external {
        uint256 unstakeAmount = restakedBalances[msg.sender][targetProtocol];
        if (unstakeAmount == 0) revert ZeroBalance();
        if (cooldownStatuses[msg.sender].cooldownStart != 0) revert AnotherCooldownInProgress();

        // remove protocol from user's restaked protocols
        address[] storage protocols = restakedProtocols[msg.sender];
        for (uint256 i = 0; i < protocols.length; i++) {
            if (protocols[i] == targetProtocol) {
                protocols[i] = protocols[protocols.length - 1];
                protocols.pop();
                break;
            }
        }

        stakedBalances[msg.sender] += unstakeAmount;
        cooldownStatuses[msg.sender] = CooldownStatus({cooldownStart: block.timestamp, amount: unstakeAmount});
        restakedBalances[msg.sender][targetProtocol] = 0;

        emit UnstakeInitiated(msg.sender, targetProtocol, unstakeAmount);
    }

    /**
     * @notice allows users to withdraw their ETH after cooldown period
     * @dev emits Withdrawn event on successful withdrawal
     */
    function withdraw() external {
        CooldownStatus storage status = cooldownStatuses[msg.sender];
        if (status.cooldownStart == 0) revert CooldownNotStarted();
        if (block.timestamp < status.cooldownStart + cooldownDuration) revert CooldownNotOver();
        if (stakedBalances[msg.sender] == 0) revert ZeroBalance();

        uint256 withdrawAmount = stakedBalances[msg.sender];
        stakedBalances[msg.sender] = 0;
        delete cooldownStatuses[msg.sender];

        (bool success,) = msg.sender.call{value: withdrawAmount}("");
        if (!success) revert WithdrawFailed();

        emit Withdrawn(msg.sender, withdrawAmount);
    }

    /**
     * @notice allows owner to slash a user's restaked ETH for misbehavior
     * @param user address of the user to slash
     * @param amount amount of ETH to slash
     * @dev only callable by owner, emits Slashed event
     */
    function slash(address user, uint256 amount) external onlyOwner {
        if (restakedProtocols[user].length == 0 && stakedBalances[user] == 0) revert NothingToSlash();

        // find maximum amount restaked in any protocol
        uint256 maxRestakedAmount = 0;
        for (uint256 i = 0; i < restakedProtocols[user].length; i++) {
            uint256 currentRestakedAmount = restakedBalances[user][restakedProtocols[user][i]];
            if (currentRestakedAmount > maxRestakedAmount) {
                maxRestakedAmount = currentRestakedAmount;
            }
        }

        // cap slash amount to maximum restaked amount
        amount = amount > maxRestakedAmount ? maxRestakedAmount : amount;
        slashedBalances[user] += amount;

        emit Slashed(user, amount);
    }
}
