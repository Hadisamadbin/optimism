package genesis

import (
	"fmt"

	"github.com/holiman/uint256"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core"
	gstate "github.com/ethereum/go-ethereum/core/state"
	"github.com/ethereum/go-ethereum/core/types"

	"github.com/ethereum-optimism/optimism/op-bindings/predeploys"
)

// BuildL2Genesis will build the L2 genesis block.
func BuildL2Genesis(config *DeployConfig, dump *gstate.Dump, l1StartBlock *types.Block) (*core.Genesis, error) {
	genspec, err := NewL2Genesis(config, l1StartBlock)
	if err != nil {
		return nil, err
	}
	// We may want to switch to just parsing the dump with the assumption that it
	// does not contain malformed accounts and storage values that otherwise have to be handled gracefully like below.
	for addrstr, acc := range dump.Accounts {
		if !common.IsHexAddress(addrstr) {
			// quirk because we use the "dump" type, which supports colliding preimages for otherwise invalid accounts.
			continue
		}
		addr := common.HexToAddress(addrstr)
		var result core.GenesisAccount
		if len(acc.Storage) > 0 {
			result.Storage = make(map[common.Hash]common.Hash, len(acc.Storage))
			for k, v := range acc.Storage {
				result.Storage[k] = common.HexToHash(v)
			}
		}
		var v uint256.Int
		if err := v.UnmarshalText([]byte(acc.Balance)); err != nil {
			return nil, fmt.Errorf("failed to parse balance of %s: %w", addr, err)
		}
		result.Balance = v.ToBig()
		result.Nonce = acc.Nonce
		result.Code = acc.Code
		genspec.Alloc[addr] = result
	}
	// sanity check the permit2 immutable, to verify we using the allocs for the right chain.
	chainID := [32]byte(genspec.Alloc[predeploys.Permit2Addr].Code[6945 : 6945+32])
	expected := uint256.MustFromBig(genspec.Config.ChainID).Bytes32()
	if chainID != expected {
		return nil, fmt.Errorf("allocs were generated for chain ID %x, but expected chain %x (%d)", chainID, expected, genspec.Config.ChainID)
	}
	return genspec, nil
}
