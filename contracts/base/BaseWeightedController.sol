// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../lib/WeightedPoolNoAMFactory.sol";
import "./BaseWeightedUtils.sol";

abstract contract BaseWeightedController is BaseWeightedUtils {
    WeightedPoolNoAMFactory public immutable weightedPoolNoAMFactory;
    address [] private _poolsUnderManagement;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedWeightedPoolFactory - Weighted pool contract address
     */
    constructor(address vaultAddress, address supportedWeightedPoolFactory)
        BaseWeightedUtils(vaultAddress) {
            weightedPoolNoAMFactory = WeightedPoolNoAMFactory(supportedWeightedPoolFactory);
    }

    /**
     * @notice Create a new weighted pool
     *
     * @param name - Pool name
     * @param symbol - Symbol representing the pool
     * @param tokens - Tokens in the pool
     * @param normalizedWeights - Normalized weights in the pool
     * @param swapFeePercentage - Fee applied to swaps
     * @param tolerance - Percentage devience
     */
    function createPool(
        string memory name,
        string memory symbol,
        address [] memory tokens,
        uint256 [] memory normalizedWeights,
        uint256 swapFeePercentage,
        uint256 tolerance
    ) external onlyManager whenNotPaused nonReentrant {
        address poolAddress = weightedPoolNoAMFactory.create(
            name,
            symbol,
            tokens,
            normalizedWeights,
            swapFeePercentage,
            address(this)
        );
        _poolsUnderManagement.push(poolAddress);

        weightedPools [poolAddress].poolName = name;
        weightedPools [poolAddress].poolSymbol = symbol;
        weightedPools [poolAddress].tolerance = tolerance;
        weightedPools [poolAddress].poolTokens = tokens;
    }

    /**
     * @notice returns a list of pools under management by this controller
     *
     */
    function getPoolsUnderManagement() external view returns (address [] memory) {
        return _poolsUnderManagement;
    }

    /**
     * @notice Returns the pools Id
     *
     * @param poolAddress - Pool to get the Id for
     */
    function getPoolId(address poolAddress) private view returns (bytes32) {
        return IWeightedPool(poolAddress).getPoolId();
    }

    /**
     * @notice Withdraw tokens from controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param recipientAddress - Address of wallet receiving funds.
     * @param tokenAddress - Address of token to be withdrawn.
     * @param amount - Amount to withdraw.
     */
    function withdrawFunds(
        address recipientAddress,
        address tokenAddress,
        uint256 amount
    ) public onlyManager nonReentrant {
        IERC20 _token = IERC20(tokenAddress);
        _token.transfer(recipientAddress, amount);
    }

    /**
     * @notice Deposit tokens to controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param amount - Amount to deposit.
     * @param tokenAddress - Address of token to be deposited.
     */
    function depositTokens(
        uint amount,
        address tokenAddress
    ) public onlyManager nonReentrant checkAllowance(amount, tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);
    }
}
