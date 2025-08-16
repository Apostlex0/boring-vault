// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BaseDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

contract HyperliquidDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error HyperliquidDecoderAndSanitizer__InvalidAddress();
    error HyperliquidDecoderAndSanitizer__CallbackNotSupported();
   

    //============================== WETHYPE ===============================

    function deposit() external pure returns (bytes memory addressesFound) {
        return addressesFound; // wHYPE deposit() has no addresses
    }

    function withdraw(uint256) external pure returns (bytes memory addressesFound) {
        return addressesFound; // wHYPE withdraw(uint256) has no addresses
    }

    //============================== OVERSEER ===============================

    function mint(address to) external pure returns (bytes memory addressesFound) {
        if (to == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(to);
    }

    function mint(address to, string calldata) 
        external pure returns (bytes memory addressesFound) 
    {
        if (to == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(to);
    }

    function burnAndRedeemIfPossible(
        address to, 
        uint256, 
        string calldata
    ) external pure returns (bytes memory addressesFound) {
        if (to == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(to);
    }

    function redeem(uint256) external pure returns (bytes memory addressesFound) {
        return addressesFound;
    }

    function previewRedeem(uint256, address) external pure returns (bytes memory addressesFound) {
        return addressesFound;
    }

    //============================== FELIX (MORPHO) ===============================

    function borrow(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        address receiver
    ) external pure returns (bytes memory addressesFound) {
        // Validate addresses
        if (onBehalf == address(0) || receiver == address(0)) 
            revert HyperliquidDecoderAndSanitizer__InvalidAddress();

        addressesFound = abi.encodePacked(
            params.loanToken, 
            params.collateralToken, 
            params.oracle, 
            params.irm, 
            onBehalf, 
            receiver
        );
    }

    function repay(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        bytes calldata data
    ) external pure returns (bytes memory addressesFound) {
        // Sanitize raw data - reject callbacks
        if (data.length > 0) revert HyperliquidDecoderAndSanitizer__CallbackNotSupported();
        // Validate onBehalf address
        if (onBehalf == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();

        addressesFound = abi.encodePacked(
            params.loanToken, 
            params.collateralToken, 
            params.oracle, 
            params.irm, 
            onBehalf
        );
    }

    function supplyCollateral(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        address onBehalf,
        bytes calldata data
    ) external pure returns (bytes memory addressesFound) {
        // Sanitize raw data - reject callbacks
        if (data.length > 0) revert HyperliquidDecoderAndSanitizer__CallbackNotSupported();
        // Validate onBehalf address
        if (onBehalf == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(
            params.loanToken, 
            params.collateralToken, 
            params.oracle, 
            params.irm, 
            onBehalf
        );
    }
    
    function withdrawCollateral(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        address onBehalf,
        address receiver
    ) external pure returns (bytes memory addressesFound) {
        // Validate addresses
        if (onBehalf == address(0) || receiver == address(0)) 
            revert HyperliquidDecoderAndSanitizer__InvalidAddress();

        addressesFound = abi.encodePacked(
            params.loanToken, 
            params.collateralToken, 
            params.oracle, 
            params.irm, 
            onBehalf, 
            receiver
        );
    }

    //============================== ERC20 ===============================

    function approve(address spender, uint256) 
        external pure override returns (bytes memory addressesFound) 
    {
        if (spender == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(spender);
    }

    function transfer(address to, uint256) 
        external pure override returns (bytes memory addressesFound) 
    {
        if (to == address(0)) revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(to);
    }

    function transferFrom(address from, address to, uint256) 
        external pure returns (bytes memory addressesFound) 
    {
        if (from == address(0) || to == address(0)) 
            revert HyperliquidDecoderAndSanitizer__InvalidAddress();
        addressesFound = abi.encodePacked(from, to);
    }
}