import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const VAULT = "";
const managedPoolFactory = "";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const controller = await deploy("BondingCurveController", {
    from: deployer,
    args: [VAULT, managedPoolFactory],
    log: true,
    value: "0",
  });

  console.log(`Controller contract: `, controller.address);
};
export default func;
func.id = "deploy_controller"; // id required to prevent reexecution
func.tags = ["BondingCurveController"];
