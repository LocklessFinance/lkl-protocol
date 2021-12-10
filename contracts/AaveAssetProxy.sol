// SPDX-License-Identifier: Apache-2.0
// WARNING: This has been validated for yearn vaults up to version 0.3.5.
// Using this code with any later version can be unsafe.
pragma solidity ^0.8.0;

import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IAaveIncentivesController.sol";
import "./WrappedPosition.sol";

/// @author Lockless Finance
/// @title Aave asset proxy
contract AaveAssetProxy is WrappedPosition {
    uint8 public immutable underlyingDecimals;
    // The aave lendingPool contract
    ILendingPool public immutable pool;
    // The aave IncentivesController contract
    IAaveIncentivesController public immutable IncentivesController;
    // Constant aave token address
    IERC20 public immutable aToken;
    // Chainlink price feed contracts
    AggregatorV3Interface public immutable underlyingFeed;
    AggregatorV3Interface public immutable incentiveFeed;
    // Deposited underlying amount
    uint256 public depositedAmount;
    // Total shares
    uint256 public shareSupply;
    // Total incentive shares
    uint256 public incentiveSupply;
    // Record incentive balance of each tranche
    mapping(address => uint256) public incentiveBalance;

    /// @notice Constructs this contract and stores needed data
    /// @param _pool The aave lendingPool
    /// @param _incentivesController The aave IncentivesController
    /// @param _underlyingFeed The chainlink underlying price feed address
    /// @param _incentiveFeed The chainlink incentive token price feed address
    /// @param _token The underlying token.
    ///               This token should revert in the event of a transfer failure.
    /// @param _aToken The aave share token
    /// @param _name The name of the token created
    /// @param _symbol The symbol of the token created
    constructor(
        address _pool,
        address _incentivesController,
        address _underlyingFeed,
        address _incentiveFeed,
        IERC20 _token,
        IERC20 _aToken,
        string memory _name,
        string memory _symbol
    ) WrappedPosition(_token, _name, _symbol) {
        pool = ILendingPool(_pool);
        IncentivesController = IAaveIncentivesController(_incentivesController);
        underlyingFeed = AggregatorV3Interface(_underlyingFeed);
        incentiveFeed = AggregatorV3Interface(_incentiveFeed);
        // Set approval for the proxy
        _token.approve(_pool, type(uint256).max);
        aToken = _aToken;
        uint8 localUnderlyingDecimals = _aToken.decimals();
        underlyingDecimals = localUnderlyingDecimals;
        require(
            uint8(_token.decimals()) == localUnderlyingDecimals,
            "Inconsistent decimals"
        );
    }

    /// @notice Makes the actual deposit into the aave lending pool
    /// @return Tuple (the shares minted, amount underlying used)
    function _deposit() internal override returns (uint256, uint256) {
        /* 1. Load deposited underlying amount
           2. Load toatal assets held by this contract including incentive rewards
           3. Perform the actual deposit into aave and receive equal aTokens
           4. Convert aToken amount to shares by following equation:
                newShares / totalShares =  depositAmount / totalValue
           5. Accumulate deposited underlying amount
           6. Return share minted and underlying consumed
           */
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override returns (uint256, uint256) {
        /*  1. Convert share amount to aToken amount and deposited amount
            2. Decrease deposited underlying amount and corresponding shares
            3. Perform withdraw from aave
            4. If it's the first withdrawal of this tranche, withdraw all rewards from
                aave incentives controller
            4. Return received underlying amount and reward amount
            */
    }

    /// @notice We seprate share value into underlying and Matic incentives
    ///     Get the underlying amount of tokens per shares given
    /// @param _amount The amount of shares you want to know the value of
    /// @return Value of shares in underlying token
    function _underlying(uint256 _amount)
        internal
        view
        override
        returns (uint256)
    {
        return ((aToken.balanceOf(address(this)) * _amount) / shareSupply);
    }

    function _withdrawRewards(uint256 amount, address to)
        internal
        returns (uint256)
    {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        uint256 incentiveReceived = IncentivesController.claimRewards(
            assets,
            amount,
            to
        );
        return incentiveReceived;
    }

    // Get incentive rewards held by this contract
    function _getIncentiveRewards() internal view returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        // First we get total incentive amount of this contract
        uint256 incentiveAmount = IncentivesController.getRewardsBalance(
            assets,
            address(this)
        );
        return incentiveAmount;
    }

    /// @notice We seprate share value into underlying and Matic incentives,
    /// and we get rewards value here
    function _getRewardsInUnderlying() internal view returns (uint256) {
        uint256 incentiveAmount = _getIncentiveRewards();
        // Convert rewards to underlying
        uint256 rewardsInUnderlying = (incentiveAmount * _getDerivedPrice()) /
            (10**underlyingDecimals);
        return rewardsInUnderlying;
    }

    /// @notice Get underlying price per incentive in units of underlying
    function _getDerivedPrice() internal view returns (uint256) {
        int256 decimals = int256(10**uint256(underlyingDecimals));
        (, int256 underlyingPrice, , , ) = underlyingFeed.latestRoundData();
        uint8 underlyingPriceDecimals = underlyingFeed.decimals();
        underlyingPrice = _scalePrice(
            underlyingPrice,
            underlyingPriceDecimals,
            underlyingDecimals
        );

        (, int256 incentivePrice, , , ) = incentiveFeed.latestRoundData();
        uint8 incentivePriceDecimals = underlyingFeed.decimals();
        incentivePrice = _scalePrice(
            incentivePrice,
            incentivePriceDecimals,
            underlyingDecimals
        );

        return uint256((underlyingPrice * decimals) / incentivePrice);
    }

    function _scalePrice(
        int256 _price,
        uint8 _priceDecimals,
        uint8 _decimals
    ) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10**uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10**uint256(_priceDecimals - _decimals));
        }
        return _price;
    }
}
