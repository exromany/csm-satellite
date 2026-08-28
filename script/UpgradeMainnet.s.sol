// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {UpgradeBase} from "./UpgradeBase.s.sol";

contract UpgradeMainnet is UpgradeBase {
    constructor()
        UpgradeBase("mainnet", 1, 0xFdDf38947aFB03C621C71b06C9C70bce73f12999)
    {}
}
