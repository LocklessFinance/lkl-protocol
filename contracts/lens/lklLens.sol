// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../interfaces/ICCPool.sol";
import "../balancer-core-v2/vault/interfaces/IVault.sol";
import "../balancer-core-v2/lib/math/LogExpMath.sol";
import "../balancer-core-v2/lib/math/FixedPoint.sol";

contract lklLens {
    using LogExpMath for uint256;
    using FixedPoint for uint256;
    struct poolDetails {
        uint256 baseReserves;
        uint256 bondReserves;
        uint256 totalSupply;
        uint256 expiration;
        uint256 tokenDecimals;
        uint256 unitSeconds;
    }

    function getPoolDetails(ICCPool pool)
        public
        view
        returns (poolDetails memory poolInfo)
    {
        bytes32 PoolId = pool.getPoolId();
        IERC20 baseToken = IERC20(pool.underlying());
        IERC20 bondToken = IERC20(pool.bond());
        IVault vault = IVault(pool.getVault());
        (IERC20[] memory tokens, uint256[] memory reserves, ) = vault
            .getPoolTokens(PoolId);
        uint256 bondIndex = tokens[0] == bondToken ? 0 : 1;
        uint256 baseIndex = tokens[0] == baseToken ? 0 : 1;
        poolInfo.baseReserves = reserves[baseIndex];
        poolInfo.bondReserves = reserves[bondIndex];
        poolInfo.totalSupply = pool.totalSupply();
        poolInfo.expiration = pool.expiration();
        poolInfo.tokenDecimals = pool.underlyingDecimals();
        poolInfo.unitSeconds = pool.unitSeconds();
    }

    function calculateSwap(
        ICCPool pool,
        uint256 amount,
        bool baseAssetIn,
        bool out
    ) public view returns (uint256) {
        poolDetails memory poolInfo = getPoolDetails(pool);
        uint256 baseReserves = _normalize(
            poolInfo.baseReserves,
            poolInfo.tokenDecimals,
            18
        );
        uint256 bondReserves = _normalize(
            poolInfo.bondReserves,
            poolInfo.tokenDecimals,
            18
        ) + poolInfo.totalSupply;

        uint256 xReserves = baseAssetIn ? baseReserves : bondReserves;
        uint256 yReserves = baseAssetIn ? bondReserves : baseReserves;

        // get 1 - t
        uint256 a = getYieldExponent(poolInfo.expiration, poolInfo.unitSeconds);

        if (out) {
            uint256 quote = solveTradeInvariant(
                amount,
                xReserves,
                yReserves,
                a,
                out
            );
            quote = _normalize(quote, 18, poolInfo.tokenDecimals);
            return quote;
        } else {
            uint256 quote = solveTradeInvariant(
                amount,
                yReserves,
                xReserves,
                a,
                out
            );
            quote = _normalize(quote, 18, poolInfo.tokenDecimals);
            return quote;
        }
    }

    /// @dev Calculates 1 - t
    /// @return Returns 1 - t, encoded as a fraction in 18 decimal fixed point
    function getYieldExponent(uint256 expiration, uint256 unitSeconds)
        public
        view
        virtual
        returns (uint256)
    {
        // The fractional time
        uint256 timeTillExpiry = block.timestamp < expiration
            ? expiration - block.timestamp
            : 0;
        timeTillExpiry *= 1e18;
        // timeTillExpiry now contains the a fixed point of the years remaining
        timeTillExpiry = timeTillExpiry.divDown(unitSeconds * 1e18);
        uint256 result = uint256(FixedPoint.ONE).sub(timeTillExpiry);
        // Sanity Check
        require(result != 0);
        // Return result
        return result;
    }

    /// @dev Takes an 'amount' encoded with 'decimalsBefore' decimals and
    ///      re encodes it with 'decimalsAfter' decimals
    /// @param amount The amount to normalize
    /// @param decimalsBefore The decimal encoding before
    /// @param decimalsAfter The decimal encoding after
    function _normalize(
        uint256 amount,
        uint256 decimalsBefore,
        uint256 decimalsAfter
    ) internal pure returns (uint256) {
        // If we need to increase the decimals
        if (decimalsBefore > decimalsAfter) {
            // Then we shift right the amount by the number of decimals
            amount = amount / 10**(decimalsBefore - decimalsAfter);
            // If we need to decrease the number
        } else if (decimalsBefore < decimalsAfter) {
            // then we shift left by the difference
            amount = amount * 10**(decimalsAfter - decimalsBefore);
        }
        // If nothing changed this is a no-op
        return amount;
    }

    /// @dev Calculates how many tokens should be outputted given an input plus reserve variables
    ///      Assumes all inputs are in 18 point fixed compatible with the balancer fixed math lib.
    ///      Since solving for an input is almost exactly the same as an output you can indicate
    ///      if this is an input or output calculation in the call.
    /// @param amountX The amount of token x sent in normalized to have 18 decimals
    /// @param reserveX The amount of the token x currently held by the pool normalized to 18 decimals
    /// @param reserveY The amount of the token y currently held by the pool normalized to 18 decimals
    /// @param out Is true if the pool will receive amountX and false if it is expected to produce it.
    /// @return Either if 'out' is true the amount of Y token to send to the user or
    ///         if 'out' is false the amount of Y Token to take from the user
    function solveTradeInvariant(
        uint256 amountX,
        uint256 reserveX,
        uint256 reserveY,
        uint256 a,
        bool out
    ) public pure returns (uint256) {
        // calculate x before ^ a
        uint256 xBeforePowA = LogExpMath.pow(reserveX, a);
        // calculate y before ^ a
        uint256 yBeforePowA = LogExpMath.pow(reserveY, a);
        // calculate x after ^ a
        uint256 xAfterPowA = out
            ? LogExpMath.pow(reserveX + amountX, a)
            : LogExpMath.pow(reserveX.sub(amountX), a);
        // Calculate y_after = ( x_before ^a + y_before ^a -  x_after^a)^(1/a)
        // Will revert with underflow here if the liquidity isn't enough for the trade
        uint256 yAfter = (xBeforePowA + yBeforePowA).sub(xAfterPowA);
        // Note that this call is to FixedPoint Div so works as intended
        yAfter = LogExpMath.pow(yAfter, uint256(FixedPoint.ONE).divDown(a));
        // The amount of Y token to send is (reserveY_before - reserveY_after)
        return out ? reserveY.sub(yAfter) : yAfter.sub(reserveY);
    }
}
