// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../vaults/GearboxVault.sol";
import "../vaults/GearboxRootVault.sol";
import "../vaults/ERC20Vault.sol";
import "../vaults/UniV3Vault.sol";

import "../utils/UniV3Helper.sol";

import "../vaults/UniV3VaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../strategies/PulseStrategyV2.sol";


contract OptimismDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IUniV3Vault uniV3Vault;

    PulseStrategyV2 strategy;
    uint256 nftStart;

    address sAdmin = 0xE8Ce688923944eBE6636d7272E7eCA1AECb68E37;
    address protocolTreasury = 0x8E4aF8cE6aD41D6E3cdbf0AAaAE3f7471775744c;
    address strategyTreasury = 0xe551d73d50b940e40471C704eA598Cd2f73e7fb1;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public op = 0x4200000000000000000000000000000000000042;
    address public bob = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;

    address public governance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
    address public registry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;
    address public rootGovernance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public erc20Governance = 0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece;
    address public uniV3Governance = 0x558055ae71ee1BC926905469301a232066eD4673;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
        rootVault = w;
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );

        rootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: strategyTreasury,
                strategyPerformanceTreasury: protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = op;
        tokens[1] = bob;

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        UniV3Helper helper = new UniV3Helper(INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

        {
            IUniV3VaultGovernance uniGovernance = IUniV3VaultGovernance(uniV3Governance);
            uniGovernance.createVault(tokens, deployer, 500, address(helper));

            IUniV3VaultGovernance.DelayedStrategyParams memory dsp = IUniV3VaultGovernance.DelayedStrategyParams({
                safetyIndicesSet: 2
            });

            uniGovernance.stageDelayedStrategyParams(erc20VaultNft + 1, dsp);
            uniGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        PulseStrategyV2 protoS = new PulseStrategyV2(INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));
        TransparentUpgradeableProxy kek = new TransparentUpgradeableProxy(address(protoS), sAdmin, "");
        strategy = PulseStrategyV2(address(kek));

        PulseStrategyV2.ImmutableParams memory sParams = PulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            uniV3Vault: uniV3Vault,
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**12;
        AA[1] = 10**12;

        PulseStrategyV2.MutableParams memory smParams = PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 5000,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 10 ** 7 * 15,
            extensionFactorD: 10 ** 7 * 175,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        PulseStrategyV2.DesiredAmounts memory kekK = PulseStrategyV2.DesiredAmounts({
            amount0Desired: 10**9,
            amount1Desired: 10**9
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        strategy.initialize(sParams, deployer);
        strategy.updateMutableParams(smParams);
        strategy.updateDesiredAmounts(kekK);

        IVaultRegistry(registry).transferFrom(deployer, sAdmin, erc20VaultNft + 2);

        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        strategy.grantRole(ADMIN_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.grantRole(OPERATOR_ROLE, sAdmin);
        strategy.grantRole(OPERATOR_ROLE, operator);
        strategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.revokeRole(ADMIN_ROLE, deployer);

        console2.log("strategy:", address(strategy));
        console2.log("root vault:", address(rootVault));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("uni vault:", address(uniV3Vault));
    }

    function run() external {
        vm.startBroadcast();

        kek();

        IERC20(op).transfer(address(strategy), 10**12);
        IERC20(bob).transfer(address(strategy), 10**12);

      //  rootVault = IERC20RootVault(0x5Fd7eA4e9F96BBBab73D934618a75746Fd88e460);

        IERC20(op).approve(address(rootVault), 10**20);
        IERC20(bob).approve(address(rootVault), 10**20);

        uint256[] memory A = new uint256[](2);
        A[0] = 10**10;
        A[1] = 10**10;

        rootVault.deposit(A, 0, "");

        A = new uint256[](2);
        A[0] = 5 * 10**17;
        A[1] = 5 * 10**17;

        rootVault.deposit(A, 0, "");


     //   kek();
    }
}