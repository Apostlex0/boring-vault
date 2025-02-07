// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {IRecipeMarketHub} from "src/interfaces/RawDataDecoderAndSanitizerInterfaces.sol";

abstract contract RoycoWeirollDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERRORS ===============================

    error RoycoWeirollDecoderAndSanitizer__TooManyOfferHashes();

    //============================== IMMUTABLES ===============================

    IRecipeMarketHub internal immutable recipeMarketHub;

    constructor(address _recipeMarketHub) {
        recipeMarketHub = IRecipeMarketHub(_recipeMarketHub);
    }

    function fillIPOffers(
        bytes32[] calldata ipOfferHashes,
        uint256[] calldata, /*fillAmounts*/
        address fundingVault,
        address frontendFeeRecipient
    ) external view virtual returns (bytes memory addressesFound) {
        if (ipOfferHashes.length != 1) revert RoycoWeirollDecoderAndSanitizer__TooManyOfferHashes();

        (, bytes32 marketHash,,,,) = recipeMarketHub.offerHashToIPOffer(ipOfferHashes[0]);

        address marketHash0 = address(bytes20(bytes16(marketHash)));
        address marketHash1 = address(bytes20(bytes16(marketHash << 128)));
        return abi.encodePacked(marketHash0, marketHash1, fundingVault, frontendFeeRecipient);
    }

    function executeWithdrawalScript(address weirollWallet)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        //WeirollWallet will check that the caller is owner (boring vault)
        //but we check here before delegating for safety.
        address owner = IWeirollWalletHelper(weirollWallet).owner();
        return abi.encodePacked(owner);
    }

    function forfeit(address weirollWallet, bool /*executeWithdraw*/ )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        //WeirollWallet will check that the caller is owner (boring vault)
        //but we check here before delegating for safety.
        address owner = IWeirollWalletHelper(weirollWallet).owner();
        addressesFound = abi.encodePacked(owner);
    }

    function claim(address weirollWallet, address to) external view virtual returns (bytes memory addressesFound) {
        address owner = IWeirollWalletHelper(weirollWallet).owner();
        addressesFound = abi.encodePacked(owner, to);
    }

    function claim(address to) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(to);
    }

    function merkleWithdraw() external pure virtual returns (bytes memory addressesFound) {
        return addressesFound;
    }

    function withdrawMerkleDeposit(
        address _weirollWallet,
        uint256, /*_merkleDepositNonce*/
        uint256, /*_amountDepositedOnSource*/
        bytes32[] calldata /*_merkleProof*/
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_weirollWallet);
    }
}

interface IWeirollWalletHelper {
    function owner() external view returns (address);
}
