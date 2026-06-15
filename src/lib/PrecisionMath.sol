// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PrecisionMath
/// @notice Generic 18-decimal fixed-point arithmetic + LST-style share conversion.
/// @dev These are standard published fixed-point formulas (not protocol-specific
///      proprietary code). Used to fuzz the ROUNDING-DIRECTION CLASS of bug
///      [T-29, T-37] that affects any protocol doing upscale/downscale or
///      shares<->assets conversion — Balancer rate providers, Lido stETH,
///      ERC-4626 vaults, etc.
library PrecisionMath {
    uint256 internal constant ONE = 1e18;

    // ── Fixed-point multiply/divide, both rounding directions ──────────────
    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        if (product == 0) return 0;
        return ((product - 1) / ONE) + 1;
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a * ONE) / b;
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return ((a * ONE - 1) / b) + 1;
    }

    // ── Scaling (upscale/downscale) — pattern used by rate-provider tokens ──
    // scalingFactor combines decimal normalization AND LST exchange rate.
    // e.g. wstETH: scalingFactor ≈ 1e18 * (wstETH/stETH rate) ≈ 1.15e18-1.30e18
    //      USDC (6 decimals, no rate): scalingFactor = 1e30 (10^(18-6) * 1e18)

    function upscale(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return mulDown(amount, scalingFactor);
    }

    function downscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return divDown(amount, scalingFactor);
    }

    function downscaleUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return divUp(amount, scalingFactor);
    }

    // ── LST-style share conversion (Lido pattern, fully generic) ───────────
    // Used by: Lido (stETH), Origin (OETH), any ERC-4626-like vault.

    function sharesToAssets(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        if (totalShares == 0) return shares; // 1:1 before first deposit
        return (shares * totalAssets) / totalShares;
    }

    function assetsToShares(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        if (totalAssets == 0) return assets; // 1:1 before first deposit
        return (assets * totalShares) / totalAssets;
    }
}
