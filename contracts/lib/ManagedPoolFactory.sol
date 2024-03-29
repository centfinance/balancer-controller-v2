// SPDX-License-Identifier: UNLICENSED
// !! THIS FILE WAS AUTOGENERATED BY abi-to-sol v0.6.6. SEE SOURCE BELOW. !!
pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

interface ManagedPoolFactory {
    event FactoryDisabled();
    event PoolCreated(address indexed pool);

    function create(
        ManagedPoolParams memory params,
        ManagedPoolSettingsParams memory settingsParams,
        address owner,
        bytes32 salt
    ) external returns (address pool);

    function disable() external;

    function getActionId(bytes4 selector) external view returns (bytes32);

    function getAuthorizer() external view returns (address);

    function getCreationCode() external view returns (bytes memory);

    function getCreationCodeContracts() external view returns (address contractA, address contractB);

    function getPauseConfiguration() external view returns (uint256 pauseWindowDuration, uint256 bufferPeriodDuration);

    function getPoolVersion() external view returns (string memory);

    function getProtocolFeePercentagesProvider() external view returns (address);

    function getRecoveryModeHelper() external view returns (address);

    function getVault() external view returns (address);

    function getWeightedMath() external view returns (address);

    function isDisabled() external view returns (bool);

    function isPoolFromFactory(address pool) external view returns (bool);

    function version() external view returns (string memory);
}

struct ManagedPoolParams {
    string name;
    string symbol;
    address[] assetManagers;
}

struct ManagedPoolSettingsParams {
    IERC20[] tokens;
    uint256[] normalizedWeights;
    uint256 swapFeePercentage;
    bool isSwapEnabledOnStart;
    bool isMustAllowlistLPs;
    uint256 managementAumFeePercentage;
    uint256 aumFeeId;
}
