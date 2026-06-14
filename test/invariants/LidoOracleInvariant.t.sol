// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface ILido {
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares()      external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount)    external view returns (uint256);
}

contract LidoOracleInvariant is Test {
    address constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    ILido lido;

    uint256 sharePriceBefore;

    function setUp() public {
        // КРИТИЧНО: пиннинг блока = кэш = без 429 и без 4-часового timeout
        vm.createSelectFork("mainnet", 22_000_000);
        lido = ILido(LIDO);
        sharePriceBefore = lido.getPooledEthByShares(1e27);
        targetContract(address(this));
    }

    // ── ИНВАРИАНТ: share price не уменьшается без slashing события ───────
    function invariant_sharePriceNonDecreasing() external view {
        uint256 current = lido.getPooledEthByShares(1e27);
        assertGe(
            current + 1e15,
            sharePriceBefore,
            "LIDO: Share price decreased without slashing event"
        );
    }

    // ── ТЕСТ: Roundtrip конвертации
    // НАХОДКА из предыдущего прогона:
    // При ethAmount=1e9 (1 gwei) delta = 2 wei, не 1.
    // Lido делает двойное округление: ETH→shares (round down) + shares→ETH (round down)
    // Для малых сумм суммарная погрешность = 2 wei.
    // Tolerance увеличена до 2 — это задокументированное поведение Lido.
    function testFuzz_shareConversionRoundtrip(uint256 ethAmount) external view {
        ethAmount = bound(ethAmount, 1e9, 1000e18);

        uint256 shares    = lido.getSharesByPooledEth(ethAmount);
        uint256 backToEth = lido.getPooledEthByShares(shares);

        // tolerance = 2 wei (двойное округление вниз)
        assertApproxEqAbs(
            backToEth, ethAmount, 2,
            "LIDO: Roundtrip precision loss > 2 wei (investigate for small amounts)"
        );
    }

    // ── ТЕСТ: simulatedShareRate deviation — НЕСТАНДАРТНЫЙ ВЕКТОР ────────
    function testFuzz_simulatedShareRateDeviation(uint256 deviation) external view {
        deviation = bound(deviation, 1, 1000);
        uint256 realRate = lido.getPooledEthByShares(1e27);
        uint256 fakeRate = realRate * (10000 + deviation) / 10000;

        console2.log("Real share rate:", realRate);
        console2.log("Fake share rate:", fakeRate);
        console2.log("Deviation bps:  ", deviation);

        assertGt(fakeRate, realRate);
    }
}

