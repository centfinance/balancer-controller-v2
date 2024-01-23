// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./base/BaseWeightedUtils.sol";
import "./lib/WeightedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "./lib/WeightedPoolNoAMFactory.sol";
import "./lib/ReserveToken.sol";

contract WeightedReserveController is BaseWeightedUtils {
    using SafeMath for uint256; // Use SafeMath for uint256

    uint256 private constant DECIMALS = 10 ** 18;
    address private constant RESERVE_TOKEN = 0x7d9d314Ee8183653F800e551030d0b27663A1557;

    struct TradeValues {
        IWeightedPool collateral;
        bytes32 poolId;
        int[] tokenPrices;
        uint256[] normalizedWeights;
        IERC20[] tokens;
        uint256[] balances;
        IAsset[] assets;
    }

    address[] private registeredPools;
    mapping(address => bool) private registeredPoolsMapping;
    address internal immutable weightedPoolNoAMFactory;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedWeightedPoolNoAMFactory - ManegedPoolFactory address
     */
    constructor(address vaultAddress, address supportedWeightedPoolNoAMFactory) BaseWeightedUtils(vaultAddress) {
        weightedPoolNoAMFactory = supportedWeightedPoolNoAMFactory;
    }

    /**
     * @notice returns a list of registered pools
     *
     */
    function getRegisteredPools() public view returns (address[] memory) {
        return registeredPools;
    }

    /**
     * @notice Register weighted pool
     *
     * @param weightedPool - Address of pool being worked on.
     */
    function registerWeightedPool(address weightedPool) public onlyManager {
        registeredPools.push(weightedPool);
        registeredPoolsMapping[weightedPool] = true;
    }

    /**
     * @notice Deregister weighted pool
     *
     * @param weightedPool - Address of pool being worked on.
     */
    function deRegisterWeightedPool(address weightedPool) public onlyManager {
        removeByValue(weightedPool);
        registeredPoolsMapping[weightedPool] = false;
    }

    /**
     * @notice This function is used for pools containing two tokens.
     * It takes in a collateral token such as BPT, calculates an equal
     * value amount of the reserve token such as G$ then mints and returns it.
     *
     * @param tokenIn - Address of collateral token
     * @param amountIn - The amount being traded
     * @param recipient - Address of person to receive the reserve tokens
     */
    function buyReserveToken(
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) public nonReentrant checkPoolSupported(tokenIn) {
        IWeightedPool collateral = IWeightedPool(tokenIn);
        IERC20 collateralToken = IERC20(tokenIn);

        // Calculate the buyer's share of the pool
        uint256 totalSupply = collateralToken.totalSupply();

        // Ensure that totalSupply is not zero to prevent division by zero
        require(totalSupply > 0, "Invalid pool total supply");

        uint256 buyersShare = amountIn.mul(DECIMALS).div(totalSupply);

        // Calculate total value of the pool
        uint256 totalPoolValue = getPoolValue(collateral);

        // Calculate supplied token value
        uint256 buyersShareValue = buyersShare.mul(totalPoolValue).div(DECIMALS);

        require(collateralToken.transferFrom(msg.sender, address(this), amountIn), "Transfer of input tokens failed");

        // Mint and Transfer the output tokens from this contract to the recipient
        ReserveToken(RESERVE_TOKEN).mint(recipient, buyersShareValue);

        emit BoughtReserveToken(msg.sender, tokenIn, amountIn, buyersShareValue);
    }

    function getPoolValue(IWeightedPool collateral) internal view returns (uint256) {
        bytes32 poolId = collateral.getPoolId();
        (IERC20[] memory tokens, uint256[] memory balances, ) = vault.getPoolTokens(poolId);

        uint256 totalValue = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (balances[i] > 0) {
                int price = getTokenPrice(address(tokens[i]));
                totalValue = totalValue.add(balances[i].mul(uint256(price)).div(10 ** 10)); // Adjusting for 8 decimals of price
            }
        }
        return totalValue;
    }

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param pool - Address of collateral token
     * @param amountIn - The amount being traded
     * @param recipient - Address of person to receive the swapped tokens
     */
    function sellReserveToken(
        address pool,
        uint256 amountIn,
        address recipient
    ) public nonReentrant checkPoolSupported(pool) {
        IERC20 bptToken = IERC20(pool);

        uint256 totalSupply = bptToken.totalSupply();

        // Ensure totalSupply is not zero to prevent division by zero
        require(totalSupply > 0, "Invalid pool total supply");

        // Calculate user's proportionate share in the pool
        uint256 myShare = amountIn.mul(DECIMALS).div(totalSupply);
        uint256 myBptAmount = myShare.mul(totalSupply).div(DECIMALS);

        IERC20 reserveToken = IERC20(RESERVE_TOKEN);
        require(reserveToken.transferFrom(msg.sender, address(this), amountIn), "Transfer of input tokens failed");

        // Transfer BPT tokens from this contract to the recipient
        bptToken.transfer(recipient, myBptAmount);

        emit SoldReserveToken(msg.sender, pool, amountIn, myBptAmount);
    }

    /**
     * @notice returns the array index containing supplied address
     *
     * @param value - Address to find
     */
    function find(address value) private view returns (uint) {
        for (uint i = 0; i < registeredPools.length; i++) {
            if (registeredPools[i] == value) {
                return i;
            }
        }

        return registeredPools.length;
    }

    /**
     * @notice removes supplied address from array of addresses
     *
     * @param value - Address to look up and remove element
     */
    function removeByValue(address value) private {
        registeredPoolsMapping[value] = false;
        uint i = find(value);
        removeByIndex(i);
    }

    /**
     * @notice remove the item at index, resizing array as needed
     *
     * @param i - Index to remove
     */
    function removeByIndex(uint i) private {
        while (i < registeredPools.length - 1) {
            registeredPools[i] = registeredPools[i + 1];
            i++;
        }
        registeredPools.pop();
    }

    event BoughtReserveToken(address indexed buyer, address indexed tokenIn, uint256 amountIn, uint256 reserveTokenOut);
    event SoldReserveToken(address indexed seller, address indexed pool, uint256 amountIn, uint256 bptOut);

    /**
     * @dev Modifier to check token allowance
     *
     * @param supportedWeightedPool - Weighted pool address to remove
     */
    modifier checkPoolSupported(address supportedWeightedPool) {
        require(registeredPoolsMapping[supportedWeightedPool], "Pool not registered");
        _;
    }
}
