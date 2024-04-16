package genesis

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/holiman/uint256"

	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/types"

	"github.com/ethereum-optimism/optimism/op-bindings/predeploys"
)

type L2AllocsMode string

const (
	L2AllocsDelta   L2AllocsMode = "-delta"
	L2AllocsEcotone L2AllocsMode = "" // the default in solidity scripting / testing
)

type AllocsLoader func(mode L2AllocsMode) *ForgeAllocs

// BuildL2Genesis will build the L2 genesis block.
func BuildL2Genesis(config *DeployConfig, dump *ForgeAllocs, l1StartBlock *types.Block) (*core.Genesis, error) {
	genspec, err := NewL2Genesis(config, l1StartBlock)
	if err != nil {
		return nil, err
	}
	genspec.Alloc = dump.Accounts
	// sanity check the permit2 immutable, to verify we using the allocs for the right chain.
	chainID := [32]byte(genspec.Alloc[predeploys.Permit2Addr].Code[6945 : 6945+32])
	expected := uint256.MustFromBig(genspec.Config.ChainID).Bytes32()
	if chainID != expected {
		return nil, fmt.Errorf("allocs were generated for chain ID %x, but expected chain %x (%d)", chainID, expected, genspec.Config.ChainID)
	}
	return genspec, nil
}

func LoadForgeAllocs(allocsPath string) (*ForgeAllocs, error) {
	path := filepath.Join(allocsPath)
	f, err := os.OpenFile(path, os.O_RDONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open forge allocs %q: %w", path, err)
	}
	defer f.Close()
	var out ForgeAllocs
	if err := json.NewDecoder(f).Decode(&out); err != nil {
		return nil, fmt.Errorf("failed to json-decode forge allocs %q: %w", path, err)
	}
	return &out, nil
}
