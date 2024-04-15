// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/ISemver.sol";
import { FeeVault } from "src/universal/FeeVault.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @custom:proxied
/// @custom:predeploy 0x420000000000000000000000000000000000001A
/// @title L1FeeVault
/// @notice The L1FeeVault accumulates the L1 portion of the transaction fees.
contract L1FeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.4.1
    string public constant version = "1.4.1";

    /// @notice Constructs the L1FeeVault contract.
    constructor() FeeVault(Predeploys.REVENUE_SHARER) { }
}
