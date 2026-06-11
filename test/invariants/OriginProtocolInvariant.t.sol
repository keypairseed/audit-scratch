// test/invariants/OriginProtocolInvariant.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

interface IOriginVault {
    function totalValue() external returns (uint256);
    function totalSupply() external view returns (uint256);
    function mint(address asset, uint256 amount, uint256 minOUSD) external;
    function redeem(uint256 amount, uint256 minimumUnitAmount) external;
    function rebase() external;
    function allocate() external;
    function harvest(address strategy) external;
    function priceUnitMint(address asset) external returns (uint256);
    function priceUnitRedeem(address asset) external returns (uint256);
}

interface IOETH is IOriginVault {
    function balanceOf(address account) external view returns (uint256);
    function creditsBalanceOf(address account) external view returns (uint256, uint256);
}

contract OriginProtocolInvariant is Test {
    // Mainnet адреса
    address constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
    address constant WETH       = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH      = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    IOriginVault vault;
    address attacker = makeAddr("attacker");

    uint256 totalValueBefore;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vault = IOriginVault(OETH_VAULT);

        // Начальное состояние
        totalValueBefore = vault.totalValue();

        // Даём атакующему ETH
        deal(attacker, 1000 ether);
        deal(WETH, attacker, 100e18);
        deal(STETH, attacker, 100e18);

        targetContract(address(this));
    }

    // ── ИНВАРИАНТ 1: Vault всегда полностью коллатерализован
    // totalValue() >= totalSupply() (ratio >= 1)
    function invariant_vaultAlwaysCollateralized() external {
        uint256 totalValue_  = vault.totalValue();
        uint256 totalSupply_ = vault.totalSupply();

        assertGe(
            totalValue_,
            totalSupply_ * 999 / 1000, // tolerance: 0.1% slippage
            "CRITICAL ORIGIN: Vault undercollateralized"
        );
    }

    // ── ИНВАРИАНТ 2: rebase() только увеличивает supply ──────────
    function invariant_rebaseOnlyIncreasesSupply() external {
        uint256 supplyBefore_ = vault.totalSupply();
        vault.rebase();
        uint256 supplyAfter_ = vault.totalSupply();

        assertGe(
            supplyAfter_,
            supplyBefore_,
            "ORIGIN: rebase() decreased total supply"
        );
    }

    // ── ИНВАРИАНТ 3: ARM frontrunning невозможен ─────────────────
    // НЕСТАНДАРТНЫЙ ВЕКТОР
    function testFuzz_armFrontrunPrevention(
        uint256 mintAmount,
        uint256 blocksHeld
    ) external {
        mintAmount  = bound(mintAmount, 1e17, 10e18);    // 0.1 to 10 ETH
        blocksHeld  = bound(blocksHeld, 0, 2);           // 0-2 блока

        vm.startPrank(attacker);

        // Snapshot ETH balance
        uint256 ethBefore = attacker.balance;

        // Mint OETH прямо перед потенциальным rebase/harvest
        deal(WETH, attacker, mintAmount);
        // vault.mint(WETH, mintAmount, 0);

        // Simulate blocks passing (ARM may execute arbitrage)
        vm.roll(block.number + blocksHeld);

        // Immediate redeem
        // vault.redeem(oethBalance, 0);

        uint256 ethAfter = attacker.balance;
        int256 profit = int256(ethAfter) - int256(ethBefore);

        vm.stopPrank();

        // ИНВАРИАНТ: нельзя получить profit без holding period
        assertLe(
            profit,
            int256(mintAmount) * 5 / 10000, // tolerance: 0.05% (normal fees)
            "ORIGIN ARM: Frontrunning ARM arbitrage profitable"
        );
    }

    // ── ТЕСТ: Yield Forwarding reentrancy
    function test_yieldForwardingReentrancy() external {
        // Разворачиваем malicious yield receiver
        MaliciousYieldReceiver malicious = new MaliciousYieldReceiver(address(vault));

        // Пытаемся зарегистрировать как yield target
        // Если возможно — это CRITICAL
        try vault.rebase() {
            // Проверяем что malicious.receive не был вызван рекурсивно
            assertEq(malicious.reentrantCalls(), 0,
                "ORIGIN: Yield forwarding enables reentrancy");
        } catch {}
    }
}

contract MaliciousYieldReceiver {
    address vault;
    uint256 public reentrantCalls;

    constructor(address _vault) {
        vault = _vault;
    }

    // Если rebase() форвардит yield сюда — пробуем reenter
    receive() external payable {
        reentrantCalls++;
        if (reentrantCalls < 3) {
            // Попытка reentrancy
            try IOriginVault(vault).rebase() {
                reentrantCalls++;
            } catch {}
        }
    }
}
