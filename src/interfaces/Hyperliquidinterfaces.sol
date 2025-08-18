// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ========== FELIX (Morpho-like lending protocol) Interface ==========
interface IFelix {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) external;

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256, uint256);

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    // Query functions for debt calculation
    function position(bytes32 id, address user) external view returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);
    
    function market(bytes32 id) external view returns (uint128 totalSupplyAssets, uint128 totalSupplyShares, uint128 totalBorrowAssets, uint128 totalBorrowShares, uint128 lastUpdate, uint128 fee);
    
    function accrueInterest(MarketParams memory marketParams) external;
}

// ========== OVERSEER Interface ==========
interface IOverseer {
    // Overloaded mint functions
    function mint(address to) external payable returns (uint256);
    
    function mint(address to, string memory communityCode) external payable returns (uint256);

    // Overloaded burn functions
    function burn(address to, uint256 amount) external returns (uint256);
    
    function burn(address to, uint256 amount, string memory communityCode) external returns (uint256);

    // Primary burn function - burns and instantly redeems up to maxRedeemable(), returns burnID for rest
    function burnAndRedeemIfPossible(
        address to,
        uint256 amount,
        string memory communityCode
    ) external returns (uint256 burnID);

    // Check maximum amount that can be instantly redeemed
    function maxRedeemable() external view returns (uint256);

    // Check if a burn request is ready for redemption
    function redeemable(uint256 burnId) external view returns (bool);

    // Redeem pending HYPE from a completed burn request
    function redeem(uint256 burnId) external;
}

// ========== stHYPE Interface ==========
interface IstHYPE {
    function approve(address spender, uint256 value) external returns (bool);
}

// ========== wstHYPE (Wrapped staked HYPE) Interface ==========
interface IwstHYPE {
    function approve(address spender, uint256 value) external returns (bool);
}

// ========== WHYPE (Wrapped HYPE) Interface ==========
interface IWHYPE {
    function withdraw(uint256 wad) external;

    function deposit() external payable;
    
    function approve(address spender, uint256 value) external returns (bool);
}