import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
import type { HardhatUserConfig } from "hardhat/config";
import { subtask, vars } from "hardhat/config";
import type { NetworkUserConfig } from "hardhat/types";
import path from "path";
import "solidity-coverage";

import "./tasks/accounts";
import "./tasks/lock";

// Run 'npx hardhat vars setup' to see the list of variables that need to be set

const mnemonic: string = vars.get("MNEMONIC");
// const infuraApiKey: string = vars.get("INFURA_API_KEY");

const chainIds = {
  hardhat: 31337,
  ganache: 1337,
  telos: 40,
  "telos-testnet": 41,
  celo: 42220,
  "celo-alfajores": 44787,
  gnosis: 100,
  "gnosis-testnet": 69,
};

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS, async (_, { config }, runSuper) => {
  const paths = await runSuper();
  const excludedFiles = [
    "ReserveController.sol",
    "BasePoolController.sol",
    "BondingCurveController.sol",
    "WeightedBondingCurveController.sol",
    "WeightedReserveController.sol",
    "base/BaseController.sol",
    "base/BaseUtils.sol",
    "base/BaseWeightedController.sol",
    "base/BaseWeightedUtils.sol",
    "lib/SupportLib.sol",
  ]; // Add the names of the files you want to exclude

  return paths.filter((solidityFilePath: string) => {
    const relativePath = path.relative(config.paths.sources, solidityFilePath);
    return !excludedFiles.includes(relativePath);
  });
});

function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  let jsonRpcUrl: string;
  switch (chain) {
    case "telos":
      jsonRpcUrl = "https://mainnet15a.telos.net/evm";
      break;
    case "telos-testnet":
      jsonRpcUrl = "https://testnet.telos.net/evm";
      break;
    default:
      jsonRpcUrl = "https://mainnet15a.telos.net/evm";
  }
  return {
    accounts: {
      count: 10,
      mnemonic,
      path: "m/44'/60'/0'/0",
    },
    chainId: chainIds[chain],
    url: jsonRpcUrl,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: {
      celo: vars.get("CELO_API_KEY", ""),
      "celo-alfajores": vars.get("CELO_ALFAJORES_API_KEY", ""),
      gnosis: vars.get("GNOIS_API_KEY", ""),
      "gnosis-testnet": vars.get("GNOSIS_TESTNET_API_KEY", ""),
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      gas: "auto",
      forking: {
        enabled: true,
        url: "https://celo-mainnet.infura.io/v3/1e78db6f14a14ab683177c462c7e7a52",
      },
      accounts: [{ privateKey: mnemonic, balance: "1000" }],
      chainId: chainIds.hardhat,
    },
    ganache: {
      accounts: {
        mnemonic,
      },
      chainId: chainIds.ganache,
      url: "http://localhost:8545",
    },
    telos: getChainConfig("telos"),
    "telos-testnet": getChainConfig("telos-testnet"),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.7.1",
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/hardhat-template/issues/31
        bytecodeHash: "none",
      },
      // Disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
