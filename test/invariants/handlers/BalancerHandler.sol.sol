// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ПУСТОЙ ПЛЕЙСХОЛДЕР
//
// Старая версия этого файла содержала контракт с именем
// BalancerPrecisionInvariant — тем же именем что в основном тест-файле.
// forge test --match-contract BalancerPrecisionInvariant находил ОБА файла
// и запускал setUp() из неправильного контекста → revert.
//
// Текущая версия BalancerPrecisionInvariant.t.sol самодостаточна:
// targetContract(address(this)) регистрирует сам тестовый контракт
// как target для invariant fuzzing — отдельный handler не нужен.
//
// Когда понадобится handler (для multi-actor stateful fuzzing):
// раскомментируй и реализуй ниже с ДРУГИМ именем контракта.

/*
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats}  from "forge-std/StdCheats.sol";
import {StdUtils}   from "forge-std/StdUtils.sol";

contract BalancerActionsHandler is CommonBase, StdCheats, StdUtils {
    // действия для stateful fuzzing будут здесь
}
*/

