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
        // Load the underlying balance of contract
        uint256 amount = token.balanceOf(address(this));
        // Deposit into aave
        pool.deposit(
            address(token),
            amount,
            address(this),
            0
        );
        // Return shares minted and underlying consumed, which are equal
        return (amount, amount);
    }

    /// @notice Withdraw the number of shares
    /// @param _shares The number of shares to withdraw
    /// @param _destination The address to send the output funds
    // @param _underlyingPerShare The possibly precomputed underlying per share
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override returns (uint256) {
        // Do the withdraw and send underlying to destination directly
        uint256 amountReceived = pool.withdraw(
            address(token),
            _shares,
            _destination
        );
        return amountReceived;
    }

    /// @notice Get the underlying amount of tokens per shares given
    /// @param _amount The amount of shares you want to know the value of
    /// @return Value of shares in underlying token which is equivalent in aave
    function _underlying(uint256 _amount)
        internal
        pure
        override
        returns (uint256)
    {
        return _amount;
    }

    /// @notice Get the price per position in the contract
    /// @return The price per position in units of share
    function pricePerPosition() external view override returns (uint256) {
        // Calculate one uint of position
        uint256 oneUnit = 10**decimals;
        // Load the Wrapped Position token total supply and shares reserve of the contract
        uint256 positionSupply = totalSupply;
        // If position token supply is 0, these to assets are equivalent
        if (totalSupply == 0) {
            return oneUnit;
        } else {
            // Load shares in contract
            uint256 sharesReserve = aToken.balanceOf(address(this));
            // Calculate shares amount that one uint position token value
            uint256 _pricePerPosition = (sharesReserve * oneUnit) /
                positionSupply;
            return _pricePerPosition;
        }
    }

    /// @notice Function to reset approvals for the proxy
    function approve() external {
        token.approve(address(pool), 0);
        token.approve(address(pool), type(uint256).max);
    }

    /// @notice Get the underlying value of an address, convert position amount to
    ///     to shares first. Since 1 aave share is equivalent to 1 underlying, we return
    ///     the shares amount
    /// @param _who The address to query
    /// @return The underlying value of the address
    function balanceOfUnderlying(address _who)
        external
        view
        override
        returns (uint256)
    {
        uint256 sharesBalance = _positionConverter(balanceOf[_who], true);
        return sharesBalance;
    }

    /// @notice Converts an input of Wrapped Position tokens to it's output of shares or an input
    ///      of shares to an output of underlying, using ratio between position supply and
    ///      shares balance of contract
    /// @param amount the amount of input, Wrapped Position token if 'positionIn == true' shares if not
    /// @param positionIn true to convert from Wrapped Position tokens to shares, false to convert from
    ///                 shares to Wrapped Position tokens
    /// @return The converted output of either aave shares or Wrapped Position tokens
    function _positionConverter(uint256 amount, bool positionIn)
        internal
        view
        virtual
        returns (uint256)
    {
        // Load the Wrapped Position token total supply and shares reserve
        uint256 positionSupply = totalSupply;
        uint256 sharesReserve = aToken.balanceOf(address(this));
        // If we are converted positions to shares
        if (positionIn) {
            // then we get the fraction of position supply this is and multiply by position amount
            return (sharesReserve * amount) / positionSupply;
        } else {
            // otherwise we figure out the faction of shares this is and see how
            // many Wrapped Position tokens we get out.
            return (positionSupply * amount) / sharesReserve;
        }
    }

    /// @notice Entry point to deposit tokens into the Wrapped Position contract
    ///         Transfers tokens on behalf of caller so the caller must set
    ///         allowance on the contract prior to call.
    /// @param _amount The amount of underlying tokens to deposit
    /// @param _destination The address to mint to
    /// @return Returns the number of Wrapped Position tokens minted
    function deposit(address _destination, uint256 _amount)
        external
        override
        returns (uint256)
    {
        // Send tokens to the proxy
        token.transferFrom(msg.sender, address(this), _amount);
        // Calls our internal deposit function
        (uint256 shares, ) = _deposit();
        // Calculate the Wrapped Position token to be minted to tranche, split on
        // if this is the initialization case
        uint256 mintAmount = totalSupply == 0
            ? shares
            : _positionConverter(shares, false);

        // Mint them internal ERC20 tokens corresponding to the deposit
        _mint(_destination, mintAmount);
        return shares;
    }

    /// @notice Entry point to deposit tokens into the Wrapped Position contract
    ///         Assumes the tokens were transferred before this was called
    /// @param _destination the destination of this deposit
    /// @return Returns (WP tokens minted, used underlying,
    ///                  senders WP balance before mint)
    /// @dev WARNING - The call which funds this method MUST be in the same transaction
    //                 as the call to this method or you risk loss of funds
    function prefundedDeposit(address _destination)
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Calls our internal deposit function
        (uint256 shares, uint256 usedUnderlying) = _deposit();
        // Load the position balance
        uint256 balanceBefore = balanceOf[_destination];

        // Calculate the Wrapped Position token to mint to tranche, split on
        // if this is the initialization case
        uint256 mintAmount = totalSupply == 0
            ? shares
            : _positionConverter(shares, false);

        // Mint them internal ERC20 tokens corresponding to the deposit
        _mint(_destination, mintAmount);
        return (shares, usedUnderlying, balanceBefore);
    }

    /// @notice This function burns enough tokens from the sender to send _amount
    ///          of underlying to the _destination.
    /// @param _destination The address to send the output to
    /// @param _amount The amount of underlying to try to redeem for
    /// @param _minUnderlying The minium underlying to receive
    /// @return The amount of underlying released, and shares used
    function withdrawUnderlying(
        address _destination,
        uint256 _amount,
        uint256 _minUnderlying
    ) external override returns (uint256, uint256) {
        // Using this we call the normal withdraw function
        uint256 underlyingReceived = _positionWithdraw(
            _destination,
            _amount,
            _minUnderlying,
            0
        );
        return (underlyingReceived, _amount);
    }

    /// @notice This internal function allows the caller to provide a precomputed 'underlyingPerShare'
    ///         so that we can avoid calling it again in the internal function
    /// @param _destination The destination to send the output to
    /// @param _shares The number of shares to withdraw
    /// @param _minUnderlying The min amount of output to produce
    /// @param _underlyingPerShare The precomputed shares per underlying
    /// @return The amount of underlying released
    function _positionWithdraw(
        address _destination,
        uint256 _shares,
        uint256 _minUnderlying,
        uint256 _underlyingPerShare
    ) internal override returns (uint256) {
        // Calculate Wrapped Position tokens amount to burn
        uint256 positionAmount = _positionConverter(_shares, false);
        // Burn users Wrapped Position tokens
        _burn(msg.sender, positionAmount);

        // Withdraw shares from the vault
        uint256 withdrawAmount = _withdraw(
            _shares,
            _destination,
            _underlyingPerShare
        );

        // We revert if this call doesn't produce enough underlying
        // This security feature is useful in some edge cases
        require(withdrawAmount >= _minUnderlying, "Not enough underlying");
        return withdrawAmount;
    }

    /// @notice Get underlying price per incetive in units of underlying
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
