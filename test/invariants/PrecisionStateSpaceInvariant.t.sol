// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PrecisionMath}  from "../../src/lib/PrecisionMath.sol";

/// @title Handler — Lido-style share/asset accounting, no external dependencies
/// @notice Medusa and Foundry invariant fuzzer call these functions in random
///         sequences. State evolves freely — including ratios that DON'T YET
///         EXIST on mainnet but WILL in 1-2 years [T-44 Time Bomb].
contract PrecisionHandler is Test {
    using PrecisionMath for uint256;

    uint256 public totalAssets = 1000e18;
    uint256 public totalShares = 1000e18;

    // Track cumulative "drift" — value created/destroyed by rounding alone
    int256 public cumulativeDrift;

    // ── Action 1: deposit (mint shares for assets) ──────────────────────────
    function deposit(uint256 assets) external {
        assets = bound(assets, 1, 1_000_000e18);

        uint256 shares = PrecisionMath.assetsToShares(assets, totalAssets, totalShares);

        totalAssets += assets;
        totalShares += shares;
    }

    // ── Action 2: redeem (burn shares for assets) ───────────────────────────
    function redeem(uint256 shares) external {
        shares = bound(shares, 0, totalShares);
        if (shares == 0 || totalShares == 0) return;

        uint256 assets = PrecisionMath.sharesToAssets(shares, totalAssets, totalShares);
        if (assets > totalAssets) return; // can't redeem more than exists

        totalAssets -= assets;
        totalShares -= shares;
    }

    // ── Action 3: rebase (rewards accrue, shares unchanged) ─────────────────
    // This is what makes the ETH-per-share ratio GROW over time on Lido.
    function rebase(uint256 rewardAmount) external {
        rewardAmount = bound(rewardAmount, 0, totalAssets / 50); // max 2% per call
        totalAssets += rewardAmount;
    }

    // ── Action 4: roundtrip drift accounting ─────────────────────────────────
    // deposit(x) then immediately redeem(shares received) — should never
    // CREATE value. May lose up to a few wei per call (acceptable);
    // accumulated drift across thousands of calls is what we're hunting.
    function roundtripDrift(uint256 assets) external {
        assets = bound(assets, 1e9, 1000e18); // 1 gwei .. 1000 ETH

        uint256 before = totalAssets;
        uint256 shares = PrecisionMath.assetsToShares(assets, totalAssets, totalShares);

        totalAssets += assets;
        totalShares += shares;

        uint256 backAssets = PrecisionMath.sharesToAssets(shares, totalAssets, totalShares);
        if (backAssets > totalAssets) return;

        totalAssets -= backAssets;
        totalShares -= shares;

        int256 drift = int256(backAssets) - int256(assets);
        cumulativeDrift += drift;

        // Sanity: totalAssets shouldn't have net-changed vs before by more
        // than the single-call drift
        assertApproxEqAbs(
            totalAssets, before, 2,
            "Single roundtrip drift exceeds 2 wei"
        );
    }
}

/// @title PrecisionStateSpaceInvariant
/// @notice NO RPC — runs entirely in-memory. Safe to run 50k-100k+ invariant
///         runs for hours without touching any RPC quota.
contract PrecisionStateSpaceInvariant is Test {
    PrecisionHandler handler;

    function setUp() public {
        handler = new PrecisionHandler();
        targetContract(address(handler));
    }

    // ── INVARIANT 1: ratio never goes to zero or explodes ───────────────────
    // sharesToAssets(totalShares) should always ≈ totalAssets
    function invariant_ratioConsistent() external view {
        uint256 ta = handler.totalAssets();
        uint256 ts = handler.totalShares();

        if (ts == 0) return;

        uint256 derived = PrecisionMath.sharesToAssets(ts, ta, ts);

        // derived should equal ta (sharesToAssets(totalShares) == totalAssets)
        assertApproxEqAbs(
            derived, ta, 1,
            "INVARIANT: totalShares does not convert back to totalAssets"
        );
    }

    // ── INVARIANT 2: cumulative drift never favors the USER ────────────────
    // Rounding must ALWAYS favor the protocol (vault), never the depositor.
    // Positive cumulativeDrift = user extracted more than deposited = CRITICAL.
    function invariant_driftNeverFavorsUser() external view {
        int256 drift = handler.cumulativeDrift();
        assertLe(
            drift, 0,
            "CRITICAL: Cumulative rounding drift is POSITIVE - value created from nothing"
        );
    }

    // ── INVARIANT 3: share price monotonic across rebases ───────────────────
    // (rebase-only growth; deposit/redeem at fair value shouldn't move price
    //  outside of rounding tolerance)
    function invariant_totalAssetsNeverBelowTotalShares() external view {
        uint256 ta = handler.totalAssets();
        uint256 ts = handler.totalShares();

        // In this model totalAssets >= totalShares always
        // (1:1 at genesis, only grows via rebase)
        assertGe(
            ta + 1e15, // tolerance for accumulated rounding
            ts,
            "INVARIANT: totalAssets fell below totalShares without explanation"
        );
    }

    // ── FUZZ: extreme ratio exploration [T-44] ──────────────────────────────
    // Directly test conversion at ratios that DON'T exist on mainnet YET
    // but are plausible in 1-3 years (Lido share rate grows ~5-8%/year)
    function testFuzz_futureRatioRoundtrip(
        uint256 totalAssets,
        uint256 totalShares,
        uint256 testAmount
    ) external pure {
        // Ratios from 1.0x (genesis) to 3.0x (10+ years of compounding)
        totalAssets = bound(totalAssets, 1e18, 3e18);
        totalShares = bound(totalShares, 1e18, 1e18); // shares fixed at 1e18
        testAmount  = bound(testAmount, 1, 1e24);

        uint256 shares = PrecisionMath.assetsToShares(testAmount, totalAssets, totalShares);
        uint256 back   = PrecisionMath.sharesToAssets(shares, totalAssets, totalShares);

        // Roundtrip must not CREATE value at ANY future ratio
        assertLe(back, testAmount, "Roundtrip creates value at this ratio");
    }
}
