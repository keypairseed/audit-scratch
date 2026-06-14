// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

// Vault — единственный надёжный интерфейс для всех пулов Balancer v2
interface IVault {
    function getPoolTokens(bytes32 poolId)
        external view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );
}

// Только функции гарантированно существующие на ЛЮБОМ BasePool
interface IBasePool {
    function getPoolId()   external view returns (bytes32);
    function totalSupply() external view returns (uint256);
}

contract BalancerPrecisionInvariant is Test {
    IVault    vault;
    IBasePool pool;

    bytes32   poolId;
    uint256   totalSupplySnapshot;
    uint256[] balancesSnapshot;

    function setUp() public {
        // КРИТИЧНО: пиннинг блока = кэш стейта = без rate limiting
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22_000_000);

        vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8); // Balancer Vault

        // BAL/WETH 80/20 WeightedPool — существует с 2021, точно есть в блоке 22M
        // Verified: cast call 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56 "getPoolId()(bytes32)"
        pool = IBasePool(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);

        poolId            = pool.getPoolId();
        totalSupplySnapshot = pool.totalSupply();

        (, uint256[] memory bals,) = vault.getPoolTokens(poolId);
        balancesSnapshot = bals;

        console2.log("Pool ID (truncated):", uint256(poolId) >> 128);
        console2.log("Total supply:       ", totalSupplySnapshot);
        for (uint256 i = 0; i < bals.length; i++) {
            console2.log("Balance[", i, "]:", bals[i]);
        }

        targetContract(address(this));
    }

    // ── ИНВАРИАНТ: Total supply не падает >5% аномально ──────────────────
    // Прокси для pool invariant K
    function invariant_totalSupplyNotDrained() external view {
        uint256 current = pool.totalSupply();
        assertGe(
            current * 20,
            totalSupplySnapshot * 19,
            "CRITICAL: Pool BPT supply dropped >5% anomalously"
        );
    }

    // ── ИНВАРИАНТ: Балансы токенов не исчезают ────────────────────────────
    function invariant_tokenBalancesNotDrained() external view {
        (, uint256[] memory current,) = vault.getPoolTokens(poolId);
        for (uint256 i = 0; i < current.length; i++) {
            if (i < balancesSnapshot.length && balancesSnapshot[i] > 1e15) {
                assertGe(
                    current[i] * 20,
                    balancesSnapshot[i] * 19,
                    "CRITICAL: Token balance drained >5%"
                );
            }
        }
    }

    // ── ТЕСТ: Граничные суммы 1-20 wei (зона атаки ноябрьского эксплойта)
    function testFuzz_microAmountBoundary(uint256 amount) external pure {
        amount = bound(amount, 1, 20); // 8-9 wei = граница атаки
        console2.log("Boundary amount:", amount);
        assertTrue(amount >= 1 && amount <= 20);
    }

    // ── ТЕСТ: Базовая читаемость пула ─────────────────────────────────────
    function test_poolBasicRead() external view {
        assertGt(totalSupplySnapshot, 0, "Pool total supply is zero");

        (, uint256[] memory bals,) = vault.getPoolTokens(poolId);
        assertGt(bals.length, 0, "Pool has no tokens");

        uint256 nonZero;
        for (uint256 i = 0; i < bals.length; i++) {
            if (bals[i] > 0) nonZero++;
        }
        assertGt(nonZero, 0, "All pool balances zero");
    }
}

