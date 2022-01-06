import { Assertion, expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { AddressPermissionIds } from "./library/AddressPermissionIds";
import {
    DelayedProtocolParamsStruct,
    ERC20VaultGovernance,
} from "./types/ERC20VaultGovernance";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    InternalParamsStructOutput,
} from "./types/IVaultGovernance";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
    trader?: string;
    skipInit?: boolean;
};

contract<ERC20VaultGovernance, DeployOptions, CustomContext>(
    "ERC20VaultGovernance",
    function () {
        before(async () => {
            const traderAddress = (await getNamedAccounts()).aaveLendingPool;
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    const { address: singleton } = await deployments.get(
                        "ERC20Vault"
                    );
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton,
                        },
                        trader = traderAddress,
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "ERC20VaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "ERC20VaultGovernance",
                            args: [internalParams, { trader }],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "ERC20VaultGovernance",
                        address
                    );
                    this.ownerSigner = await addSigner(randomAddress());
                    this.strategySigner = await addSigner(randomAddress());

                    if (!skipInit) {
                        await this.protocolGovernance
                            .connect(this.admin)
                            .stageGrantPermissions(this.subject.address, [
                                AddressPermissionIds.VAULT_GOVERNANCE,
                            ]);
                        await sleep(this.governanceDelay);
                        await this.protocolGovernance
                            .connect(this.admin)
                            .commitStagedPermissions();
                        await this.subject.createVault(
                            this.tokens.map((x: any) => x.address),
                            this.ownerSigner.address
                        );
                        this.nft = (
                            await this.vaultRegistry.vaultsCount()
                        ).toNumber();
                        await this.vaultRegistry
                            .connect(this.ownerSigner)
                            .approve(this.strategySigner.address, this.nft);
                    }
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
            address.map((trader) => ({ trader }));

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("edge cases", () => {
                describe("when trader address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        const { address: singleton } = await deployments.get(
                            "ERC20Vault"
                        );
                        await expect(
                            deployments.deploy("ERC20VaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton,
                                    },
                                    {
                                        trader: ethers.constants.AddressZero,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        vaultGovernanceBehavior.call(this, {
            delayedProtocolParams,
            ...this,
        });
    }
);
