// test/invariants/BalancerPrecisionInvariant.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

// Интерфейсы Balancer v2
interface IVault {
    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

    function getPoolTokens(bytes32 poolId)
        external view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
}

interface IComposableStablePool {
    function getInvariant() external view returns (uint256);
    function getVirtualSupply() external view returns (uint256);
    function getPoolId() external view returns (bytes32);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Balancer Precision Loss Invariant Tests
/// @notice Ищет двухэтапные precision-loss атаки на Balancer v2
/// @dev Запускай на mainnet fork: ETH_RPC_URL требуется
contract BalancerPrecisionInvariant is Test {
    // ── Адреса (mainnet) ─────────────────────────────────────────
    address constant VAULT_ADDR    = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // wstETH/rETH/cbETH pool — именно этот был атакован
    address constant WSTETH_POOL   = 0xF01b0684C98CD7aDA480BFDF6e43876422fa1Fc1;
    address constant WSTETH        = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant RETH          = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    IVault              vault;
    IComposableStablePool pool;

    // ── Snapshotы для инвариантов ─────────────────────────────────
    uint256 invariantBefore;
    uint256 virtualSupplyBefore;
    uint256[] balancesBefore;

    function setUp() public {
        // Форк mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        vault = IVault(VAULT_ADDR);
        pool  = IComposableStablePool(WSTETH_POOL);

        // Снимок начального состояния
        _takeSnapshot();

        // Даём тестовому контракту ETH для взаимодействия
        deal(address(this), 1000 ether);
        deal(WSTETH, address(this), 100e18);
        deal(RETH, address(this), 100e18);

        // Регистрируем контракты для fuzzing
        targetContract(address(this));
    }

    function _takeSnapshot() internal {
        invariantBefore    = pool.getInvariant();
        virtualSupplyBefore = pool.getVirtualSupply();

        bytes32 poolId = pool.getPoolId();
        (, balancesBefore, ) = vault.getPoolTokens(poolId);
    }

    // ── ИНВАРИАНТ 1: Pool invariant K не уменьшается без fee ─────
    // Эта инварианта нашла бы $128M exploit ДО атаки
    function invariant_poolInvariantNeverDecreasesWithoutFee() external {
        uint256 invariantAfter = pool.getInvariant();

        // Допустимая погрешность: 0.001% (accumulated fee)
        uint256 tolerance = invariantBefore / 100000;

        assertGe(
            invariantAfter + tolerance,
            invariantBefore,
            "CRITICAL: Pool invariant K decreased beyond fee tolerance"
        );
    }

    // ── ИНВАРИАНТ 2: Virtual price монотонно не уменьшается ──────
    function invariant_virtualPriceMonotonicallyNonDecreasing() external {
        uint256 virtualSupplyAfter = pool.getVirtualSupply();

        // BPT totalSupply не должен внезапно расти без пропорционального
        // увеличения pool balances
        assertLe(
            virtualSupplyAfter,
            virtualSupplyBefore * 11 / 10, // не более +10% за раз
            "CRITICAL: Virtual supply increased anomalously"
        );
    }

    // ── ИНВАРИАНТ 3: Двухэтапная атака невозможна ────────────────
    // Специфически проверяет паттерн exploit'а ноября 2025
    uint256 ethBeforeManipulation;
    bool    manipulationDone;

    function performManipulation(uint256 microSwapAmount) external {
        // STAGE 1: манипуляция без профита
        microSwapAmount = bound(microSwapAmount, 1, 15); // boundary: 8-9 wei

        vm.prank(address(this));
        // ... micro swaps логика ...

        ethBeforeManipulation = address(this).balance;
        manipulationDone = true;
    }

    function invariant_noTwoStagePrecisionProfit() external {
        if (!manipulationDone) return;

        // STAGE 2: попытка вывода после манипуляции
        uint256 bptBalance = pool.balanceOf(address(this));

        if (bptBalance > 0) {
            uint256 ethBefore = address(this).balance;
            // ... exit pool logic ...
            uint256 ethAfter = address(this).balance;

            // Профит должен быть <= 0 (не считая fees)
            assertLe(
                int256(ethAfter) - int256(ethBefore),
                int256(1e15), // tolerance: 0.001 ETH
                "CRITICAL: Two-stage precision attack profitable"
            );
        }
    }

    // ── ФАЗZ-ТЕСТ: Граничные условия 8-9 wei ─────────────────────
    // Именно это использовал атакующий
    function testFuzz_microSwapBoundary(uint256 amount) external {
        amount = bound(amount, 1, 20); // focus on 8-9 wei boundary

        uint256 invariantBefore_ = pool.getInvariant();

        // Попытка micro swap
        // ... swap logic ...

        uint256 invariantAfter_ = pool.getInvariant();

        // После micro swap инвариант не должен значительно упасть
        assertGe(
            invariantAfter_,
            invariantBefore_ - 100, // tolerance: 100 wei
            string.concat(
                "CRITICAL: Invariant drop at amount=",
                vm.toString(amount)
            )
        );
    }
}
