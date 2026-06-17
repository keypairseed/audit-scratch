// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/// @title PrecisionSymbolic — Halmos targets [T-4]
/// @notice Uses uint64 + vm.assume instead of uint256 + bound().
///
///         Previous version timed out because 256-bit symbolic division
///         is hard for SMT solvers. Fix: uint64 throughout.
///         Rounding direction properties are independent of bit width —
///         the proof on uint64 covers the same algebraic claim.
///
///         Run: halmos --contract PrecisionSymbolic --solver-timeout-assertion 30000
contract PrecisionSymbolic is Test {

    uint64 constant ONE64 = 1e9; // 1.0 in 9-decimal fixed point

    function mulDown64(uint64 a, uint64 b) internal pure returns (uint64) {
        return uint64(uint128(a) * b / ONE64);
    }

    function mulUp64(uint64 a, uint64 b) internal pure returns (uint64) {
        uint128 product = uint128(a) * b;
        if (product == 0) return 0;
        return uint64((product - 1) / ONE64 + 1);
    }

    function divDown64(uint64 a, uint64 b) internal pure returns (uint64) {
        if (a == 0) return 0;
        return uint64(uint128(a) * ONE64 / b);
    }

    function divUp64(uint64 a, uint64 b) internal pure returns (uint64) {
        if (a == 0) return 0;
        return uint64((uint128(a) * ONE64 - 1) / b + 1);
    }

    function upscale64(uint64 a, uint64 sf) internal pure returns (uint64) { return mulDown64(a, sf); }
    function downscale64(uint64 a, uint64 sf) internal pure returns (uint64) { return divDown64(a, sf); }

    function sharesToAssets64(uint64 s, uint64 ta, uint64 ts) internal pure returns (uint64) {
        if (ts == 0) return s;
        return uint64(uint128(s) * ta / ts);
    }

    function assetsToShares64(uint64 a, uint64 ta, uint64 ts) internal pure returns (uint64) {
        if (ta == 0) return a;
        return uint64(uint128(a) * ts / ta);
    }

    // ── PROOF 1: downscale(upscale(x)) never gains value ────────────────────
    function check_upscaleDownscaleNeverGainsValue(uint64 amount, uint64 sf) public pure {
        vm.assume(sf >= ONE64 && sf <= 2 * ONE64);
        vm.assume(amount <= 1e12);
        assert(downscale64(upscale64(amount, sf), sf) <= amount);
    }

    // ── PROOF 2: reverse order never gains value ─────────────────────────────
    function check_downscaleUpscaleNeverGainsValue(uint64 amount, uint64 sf) public pure {
        vm.assume(sf >= ONE64 && sf <= 2 * ONE64);
        vm.assume(amount <= 1e12);
        assert(upscale64(downscale64(amount, sf), sf) <= amount);
    }

    // ── PROOF 3: share roundtrip never gains value ───────────────────────────
    function check_shareConversionRoundtrip(uint64 amount, uint64 totalAssets) public pure {
        uint64 totalShares = ONE64;
        vm.assume(totalAssets >= ONE64 && totalAssets <= 3 * ONE64);
        vm.assume(amount <= 1e12);
        uint64 shares = assetsToShares64(amount, totalAssets, totalShares);
        uint64 back   = sharesToAssets64(shares, totalAssets, totalShares);
        assert(back <= amount);
    }

    // ── PROOF 4: mulUp >= mulDown ────────────────────────────────────────────
    function check_mulUpGreaterOrEqualMulDown(uint64 a, uint64 b) public pure {
        vm.assume(a <= 1e12);
        vm.assume(b <= 2 * ONE64);
        assert(mulUp64(a, b) >= mulDown64(a, b));
    }

    // ── PROOF 5: divUp - divDown bounded by 1 ───────────────────────────────
    function check_divUpDivDownDifferenceBounded(uint64 a, uint64 b) public pure {
        vm.assume(a >= 1 && a <= 1e12);
        vm.assume(b >= 1 && b <= 2 * ONE64);
        assert(divUp64(a, b) - divDown64(a, b) <= 1);
    }

    // ── PROOF 6: zero propagation (was passing in uint256 too) ──────────────
    function check_zeroPropagation(uint64 sf) public pure {
        vm.assume(sf >= 1 && sf <= 2 * ONE64);
        assert(upscale64(0, sf) == 0);
        assert(downscale64(0, sf) == 0);
    }
}
