// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./libraries/CommonLibrary.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/ILpIssuer.sol";
import "./DefaultAccessControl.sol";
import "./LpIssuerGovernance.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract LpIssuer is IERC721Receiver, ILpIssuer, ERC20 {
    using SafeERC20 for IERC20;
    uint256 private _subvaultNft;
    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;
    uint256 private _nft;
    uint256[] private _lpHighWaterMarks;

    uint256 public lastFeeCharge;

    /// @notice Creates a new contract.
    /// @dev All subvault nfts must be owned by this vault before.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    /// @param name_ Name of the ERC-721 token
    /// @param symbol_ Symbol of the ERC-721 token
    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        require(CommonLibrary.isSortedAndUnique(vaultTokens_), "SAU");
        _vaultGovernance = vaultGovernance_;
        _vaultTokens = vaultTokens_;
        for (uint256 i = 0; i < vaultTokens_.length; i++) {
            _vaultTokensIndex[vaultTokens_[i]] = true;
            _lpHighWaterMarks.push(0);
        }
        lastFeeCharge = block.timestamp;
    }

    function vaultGovernance() external view returns (IVaultGovernance) {
        return _vaultGovernance;
    }

    function vaultTokens() external view returns (address[] memory) {
        return _vaultTokens;
    }

    /// @inheritdoc ILpIssuer
    function subvaultNft() external view returns (uint256) {
        return _subvaultNft;
    }

    function nft() external view returns (uint256) {
        return _nft;
    }

    function initialize(uint256 nft_) external {
        require(msg.sender == address(_vaultGovernance), "VG");
        _nft = nft_;

        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        registry.setApprovalForAll(address(registry), true);
    }

    /// @notice Deposit tokens into LpIssuer
    /// @param tokenAmounts Amounts of tokens to push
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function deposit(uint256[] calldata tokenAmounts, bytes memory options) external {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        require(_nft > 0, "INIT");
        require(_subvaultNft > 0, "INITSV");
        require(registry.ownerOf(_nft) == address(this), "INITOWN");
        IVault subvault = _subvault();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _allowTokenIfNecessary(_vaultTokens[i], address(subvault));
            IERC20(_vaultTokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
        }
        uint256[] memory actualTokenAmounts = subvault.transferAndPush(
            address(this),
            _vaultTokens,
            tokenAmounts,
            options
        );
        // TODO: Think if it's better to make pre-money valuation
        uint256[] memory tvl = subvault.tvl(); //post-money
        uint256 amountToMint = 0;
        uint256 supply = totalSupply();
        if (supply == 0) {
            for (uint256 i = 0; i < _vaultTokens.length; i++) {
                // TODO: check if there could be smth better
                if (actualTokenAmounts[i] > amountToMint) {
                    amountToMint = actualTokenAmounts[i]; // some number correlated to invested assets volume
                }
            }
        }
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (tvl[i] > 0) {
                // TODO: Check price manipulation here for yearn / aave (cached tvls)
                // TODO: Should be (actualTokenAmounts[i] * totalSupply()) / (tvl[i] - actualTokenAmounts[i]) for consistent post-money valuation
                // However care needs to be taken in terms of rounding, etc.
                uint256 newMint = (actualTokenAmounts[i] * supply) / tvl[i];
                // TODO: check this algo. The assumption is that everything is rounded down.
                // So that max token has the least error. Think about the case when one token is dust.
                if (newMint > amountToMint) {
                    amountToMint = newMint;
                }
            }
            if (tokenAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_vaultTokens[i]).safeTransfer(msg.sender, tokenAmounts[i] - actualTokenAmounts[i]);
            }
        }
        require(
            amountToMint + balanceOf(msg.sender) <=
                ILpIssuerGovernance(address(_vaultGovernance)).strategyParams(_nft).tokenLimitPerAddress,
            "LPA"
        );
        _chargeFees(tvl, supply + amountToMint);
        if (amountToMint > 0) {
            _mint(msg.sender, amountToMint);
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, amountToMint);
    }

    /// @notice Withdraw tokens from LpIssuer
    /// @param to Address to withdraw to
    /// @param lpTokenAmount Amount of token to withdraw
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        bytes memory options
    ) external {
        uint256 supply = totalSupply();
        require(supply > 0, "TS0");
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        // TODO: Check price manipulation here
        uint256[] memory tvl = _subvault().tvl();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            tokenAmounts[i] = (lpTokenAmount * tvl[i]) / supply;
        }
        uint256[] memory actualTokenAmounts = _subvault().pull(address(this), _vaultTokens, tokenAmounts, options);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }
            IERC20(_vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _burn(msg.sender, lpTokenAmount);
        _chargeFees(tvl, supply - lpTokenAmount);
        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    /// @inheritdoc ILpIssuer
    function addSubvault(uint256 nft_) external {
        require(msg.sender == address(_vaultGovernance), "RVG");
        require(_subvaultNft == 0, "SBIN");
        require(nft_ > 0, "NFT0");
        _subvaultNft = nft_;
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        require(msg.sender == address(registry), "NFTVR");
        registry.lockNft(tokenId);
        return this.onERC721Received.selector;
    }

    function _allowTokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(to), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(to), type(uint256).max);
        }
    }

    function _subvault() internal view returns (IVault) {
        return IVault(_vaultGovernance.internalParams().registry.vaultForNft(_subvaultNft));
    }

    /// @dev We don't charge on any deposit / withdraw to save gas.
    /// While this introduce some error, the charge always goes for lower lp token supply (pre-deposit / post-withdraw)
    /// So the error results in slightly lower management fees than in exact case
    function _chargeFees(uint256[] memory tvls, uint256 supply) internal {
        ILpIssuerGovernance vg = ILpIssuerGovernance(address(_vaultGovernance));
        uint256 thisNft = _nft;
        uint256 elapsed = block.timestamp - lastFeeCharge;
        if (elapsed < vg.delayedProtocolParams().managementFeeChargeDelay) {
            return;
        }
        lastFeeCharge = block.timestamp;
        if (supply == 0) {
            return;
        }

        ILpIssuerGovernance.DelayedStrategyParams memory strategyParams = vg.delayedStrategyParams(thisNft);
        if (strategyParams.managementFee > 0) {
            uint256 toMint = (strategyParams.managementFee * supply * elapsed) /
                (CommonLibrary.DENOMINATOR * CommonLibrary.YEAR);
            _mint(strategyParams.strategyTreasury, toMint);
            emit ManagementFeesCharged(strategyParams.strategyTreasury, strategyParams.managementFee, toMint);
        }
        uint256 protocolFee = vg.delayedProtocolPerVaultParams(thisNft).protocolFee;
        if (protocolFee > 0) {
            address treasury = vg.internalParams().protocolGovernance.protocolTreasury();
            uint256 toMint = (protocolFee * supply * elapsed) / (CommonLibrary.DENOMINATOR * CommonLibrary.YEAR);
            _mint(treasury, toMint);
            emit ProtocolFeesCharged(treasury, protocolFee, toMint);
        }
        uint256 performanceFee = strategyParams.performanceFee;
        uint256[] memory hwms = _lpHighWaterMarks;
        if (performanceFee > 0) {
            uint256 minLpDelta = type(uint256).max;
            for (uint256 i = 0; i < tvls.length; i++) {
                uint256 hwm = hwms[i];
                uint256 lpPrice = (tvls[i] * CommonLibrary.DENOMINATOR) / supply;
                if (lpPrice > hwm) {
                    uint256 delta = lpPrice - hwm;
                    if (delta < minLpDelta) {
                        minLpDelta = delta;
                    }
                } else {
                    // not eligible for performance fees
                    return;
                }
            }
            for (uint256 i = 0; i < tvls.length; i++) {
                _lpHighWaterMarks[i] += minLpDelta * hwms[i];
            }
            address treasury = strategyParams.strategyPerformanceTreasury;
            _mint(treasury, minLpDelta);
            emit PerformanceFeesCharged(treasury, performanceFee, minLpDelta);
        }
    }

    /// @notice Emitted when management fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event ManagementFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when protocol fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event ProtocolFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when performance fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event PerformanceFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when liquidity is deposited
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens deposited
    /// @param actualTokenAmounts Token amounts deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted);

    /// @notice Emitted when liquidity is withdrawn
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens withdrawn
    /// @param actualTokenAmounts Token amounts withdrawn
    /// @param lpTokenBurned LP tokens burned from the liquidity provider
    event Withdraw(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned);
}
