// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;

import "@balancer-labs/v2-interfaces/contracts/pool-utils/IRateProvider.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RateProviders is Ownable {
    mapping(address => IRateProvider) private rateProviders;

    /**
     * @dev Adds rate providers for the specified tokens.
     * The tokens and providers arrays must have the same length.
     * The token addresses and provider addresses cannot be zero.
     * This function can only be called by the owner of the contract.
     * @param tokens The tokens to add rate providers for.
     * @param providers The rate providers to add.
     */
    function addRateProviders(IERC20[] memory tokens, IRateProvider[] memory providers) external onlyOwner {
        require(tokens.length == providers.length, "Tokens and providers arrays must have the same length");

        for (uint i = 0; i < tokens.length; i++) {
            require(address(tokens[i]) != address(0), "Token address cannot be zero");
            require(address(providers[i]) != address(0), "Provider address cannot be zero");

            rateProviders[address(tokens[i])] = providers[i];
        }
    }

    /**
     * @dev Removes the rate providers for the specified tokens.
     * The token addresses cannot be zero.
     * This function can only be called by the owner of the contract.
     * @param tokens The tokens to remove rate providers for.
     */
    function removeRateProviders(IERC20[] memory tokens) external onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            require(address(tokens[i]) != address(0), "Token address cannot be zero");

            delete rateProviders[address(tokens[i])];
        }
    }

    /**
     * @dev Returns the rate provider for the specified token.
     * @param token The token to get the rate provider for.
     * @return The rate provider for the token.
     */
    function getRateProvider(IERC20 token) public view returns (IRateProvider) {
        return rateProviders[address(token)];
    }

    /**
     * @dev Returns the price of the specified token.
     * The price is obtained by calling the getRate function of the token's rate provider.
     * The token must have a rate provider.
     * @param token The token to get the price of.
     * @return The price of the token.
     */
    function getPrice(IERC20 token) public view returns (uint256) {
        IRateProvider provider = rateProviders[address(token)];
        require(address(provider) != address(0), "No rate provider for this token");

        return provider.getRate();
    }
}
