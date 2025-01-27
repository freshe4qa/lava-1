package types

import (
	"encoding/binary"

	tendermintcrypto "github.com/tendermint/tendermint/crypto"
)

const (
	StateCommit = 0
	StateReveal = 1
)

// vote status for each voter
const (
	NoVote             = 0
	Commit             = 1
	Provider0          = 2
	Provider1          = 3
	NoneOfTheProviders = 4
)

const (
	ConflictVoteRevealEventName        = "conflict_vote_reveal_started"
	ConflictDetectionRecievedEventName = "conflict_detection_received"
	ConflictVoteDetectionEventName     = "response_conflict_detection"
	ConflictVoteResolvedEventName      = "conflict_detection_vote_resolved"
	ConflictVoteUnresolvedEventName    = "conflict_detection_vote_unresolved"
	ConflictVoteGotCommitEventName     = "conflict_vote_got_commit"
	ConflictVoteGotRevealEventName     = "conflict_vote_got_reveal"
	ConflictUnstakeFraudVoterEventName = "conflict_unstake_fraud_voter"
)

// unstake description
const (
	UnstakeDescriptionFraudVote = "fraud provider found in conflict detection"
)

func CommitVoteData(nonce int64, dataHash []byte) []byte {
	commitData := make([]byte, 8) // nonce bytes
	binary.LittleEndian.PutUint64(commitData, uint64(nonce))
	commitData = append(commitData, dataHash...)
	commitDataHash := tendermintcrypto.Sha256(commitData)
	return commitDataHash
}
