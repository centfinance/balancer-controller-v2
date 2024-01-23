import { time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

import type { BondingCurveController } from "../../types/contracts/BondingCurveController";
import type { BondingCurveController__factory } from "../../types/factories/contracts/BondingCurveController__factory";

export async function deployLockFixture() {
  const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  const ONE_GWEI = 1_000_000_000;

  const lockedAmount = ONE_GWEI;
  const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

  // Contracts are deployed using the first signer/account by default
  const [owner, otherAccount] = await ethers.getSigners();

  const Controller = (await ethers.getContractFactory("BondingCurveController")) as BondingCurveController__factory;
  const controller = (await Controller.deploy()) as BondingCurveController;
  const lock_address = await controller.getAddress();

  return { lock, lock_address, unlockTime, lockedAmount, owner, otherAccount };
}