// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {HyperliquidDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/HyperLiquidDecoderAndSanitizer.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";

contract HyperLiquidDecoderAndSanitizerTest is Test {
    using stdStorage for StdStorage;

    HyperliquidDecoderAndSanitizer public decoder;
    
    // Test addresses
    address public constant VALID_ADDRESS = 0x1234567890123456789012345678901234567890;
    address public constant ZERO_ADDRESS = address(0);
    address public constant BORING_VAULT = 0x1234567890123456789012345678901234567891;
    address public constant LOAN_TOKEN = 0x1111111111111111111111111111111111111111;
    address public constant COLLATERAL_TOKEN = 0x2222222222222222222222222222222222222222;
    address public constant ORACLE = 0x3333333333333333333333333333333333333333;
    address public constant IRM = 0x4444444444444444444444444444444444444444;

    function setUp() external {
        decoder = new HyperliquidDecoderAndSanitizer();
    }

    // ========================================= wHYPE FUNCTIONS =========================================

    function testWHYPEDeposit() external {
        bytes memory addressesFound = decoder.deposit();
        
        // deposit() should return empty bytes as it has no address parameters
        assertEq(addressesFound.length, 0, "deposit() should return empty addresses");
    }

    function testWHYPEWithdraw() external {
        uint256 amount = 1000e18;
        bytes memory addressesFound = decoder.withdraw(amount);
        
        // withdraw(uint256) should return empty bytes as it has no address parameters
        assertEq(addressesFound.length, 0, "withdraw() should return empty addresses");
    }

    // ========================================= OVERSEER FUNCTIONS =========================================

    function testOverseerMintWithValidAddress() external {
        bytes memory addressesFound = decoder.mint(VALID_ADDRESS);
        
        // Should return the address packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "mint() should return the to address");
    }

    function testOverseerMintWithZeroAddressReverts() external {
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.mint(ZERO_ADDRESS);
    }

    function testOverseerMintWithCommunityCodeValidAddress() external {
        string memory communityCode = "test-community";
        bytes memory addressesFound = decoder.mint(VALID_ADDRESS, communityCode);
        
        // Should return the address packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "mint() with community code should return the to address");
    }

    function testOverseerMintWithCommunityCodeZeroAddressReverts() external {
        string memory communityCode = "test-community";
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.mint(ZERO_ADDRESS, communityCode);
    }

    function testOverseerBurnAndRedeemIfPossible() external {
        uint256 amount = 500e18;
        string memory communityCode = "test-community";
        bytes memory addressesFound = decoder.burnAndRedeemIfPossible(VALID_ADDRESS, amount, communityCode);
        
        // Should return the to address packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "burnAndRedeemIfPossible() should return the to address");
    }

    function testOverseerBurnAndRedeemIfPossibleZeroAddressReverts() external {
        uint256 amount = 500e18;
        string memory communityCode = "test-community";
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.burnAndRedeemIfPossible(ZERO_ADDRESS, amount, communityCode);
    }

    // ========================================= ERC20 FUNCTIONS =========================================

    function testERC20Transfer() external {
        uint256 amount = 1000e18;
        bytes memory addressesFound = decoder.transfer(VALID_ADDRESS, amount);
        
        // Should return the to address packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "transfer() should return the to address");
    }

    function testERC20TransferZeroAddressReverts() external {
        uint256 amount = 1000e18;
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.transfer(ZERO_ADDRESS, amount);
    }

    function testERC20TransferFrom() external {
        uint256 amount = 1000e18;
        bytes memory addressesFound = decoder.transferFrom(VALID_ADDRESS, BORING_VAULT, amount);
        
        // Should return both from and to addresses packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS, BORING_VAULT);
        assertEq(addressesFound, expected, "transferFrom() should return from and to addresses");
    }

    function testERC20TransferFromZeroFromAddressReverts() external {
        uint256 amount = 1000e18;
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.transferFrom(ZERO_ADDRESS, BORING_VAULT, amount);
    }

    function testERC20TransferFromZeroToAddressReverts() external {
        uint256 amount = 1000e18;
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.transferFrom(VALID_ADDRESS, ZERO_ADDRESS, amount);
    }

    function testERC20Approve() external {
        uint256 amount = 1000e18;
        bytes memory addressesFound = decoder.approve(VALID_ADDRESS, amount);
        
        // Should return the spender address packed in bytes
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "approve() should return the spender address");
    }

    function testERC20ApproveZeroAddressReverts() external {
        uint256 amount = 1000e18;
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.approve(ZERO_ADDRESS, amount);
    }

    // ========================================= FELIX (MORPHO) FUNCTIONS =========================================

    function _createValidMarketParams() internal pure returns (DecoderCustomTypes.MarketParams memory) {
        return DecoderCustomTypes.MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: ORACLE,
            irm: IRM,
            lltv: 800000000000000000 // 80% LLTV
        });
    }

    function testFelixBorrow() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        
        bytes memory addressesFound = decoder.borrow(params, amount, shares, BORING_VAULT, VALID_ADDRESS);
        
        // Should return 6 addresses: loanToken, collateralToken, oracle, irm, onBehalf, receiver
        bytes memory expected = abi.encodePacked(
            params.loanToken,
            params.collateralToken, 
            params.oracle,
            params.irm,
            BORING_VAULT,
            VALID_ADDRESS
        );
        assertEq(addressesFound, expected, "borrow() should return all 6 addresses");
    }

    function testFelixBorrowZeroOnBehalfReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.borrow(params, amount, shares, ZERO_ADDRESS, VALID_ADDRESS);
    }

    function testFelixBorrowZeroReceiverReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.borrow(params, amount, shares, BORING_VAULT, ZERO_ADDRESS);
    }

    function testFelixRepay() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        bytes memory emptyData = "";
        
        bytes memory addressesFound = decoder.repay(params, amount, shares, BORING_VAULT, emptyData);
        
        // Should return 5 addresses: loanToken, collateralToken, oracle, irm, onBehalf
        bytes memory expected = abi.encodePacked(
            params.loanToken,
            params.collateralToken,
            params.oracle,
            params.irm,
            BORING_VAULT
        );
        assertEq(addressesFound, expected, "repay() should return all 5 addresses");
    }

    function testFelixRepayZeroOnBehalfReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        bytes memory emptyData = "";
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.repay(params, amount, shares, ZERO_ADDRESS, emptyData);
    }

    function testFelixRepayWithCallbackDataReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        uint256 shares = 900e18;
        bytes memory callbackData = "malicious callback";
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__CallbackNotSupported.selector);
        decoder.repay(params, amount, shares, BORING_VAULT, callbackData);
    }

    function testFelixSupplyCollateral() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        bytes memory emptyData = "";
        
        bytes memory addressesFound = decoder.supplyCollateral(params, amount, BORING_VAULT, emptyData);
        
        // Should return 5 addresses: loanToken, collateralToken, oracle, irm, onBehalf
        bytes memory expected = abi.encodePacked(
            params.loanToken,
            params.collateralToken,
            params.oracle,
            params.irm,
            BORING_VAULT
        );
        assertEq(addressesFound, expected, "supplyCollateral() should return all 5 addresses");
    }

    function testFelixSupplyCollateralZeroOnBehalfReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        bytes memory emptyData = "";
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.supplyCollateral(params, amount, ZERO_ADDRESS, emptyData);
    }

    function testFelixSupplyCollateralWithCallbackDataReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        bytes memory callbackData = "malicious callback";
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__CallbackNotSupported.selector);
        decoder.supplyCollateral(params, amount, BORING_VAULT, callbackData);
    }

    function testFelixWithdrawCollateral() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        
        bytes memory addressesFound = decoder.withdrawCollateral(params, amount, BORING_VAULT, VALID_ADDRESS);
        
        // Should return 6 addresses: loanToken, collateralToken, oracle, irm, onBehalf, receiver
        bytes memory expected = abi.encodePacked(
            params.loanToken,
            params.collateralToken,
            params.oracle,
            params.irm,
            BORING_VAULT,
            VALID_ADDRESS
        );
        assertEq(addressesFound, expected, "withdrawCollateral() should return all 6 addresses");
    }

    function testFelixWithdrawCollateralZeroOnBehalfReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.withdrawCollateral(params, amount, ZERO_ADDRESS, VALID_ADDRESS);
    }

    function testFelixWithdrawCollateralZeroReceiverReverts() external {
        DecoderCustomTypes.MarketParams memory params = _createValidMarketParams();
        uint256 amount = 1000e18;
        
        vm.expectRevert(HyperliquidDecoderAndSanitizer.HyperliquidDecoderAndSanitizer__InvalidAddress.selector);
        decoder.withdrawCollateral(params, amount, BORING_VAULT, ZERO_ADDRESS);
    }

    // ========================================= EDGE CASES =========================================

    function testFuzzValidAddresses(address validAddr) external {
        vm.assume(validAddr != address(0));
        
        // Test mint function with fuzzed valid address
        bytes memory addressesFound = decoder.mint(validAddr);
        bytes memory expected = abi.encodePacked(validAddr);
        assertEq(addressesFound, expected, "mint() should work with any valid address");
        
        // Test transfer function with fuzzed valid address
        addressesFound = decoder.transfer(validAddr, 100e18);
        expected = abi.encodePacked(validAddr);
        assertEq(addressesFound, expected, "transfer() should work with any valid address");
    }

    function testFuzzAmounts(uint256 amount) external {
        // Test withdraw with fuzzed amounts
        bytes memory addressesFound = decoder.withdraw(amount);
        assertEq(addressesFound.length, 0, "withdraw() should always return empty addresses regardless of amount");
        
        // Test transfer with fuzzed amounts
        addressesFound = decoder.transfer(VALID_ADDRESS, amount);
        bytes memory expected = abi.encodePacked(VALID_ADDRESS);
        assertEq(addressesFound, expected, "transfer() should work with any amount");
    }

    function testMultipleConsecutiveCalls() external {
        // Test that decoder state doesn't interfere between calls
        bytes memory result1 = decoder.mint(VALID_ADDRESS);
        bytes memory result2 = decoder.mint(BORING_VAULT);
        bytes memory result3 = decoder.transfer(VALID_ADDRESS, 100e18);
        
        assertEq(result1, abi.encodePacked(VALID_ADDRESS), "First call should work correctly");
        assertEq(result2, abi.encodePacked(BORING_VAULT), "Second call should work correctly");
        assertEq(result3, abi.encodePacked(VALID_ADDRESS), "Third call should work correctly");
    }
}
