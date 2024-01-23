// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../lib/WeightedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/SupportLib.sol";

struct PoolSettings {
    string poolName;
    string poolSymbol;
    uint256 tolerance;
    address[] poolTokens;
}

struct PoolAdjustments {
    IVault.ExitPoolRequest newExitRequest;
    IVault.JoinPoolRequest newJoinRequest;
    uint256 poolTolerance;
}

struct PoolAdjustmentValues {
    uint256[] referenceNormalizedWeights;
    int256[] priceDeltas;
    uint256[] oraclePrices;
    uint256[] oracleReferencePrices;
    uint256[] tokenBalancesToAdd;
    uint256[] tokenBalancesToRemove;
    uint256[] poolTokenPrices;
}

abstract contract BaseWeightedUtils is ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    uint256 private constant PERCENTAGE_DENOMINATOR = 100;
    mapping(address => PoolSettings) public weightedPools; // Pools and their prices
    mapping(address => bool) public isManager; // Managers that can call special functions
    mapping(address => address) public tokenFeeds; // Token mappings from oracle
    mapping(IERC20 => uint256) private internalPoolPrice;
    mapping(IERC20 => uint256) private oraclePoolPrice;
    address private referencePoolAddress = 0x5772a773b3779b373Bf11d1070F39569f50d37d3;
    address private stableTokenAddress = 0xef4229c8c3250C675F21BCefa42f58EfbfF6002a;
    address private constant wbtcAddress = 0xBAAB46E28388d2779e6E31Fd00cF0e5Ad95E327B;
    uint private constant ORACLE_DECIMAL_PLACES = 10000000000;
    uint private constant WBTC_ORACLE_DECIMAL_PLACES = 100000000000000000000;

    IVault internal immutable vault;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     */
    constructor(address vaultAddress) {
        vault = IVault(vaultAddress);
        isManager[msg.sender] = true;

        // set up the token price feed mapping
        tokenFeeds[0xBAAB46E28388d2779e6E31Fd00cF0e5Ad95E327B] = 0x128fE88eaa22bFFb868Bb3A584A54C96eE24014b; // WBTCv2
        tokenFeeds[0x471EcE3750Da237f93B8E339c536989b8978a438] = 0x0568fD19986748cEfF3301e55c0eb1E729E0Ab7e; // CELO
        tokenFeeds[0x122013fd7dF1C6F636a5bb8f03108E876548b455] = 0x1FcD30A73D67639c1cD89ff5746E7585731c083B; // WETHv2
        tokenFeeds[0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73] = 0x3D207061Dbe8E2473527611BFecB87Ff12b28dDa; // CEUR
        //   tokenFeeds[0x72d7f41eF46a988b13530F67423B36CD9cADBc3a] = 0x6b6a4c71ec3858A024f3f0Ee44bb0AdcBEd3DcC2; // LINK
        //   tokenFeeds[0x2A3684e9Dc20B857375EA04235F2F7edBe818FA7] = 0xc7A353BaE210aed958a1A2928b654938EC59DaB2; // USDC
        tokenFeeds[0xef4229c8c3250C675F21BCefa42f58EfbfF6002a] = 0xc7A353BaE210aed958a1A2928b654938EC59DaB2; // USDC
        //  tokenFeeds[0xf6D198Cd2A85bB2F3021cDBDAb6B878474079Be7] = 0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02; // USDT
        tokenFeeds[0x765DE816845861e75A25fCA122bb6898B8B1282a] = 0xc7A353BaE210aed958a1A2928b654938EC59DaB2; // CUSD (Mapped to USDC so beware!)
    }

    /**
     * @notice Set a new token oracle feed
     *
     * @param token - Token address
     * @param feed - Oracle feed address
     */
    function setTokenFeed(address token, address feed) external onlyManager {
        tokenFeeds[token] = feed;
    }

    /**
     * @notice Set a new token oracle feed
     *
     * @param poolAddress - Reference pool address
     */
    function setReferencePool(address poolAddress) external onlyManager {
        referencePoolAddress = poolAddress;
    }

    /**
     * @notice Set a new token oracle feed
     *
     * @param stableToken - Stable token address
     */
    function setStableToken(address stableToken) external onlyManager {
        stableTokenAddress = stableToken;
    }

    /**
     * @notice Add a new manager to the collection of managers
     *
     * @param manager - Manager to add
     */
    function addManager(address manager) external onlyManager {
        require(manager != address(0), "Invalid address");
        require(!isManager[manager], "Address is already a manager");
        isManager[manager] = true;
    }

    /**
     * @notice Remove a manager to the collection of managers
     *
     * @param manager - Manager to remove
     */
    function removeManager(address manager) external onlyManager {
        require(isManager[manager], "Address isn't a manager");
        isManager[manager] = false;
    }

    /**
     * @notice returns the oracle supplied price for the requested token
     *
     * @param tokenAddress - Token to find a price for
     */
    function getTokenPrice(address tokenAddress) public view returns (int) {
        address feedAddress = tokenFeeds[tokenAddress];
        require(feedAddress != address(0), "Token not supported");

        AggregatorV3Interface dataFeed = AggregatorV3Interface(feedAddress);
        (, int tokenPrice, , , ) = dataFeed.latestRoundData();

        return tokenPrice;
    }

    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            // Uppercase character...
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                // So we add 32 to make it lowercase
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }

    /**
     * @notice Calculates a number of tokens to add or remove to rebalance pricing
     *
     * @param poolAddress - Address of pool being worked on.
     */
    function calculateBalancing(address poolAddress) public onlyManager whenNotPaused returns (PoolAdjustments memory) {
        IWeightedPool weightedPool = IWeightedPool(poolAddress);
        bytes32 poolId = weightedPool.getPoolId();

        IWeightedPool referencePool = IWeightedPool(referencePoolAddress);
        bytes32 referencePoolCallId = referencePool.getPoolId();

        (IERC20[] memory tokens, uint256[] memory balances, ) = vault.getPoolTokens(poolId);
        (IERC20[] memory referenceTokens, uint256[] memory referenceBalances, ) = vault.getPoolTokens(
            referencePoolCallId
        );

        PoolAdjustmentValues memory poolAdjustmentValues;

        poolAdjustmentValues.referenceNormalizedWeights = referencePool.getNormalizedWeights();
        poolAdjustmentValues.oraclePrices = new uint256[](tokens.length);
        poolAdjustmentValues.oracleReferencePrices = new uint256[](referenceTokens.length);
        poolAdjustmentValues.priceDeltas = new int256[](tokens.length);
        poolAdjustmentValues.poolTokenPrices = new uint256[](referenceTokens.length);

        // Get oracle prices for all tokens in pool
        for (uint256 i = 0; i < tokens.length; i++) {
            poolAdjustmentValues.oraclePrices[i] = uint256(getTokenPrice(address(tokens[i])));
        }

        // Get oracle prices for all tokens in reference pool
        for (uint256 i = 0; i < referenceTokens.length; i++) {
            poolAdjustmentValues.oracleReferencePrices[i] = uint256(getTokenPrice(address(referenceTokens[i])));
        }

        // Get internal prices for all
        for (uint256 i = 0; i < referenceTokens.length; i++) {
            if (address(referenceTokens[i]) != stableTokenAddress) {
                uint256 referencePoolTokenPrice = 1;
                uint256 referencePoolTokenPrice1 = 1;
                uint256 referencePoolTokenPrice2 = 1;

                if (referenceBalances[i] > 0) {
                    referencePoolTokenPrice1 = referenceBalances[i].mul(
                        poolAdjustmentValues.referenceNormalizedWeights[i]
                    );
                    referencePoolTokenPrice2 = referenceBalances[2].mul(1000000000000000000).mul(
                        poolAdjustmentValues.referenceNormalizedWeights[2]
                    );
                    referencePoolTokenPrice = referencePoolTokenPrice2.div(referencePoolTokenPrice1);
                }

                if (address(referenceTokens[i]) != wbtcAddress) {
                    referencePoolTokenPrice = referencePoolTokenPrice / ORACLE_DECIMAL_PLACES;
                } else {
                    referencePoolTokenPrice = referencePoolTokenPrice / WBTC_ORACLE_DECIMAL_PLACES;
                }
                internalPoolPrice[referenceTokens[i]] = referencePoolTokenPrice;
                oraclePoolPrice[referenceTokens[i]] = poolAdjustmentValues.oracleReferencePrices[i];
            } else {
                internalPoolPrice[referenceTokens[i]] = 1;
                oraclePoolPrice[referenceTokens[i]] = 1;
            }

            poolAdjustmentValues.poolTokenPrices[i] = internalPoolPrice[referenceTokens[i]];
        }

        for (uint256 i = 1; i < tokens.length; i++) {
            // Handle potential underflow
            if (poolAdjustmentValues.oraclePrices[i] >= internalPoolPrice[tokens[i]]) {
                poolAdjustmentValues.priceDeltas[i] = int256(
                    oraclePoolPrice[tokens[i]].sub(internalPoolPrice[tokens[i]])
                );
            } else {
                poolAdjustmentValues.priceDeltas[i] = 0;
            }
        }

        poolAdjustmentValues.tokenBalancesToAdd = new uint256[](tokens.length);
        poolAdjustmentValues.tokenBalancesToRemove = new uint256[](tokens.length);

        PoolAdjustments memory poolAdjustments;
        bool isJoin = false;
        bool isExit = false;
        poolAdjustments.poolTolerance = weightedPools[poolAddress].tolerance;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (poolAdjustmentValues.priceDeltas[i] >= int256(poolAdjustments.poolTolerance)) {
                poolAdjustmentValues.tokenBalancesToRemove[i] = balances[i].mul(poolAdjustments.poolTolerance).div(
                    PERCENTAGE_DENOMINATOR
                );
                isExit = true;
            } else if (poolAdjustmentValues.priceDeltas[i] <= -int256(poolAdjustments.poolTolerance)) {
                poolAdjustmentValues.tokenBalancesToAdd[i] = balances[i].mul(poolAdjustments.poolTolerance).div(
                    PERCENTAGE_DENOMINATOR
                );
                isJoin = true;
            }
        }

        IAsset[] memory assets = SupportLib._convertERC20sToAssets(tokens);

        if (isExit) {
            poolAdjustments.newExitRequest = IVault.ExitPoolRequest({
                assets: assets,
                userData: "",
                toInternalBalance: true,
                minAmountsOut: poolAdjustmentValues.tokenBalancesToRemove
            });
        }

        if (isJoin) {
            poolAdjustments.newJoinRequest = IVault.JoinPoolRequest({
                assets: assets,
                userData: "",
                fromInternalBalance: true,
                maxAmountsIn: poolAdjustmentValues.tokenBalancesToAdd
            });
        }

        return poolAdjustments;
    }

    function calculateBalancingValues(
        address poolAddress
    ) public onlyManager whenNotPaused returns (PoolAdjustmentValues memory) {
        IWeightedPool weightedPool = IWeightedPool(poolAddress);
        bytes32 poolId = weightedPool.getPoolId();

        IWeightedPool referencePool = IWeightedPool(referencePoolAddress);
        bytes32 referencePoolCallId = referencePool.getPoolId();

        (IERC20[] memory tokens, uint256[] memory balances, ) = vault.getPoolTokens(poolId);
        (IERC20[] memory referenceTokens, uint256[] memory referenceBalances, ) = vault.getPoolTokens(
            referencePoolCallId
        );

        PoolAdjustmentValues memory poolAdjustmentValues;

        poolAdjustmentValues.referenceNormalizedWeights = referencePool.getNormalizedWeights();
        poolAdjustmentValues.oraclePrices = new uint256[](tokens.length);
        poolAdjustmentValues.oracleReferencePrices = new uint256[](referenceTokens.length);
        poolAdjustmentValues.priceDeltas = new int256[](tokens.length);
        poolAdjustmentValues.poolTokenPrices = new uint256[](referenceTokens.length);

        // Get oracle prices for all tokens in pool
        for (uint256 i = 0; i < tokens.length; i++) {
            poolAdjustmentValues.oraclePrices[i] = uint256(getTokenPrice(address(tokens[i])));
        }

        // Get oracle prices for all tokens in reference pool
        for (uint256 i = 0; i < referenceTokens.length; i++) {
            poolAdjustmentValues.oracleReferencePrices[i] = uint256(getTokenPrice(address(referenceTokens[i])));
        }

        // Get internal prices for all
        for (uint256 i = 0; i < referenceTokens.length; i++) {
            if (address(referenceTokens[i]) != stableTokenAddress) {
                uint256 referencePoolTokenPrice = 1;
                uint256 referencePoolTokenPrice1 = 1;
                uint256 referencePoolTokenPrice2 = 1;

                if (referenceBalances[i] > 0) {
                    referencePoolTokenPrice1 = referenceBalances[i].mul(
                        poolAdjustmentValues.referenceNormalizedWeights[i]
                    );
                    referencePoolTokenPrice2 = referenceBalances[2].mul(1000000000000000000).mul(
                        poolAdjustmentValues.referenceNormalizedWeights[2]
                    );
                    referencePoolTokenPrice = referencePoolTokenPrice2.div(referencePoolTokenPrice1);
                }

                if (address(referenceTokens[i]) != wbtcAddress) {
                    referencePoolTokenPrice = referencePoolTokenPrice / ORACLE_DECIMAL_PLACES;
                } else {
                    referencePoolTokenPrice = referencePoolTokenPrice / WBTC_ORACLE_DECIMAL_PLACES;
                }
                internalPoolPrice[referenceTokens[i]] = referencePoolTokenPrice;
                oraclePoolPrice[referenceTokens[i]] = poolAdjustmentValues.oracleReferencePrices[i];
            } else {
                internalPoolPrice[referenceTokens[i]] = 1;
                oraclePoolPrice[referenceTokens[i]] = 1;
            }

            poolAdjustmentValues.poolTokenPrices[i] = internalPoolPrice[referenceTokens[i]];
        }

        for (uint256 i = 1; i < tokens.length; i++) {
            // Handle potential underflow
            if (poolAdjustmentValues.oraclePrices[i] >= internalPoolPrice[tokens[i]]) {
                poolAdjustmentValues.priceDeltas[i] = int256(
                    oraclePoolPrice[tokens[i]].sub(internalPoolPrice[tokens[i]])
                );
            } else {
                poolAdjustmentValues.priceDeltas[i] = 0;
            }
        }

        poolAdjustmentValues.tokenBalancesToAdd = new uint256[](tokens.length);
        poolAdjustmentValues.tokenBalancesToRemove = new uint256[](tokens.length);
        PoolAdjustments memory poolAdjustments;

        bool isJoin = false;
        bool isExit = false;
        poolAdjustments.poolTolerance = weightedPools[poolAddress].tolerance;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (poolAdjustmentValues.priceDeltas[i] >= int256(poolAdjustments.poolTolerance)) {
                poolAdjustmentValues.tokenBalancesToRemove[i] = balances[i].mul(poolAdjustments.poolTolerance).div(
                    PERCENTAGE_DENOMINATOR
                );
                isExit = true;
            } else if (poolAdjustmentValues.priceDeltas[i] <= -int256(poolAdjustments.poolTolerance)) {
                poolAdjustmentValues.tokenBalancesToAdd[i] = balances[i].mul(poolAdjustments.poolTolerance).div(
                    PERCENTAGE_DENOMINATOR
                );
                isJoin = true;
            }
        }

        IAsset[] memory assets = SupportLib._convertERC20sToAssets(tokens);

        if (isExit) {
            poolAdjustments.newExitRequest = IVault.ExitPoolRequest({
                assets: assets,
                userData: "",
                toInternalBalance: true,
                minAmountsOut: poolAdjustmentValues.tokenBalancesToRemove
            });
        }

        if (isJoin) {
            poolAdjustments.newJoinRequest = IVault.JoinPoolRequest({
                assets: assets,
                userData: "",
                fromInternalBalance: true,
                maxAmountsIn: poolAdjustmentValues.tokenBalancesToAdd
            });
        }

        return poolAdjustmentValues;
    }

    /**
     * @notice Pause sensitive functions
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause sensitive functions
     */
    function unpause() external onlyManager {
        _unpause();
    }

    /**
     * @dev Modifier to restrict access to managers
     */
    modifier onlyManager() {
        require(isManager[msg.sender], "Not a manager");
        _;
    }

    /**
     * @dev Modifier to check token allowance
     *
     * @param amount - Amount that is to be transferred
     * @param tokenAddress - Collateral token to check
     */
    modifier checkAllowance(uint amount, address tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "Error");
        _;
    }
}
