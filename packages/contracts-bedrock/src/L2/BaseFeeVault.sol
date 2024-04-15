// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/ISemver.sol";
import { FeeVault } from "src/universal/FeeVault.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000019
/// @title BaseFeeVault
/// @notice The BaseFeeVault accumulates the base fee that is paid by transactions.
contract BaseFeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.4.1
    string public constant version = "1.4.1";

    /// @notice Constructs the BaseFeeVault contract.
    constructor() FeeVault(Predeploys.REVENUE_SHARER) { }
}
