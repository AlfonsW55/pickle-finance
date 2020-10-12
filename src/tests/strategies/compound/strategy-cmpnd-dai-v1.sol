// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../../lib/hevm.sol";
import "../../lib/user.sol";
import "../../lib/test-approx.sol";
import "../../lib/test-defi-base.sol";

import "../../../interfaces/compound.sol";

import "../../../pickle-jar.sol";
import "../../../controller-v3.sol";

import "../../../strategies/compound/strategy-cmpd-dai-v1.sol";

contract StrategyCmpndDaiV1 is DSTestDefiBase {
    StrategyCmpdDaiV1 strategy;
    ControllerV3 controller;
    PickleJar pickleJar;

    address governance;
    address strategist;
    address timelock;
    address devfund;
    address treasury;

    address want;

    function setUp() public {
        want = dai;

        governance = address(this);
        strategist = address(new User());
        timelock = address(this);
        devfund = address(new User());
        treasury = address(new User());

        controller = new ControllerV3(
            governance,
            strategist,
            timelock,
            devfund,
            treasury
        );

        strategy = new StrategyCmpdDaiV1(
            governance,
            strategist,
            address(controller),
            timelock
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
    }

    function testFail_cmpnd_dai_v1_onlyKeeper_leverage() public {
        _getERC20(want, 100e18);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);

        User randomUser = new User();
        randomUser.execute(address(strategy), 0, "maxLeverage()", "");
    }

    function testFail_cmpnd_dai_v1_onlyKeeper_deleverage() public {
        _getERC20(want, 100e18);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        strategy.maxLeverage();

        User randomUser = new User();
        randomUser.execute(address(strategy), 0, "maxDeleverage()", "");
    }

    function test_cmpnd_dai_v1_leverage() public {
        _getERC20(want, 100e18);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();

        uint256 _stratInitialBal = strategy.balanceOf();

        uint256 _beforeCR = strategy.getColRatio();
        uint256 _beforeLev = strategy.getCurrentLeverage();
        strategy.maxLeverage();
        uint256 _afterCR = strategy.getColRatio();
        uint256 _afterLev = strategy.getCurrentLeverage();
        uint256 _safeColRatio = strategy.getSafeColRatio();

        assertTrue(_afterCR > _beforeCR);
        assertTrue(_afterLev > _beforeLev);
        assertEqApprox(_safeColRatio, _afterCR);

        uint256 _maxLeverage = strategy.getMaxLeverage();
        assertTrue(_maxLeverage > 2e18); // Should be ~2.6, depending on colRatioLeverageBuffer

        uint256 leverageTarget = strategy.getLeveragedSupplyTarget(
            _stratInitialBal
        );
        uint256 leverageSupplied = strategy.getSupplied();
        assertEqApprox(
            leverageSupplied,
            _stratInitialBal.mul(_maxLeverage).div(1e18)
        );
        assertEqApprox(leverageSupplied, leverageTarget);

        uint256 unleveragedSupplied = strategy.getSuppliedUnleveraged();
        assertEqApprox(unleveragedSupplied, _stratInitialBal);
    }

    function test_cmpnd_dai_v1_deleverage() public {
        _getERC20(want, 100e18);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();
        strategy.maxLeverage();

        uint256 _beforeCR = strategy.getColRatio();
        uint256 _beforeLev = strategy.getCurrentLeverage();
        strategy.maxDeleverage();
        uint256 _afterCR = strategy.getColRatio();
        uint256 _afterLev = strategy.getCurrentLeverage();

        assertTrue(_afterCR < _beforeCR);
        assertTrue(_afterLev < _beforeLev);
        assertEq(0, _afterCR); // 0 since we're not borrowing anything

        uint256 unleveragedSupplied = strategy.getSuppliedUnleveraged();
        uint256 supplied = strategy.getSupplied();
        assertEqApprox(unleveragedSupplied, supplied);
    }

    function test_cmpnd_dai_v1_withdrawSome() public {
        _getERC20(want, 100e18);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();
        strategy.maxLeverage();

        uint256 _before = IERC20(want).balanceOf(address(this));
        pickleJar.withdraw(25e18); // 25%
        uint256 _after = IERC20(want).balanceOf(address(this));

        assertTrue(_after > _before);
        assertEqApprox(_after.sub(_before), 25e18);

        // Make sure we're still leveraging
        uint256 _leverage = strategy.getCurrentLeverage();
        assertTrue(_leverage > 1e18);
    }

    function test_cmpnd_dai_v1_withdrawAll() public {
        _getERC20(want, 100e18);

        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();

        strategy.maxLeverage();

        hevm.warp(block.timestamp + 1 days);
        hevm.roll(block.number + 6171); // Roughly number of blocks per day

        strategy.harvest();

        // Withdraws back to pickleJar
        uint256 _before = IERC20(want).balanceOf(address(pickleJar));
        controller.withdrawAll(want);
        uint256 _after = IERC20(want).balanceOf(address(pickleJar));

        assertTrue(_after > _before);

        _before = IERC20(want).balanceOf(address(this));
        pickleJar.withdrawAll();
        _after = IERC20(want).balanceOf(address(this));

        assertTrue(_after > _before);

        // Gained some interest
        assertTrue(_after > _want);
    }

    function test_cmpnd_dai_v1_earn_harvest_rewards() public {
        _getERC20(want, 100e18);

        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).approve(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();

        // Fast forward one week
        hevm.warp(block.timestamp + 1 days);
        hevm.roll(block.number + 6171); // Roughly number of blocks per day

        // Call the harvest function
        uint256 _before = strategy.getSupplied();
        uint256 _treasuryBefore = IERC20(want).balanceOf(treasury);
        strategy.harvest();
        uint256 _after = strategy.getSupplied();
        uint256 _treasuryAfter = IERC20(want).balanceOf(treasury);

        uint256 earned = _after.sub(_before).mul(1000).div(955);
        uint256 earnedRewards = earned.mul(45).div(1000); // 4.5%
        uint256 actualRewardsEarned = _treasuryAfter.sub(_treasuryBefore);

        // 4.5% performance fee is given
        assertEqApprox(earnedRewards, actualRewardsEarned);

        // Withdraw
        uint256 _devBefore = IERC20(want).balanceOf(devfund);
        _treasuryBefore = IERC20(want).balanceOf(treasury);
        uint256 _stratBal = strategy.balanceOf();
        pickleJar.withdrawAll();
        uint256 _devAfter = IERC20(want).balanceOf(devfund);
        _treasuryAfter = IERC20(want).balanceOf(treasury);

        // 0.175% goes to dev
        uint256 _devFund = _devAfter.sub(_devBefore);
        assertEq(_devFund, _stratBal.mul(175).div(100000));

        // 0.325% goes to treasury
        uint256 _treasuryFund = _treasuryAfter.sub(_treasuryBefore);
        assertEq(_treasuryFund, _stratBal.mul(325).div(100000));
    }
}
