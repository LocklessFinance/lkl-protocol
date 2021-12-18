// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./ERC20Permit.sol";
import "../interfaces/ILKLStaking.sol";

abstract contract ERC20PermitWithMining is ERC20Permit {
    ILKLStaking public lklStaking;
    uint256 public pid;

    /// @notice Transfers an amount of erc20 from a spender to a receipt
    /// @param spender The source of the ERC20 tokens
    /// @param recipient The destination of the ERC20 tokens
    /// @param amount the number of tokens to send
    /// @return returns true on success and reverts on failure
    /// @dev will fail transfers which send funds to this contract or 0
    function transferFrom(
        address spender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        // Load balance and allowance
        uint256 balance = balanceOf[spender];
        require(balance >= amount, "ERC20: insufficient-balance");
        // We potentially have to change allowances
        if (spender != msg.sender) {
            // Loading the allowance in the if block prevents vanilla transfers
            // from paying for the sload.
            uint256 allowed = allowance[spender][msg.sender];
            // If the allowance is max we do not reduce it
            // Note - This means that max allowances will be more gas efficient
            // by not requiring a sstore on 'transferFrom'
            if (allowed != type(uint256).max) {
                require(allowed >= amount, "ERC20: insufficient-allowance");
                allowance[spender][msg.sender] = allowed - amount;
            }
        }
        // Update the balances
        balanceOf[spender] = balance - amount;
        // Note - In the constructor we initialize the 'balanceOf' of address 0 and
        //        the token address to uint256.max and so in 8.0 transfers to those
        //        addresses revert on this step.
        balanceOf[recipient] = balanceOf[recipient] + amount;
        lklStaking.withdraw(spender, pid, amount);
        lklStaking.deposit(recipient, pid, amount);
        // Emit the needed event
        emit Transfer(spender, recipient, amount);
        // Return that this call succeeded
        return true;
    }

    /// @notice This function overrides the ERC20Permit Library's _mint and causes it
    ///          to perform a deposit in our mining contract
    /// @param account the address which will receive the token.
    /// @param amount the amount of token which they will receive
    /// @dev This function is virtual so that it can be overridden, if you
    ///      are reviewing this contract for security you should ensure to
    ///      check for overrides
    function _mint(address account, uint256 amount) internal override {
        // Add tokens to the account
        balanceOf[account] = balanceOf[account] + amount;
        lklStaking.deposit(account, pid, amount);
        // Emit an event to track the minting
        emit Transfer(address(0), account, amount);
    }

    /// @notice This function overrides the ERC20Permit Library's _burn to perform
    ///     a withdraw in our mining contract
    /// @param account the account to remove tokens from
    /// @param amount  the amount of tokens to remove
    /// @dev This function is virtual so that it can be overridden, if you
    ///      are reviewing this contract for security you should ensure to
    ///      check for overrides
    function _burn(address account, uint256 amount) internal override {
        // Reduce the balance of the account
        balanceOf[account] = balanceOf[account] - amount;
        lklStaking.withdraw(account, pid, amount);
        // Emit an event tracking transfers
        emit Transfer(account, address(0), amount);
    }
}
