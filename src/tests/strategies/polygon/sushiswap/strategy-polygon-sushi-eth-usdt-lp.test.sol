pragma solidity ^0.6.7;



import "../../../lib/polygon/sushiswap/test-strategy-sushi-farm-base.sol";

import "../../../../interfaces/sushi-strategy.sol";
import "../../../../interfaces/curve.sol";
import "../../../../interfaces/uniswapv2.sol";

import "../../../../pickle-jar.sol";
import "../../../../controller-v4.sol";
import "../../../../strategies/polygon/sushiswap/strategy-sushi-eth-usdt-lp.sol";

contract StrategySushiEthUsdtLpTest is StrategySushiFarmTestBase {
    function setUp() public {
        want = 0xc2755915a85C6f6c1C0F3a86ac8C058F11Caa9C9;

        governance = address(this);
        strategist = address(this);
        devfund = address(new User());
        treasury = address(new User());
        timelock = address(this);

        controller = new ControllerV4(
            governance,
            strategist,
            timelock,
            devfund,
            treasury
        );

        strategy = ISushiStrategy(
            address(
                new StrategySushiEthUsdtLp(
                    governance,
                    strategist,
                    address(controller),
                    timelock
                )
            )
        );

        pickleJar = new PickleJar(
            strategy.want(),
            governance,
            timelock,
            address(controller)
        );

        controller.setJar(strategy.want(), address(pickleJar));
        controller.approveStrategy(strategy.want(), address(strategy));
        controller.setStrategy(strategy.want(), address(strategy));

        // Set time
        hevm.warp(startTime);
    }

    // **** Tests ****

    function test_ethusdtv3_1_timelock() public {
        _test_timelock();
    }

    function test_ethusdtv3_1_withdraw_release() public {
        _test_withdraw_release();
    }

    function test_ethusdtv3_1_get_earn_harvest_rewards() public {
        _test_get_earn_harvest_rewards();
    }
}
