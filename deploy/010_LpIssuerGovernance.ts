import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { ALL_NETWORKS } from "./000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, aaveLendingPool } = await getNamedAccounts();
    await deploy("LpIssuerGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
            { managementFeeChargeDelay: 86400 },
        ],
        log: true,
        autoMine: true,
    });
    const governance = await get("LpIssuerGovernance");
    await deploy("LpIssuerFactory", {
        from: deployer,
        args: [governance.address],
        log: true,
        autoMine: true,
    });
    const initialized = await read("LpIssuerGovernance", "initialized");
    if (!initialized) {
        log("Initializing factory...");

        const factory = await get("LpIssuerFactory");
        await execute(
            "LpIssuerGovernance",
            { from: deployer, log: true, autoMine: true },
            "initialize",
            factory.address
        );
    }
    const { address: lpIssuerVaultGovernanceAddress } = await get(
        "LpIssuerGovernance"
    );
    const approvedIssuer = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        lpIssuerVaultGovernanceAddress
    );
    if (!approvedIssuer) {
        log("Approving lp issuer governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            lpIssuerVaultGovernanceAddress,
            true
        );
    }
};
export default func;
func.tags = ["LpIssuerGovernance", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
