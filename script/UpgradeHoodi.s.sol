// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {UpgradeBase} from "./UpgradeBase.s.sol";

contract UpgradeHoodi is UpgradeBase {
    constructor()
        UpgradeBase(
            "hoodi",
            560048,
            0xCc820558B39ee15C7C45B59390B503b83fb499A8
        )
    {}
}
