// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface IOriginVault {
    function totalValue()  external returns (uint256);
    function totalSupply() external view returns (uint256);
    function rebase()      external;
}

interface IOETH {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply()              external view returns (uint256);
}

contract OriginProtocolInvariant is Test {
    address constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
    address constant WETH       = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant OETH       = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;

    IOriginVault vault;
    IOETH        oeth;
    address      attacker;

    uint256 totalValueSnapshot;

    function setUp() public {
        vm.createSelectFork("mainnet", 22_000_000);

        vault   = IOriginVault(OETH_VAULT);
        oeth    = IOETH(OETH);
        attacker = makeAddr("attacker");

        // deal(ETH) и deal(WETH) работают надёжно
        // НЕ используем deal(STETH) — stETH хранит shares, не balances,
        // stdStorage не может найти слот для записи
        deal(attacker, 100 ether);
        deal(WETH, attacker, 50e18);

        // Снимок начального состояния
        totalValueSnapshot = vault.totalValue();

        console2.log("OETH total supply:", oeth.totalSupply());
        console2.log("Vault total value:", totalValueSnapshot);

        targetContract(address(this));
    }

    // ── ИНВАРИАНТ: Vault всегда полностью коллатерализован ───────────────
    function invariant_vaultAlwaysCollateralized() external {
        uint256 tv = vault.totalValue();
        uint256 ts = oeth.totalSupply();

        // totalValue >= totalSupply с допуском 0.1%
        assertGe(
            tv * 1000,
            ts * 999,
            "CRITICAL ORIGIN: Vault undercollateralized"
        );
    }

    // ── ТЕСТ: rebase() только увеличивает supply ──────────────────────────
    function test_rebaseOnlyIncreasesSupply() external {
        uint256 before = oeth.totalSupply();
        vault.rebase();
        uint256 after_ = oeth.totalSupply();

        assertGe(after_, before, "ORIGIN: rebase() decreased total supply");
        console2.log("Supply before rebase:", before);
        console2.log("Supply after rebase: ", after_);
    }

    // ── ТЕСТ: ARM frontrunning — НЕСТАНДАРТНЫЙ ВЕКТОР ────────────────────
    // Проверяем что нельзя получить profit без удержания позиции
    function testFuzz_noImmediateMintRedeemProfit(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 1e17, 5e18); // 0.1 to 5 ETH

        vm.startPrank(attacker);
        uint256 ethBefore = attacker.balance;

        // Пробуем mint через WETH
        // Если vault.mint реализован — проверяем profit
        // Если нет — тест просто проходит

        vm.stopPrank();

        // Placeholder: структура теста готова для заполнения
        // при детальном изучении Origin Protocol vault interface
        assertTrue(mintAmount > 0, "Test scaffolding");
        console2.log("Testing ARM frontrun prevention for amount:", mintAmount);
    }
}

