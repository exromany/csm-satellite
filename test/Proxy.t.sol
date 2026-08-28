// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";
import {StakingModuleMock} from "./mocks/StakingModuleMock.sol";

contract ProxyTest is Test {
    uint256 internal constant MODULE_ID = 3;
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ACCOUNTING = address(0xACC0);

    StakingRouterMock internal router;
    StakingModuleMock internal module;
    SMDiscovery internal implementation;
    OssifiableProxy internal proxy;
    SMDiscovery internal discovery;

    function setUp() public {
        router = new StakingRouterMock();
        module = new StakingModuleMock(ACCOUNTING);
        router.setModule(MODULE_ID, address(module));

        implementation = new SMDiscovery(address(router));
        proxy = new OssifiableProxy(address(implementation), ADMIN, "");
        discovery = SMDiscovery(address(proxy));
    }

    function test_immutableStakingRouter_resolvesThroughDelegatecall()
        external
        view
    {
        assertEq(address(discovery.STAKING_ROUTER()), address(router));
    }

    function test_proxy_reportsAdminAndImplementation() external view {
        assertEq(proxy.proxy__getAdmin(), ADMIN);
        assertEq(proxy.proxy__getImplementation(), address(implementation));
        assertFalse(proxy.proxy__getIsOssified());
    }

    function test_updateModuleCache_writesThroughProxy() external {
        discovery.updateModuleCache(MODULE_ID);
        (address moduleAddress, address accountingAddress) = discovery
            .moduleCache(MODULE_ID);
        assertEq(moduleAddress, address(module));
        assertEq(accountingAddress, ACCOUNTING);
    }
}
