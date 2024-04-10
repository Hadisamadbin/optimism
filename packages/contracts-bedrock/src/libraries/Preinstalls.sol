// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Preinstalls
/// @notice Contains constant addresses for non-protocol contracts that are pre-deployed to the L2 system.
//          This excludes the predeploys (protocol contracts).
library Preinstalls {

    /// @notice Address of the MultiCall3 predeploy.
    address internal constant MultiCall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    /// @notice Address of the Create2Deployer predeploy.
    address internal constant Create2Deployer = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    /// @notice Address of the Safe_v130 predeploy.
    address internal constant Safe_v130 = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;

    /// @notice Address of the SafeL2_v130 predeploy.
    address internal constant SafeL2_v130 = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;

    /// @notice Address of the MultiSendCallOnly_v130 predeploy.
    address internal constant MultiSendCallOnly_v130 = 0xA1dabEF33b3B82c7814B6D82A79e50F4AC44102B;

    /// @notice Address of the SafeSingletonFactory predeploy.
    address internal constant SafeSingletonFactory = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @notice Address of the DeterministicDeploymentProxy predeploy.
    address internal constant DeterministicDeploymentProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Address of the MultiSend_v130 predeploy.
    address internal constant MultiSend_v130 = 0x998739BFdAAdde7C933B942a68053933098f9EDa;

    /// @notice Address of the Permit2 predeploy.
    address internal constant Permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Address of the SenderCreator predeploy.
    address internal constant SenderCreator = 0x7fc98430eAEdbb6070B35B39D798725049088348;

    /// @notice Address of the EntryPoint predeploy.
    address internal constant EntryPoint = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    /// @notice Address of beacon block roots contract, introduced in the Cancun upgrade.
    ///         See BEACON_ROOTS_ADDRESS in EIP-4788.
    ///         This contract is introduced in L2 through an Ecotone upgrade transaction.
    address internal constant BeaconBlockRoots = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;
}
