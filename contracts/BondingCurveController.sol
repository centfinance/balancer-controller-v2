// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./base/BaseController.sol";
import "./lib/SupportLib.sol";

contract BondingCurveController is BaseController {

    /**
     * @notice Constructor for the controller implementation class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedManagedPoolFactory - Managed pool contract address
     */
    constructor(
        address vaultAddress,
        address supportedManagedPoolFactory
    ) BaseController(vaultAddress, supportedManagedPoolFactory) {}

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param poolAddress - Address of pool being worked on.
     */
    function runCheck(address poolAddress) external onlyManager nonReentrant {
        PoolAdjustments memory poolAdjustments = calculateBalancing(poolAddress);
        
        // Boolean flags can make the code clearer and more optimized.
        bool shouldJoin = poolAdjustments.newJoinRequest.maxAmountsIn.length > 0;
        bool shouldExit = poolAdjustments.newExitRequest.minAmountsOut.length > 0;

        if (shouldJoin || shouldExit) {
            IManagedPool managedPool = IManagedPool(poolAddress);
            bytes32 poolId = managedPool.getPoolId();

            if (shouldJoin) {
                vault.joinPool(
                    poolId,
                    address(this),
                    payable(poolAddress),
                    poolAdjustments.newJoinRequest
                );
            }

            if (shouldExit) {
                vault.exitPool(
                    poolId,
                    address(this),
                    payable(poolAddress),
                    poolAdjustments.newExitRequest
                );
            }
        }
    }

}
