// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./DefaultAccessControl.sol";

contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _claimAllowlist;
    address[] private _pendingClaimAllowlistAdd;
    uint256 public pendingClaimAllowlistAddTimestamp;

    EnumerableSet.AddressSet private _vaultGovernances;
    address[] private _pendingVaultGovernancesAdd;
    uint256 public pendingVaultGovernancesAddTimestamp;

    IProtocolGovernance.Params public params;
    Params public pendingParams;

    uint256 public pendingParamsTimestamp;

    /// @notice Creates a new contract
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  PUBLIC, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function claimAllowlist() external view returns (address[] memory) {
        uint256 l = _claimAllowlist.length();
        address[] memory res = new address[](l);
        for (uint256 i = 0; i < l; i++) {
            res[i] = _claimAllowlist.at(i);
        }
        return res;
    }

    /// @inheritdoc IProtocolGovernance
    function vaultGovernances() external view returns (address[] memory) {
        // TODO: use iterable set
        uint256 l = _vaultGovernances.length();
        address[] memory res = new address[](l);
        for (uint256 i = 0; i < l; i++) {
            res[i] = _vaultGovernances.at(i);
        }
        return res;
    }

    /// @inheritdoc IProtocolGovernance
    function pendingClaimAllowlistAdd() external view returns (address[] memory) {
        return _pendingClaimAllowlistAdd;
    }

    /// @inheritdoc IProtocolGovernance
    function pendingVaultGovernancesAdd() external view returns (address[] memory) {
        return _pendingVaultGovernancesAdd;
    }

    /// @inheritdoc IProtocolGovernance
    function isAllowedToClaim(address addr) external view returns (bool) {
        return _claimAllowlist.contains(addr);
    }

    /// @inheritdoc IProtocolGovernance
    function isVaultGovernance(address addr) external view returns (bool) {
        return _vaultGovernances.contains(addr);
    }

    /// @inheritdoc IProtocolGovernance
    function permissionless() external view returns (bool) {
        return params.permissionless;
    }

    /// @inheritdoc IProtocolGovernance
    function maxTokensPerVault() external view returns (uint256) {
        return params.maxTokensPerVault;
    }

    /// @inheritdoc IProtocolGovernance
    function governanceDelay() external view returns (uint256) {
        return params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function strategyPerformanceFee() external view returns (uint256) {
        return params.strategyPerformanceFee;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolPerformanceFee() external view returns (uint256) {
        return params.protocolPerformanceFee;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolExitFee() external view returns (uint256) {
        return params.protocolExitFee;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolTreasury() external view returns (address) {
        return params.protocolTreasury;
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function setPendingClaimAllowlistAdd(address[] calldata addresses) external {
        require(isAdmin(msg.sender), "ADM");
        _pendingClaimAllowlistAdd = addresses;
        pendingClaimAllowlistAddTimestamp = block.timestamp + params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function removeFromClaimAllowlist(address addr) external {
        require(isAdmin(msg.sender), "ADM");
        if (!_claimAllowlist.contains(addr)) {
            return;
        }
        _claimAllowlist.remove(addr);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingVaultGovernancesAdd(address[] calldata addresses) external {
        require(isAdmin(msg.sender), "ADM");
        _pendingVaultGovernancesAdd = addresses;
        pendingVaultGovernancesAddTimestamp = block.timestamp + params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function removeFromVaultGovernances(address addr) external {
        require(isAdmin(msg.sender), "ADM");
        if (!_vaultGovernances.contains(addr)) {
            return;
        }
        _vaultGovernances.remove(addr);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params memory newParams) external {
        require(isAdmin(msg.sender), "ADM");
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    /// @inheritdoc IProtocolGovernance
    function commitClaimAllowlistAdd() external {
        require(isAdmin(msg.sender), "ADM");
        require(
            (block.timestamp >= pendingClaimAllowlistAddTimestamp) && (pendingClaimAllowlistAddTimestamp > 0),
            "TS"
        );
        for (uint256 i = 0; i < _pendingClaimAllowlistAdd.length; i++) {
            _claimAllowlist.add(_pendingClaimAllowlistAdd[i]);
        }
        delete _pendingClaimAllowlistAdd;
        delete pendingClaimAllowlistAddTimestamp;
    }

    /// @inheritdoc IProtocolGovernance
    function commitVaultGovernancesAdd() external {
        require(isAdmin(msg.sender), "ADM");
        require(
            (block.timestamp >= pendingVaultGovernancesAddTimestamp) && (pendingVaultGovernancesAddTimestamp > 0),
            "TS"
        );
        for (uint256 i = 0; i < _pendingVaultGovernancesAdd.length; i++) {
            _vaultGovernances.add(_pendingVaultGovernancesAdd[i]);
        }
        delete _pendingVaultGovernancesAdd;
        delete pendingVaultGovernancesAddTimestamp;
    }

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        require(isAdmin(msg.sender), "ADM");
        require(block.timestamp >= pendingParamsTimestamp, "TS");
        require(pendingParams.maxTokensPerVault > 0 || pendingParams.governanceDelay > 0, "P0"); // sanity check for empty params
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
    }
}
