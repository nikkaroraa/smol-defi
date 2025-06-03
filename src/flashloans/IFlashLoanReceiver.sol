// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

/**
 * @title IFlashLoanReceiver
 * @notice Interface that flash loan receivers must implement
 * @dev The receiver contract must implement this interface to handle flash loan callbacks
 */
interface IFlashLoanReceiver {
    /**
     * @notice Called by the flash loan provider during a flash loan
     * @param asset The address of the asset being borrowed
     * @param amount The amount of the asset being borrowed
     * @param fee The fee amount that must be paid back
     * @param initiator The address that initiated the flash loan
     * @param params Additional data passed by the initiator
     * @return true if the operation was successful
     */
    function executeOperation(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata params)
        external
        returns (bool);
}
