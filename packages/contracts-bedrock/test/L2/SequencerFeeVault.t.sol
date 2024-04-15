// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Reverter } from "test/mocks/Callers.sol";
import { StandardBridge } from "src/universal/StandardBridge.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contract dependencies
import { FeeVault } from "src/universal/FeeVault.sol";

// Target contract
import { SequencerFeeVault } from "src/L2/SequencerFeeVault.sol";

contract SequencerFeeVault_Test is CommonTest {
    address recipient;

    /// @dev Sets up the test suite.
    function setUp() public override {
        super.setUp();
        recipient = deploy.cfg().sequencerFeeVaultRecipient();
    }

    /// @dev Tests that the l1 fee wallet is correct.
    function test_constructor_succeeds() external {
        assertEq(sequencerFeeVault.l1FeeWallet(), recipient);
    }

    /// @dev Tests that the fee vault is able to receive ETH.
    function test_receive_succeeds() external {
        uint256 balance = address(sequencerFeeVault).balance;

        vm.prank(alice);
        (bool success,) = address(sequencerFeeVault).call{ value: 100 }(hex"");

        assertEq(success, true);
        assertEq(address(sequencerFeeVault).balance, balance + 100);
    }

    /// @dev Tests that `withdraw` successfully initiates a withdrawal to L1.
    function test_withdraw_toL1_succeeds() external {
        uint256 amount = 1;
        vm.deal(address(sequencerFeeVault), amount);

        // No ether has been withdrawn yet
        assertEq(sequencerFeeVault.totalProcessed(), 0);

        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this));
        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this));

        // The entire vault's balance is withdrawn
        vm.expectCall(
            Predeploys.L2_STANDARD_BRIDGE,
            address(sequencerFeeVault).balance,
            abi.encodeWithSelector(
                StandardBridge.bridgeETHTo.selector, sequencerFeeVault.l1FeeWallet(), 35_000, bytes("")
            )
        );

        sequencerFeeVault.withdraw();

        // The withdrawal was successful
        assertEq(sequencerFeeVault.totalProcessed(), amount);
        assertEq(address(sequencerFeeVault).balance, 0);
        assertEq(Predeploys.L2_TO_L1_MESSAGE_PASSER.balance, amount);
    }
}

contract SequencerFeeVault_L2Withdrawal_Test is CommonTest {
    /// @dev a cache for the config fee recipient
    address recipient;

    /// @dev Sets up the test suite.
    function setUp() public override {
        super.setUp();

        // Alter the deployment to use WithdrawalNetwork.L2
        vm.etch(EIP1967Helper.getImplementation(Predeploys.SEQUENCER_FEE_WALLET), address(new SequencerFeeVault()).code);

        recipient = deploy.cfg().sequencerFeeVaultRecipient();
    }

    /// @dev Tests that `withdraw` successfully initiates a withdrawal to L2.
    function test_withdraw_toL2_succeeds() external {
        uint256 amount = 1;
        vm.deal(address(sequencerFeeVault), amount);

        // No ether has been withdrawn yet
        assertEq(sequencerFeeVault.totalProcessed(), 0);

        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this));
        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this));

        // The entire vault's balance is withdrawn
        vm.expectCall(recipient, address(sequencerFeeVault).balance, bytes(""));

        sequencerFeeVault.withdraw();

        // The withdrawal was successful
        assertEq(sequencerFeeVault.totalProcessed(), amount);
        assertEq(address(sequencerFeeVault).balance, 0);
        assertEq(recipient.balance, amount);
    }
}
