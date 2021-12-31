// SPDX-License-Identifier: Apache-2.0
// WARNING: This has been validated for AaveIncentivesController revision 1
//  and Aave lending pool revision 2.
// Using this code with any other version can be unsafe.
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

        // We use local because immutables are not readable in construction
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
        // Load the total value of this contract
        uint256 holdings = aToken.balanceOf(address(this)) +
            getRewardsInUnderlying();
        // Calculate shares amount per underlying
        uint256 sharePerHolding = holdings == 0
            ? (10**underlyingDecimals)
            : (shareSupply * (10**underlyingDecimals)) / holdings;

        // Load the underlying balance of contract and deposit them to aava
        // We get aTokens as the same amount as underlying
        uint256 amount = token.balanceOf(address(this));
        pool.deposit(address(token), amount, address(this), 0);

        // Calculate shares to mint
        uint256 newShares = (amount * sharePerHolding) /
            (10**underlyingDecimals);
        // Increase deposited amount and share supply
        depositedAmount += amount;
        shareSupply += newShares;
        // Accumulate incentive shares for msg.sender. Incentive rewards will be
        // allocated depending on their incentiveBalance. Pay attention if msg.sender
        // is not the same address with _destination
        incentiveSupply += newShares;
        incentiveBalance[msg.sender] += newShares;
        // Return the amount of shares the user has produced, and the amount used for it.
        return (newShares, amount);
    }

    /// @notice Withdraw the number of shares, if it's the first withdrawal, we
    /// claim all the incentive rewards
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override returns (uint256, uint256) {
        // Convert share amount to aToken amount and deposited amount
        uint256 amount = _underlying(_shares);
        uint256 underlyingAmount = (depositedAmount * _shares) / shareSupply;

        // Decrease share supply and deposited amount
        depositedAmount -= underlyingAmount;
        shareSupply -= _shares;

        // Perform the withdrawal and send underlying to destination directly
        uint256 amountReceived = pool.withdraw(
            address(token),
            amount,
            _destination
        );

        // We claim all the incentive rewards for the first withdrawal and send them
        // to msg.sender
        uint256 rewardAmount = _withdrawRewards();

        // Return underlying received and rewards claimed
        return (amountReceived, rewardAmount);
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

    /// @notice Withdraw tranches's total rewards
    /// @return Rewards received
    function _withdrawRewards() internal returns (uint256) {
        uint256 _incentiveBalance = incentiveBalance[msg.sender];
        if (_incentiveBalance == 0) {
            return 0;
        }

        // Calculate rewards amount to withdraw
        uint256 amount = (_getIncentiveRewards() * _incentiveBalance) /
            incentiveSupply;
        // Set related variables
        incentiveSupply -= _incentiveBalance;
        incentiveBalance[msg.sender] -= _incentiveBalance;

        // Withdraw rewards from aave
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        uint256 incentiveReceived = IncentivesController.claimRewards(
            assets,
            amount,
            msg.sender
        );
        return incentiveReceived;
    }

    /// @notice Get incentive rewards held by this contract
    /// @return WMatic amount held belong to this contract
    function _getIncentiveRewards() internal view returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        uint256 incentiveAmount = IncentivesController.getRewardsBalance(
            assets,
            address(this)
        );
        return incentiveAmount;
    }

    /// @notice We seprate share value into underlying and Matic incentives,
    /// and we get rewards value here
    function getRewardsInUnderlying() public view returns (uint256) {
        uint256 incentiveAmount = _getIncentiveRewards();
        // Convert rewards to underlying
        uint256 rewardsInUnderlying = (incentiveAmount * _getDerivedPrice()) /
            (10**underlyingDecimals);
        return rewardsInUnderlying;
    }

    /// @notice Get underlying price per incentive in units of underlying from chainlink
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
