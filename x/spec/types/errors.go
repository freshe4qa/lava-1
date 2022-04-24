package types

// DONTCOVER

import (
	sdkerrors "github.com/cosmos/cosmos-sdk/types/errors"
)

// x/spec module sentinel errors
var (
	ErrSample = sdkerrors.Register(ModuleName, 1100, "sample error")

	//
	// Proposal errors
	ErrEmptySpecs        = sdkerrors.Register(ModuleName, 2, "specs list is empty")
	ErrEmptyApis         = sdkerrors.Register(ModuleName, 3, "apis list is empty")
	ErrBlankApiName      = sdkerrors.Register(ModuleName, 4, "api name is blank")
	ErrBlankSpecName     = sdkerrors.Register(ModuleName, 5, "spec name is blank")
	ErrDuplicateApiName  = sdkerrors.Register(ModuleName, 6, "api name is not unique")
	ErrSpecNotFound      = sdkerrors.Register(ModuleName, 7, "spec not found")
	ErrDuplicateSpecName = sdkerrors.Register(ModuleName, 8, "spec name is not unique")
)