// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Deployer } from "scripts/Deployer.sol";

import { Config } from "scripts/Config.sol";
import { Artifacts } from "scripts/Artifacts.s.sol";
import { DeployConfig } from "scripts/DeployConfig.s.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { L2CrossDomainMessenger } from "src/L2/L2CrossDomainMessenger.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { L2StandardBridge } from "src/L2/L2StandardBridge.sol";
import { L2ERC721Bridge } from "src/L2/L2ERC721Bridge.sol";
import { SequencerFeeVault } from "src/L2/SequencerFeeVault.sol";
import { OptimismMintableERC20Factory } from "src/universal/OptimismMintableERC20Factory.sol";
import { OptimismMintableERC721Factory } from "src/universal/OptimismMintableERC721Factory.sol";
import { BaseFeeVault } from "src/L2/BaseFeeVault.sol";
import { L1FeeVault } from "src/L2/L1FeeVault.sol";
import { GovernanceToken } from "src/governance/GovernanceToken.sol";
import { L1CrossDomainMessenger } from "src/L1/L1CrossDomainMessenger.sol";
import { L1StandardBridge } from "src/L1/L1StandardBridge.sol";
import { FeeVault } from "src/universal/FeeVault.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

interface IInitializable {
    function initialize(address _addr) external;
}

struct L1Dependencies {
    address payable deployedL1CrossDomainMessengerProxy;
    address payable deployedL1StandardBridgeProxy;
    address payable deployedL1ERC721BridgeProxy;
}

/// @notice Enum representing different ways of outputting genesis allocs.
/// @custom:value DEFAULT_LATEST Represents only latest L2 allocs, written to output path.
/// @custom:value LOCAL_LATEST   Represents latest L2 allocs, not output anywhere, but kept in-process.
/// @custom:value LOCAL_DELTA    Represents Delta-upgrade L2 allocs, not output anywhere, but kept in-process.
/// @custom:value OUTPUT_ALL     Represents creation of one L2 allocs file for every upgrade.
enum OutputMode {
    DEFAULT_LATEST,
    LOCAL_LATEST,
    LOCAL_DELTA,
    OUTPUT_ALL
}

/// @title L2Genesis
/// @notice Generates the genesis state for the L2 network.
///         The following safety invariants are used when setting state:
///         1. `vm.getDeployedBytecode` can only be used with `vm.etch` when there are no side
///         effects in the constructor and no immutables in the bytecode.
///         2. A contract must be deployed using the `new` syntax if there are immutables in the code.
///         Any other side effects from the init code besides setting the immutables must be cleaned up afterwards.
contract L2Genesis is Deployer {
    uint256 public constant PRECOMPILE_COUNT = 256;

    uint80 internal constant DEV_ACCOUNT_FUND_AMT = 10_000 ether;

    /// @notice Default Anvil dev accounts. Only funded if `cfg.fundDevAccounts == true`.
    address[10] internal devAccounts = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906,
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
        0x976EA74026E726554dB657fA54763abd0C3a0aa9,
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
    ];

    function name() public pure override returns (string memory) {
        return "L2Genesis";
    }

    function artifactDependencies() internal view returns (L1Dependencies memory l1Dependencies_) {
        console.log("retrieving L1 deployments from artifacts");
        return L1Dependencies({
            deployedL1CrossDomainMessengerProxy: mustGetAddress("L1CrossDomainMessengerProxy"),
            deployedL1StandardBridgeProxy: mustGetAddress("L1StandardBridgeProxy"),
            deployedL1ERC721BridgeProxy: mustGetAddress("L1ERC721BridgeProxy")
        });
    }

    /// @dev Sets the precompiles, proxies, and the implementation accounts to be `vm.dumpState`
    ///      to generate a L2 genesis alloc.
    /// @notice The alloc object is sorted numerically by address.
    function runWithStateDump() public {
        runWithOptions(OutputMode.DEFAULT_LATEST, artifactDependencies());
    }

    // @dev This is used by op-e2e to have a version of the L2 allocs for each upgrade.
    function runWithAllUpgrades() public {
        runWithOptions(OutputMode.OUTPUT_ALL, artifactDependencies());
    }

    function runWithOptions(OutputMode _mode, L1Dependencies memory _l1Dependencies) public {
        dealEthToPrecompiles();
        setPredeployProxies();
        setPredeployImplementations(_l1Dependencies);
        setPreinstalls();
        if (cfg.fundDevAccounts()) {
            fundDevAccounts();
        }
        // Genesis is "complete" at this point, but some hardfork activation steps remain.
        // Depending on the "Output Mode" we perform the activations and output the necessary state dumps.
        if (_mode == OutputMode.LOCAL_DELTA) {
            return;
        }
        if (_mode == OutputMode.OUTPUT_ALL) {
            writeGenesisAllocs(Config.stateDumpPath("-delta"));
        }
        activateEcotone();
        if (_mode == OutputMode.OUTPUT_ALL || _mode == OutputMode.DEFAULT_LATEST) {
            writeGenesisAllocs(Config.stateDumpPath(""));
        }
    }

    /// @notice Give all of the precompiles 1 wei
    function dealEthToPrecompiles() internal {
        for (uint256 i; i < PRECOMPILE_COUNT; i++) {
            vm.deal(address(uint160(i)), 1);
        }
    }

    /// @dev Set up the accounts that correspond to the predeploys.
    ///      The Proxy bytecode should be set. All proxied predeploys should have
    ///      the 1967 admin slot set to the ProxyAdmin predeploy. All defined predeploys
    ///      should have their implementations set.
    function setPredeployProxies() public {
        bytes memory code = vm.getDeployedCode("Proxy.sol:Proxy");
        uint160 prefix = uint160(0x420) << 148;

        console.log(
            "Setting proxy deployed bytecode for addresses in range %s through %s",
            address(prefix | uint160(0)),
            address(prefix | uint160(Predeploys.PREDEPLOY_COUNT - 1))
        );
        for (uint256 i = 0; i < Predeploys.PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));
            if (Predeploys.notProxied(addr)) {
                console.log("Skipping proxy at %s", addr);
                continue;
            }

            vm.etch(addr, code);
            EIP1967Helper.setAdmin(addr, Predeploys.PROXY_ADMIN);

            if (Predeploys.isSupportedPredeploy(addr)) {
                address implementation = Predeploys.predeployToCodeNamespace(addr);
                console.log("Setting proxy %s implementation: %s", addr, implementation);
                EIP1967Helper.setImplementation(addr, implementation);
            }
        }
    }

    /// @dev Sets all the implementations for the predeploy proxies. For contracts without proxies,
    ///      sets the deployed bytecode at their expected predeploy address.
    ///      LEGACY_ERC20_ETH and L1_MESSAGE_SENDER are deprecated and are not set.
    function setPredeployImplementations(L1Dependencies memory _l1Dependencies) internal {
        setLegacyMessagePasser(); // 0
        // 01: legacy, not used in OP-Stack
        setDeployerWhitelist(); // 2
        // 3,4,5: legacy, not used in OP-Stack.
        setWETH9(); // 6: WETH9 (not behind a proxy)
        setL2CrossDomainMessenger(_l1Dependencies.deployedL1CrossDomainMessengerProxy); // 7
        // 8,9,A,B,C,D,E: legacy, not used in OP-Stack.
        setGasPriceOracle(); // f
        setL2StandardBridge(_l1Dependencies.deployedL1StandardBridgeProxy); // 10
        setSequencerFeeVault(); // 11
        setOptimismMintableERC20Factory(); // 12
        setL1BlockNumber(); // 13
        setL2ERC721Bridge(_l1Dependencies.deployedL1ERC721BridgeProxy); // 14
        setL1Block(); // 15
        setL2ToL1MessagePasser(); // 16
        setOptimismMintableERC721Factory(); // 17
        setProxyAdmin(); // 18
        setBaseFeeVault(); // 19
        setL1FeeVault(); // 1A
        // 1B,1C,1D,1E,1F: not used.
        setSchemaRegistry(); // 20
        setEAS(); // 21
        setGovernanceToken(); // 42: OP (not behind a proxy)
    }

    function setProxyAdmin() public {
        // Note the ProxyAdmin implementation itself is behind a proxy that owns itself.
        _setImplementationCode(Predeploys.PROXY_ADMIN);

        bytes32 _ownerSlot = bytes32(0);

        // there is no initialize() function, so we just set the storage manually.
        vm.store(Predeploys.PROXY_ADMIN, _ownerSlot, bytes32(uint256(uint160(cfg.proxyAdminOwner()))));
    }

    function setL2ToL1MessagePasser() public {
        _setImplementationCode(Predeploys.L2_TO_L1_MESSAGE_PASSER);
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL2CrossDomainMessenger(address payable _deployedL1CrossDomainMessengerProxy) public {
        address impl = _setImplementationCode(Predeploys.L2_CROSS_DOMAIN_MESSENGER);

        L2CrossDomainMessenger(impl).initialize({ _l1CrossDomainMessenger: L1CrossDomainMessenger(address(0)) });

        L2CrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).initialize({
            _l1CrossDomainMessenger: L1CrossDomainMessenger(_deployedL1CrossDomainMessengerProxy)
        });
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL2StandardBridge(address payable _deployedL1StandardBridgeProxy) public {
        address impl = _setImplementationCode(Predeploys.L2_STANDARD_BRIDGE);

        L2StandardBridge(payable(impl)).initialize({ _otherBridge: L1StandardBridge(payable(address(0))) });

        L2StandardBridge(payable(Predeploys.L2_STANDARD_BRIDGE)).initialize({
            _otherBridge: L1StandardBridge(_deployedL1StandardBridgeProxy)
        });
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL2ERC721Bridge(address payable _deployedL1ERC721BridgeProxy) public {
        address impl = _setImplementationCode(Predeploys.L2_ERC721_BRIDGE);

        L2ERC721Bridge(impl).initialize({ _l1ERC721Bridge: payable(address(0)) });

        L2ERC721Bridge(Predeploys.L2_ERC721_BRIDGE).initialize({ _l1ERC721Bridge: payable(_deployedL1ERC721BridgeProxy) });
    }

    /// @notice This predeploy is following the safety invariant #2,
    function setSequencerFeeVault() public {
        SequencerFeeVault vault = new SequencerFeeVault({
            _recipient: cfg.sequencerFeeVaultRecipient(),
            _minWithdrawalAmount: cfg.sequencerFeeVaultMinimumWithdrawalAmount(),
            _withdrawalNetwork: FeeVault.WithdrawalNetwork(cfg.sequencerFeeVaultWithdrawalNetwork())
        });

        address impl = Predeploys.predeployToCodeNamespace(Predeploys.SEQUENCER_FEE_WALLET);
        console.log("Setting %s implementation at: %s", "SequencerFeeVault", impl);
        vm.etch(impl, address(vault).code);

        /// Reset so its not included state dump
        vm.etch(address(vault), "");
        vm.resetNonce(address(vault));
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setOptimismMintableERC20Factory() public {
        address impl = _setImplementationCode(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY);

        OptimismMintableERC20Factory(impl).initialize({ _bridge: address(0) });

        OptimismMintableERC20Factory(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY).initialize({
            _bridge: Predeploys.L2_STANDARD_BRIDGE
        });
    }

    /// @notice This predeploy is following the safety invariant #2,
    function setOptimismMintableERC721Factory() public {
        OptimismMintableERC721Factory factory =
            new OptimismMintableERC721Factory({ _bridge: Predeploys.L2_ERC721_BRIDGE, _remoteChainId: cfg.l1ChainID() });

        address impl = Predeploys.predeployToCodeNamespace(Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY);
        console.log("Setting %s implementation at: %s", "OptimismMintableERC721Factory", impl);
        vm.etch(impl, address(factory).code);

        /// Reset so its not included state dump
        vm.etch(address(factory), "");
        vm.resetNonce(address(factory));
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL1Block() public {
        _setImplementationCode(Predeploys.L1_BLOCK_ATTRIBUTES);
        // Note: L1 block attributes are set to 0.
        // Before the first user-tx the state is overwritten with actual L1 attributes.
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setGasPriceOracle() public {
        _setImplementationCode(Predeploys.GAS_PRICE_ORACLE);
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setDeployerWhitelist() public {
        _setImplementationCode(Predeploys.DEPLOYER_WHITELIST);
    }

    /// @notice This predeploy is following the safety invariant #1.
    ///         This contract is NOT proxied and the state that is set
    ///         in the constructor is set manually.
    function setWETH9() public {
        console.log("Setting %s implementation at: %s", "WETH9", Predeploys.WETH9);
        vm.etch(Predeploys.WETH9, vm.getDeployedCode("WETH9.sol:WETH9"));

        vm.store(
            Predeploys.WETH9,
            /// string public name
            hex"0000000000000000000000000000000000000000000000000000000000000000",
            /// "Wrapped Ether"
            hex"577261707065642045746865720000000000000000000000000000000000001a"
        );
        vm.store(
            Predeploys.WETH9,
            /// string public symbol
            hex"0000000000000000000000000000000000000000000000000000000000000001",
            /// "WETH"
            hex"5745544800000000000000000000000000000000000000000000000000000008"
        );
        vm.store(
            Predeploys.WETH9,
            // uint8 public decimals
            hex"0000000000000000000000000000000000000000000000000000000000000002",
            /// 18
            hex"0000000000000000000000000000000000000000000000000000000000000012"
        );
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL1BlockNumber() public {
        _setImplementationCode(Predeploys.L1_BLOCK_NUMBER);
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setLegacyMessagePasser() public {
        _setImplementationCode(Predeploys.LEGACY_MESSAGE_PASSER);
    }

    /// @notice This predeploy is following the safety invariant #2.
    function setBaseFeeVault() public {
        BaseFeeVault vault = new BaseFeeVault({
            _recipient: cfg.baseFeeVaultRecipient(),
            _minWithdrawalAmount: cfg.baseFeeVaultMinimumWithdrawalAmount(),
            _withdrawalNetwork: FeeVault.WithdrawalNetwork(cfg.baseFeeVaultWithdrawalNetwork())
        });

        address impl = Predeploys.predeployToCodeNamespace(Predeploys.BASE_FEE_VAULT);
        console.log("Setting %s implementation at: %s", "BaseFeeVault", impl);
        vm.etch(impl, address(vault).code);

        /// Reset so its not included state dump
        vm.etch(address(vault), "");
        vm.resetNonce(address(vault));
    }

    /// @notice This predeploy is following the safety invariant #2.
    function setL1FeeVault() public {
        L1FeeVault vault = new L1FeeVault({
            _recipient: cfg.l1FeeVaultRecipient(),
            _minWithdrawalAmount: cfg.l1FeeVaultMinimumWithdrawalAmount(),
            _withdrawalNetwork: FeeVault.WithdrawalNetwork(cfg.l1FeeVaultWithdrawalNetwork())
        });

        address impl = Predeploys.predeployToCodeNamespace(Predeploys.L1_FEE_VAULT);
        console.log("Setting %s implementation at: %s", "L1FeeVault", impl);
        vm.etch(impl, address(vault).code);

        /// Reset so its not included state dump
        vm.etch(address(vault), "");
        vm.resetNonce(address(vault));
    }

    /// @notice This predeploy is following the safety invariant #2.
    function setGovernanceToken() public {
        if (!cfg.enableGovernance()) {
            console.log("Governance not enabled, skipping setting governanace token");
            return;
        }

        GovernanceToken token = new GovernanceToken();
        console.log("Setting %s implementation at: %s", "GovernanceToken", Predeploys.GOVERNANCE_TOKEN);
        vm.etch(Predeploys.GOVERNANCE_TOKEN, address(token).code);

        bytes32 _nameSlot = hex"0000000000000000000000000000000000000000000000000000000000000003";
        bytes32 _symbolSlot = hex"0000000000000000000000000000000000000000000000000000000000000004";
        bytes32 _ownerSlot = hex"000000000000000000000000000000000000000000000000000000000000000a";

        vm.store(Predeploys.GOVERNANCE_TOKEN, _nameSlot, vm.load(address(token), _nameSlot));
        vm.store(Predeploys.GOVERNANCE_TOKEN, _symbolSlot, vm.load(address(token), _symbolSlot));
        vm.store(Predeploys.GOVERNANCE_TOKEN, _ownerSlot, bytes32(uint256(uint160(cfg.governanceTokenOwner()))));

        /// Reset so its not included state dump
        vm.etch(address(token), "");
        vm.resetNonce(address(token));
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setSchemaRegistry() public {
        _setImplementationCode(Predeploys.SCHEMA_REGISTRY);
    }

    /// @notice This predeploy is following the safety invariant #2,
    ///         It uses low level create to deploy the contract due to the code
    ///         having immutables and being a different compiler version.
    function setEAS() public {
        string memory cname = Predeploys.getName(Predeploys.EAS);
        address impl = Predeploys.predeployToCodeNamespace(Predeploys.EAS);
        bytes memory code = vm.getCode(string.concat(cname, ".sol:", cname));

        address eas;
        assembly {
            eas := create(0, add(code, 0x20), mload(code))
        }

        console.log("Setting %s implementation at: %s", cname, impl);
        vm.etch(impl, eas.code);

        /// Reset so its not included state dump
        vm.etch(address(eas), "");
        vm.resetNonce(address(eas));
    }

    /// @dev Sets all the preinstalls.
    function setPreinstalls() internal {
        _setPreinstallCode(Preinstalls.MultiCall3);
        _setPreinstallCode(Preinstalls.Create2Deployer);
        _setPreinstallCode(Preinstalls.Safe_v130);
        _setPreinstallCode(Preinstalls.SafeL2_v130);
        _setPreinstallCode(Preinstalls.MultiSendCallOnly_v130);
        _setPreinstallCode(Preinstalls.SafeSingletonFactory);
        _setPreinstallCode(Preinstalls.DeterministicDeploymentProxy);
        _setPreinstallCode(Preinstalls.MultiSend_v130);
        _setPreinstallCode(Preinstalls.Permit2);
        _setPreinstallCode(Preinstalls.SenderCreator);
        _setPreinstallCode(Preinstalls.EntryPoint); // ERC 4337
        _setPreinstallCode(Preinstalls.BeaconBlockRoots);
    }

    function activateEcotone() public {
        bool hasBeaconBlockRoots = false;
        address addr = Preinstalls.BeaconBlockRoots;
        assembly {
            hasBeaconBlockRoots := extcodesize(addr)
        }
        require(hasBeaconBlockRoots, "must have beacon-block-roots contract");
        console.log("Activating ecotone in L1Block contract");
        vm.prank(L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).DEPOSITOR_ACCOUNT());
        L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).setL1BlockValuesEcotone();
    }

    /// @notice Sets the bytecode in state
    function _setImplementationCode(address _addr) internal returns (address) {
        string memory cname = Predeploys.getName(_addr);
        address impl = Predeploys.predeployToCodeNamespace(_addr);
        console.log("Setting %s implementation at: %s", cname, impl);
        vm.etch(impl, vm.getDeployedCode(string.concat(cname, ".sol:", cname)));
        return impl;
    }

    /// @notice Sets the bytecode in state
    function _setPreinstallCode(address _addr) internal {
        string memory cname = Preinstalls.getName(_addr);
        console.log("Setting %s preinstall code at: %s", cname, _addr);
        vm.etch(_addr, Preinstalls.getDeployedCode(_addr, cfg.l2ChainID()));
    }

    /// @notice Writes the genesis allocs, i.e. the state dump, to disk
    function writeGenesisAllocs(string memory _path) public {
        /// Reset so its not included state dump
        vm.etch(address(cfg), "");
        vm.etch(msg.sender, "");
        vm.resetNonce(msg.sender);
        vm.deal(msg.sender, 0);

        console.log("Writing state dump to: %s", _path);
        vm.dumpState(_path);
        sortJsonByKeys(_path);
    }

    /// @notice Sorts the allocs by address
    function sortJsonByKeys(string memory _path) internal {
        string[] memory commands = new string[](3);
        commands[0] = "bash";
        commands[1] = "-c";
        commands[2] = string.concat("cat <<< $(jq -S '.' ", _path, ") > ", _path);
        vm.ffi(commands);
    }

    /// @notice Funds the default dev accounts with ether
    function fundDevAccounts() internal {
        for (uint256 i; i < devAccounts.length; i++) {
            console.log("Funding dev account %s with %s ETH", devAccounts[i], DEV_ACCOUNT_FUND_AMT / 1e18);
            vm.deal(devAccounts[i], DEV_ACCOUNT_FUND_AMT);
        }
    }
}
