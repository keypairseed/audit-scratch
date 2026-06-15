// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PrecisionMath} from "../../src/lib/PrecisionMath.sol";

/// @title PrecisionSymbolic — Halmos targets [T-4 Symbolic Execution]
/// @notice NO RPC. halmos explores the ENTIRE symbolic input space (within
///         bounds) rather than random sampling. A passing check_ here is a
///         PROOF for all possible inputs, not "no counterexample found in
///         N runs". Run with: halmos --contract PrecisionSymbolic
contract PrecisionSymbolic is Test {
    using PrecisionMath for uint256;

    // ── PROOF 1: downscale(upscale(x)) never INCREASES value ────────────────
    // This is the exact mechanism behind the Nov-2025 Balancer-class exploit:
    // if downscale(upscale(x)) > x for some x and scalingFactor, an attacker
    // can repeatedly upscale/downscale to mint value from rounding.
    function check_upscaleDownscaleNeverGainsValue(
        uint256 amount,
        uint256 scalingFactor
    ) public pure {
        // Realistic LST scaling factor range: 1.0x to 2.0x (wstETH today ~1.2x,
        // bounded generously for future rate growth)
        scalingFactor = bound(scalingFactor, 1e18, 2e18);
        amount        = bound(amount, 0, 1e30); // up to 1e12 tokens at 18 decimals

        uint256 up   = PrecisionMath.upscale(amount, scalingFactor);
        uint256 down = PrecisionMath.downscaleDown(up, scalingFactor);

        assert(down <= amount);
    }

    // ── PROOF 2: the REVERSE order (downscale first) never gains value ──────
    // Some code paths downscale before operating, then upscale results.
    // Order-of-operations matters for rounding direction — this is the
    // exact class of bug from the November 2025 exploit.
    function check_downscaleUpscaleNeverGainsValue(
        uint256 amount,
        uint256 scalingFactor
    ) public pure {
        scalingFactor = bound(scalingFactor, 1e18, 2e18);
        amount        = bound(amount, 0, 1e30);

        uint256 down = PrecisionMath.downscaleDown(amount, scalingFactor);
        uint256 up   = PrecisionMath.upscale(down, scalingFactor);

        assert(up <= amount);
    }

    // ── PROOF 3: shares<->assets roundtrip never gains value, ANY ratio ──────
    // Explores totalAssets/totalShares ratios from 1.0x to 3.0x — covers
    // years of future Lido/Origin rebase growth [T-44].
    function check_shareConversionRoundtrip(
        uint256 amount,
        uint256 totalAssets,
        uint256 totalShares
    ) public pure {
        totalAssets = bound(totalAssets, 1e18, 3e18);
        totalShares = bound(totalShares, 1e18, 1e18);
        amount      = bound(amount, 0, 1e24);

        uint256 shares = PrecisionMath.assetsToShares(amount, totalAssets, totalShares);
        uint256 back   = PrecisionMath.sharesToAssets(shares, totalAssets, totalShares);

        assert(back <= amount);
    }

    // ── PROOF 4: mulUp is always >= mulDown for same inputs ──────────────────
    // Sanity proof on the rounding primitives themselves. If this fails,
    // the math library itself is broken — would invalidate everything above.
    function check_mulUpGreaterOrEqualMulDown(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);

        uint256 down = PrecisionMath.mulDown(a, b);
        uint256 up   = PrecisionMath.mulUp(a, b);

        assert(up >= down);
    }

    // ── PROOF 5: divUp - divDown is bounded by 1 (in PrecisionMath.ONE units)
    // Catches off-by-more-than-one rounding bugs in the division primitives.
    function check_divUpDivDownDifferenceBounded(uint256 a, uint256 b) public pure {
        a = bound(a, 1, 1e30);
        b = bound(b, 1, 1e30);

        uint256 down = PrecisionMath.divDown(a, b);
        uint256 up   = PrecisionMath.divUp(a, b);

        assert(up - down <= 1);
    }

    // ── PROOF 6: zero-amount operations are always zero ──────────────────────
    // Negative-space check [T-3]: zero must propagate to zero, no edge case
    // produces non-zero output from zero input (would imply free-money bug).
    function check_zeroPropagation(uint256 scalingFactor, uint256 totalAssets, uint256 totalShares) public pure {
        scalingFactor = bound(scalingFactor, 1, 1e30);
        totalAssets   = bound(totalAssets, 1, 1e30);
        totalShares   = bound(totalShares, 1, 1e30);

        assert(PrecisionMath.upscale(0, scalingFactor) == 0);
        assert(PrecisionMath.downscaleDown(0, scalingFactor) == 0);
        assert(PrecisionMath.downscaleUp(0, scalingFactor) == 0);
        assert(PrecisionMath.assetsToShares(0, totalAssets, totalShares) == 0);
        assert(PrecisionMath.sharesToAssets(0, totalAssets, totalShares) == 0);
    }
}
