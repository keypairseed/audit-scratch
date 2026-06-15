// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PrecisionMath}  from "../../src/lib/PrecisionMath.sol";

/// @title ScalingOrderDifferential — [T-3 Differential Testing]
/// @notice NO RPC. Compares two CORRECT-LOOKING implementations that differ
///         only in OPERATION ORDER. The November 2025 Balancer exploit's
///         root cause was exactly this class: two code paths that SHOULD be
///         equivalent but diverge under specific scaling factors, creating
///         an exploitable two-stage manipulation.
///
///         This directly addresses the DeFi Saver hypothesis: their adapter
///         may assume one ordering while the patched Balancer pool now uses
///         the other. Differential fuzzing finds the exact (amount,
///         scalingFactor) pairs where they diverge.
contract ScalingOrderDifferential is Test {
    using PrecisionMath for uint256;

    // ── PATH A: "upscale, operate, downscale" (apply fee, THEN convert back)
    // Pattern: take user input in pool-native units, upscale to 18-decimals,
    // apply the operation (here: deduct a fee), downscale back.
    function pathA_feeAfterUpscale(
        uint256 amount,
        uint256 scalingFactor,
        uint256 feeBps
    ) internal pure returns (uint256) {
        uint256 upscaled  = PrecisionMath.upscale(amount, scalingFactor);
        uint256 afterFee  = upscaled - (upscaled * feeBps / 10_000);
        return PrecisionMath.downscaleDown(afterFee, scalingFactor);
    }

    // ── PATH B: "operate, then upscale/downscale" (apply fee in native units)
    // Pattern: deduct fee BEFORE any scaling — mathematically "should" be
    // equivalent for exact scalingFactor, but integer rounding at each step
    // can diverge.
    function pathB_feeBeforeScaling(
        uint256 amount,
        uint256 scalingFactor,
        uint256 feeBps
    ) internal pure returns (uint256) {
        uint256 afterFee = amount - (amount * feeBps / 10_000);
        uint256 upscaled = PrecisionMath.upscale(afterFee, scalingFactor);
        return PrecisionMath.downscaleDown(upscaled, scalingFactor);
    }

    // ── DIFFERENTIAL: the two paths should match within 1 wei ───────────────
    // If they diverge by MORE than 1 wei for some (amount, scalingFactor,
    // feeBps), that divergence is the exploitable two-stage manipulation
    // surface — same CLASS as the Nov 2025 exploit's 8-9 wei boundary.
    function testFuzz_feeOrderingDivergence(
        uint256 amount,
        uint256 scalingFactor,
        uint256 feeBps
    ) external pure {
        // scalingFactor range covers: USDC-style (1e30), wstETH-style (~1.2e18
        // adjusted), and edge cases near 1e18 (no adjustment)
        scalingFactor = bound(scalingFactor, 1e15, 1e21);
        amount        = bound(amount, 1, 1e30);
        feeBps        = bound(feeBps, 0, 1000); // 0-10%

        uint256 resultA = pathA_feeAfterUpscale(amount, scalingFactor, feeBps);
        uint256 resultB = pathB_feeBeforeScaling(amount, scalingFactor, feeBps);

        // Allow 1 wei divergence from independent rounding. >1 wei = finding.
        if (resultA > resultB) {
            assertLe(resultA - resultB, 1,
                "DIVERGENCE: Path A (upscale-first) yields MORE than Path B - exploitable");
        } else {
            assertLe(resultB - resultA, 1,
                "DIVERGENCE: Path B (fee-first) yields MORE than Path A - exploitable");
        }
    }

    // ── SPECIFIC BOUNDARY: replicate the 8-9 wei zone from the real exploit ─
    // The actual Nov-2025 attack operated in a narrow wei-boundary window.
    // This test exhaustively checks amount = 1..20 against realistic
    // wstETH/rETH/cbETH scaling factors observed on mainnet.
    function test_knownBoundaryZone() external pure {
        // Approximate real LST scaling factors (rate * 1e18), late-2025 values
        uint256[3] memory scalingFactors = [
            uint256(1_150_000_000_000_000_000), // wstETH ~1.15
            uint256(1_080_000_000_000_000_000), // rETH   ~1.08
            uint256(1_060_000_000_000_000_000)  // cbETH  ~1.06
        ];

        for (uint256 s = 0; s < scalingFactors.length; s++) {
            for (uint256 amount = 1; amount <= 20; amount++) {
                uint256 resultA = pathA_feeAfterUpscale(amount, scalingFactors[s], 30); // 0.3% fee
                uint256 resultB = pathB_feeBeforeScaling(amount, scalingFactors[s], 30);

                uint256 diff = resultA > resultB ? resultA - resultB : resultB - resultA;

                if (diff > 1) {
                    console2.log("DIVERGENCE FOUND");
                    console2.log("  scalingFactor:", scalingFactors[s]);
                    console2.log("  amount:       ", amount);
                    console2.log("  pathA result: ", resultA);
                    console2.log("  pathB result: ", resultB);
                    console2.log("  difference:   ", diff);
                }

                assertLe(diff, 1,
                    "Boundary zone divergence >1 wei at known-exploitable amounts");
            }
        }
    }
}
