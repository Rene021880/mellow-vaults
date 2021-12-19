import { PopulatedTransaction } from "@ethersproject/contracts";
import { TransactionReceipt } from "@ethersproject/abstract-provider";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import {
    equals,
    filter,
    fromPairs,
    keys,
    KeyValuePair,
    map,
    pipe,
} from "ramda";
import { read } from "fs";
import { deployments } from "hardhat";
import { BigNumber, BigNumberish, ethers } from "ethers";

export const ALL_NETWORKS = [
    "hardhat",
    "localhost",
    "mainnet",
    "kovan",
    "arbitrum",
    "optimism",
    "bsc",
    "avalance",
    "polygon",
    "fantom",
];
export const MAIN_NETWORKS = ["hardhat", "localhost", "mainnet", "kovan"];

export const setupVault = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    contractName: string,
    {
        deployOptions,
        delayedStrategyParams,
        strategyParams,
        delayedProtocolPerVaultParams,
    }: {
        deployOptions: any[];
        delayedStrategyParams?: { [key: string]: any };
        strategyParams?: { [key: string]: any };
        delayedProtocolPerVaultParams?: { [key: string]: any };
    }
) => {
    delayedStrategyParams ||= {};
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, admin } = await getNamedAccounts();
    const currentNft = await read("VaultRegistry", "vaultsCount");
    if (currentNft <= expectedNft) {
        log(`Deploying ${contractName.replace("Governance", "")}...`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            ...deployOptions
        );
        log(`Done, nft = ${expectedNft}`);
    } else {
        log(
            `${contractName.replace(
                "Governance",
                ""
            )} with nft = ${expectedNft} already deployed`
        );
    }
    if (strategyParams) {
        const currentParams = await read(
            contractName,
            "strategyParams",
            expectedNft
        );

        if (!equals(strategyParams, currentParams)) {
            log(`Setting Strategy params for ${contractName}`);
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "setStrategyParams",
                expectedNft,
                strategyParams
            );
        }
    }
    let strategyTreasury;
    try {
        const data = await read(
            contractName,
            "delayedStrategyParams",
            expectedNft
        );
        strategyTreasury = data.strategyTreasury;
    } catch {
        return;
    }

    if (strategyTreasury !== delayedStrategyParams.strategyTreasury) {
        log(`Setting delayed strategy params for ${contractName}`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "stageDelayedStrategyParams",
            expectedNft,
            delayedStrategyParams
        );
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "commitDelayedStrategyParams",
            expectedNft
        );
    }
    if (delayedProtocolPerVaultParams) {
        const params = await read(
            contractName,
            "delayedProtocolPerVaultParams",
            expectedNft
        );
        if (!equals(toObject(params), delayedProtocolPerVaultParams)) {
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "stageDelayedProtocolPerVaultParams",
                expectedNft,
                delayedProtocolPerVaultParams
            );
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "commitDelayedProtocolPerVaultParams",
                expectedNft
            );
        }
    }
};

export const combineVaults = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    nfts: number[],
    strategyAddress: string,
    strategyTreasuryAddress: string,
    options?: {
        limits?: BigNumberish[];
        strategyPerformanceTreasuryAddress?: string;
        tokenLimitPerAddress: BigNumberish;
        managementFee: BigNumberish;
        performanceFee: BigNumberish;
    }
): Promise<void> => {
    if (nfts.length === 0) {
        throw `Trying to combine 0 vaults`;
    }
    const { deployer } = await hre.getNamedAccounts();
    const firstNft = nfts[0];
    const firstAddress = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        firstNft
    );
    const vault = await hre.ethers.getContractAt("IVault", firstAddress);
    const tokens = await vault.vaultTokens();
    const coder = hre.ethers.utils.defaultAbiCoder;

    const {
        limits = tokens.map((_) => ethers.constants.MaxUint256),
        strategyPerformanceTreasuryAddress = strategyTreasuryAddress,
        tokenLimitPerAddress = ethers.constants.MaxUint256,
        managementFee = 2 * 10 ** 9,
        performanceFee = 20 * 10 ** 9,
    } = options || {};
    await setupVault(hre, expectedNft, "GatewayVaultGovernance", {
        deployOptions: [
            tokens,
            coder.encode(["uint256[]"], [nfts]),
            strategyAddress,
        ],

        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            redirects: nfts,
        },
        strategyParams: {
            limits: limits.map((x: BigNumberish) => BigNumber.from(x)),
        },
    });

    await setupVault(hre, expectedNft + 1, "LpIssuerGovernance", {
        deployOptions: [
            tokens,
            coder.encode(
                ["uint256", "string", "string"],
                [expectedNft, "MStrategy LP Token", "MSLP"]
            ),
            deployer,
        ],
        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            strategyPerformanceTreasury: strategyPerformanceTreasuryAddress,
            managementFee: BigNumber.from(managementFee),
            performanceFee: BigNumber.from(performanceFee),
        },
        strategyParams: {
            tokenLimitPerAddress: BigNumber.from(tokenLimitPerAddress),
        },
    });
    const lpIssuer = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        expectedNft + 1
    );
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true },
        "safeTransferFrom(address,address,uint256)",
        deployer,
        lpIssuer,
        expectedNft + 1
    );
};

const deployMStrategy = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get } = deployments;
    const { deployer, mStrategyAdmin } = await getNamedAccounts();

    const proxyAdminDeployment = await deploy("MStrategyProxyAdmin", {
        from: deployer,
        contract: "DefaultProxyAdmin",
        args: [],
        log: true,
        autoMine: true,
    });

    const mStrategyDeployment = await deploy("MStrategy", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        proxy: {
            execute: { init: { methodName: "init", args: [deployer] } },
            proxyContract: "DefaultProxy",
            viaAdminContract: {
                name: "MStrategyProxyAdmin",
                artifact: "DefaultProxyAdmin",
            },
        },
    });
    await execute(
        "MStrategyProxyAdmin",
        {
            from: deployer,
            log: true,
            autoMine: true,
        },
        "transferOwnership",
        mStrategyAdmin
    );
};

const initMStrategy = async (
    hre: HardhatRuntimeEnvironment,
    tokens: string[],
    erc20Vault: string,
    moneyVault: string,
    uniPool: "500" | "3000" | "10000"
) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log, execute, read, get } = deployments;

    const { deployer, uniswapV3Router, uniswapV3Factory, mStrategyAdmin } =
        await getNamedAccounts();

    const vaultCount = await read("MStrategy", "vaultCount");
    if (vaultCount.toNumber() === 0) {
        log("Setting Strategy params");
        const uniFactory = await hre.ethers.getContractAt(
            "IUniswapV3Factory",
            uniswapV3Factory
        );
        const uniV3Pool = await uniFactory.getPool(
            tokens[0],
            tokens[1],
            BigNumber.from(uniV3Fee)
        );
        const immutableParams = {
            token0: tokens[0],
            token1: tokens[1],
            uniV3Pool,
            uniV3Router: uniswapV3Router,
            erc20Vault,
            moneyVault,
        };
        const params = {
            oraclePriceTimespan: 1800,
            oracleLiquidityTimespan: 1800,
            liquidToFixedRatioX96: BigNumber.from(2).pow(96 - 2),
            sqrtPMinX96: BigNumber.from(
                Math.round((1 / Math.sqrt(3000)) * 10 ** 6 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            sqrtPMaxX96: BigNumber.from(
                Math.round((1 / Math.sqrt(5000)) * 10 ** 6 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            tokenRebalanceThresholdX96: BigNumber.from(
                Math.round(1.1 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
            poolRebalanceThresholdX96: BigNumber.from(
                Math.round(1.1 * 2 ** 20)
            ).mul(BigNumber.from(2).pow(76)),
        };
        log(
            `Immutable Params:`,
            map((x) => x.toString(), immutableParams)
        );
        log(
            `Params:`,
            map((x) => x.toString(), params)
        );
        await execute(
            "MStrategy",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "addVault",
            immutableParams,
            params
        );
    }
    const adminRole = await read("MStrategy", "ADMIN_ROLE");
    const deployerIsAdmin = await read("MStrategy", "isAdmin", deployer);
    if (deployerIsAdmin) {
        await execute(
            "MStrategy",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "grantRole",
            adminRole,
            mStrategyAdmin
        );
        await execute(
            "MStrategy",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "renounceRole",
            adminRole,
            deployer
        );
    }
};

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};
export default func;
