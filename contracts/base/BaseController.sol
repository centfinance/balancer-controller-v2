// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../lib/ManagedPoolFactory.sol";
import "./BaseUtils.sol";

abstract contract BaseController is BaseUtils {
    ManagedPoolFactory public immutable managedPoolFactory;
    address [] private _poolsUnderManagement;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedManagedPoolFactory - Managed pool contract address
     */
    constructor(address vaultAddress, address supportedManagedPoolFactory)
    BaseUtils(vaultAddress) {
        managedPoolFactory = ManagedPoolFactory(supportedManagedPoolFactory);
    }

    /**
     * @notice Create a new managed pool
     *
     * @param name - Pool name
     * @param symbol - Symbol representing the pool
     * @param tokens - Tokens in the pool
     * @param normalizedWeights - Normalized weights in the pool
     * @param assetManagers - Asset manager for the pool
     * @param swapFeePercentage - Fee applied to swaps
     * @param isSwapEnabledOnStart - Whether swaps are enabled straight away
     * @param isMustAllowlistLPs - List of LP's allowed in the pool
     * @param managementAumFeePercentage - Management Aum fee to apply
     * @param aumFeeId - Aum Fee Id
     * @param tolerance - Percentage devience 
     * @param salt - Salt used towards calculating pool address
     */
    function createPool(
        string memory name,
        string memory symbol,
        IERC20 [] memory tokens,
        uint256 [] memory normalizedWeights,
        address [] memory assetManagers,
        uint256 swapFeePercentage,
        bool isSwapEnabledOnStart,
        bool isMustAllowlistLPs,
        uint256 managementAumFeePercentage,
        uint256 aumFeeId,
        uint256 tolerance,
        bytes32 salt
    ) external onlyManager nonReentrant {
        ManagedPoolParams memory poolParams;
        poolParams.name = name;
        poolParams.symbol = symbol;
        poolParams.assetManagers = assetManagers;

        ManagedPoolSettingsParams memory poolSettingsParams;
        poolSettingsParams.tokens = tokens;
        poolSettingsParams.normalizedWeights = normalizedWeights;
        poolSettingsParams.swapFeePercentage = swapFeePercentage;
        poolSettingsParams.isSwapEnabledOnStart = isSwapEnabledOnStart;
        poolSettingsParams.isMustAllowlistLPs = isMustAllowlistLPs;
        poolSettingsParams.managementAumFeePercentage = managementAumFeePercentage;
        poolSettingsParams.aumFeeId = aumFeeId;

        address poolAddress = managedPoolFactory.create(
            poolParams,
            poolSettingsParams,
            address(this),
            salt
        );
        _poolsUnderManagement.push(poolAddress);

        managedPools [poolAddress].poolName = name;
        managedPools [poolAddress].poolSymbol = symbol;
        managedPools [poolAddress].tolerance = tolerance;
        managedPools [poolAddress].poolTokens = tokens;
    }

    /**
     * @notice returns a list of pools under management by this controller
     *
     */
    function getPoolsUnderManagement() public view returns (address [] memory) {
        return _poolsUnderManagement;
    }

    /**
     * @notice Schedule a gradual swap fee update.
     * @dev The swap fee will change from the given starting value (which may or may not be the current
     * value) to the given ending fee percentage, over startTime to endTime.
     *
     * Note that calling this with a starting swap fee different from the current value will immediately change the
     * current swap fee to `startSwapFeePercentage`, before commencing the gradual change at `startTime`.
     * Emits the GradualSwapFeeUpdateScheduled event.
     * This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param startTime - The timestamp when the swap fee change will begin.
     * @param endTime - The timestamp when the swap fee change will end (must be >= startTime).
     * @param startSwapFeePercentage - The starting value for the swap fee change.
     * @param endSwapFeePercentage - The ending value for the swap fee change. If the current timestamp >= endTime,
     * `getSwapFeePercentage()` will return this value.
     */
    function updateSwapFeeGradually(
        address poolAddress,
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.updateSwapFeeGradually(
            startTime,
            endTime,
            startSwapFeePercentage,
            endSwapFeePercentage
        );
    }

    /**
     * @notice Schedule a gradual weight change.
     * @dev The weights will change from their current values to the given endWeights, over startTime to endTime.
     * This is a permissioned function.
     *
     * Since, unlike with swap fee updates, we generally do not want to allow instantaneous weight changes,
     * the weights always start from their current values. This also guarantees a smooth transition when
     * updateWeightsGradually is called during an ongoing weight change.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param startTime - The timestamp when the weight change will begin.
     * @param endTime - The timestamp when the weight change will end (can be >= startTime).
     * @param tokens - The tokens associated with the target weights (must match the current pool tokens).
     * @param endWeights - The target weights. If the current timestamp >= endTime, `getNormalizedWeights()`
     * will return these values.
     */
    function updateWeightsGradually(
        address poolAddress,
        uint256 startTime,
        uint256 endTime,
        IERC20 [] memory tokens,
        uint256 [] memory endWeights
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.updateWeightsGradually(
            startTime,
            endTime,
            tokens,
            endWeights
        );
    }

    /**
     * @notice Returns the pools Id
     *
     * @param poolAddress - Pool to get the Id for
     */
    function getPoolId(address poolAddress) public view returns (bytes32) {
        return IManagedPool(poolAddress).getPoolId();
    }

    /**
     * @notice Enable or disable joins and exits. Note that this does not affect Recovery Mode exits.
     * @dev Emits the JoinExitEnabledSet event. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param isJoinExitEnabled - The new value of the join/exit enabled flag.
     */
    function setJoinExitEnabled(
        address poolAddress,
        bool isJoinExitEnabled
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.setJoinExitEnabled(isJoinExitEnabled);
    }

    /**
     * @notice Returns the whether swapping is enabled for pool
     *
     * @param poolAddress - Pool to get the swap state for
     */
    function getSwapEnabled(address poolAddress) external view returns (bool) {
        return IManagedPool(poolAddress).getSwapEnabled();
    }

    /**
     * @notice Enable or disable trading.
     * @dev Emits the SwapEnabledSet event. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param isSwapEnabled - The new value of the swap enabled flag.
     */
    function setSwapEnabled(
        address poolAddress,
        bool isSwapEnabled
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.setSwapEnabled(isSwapEnabled);
    }

    /**
     * @notice Enable or disable the LP allowlist.
     * @dev Note that any addresses added to the allowlist will be retained if the allowlist is toggled off and
     * back on again, because this action does not affect the list of LP addresses.
     * Emits the MustAllowlistLPsSet event. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param isMustAllowlistLPs - The new value of the mustAllowlistLPs flag.
     */
    function setMustAllowlistLPs(
        address poolAddress,
        bool isMustAllowlistLPs
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.setMustAllowlistLPs(isMustAllowlistLPs);
    }

    /**
     * @notice Adds an address to the LP allowlist.
     * @dev Will fail if the address is already allowlisted.
     * Emits the AllowlistAddressAdded event. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param member - The address to be added to the allowlist.
     */
    function addAllowedAddress(
        address poolAddress,
        address member
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.addAllowedAddress(member);
    }

    /**
     * @notice Removes an address from the _poolAddress - Address of pool being worked on.
     *
     * @param poolAddress - Pool address being worked on
     * @param member - The address to be removed from the allowlist.
     */
    function removeAllowedAddress(
        address poolAddress,
        address member
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.removeAllowedAddress(member);
    }

    /**
     * @notice Collect any accrued AUM fees and send them to the pool manager.
     * @dev This can be called by anyone to collect accrued AUM fees - and will be called automatically
     * whenever the supply changes (e.g., joins and exits, add and remove token), and before the fee
     * percentage is changed by the manager, to prevent fees from being applied retroactively.
     *
     * @param poolAddress - Address of pool being worked on.
     */
    function collectAumManagementFees(
        address poolAddress
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.collectAumManagementFees();
    }

    /**
     * @notice Setter for the yearly percentage AUM management fee, which is payable to the pool manager.
     * @dev Attempting to collect AUM fees in excess of the maximum permitted percentage will revert.
     * To avoid retroactive fee increases, we force collection at the current fee percentage before processing
     * the update. Emits the ManagementAumFeePercentageChanged event. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param managementAumFeePercentage - The new management AUM fee percentage.
     */
    function setManagementAumFeePercentage(
        address poolAddress,
        uint256 managementAumFeePercentage
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.setManagementAumFeePercentage(managementAumFeePercentage);
    }

    /**
     * @notice Set a circuit breaker for one or more tokens.
     * @dev This is a permissioned function. The lower and upper bounds are percentages, corresponding to a
     * relative change in the token's spot price: e.g., a lower bound of 0.8 means the breaker should prevent
     * trades that result in the value of the token dropping 20% or more relative to the rest of the pool.
     *
     * @param poolAddress - Pool to have a circruit breaker set
     * @param tokens - Tokens in the pool
     * @param bptPrices - Token prices to for the circuit breaker
     * @param lowerBoundPercentages - The lower limit to trigger the circuit breaker
     * @param upperBoundPercentages - The upper limit to trigger the circuit breaker
     */
    function setCircuitBreakers(
        address poolAddress,
        IERC20 [] memory tokens,
        uint256 [] memory bptPrices,
        uint256 [] memory lowerBoundPercentages,
        uint256 [] memory upperBoundPercentages
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.setCircuitBreakers(
            tokens,
            bptPrices,
            lowerBoundPercentages,
            upperBoundPercentages
        );
    }

    /**
     * @notice Adds a token to the Pool's list of tradeable tokens. This is a permissioned function.
     *
     * @dev By adding a token to the Pool's composition, the weights of all other tokens will be decreased. The new
     * token will have no balance - it is up to the owner to provide some immediately after calling this function.
     * Note however that regular join functions will not work while the new token has no balance: the only way to
     * deposit an initial amount is by using an Asset Manager.
     *
     * Token addition is forbidden during a weight change, or if one is scheduled to happen in the future.
     *
     * The caller may additionally pass a non-zero `mintAmount` to have some BPT be minted for them, which might be
     * useful in some scenarios to account for the fact that the Pool will have more tokens.
     *
     * Emits the TokenAdded event.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param tokenToAdd - The ERC20 token to be added to the Pool.
     * @param assetManager - The Asset Manager for the token.
     * @param tokenToAddNormalizedWeight - The normalized weight of `token` relative to the other tokens in the Pool.
     * @param mintAmount - The amount of BPT to be minted as a result of adding `token` to the Pool.
     * @param recipient - The address to receive the BPT minted by the Pool.
     */
    function addToken(
        address poolAddress,
        IERC20 tokenToAdd,
        address assetManager,
        uint256 tokenToAddNormalizedWeight,
        uint256 mintAmount,
        address recipient
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.addToken(
            tokenToAdd,
            assetManager,
            tokenToAddNormalizedWeight,
            mintAmount,
            recipient
        );
    }

    /**
     * @notice Removes a token from the Pool's list of tradeable tokens.
     * @dev Tokens can only be removed if the Pool has more than 2 tokens, as it can never have fewer than 2 (not
     * including BPT). Token removal is also forbidden during a weight change, or if one is scheduled to happen in
     * the future.
     *
     * Emits the TokenRemoved event. This is a permissioned function.
     *
     * The caller may additionally pass a non-zero `burnAmount` to burn some of their BPT, which might be useful
     * in some scenarios to account for the fact that the Pool now has fewer tokens. This is a permissioned function.
     *
     * @param poolAddress - Address of pool being worked on.
     * @param tokenToRemove - The ERC20 token to be removed from the Pool.
     * @param burnAmount - The amount of BPT to be burned after removing `token` from the Pool.
     * @param sender - The address to burn BPT from.
     */
    function removeToken(
        address poolAddress,
        IERC20 tokenToRemove,
        uint256 burnAmount,
        address sender
    ) external onlyManager nonReentrant {
        IManagedPool managedPool;
        managedPool = IManagedPool(poolAddress);
        managedPool.removeToken(tokenToRemove, burnAmount, sender);
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
    ) external onlyManager nonReentrant {
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
    ) external onlyManager nonReentrant checkAllowance(amount, tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);
    }
}
