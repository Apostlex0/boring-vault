// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract SymbioticVaultDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== SYMBIOTIC ===============================

    function deposit(address onBehalfOf, uint256 /*amount*/ )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(onBehalfOf);
    }

    function withdraw(address claimer, uint256 /*amount*/ )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(claimer);
    }

    //  Pulled from https://github.com/symbioticfi/rewards/blob/7844a6ceaf4d740c7083a37e410194c1ef7867d3/src/contracts/defaultOperatorRewards/DefaultOperatorRewards.sol#L75-L81
    function claimRewards(
        address recipient,
        address, /*network*/
        address, /*token*/
        uint256, /*totalClaimable*/
        bytes32[] calldata /*proof*/
    ) external pure virtual returns (bytes memory addressesFound) {
        // We only sanitize recipient since this function only increases value for the boring vault.
        addressesFound = abi.encodePacked(recipient);
    }

    function claim(address recipient, uint256 /*epoch*/ ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(recipient);
    }

    function claimBatch(address recipient, uint256[] calldata /*epoch*/ )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(recipient);
    }
}
