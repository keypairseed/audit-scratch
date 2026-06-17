// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ScalingHelpers} from "../../src/balancer-real/contracts/helpers/ScalingHelpers.sol";

/// @title RealScalingHelpersInvariant
/// @notice Тестирует НАСТОЯЩИЙ ScalingHelpers.sol из Balancer v3 (скопирован
///         напрямую из Immunefi Instascope дампа), не синтетическую модель.
///
///         КЛЮЧЕВОЕ ОТЛИЧИЕ от предыдущего ScalingOrderDifferential.t.sol:
///         scalingFactor и tokenRate — РАЗДЕЛЬНЫЕ параметры в реальном коде.
///         scalingFactor = 10^(18-decimals), целая степень десяти, >= 1.
///         tokenRate — внешний rate provider, потенциально аномальный.
///         Предыдущий тест ошибочно объединял их в один параметр.
contract RealScalingHelpersInvariant is Test {
    using ScalingHelpers for uint256;

    // Все легальные значения scalingFactor: 10^(18-decimals) для decimals 0..18
    uint256[19] DECIMAL_SCALING_FACTORS = [
        uint256(1), 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
        1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18
    ];

    // ── ТЕСТ 1: roundtrip при нормальном rate (0.5x-5x) ─────────────────────
    function testFuzz_realScalingRoundtrip_normalRate(
        uint256 amount,
        uint8 decimalsIndex,
        uint256 tokenRate
    ) external view {
        uint256 scalingFactor = DECIMAL_SCALING_FACTORS[decimalsIndex % 19];
        tokenRate = bound(tokenRate, 5e17, 5e18); // щедрый диапазон LST/RWA rate
        amount    = bound(amount, 1, 1e24);

        uint256 scaled18 = ScalingHelpers.toScaled18ApplyRateRoundDown(amount, scalingFactor, tokenRate);
        uint256 back      = ScalingHelpers.toRawUndoRateRoundDown(scaled18, scalingFactor, tokenRate);

        assertLe(back, amount, "REAL CODE: roundtrip gains value at normal rate");
    }

    // ── ТЕСТ 2: roundtrip при АНОМАЛЬНО МАЛЕНЬКОМ rate ──────────────────────
    // Сценарий: rate provider сломан или скомпрометирован, возвращает rate
    // близкий к нулю вместо ~1e18. Единственный реалистичный путь получить
    // tiny "scalingFactor * tokenRate" в настоящем коде.
    function testFuzz_realScalingRoundtrip_brokenRateProvider(
        uint256 amount,
        uint8 decimalsIndex,
        uint256 tinyRate
    ) external view {
        uint256 scalingFactor = DECIMAL_SCALING_FACTORS[decimalsIndex % 19];
        tinyRate = bound(tinyRate, 1, 1e15); // 0.000001x до 0.001x — broken provider
        amount   = bound(amount, 1, 1e24);

        uint256 scaled18 = ScalingHelpers.toScaled18ApplyRateRoundDown(amount, scalingFactor, tinyRate);
        uint256 back      = ScalingHelpers.toRawUndoRateRoundDown(scaled18, scalingFactor, tinyRate);

        assertLe(back, amount,
            "REAL CODE: broken rate provider enables roundtrip value creation");
    }

    // ── ТЕСТ 3: RoundUp вариант не должен давать меньше чем RoundDown ──────
    function testFuzz_realScalingRoundUp_neverUndershoots(
        uint256 amount,
        uint8 decimalsIndex,
        uint256 tokenRate
    ) external view {
        uint256 scalingFactor = DECIMAL_SCALING_FACTORS[decimalsIndex % 19];
        tokenRate = bound(tokenRate, 1e15, 1e19);
        amount    = bound(amount, 1, 1e24);

        uint256 up   = ScalingHelpers.toScaled18ApplyRateRoundUp(amount, scalingFactor, tokenRate);
        uint256 down = ScalingHelpers.toScaled18ApplyRateRoundDown(amount, scalingFactor, tokenRate);

        assertGe(up, down, "REAL CODE: RoundUp variant smaller than RoundDown - inverted rounding");
    }

    // ── ТЕСТ 4: computeRateRoundUp никогда не уменьшает rate ────────────────
    function testFuzz_computeRateRoundUp_neverDecreases(uint256 rate) external view {
        rate = bound(rate, 1, 1e30);
        uint256 rounded = ScalingHelpers.computeRateRoundUp(rate);

        assertGe(rounded, rate, "REAL CODE: computeRateRoundUp decreased the rate");
        assertLe(rounded - rate, 1e18, "REAL CODE: rounding adjustment larger than expected");
    }

    // ── ТЕСТ 5: known boundary — экстремальный decimals спред (0 vs 18) ────
    // USDC-подобный токен (6 decimals, sf=1e12) против чистого 18-decimal,
    // с rate на грани депега LST (0.9x), точка где Nov-2025-класс атак искал
    function test_extremeDecimalsSpreadWithDepeg() external view {
        uint256 sfUSDC = 1e12;  // 6 decimals
        uint256 sf18   = 1;     // 18 decimals
        uint256 depegRate = 9e17; // 0.9x — депег сценарий

        for (uint256 amount = 1; amount <= 20; amount++) {
            uint256 scaledUSDC = ScalingHelpers.toScaled18ApplyRateRoundDown(amount, sfUSDC, depegRate);
            uint256 backUSDC   = ScalingHelpers.toRawUndoRateRoundDown(scaledUSDC, sfUSDC, depegRate);

            uint256 scaled18   = ScalingHelpers.toScaled18ApplyRateRoundDown(amount, sf18, depegRate);
            uint256 back18     = ScalingHelpers.toRawUndoRateRoundDown(scaled18, sf18, depegRate);

            assertLe(backUSDC, amount, "USDC-scale roundtrip gains value at depeg rate");
            assertLe(back18, amount, "18-decimal roundtrip gains value at depeg rate");
        }
    }
}
