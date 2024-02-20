// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;

import "./RateProviders.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BalancePool is RateProviders, Ownable {
    using SafeMath for uint256;

    IVault public vault;
    IManagedPool public managedPool;

    constructor(IVault _vault, IManagedPool _managedPool) {
        vault = _vault;
        managedPool = _managedPool;
    }

    /**
     * @dev Balances the pool by adjusting the liquidity of the tokens in the pool.
     * This function can only be called by the owner of the contract.
     */
    function balancePool() external onlyOwner {
        (IERC20[] memory tokens, uint256[] memory balances, uint256[] memory normalizedWeights) = managedPool
            .getPoolTokens();
        (uint256[] memory values, uint256 totalValue) = _calculateValuesAndTotalValue(tokens, balances);
        _adjustLiquidity(tokens, balances, normalizedWeights, values, totalValue);
    }

    /**
     * @dev Calculates the external values of the tokens in the pool and the total external value.
     * The external value of a token is its price multiplied by its upscaled balance.
     * The total external value is the sum of the external values of all tokens.
     * @param tokens The tokens in the pool.
     * @param balances The balances of the tokens in the pool.
     * @return values The external values of the tokens.
     * @return totalValue The total external value.
     */
    function _calculateValuesAndTotalValue(
        IERC20[] memory tokens,
        uint256[] memory balances
    ) internal view returns (uint256[] memory values, uint256 totalValue) {
        values = new uint256[](tokens.length);
        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 scale = 10 ** (18 - tokens[i].decimals());
            uint256 upscaledBalance = balances[i].mul(scale);
            values[i] = getPrice(tokens[i]).mul(upscaledBalance);
            totalValue = totalValue.add(values[i]);
        }
        return (values, totalValue);
    }

    /**
     * @dev Adjusts the liquidity of the pool based on the external and normalized weights of the tokens.
     * If the external weight of a token is greater than its normalized weight, it adds liquidity to the pool.
     * If the external weight of a token is less than its normalized weight, it removes liquidity from the pool.
     * The sender for joinPool is the reserve wallet and the recipient for exitPool is the reserve wallet.
     * @param tokens The tokens in the pool.
     * @param balances The balances of the tokens in the pool.
     * @param normalizedWeights The normalized weights of the tokens in the pool.
     * @param values The external values of the tokens.
     * @param totalValue The total external value.
     */
    function _adjustLiquidity(
        IERC20[] memory tokens,
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory values,
        uint256 totalValue
    ) internal {
        IVault.JoinPoolRequest memory joinRequest;
        IVault.ExitPoolRequest memory exitRequest;

        joinRequest.assets = tokens;
        joinRequest.maxAmountsIn = new uint256[](tokens.length);
        joinRequest.fromInternalBalance = true;

        exitRequest.assets = tokens;
        exitRequest.minAmountsOut = new uint256[](tokens.length);
        exitRequest.toInternalBalance = true;

        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 externalWeight = values[i].mul(1e18).div(totalValue); // external weight as a fraction of total value
            uint256 normalizedWeight = normalizedWeights[i];

            if (externalWeight > normalizedWeight) {
                // Add liquidity
                uint256 weightDifference = externalWeight.sub(normalizedWeight);
                uint256 amount = balances[i].mul(weightDifference).div(1e18);
                joinRequest.maxAmountsIn[i] = amount;
            } else if (externalWeight < normalizedWeight) {
                // Remove liquidity
                uint256 weightDifference = normalizedWeight.sub(externalWeight);
                uint256 amount = balances[i].mul(weightDifference).div(1e18);
                exitRequest.minAmountsOut[i] = amount;
            }
        }

        joinRequest.userData = abi.encode(IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, joinRequest.maxAmountsIn, 0);
        exitRequest.userData = abi.encode(IVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, exitRequest.minAmountsOut, 0);

        vault.joinPool(managedPool.getPoolId(), address(this), address(this), joinRequest);
        vault.exitPool(managedPool.getPoolId(), address(this), address(this), exitRequest);
    }

    /**
     * @dev Adds the specified amount of a token to the contract's internal balance on the vault.
     * The token is transferred from the reserve wallet to the contract before being added to the internal balance.
     * Only the owner of the contract can call this function.
     * @param token The token to add.
     * @param amount The amount of the token to add.
     */
    function addTokenToInternalBalance(IERC20 token, uint256 amount) external onlyOwner {
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        IVault.UserBalanceOp[] memory ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({
            asset: IAsset(address(token)),
            amount: amount,
            sender: address(this),
            recipient: address(this),
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL
        });

        vault.manageUserBalance(ops);
    }

    /**
     * @dev Removes the specified amount of a token from the contract's internal balance on the vault.
     * The token is transferred from the contract to the reserve wallet after being removed from the internal balance.
     * Only the owner of the contract can call this function.
     * @param token The token to remove.
     * @param amount The amount of the token to remove.
     */
    function removeTokenFromInternalBalance(IERC20 token, uint256 amount) external onlyOwner {
        IVault.UserBalanceOp[] memory ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({
            asset: IAsset(address(token)),
            amount: amount,
            sender: address(this),
            recipient: address(this),
            kind: IVault.UserBalanceOpKind.WITHDRAW_INTERNAL
        });

        vault.manageUserBalance(ops);
        require(token.transfer(msg.sender, amount), "Transfer failed");
    }
}
