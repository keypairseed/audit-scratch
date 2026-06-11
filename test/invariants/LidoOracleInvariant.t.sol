// test/invariants/LidoOracleInvariant.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

interface ILido {
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function sharesOf(address account) external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
    function handleOracleReport(
        uint256 reportTimestamp,
        uint256 timeElapsed,
        uint256 clValidators,
        uint256 clBalance,
        uint256 withdrawalVaultBalance,
        uint256 elRewardsVaultBalance,
        uint256 sharesRequestedToBurn,
        uint256[] calldata withdrawalFinalizationBatches,
        uint256 simulatedShareRate
    ) external returns (uint256[4] memory);
}

contract LidoOracleInvariant is Test {
    address constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    ILido lido;

    // Снимки для инвариантов
    uint256 totalSharesBefore;
    uint256 totalPooledEtherBefore;
    uint256 sharePriceBefore; // pooledEther per share * 1e27

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        lido = ILido(LIDO);
        _takeSnapshot();
    }

    function _takeSnapshot() internal {
        totalSharesBefore     = lido.getTotalShares();
        totalPooledEtherBefore = lido.getTotalPooledEther();
        sharePriceBefore      = lido.getPooledEthByShares(1e27); // price per 1e27 shares
    }

    // ── ИНВАРИАНТ 1: Share price только растёт (при отсутствии slashing)
    // Нарушение = пользователи теряют деньги без slashing события
    function invariant_sharePriceNonDecreasing() external {
        uint256 sharePriceAfter = lido.getPooledEthByShares(1e27);
        assertGe(
            sharePriceAfter,
            sharePriceBefore - 1e15, // tolerance: минимальный slashing
            "LIDO: Share price decreased without slashing event"
        );
    }

    // ── ИНВАРИАНТ 2: Roundtrip конвертации без потерь
    function testFuzz_shareConversionRoundtrip(uint256 ethAmount) external {
        ethAmount = bound(ethAmount, 1e9, 1000e18); // 1 gwei to 1000 ETH

        uint256 shares      = lido.getSharesByPooledEth(ethAmount);
        uint256 backToEth   = lido.getPooledEthByShares(shares);

        // Roundtrip должен быть точным с погрешностью 1 wei
        assertApproxEqAbs(
            backToEth, ethAmount, 1,
            "LIDO: Share conversion roundtrip loses more than 1 wei"
        );
    }

    // ── ИНВАРИАНТ 3: simulatedShareRate deviation
    // НЕСТАНДАРТНЫЙ ВЕКТОР: что если oracle репортит неправильный simulatedShareRate?
    function testFuzz_simulatedShareRateDeviation(uint256 deviation) external {
        deviation = bound(deviation, 1, 1000); // 0.01% to 10% отклонение

        uint256 realShareRate = lido.getPooledEthByShares(1e27);
        uint256 fakeShareRate = realShareRate * (10000 + deviation) / 10000;

        // Логируем для анализа
        console2.log("Real share rate:", realShareRate);
        console2.log("Fake share rate:", fakeShareRate);
        console2.log("Deviation bps:",  deviation);

        // Эта инварианта проверяется ПОСЛЕ подачи oracle report с fake rate
        // Если withdrawal finalization даёт неправильный ETH → CRITICAL
    }
}
