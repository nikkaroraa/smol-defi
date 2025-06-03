// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FlashLoanProvider} from "../../src/flashloans/FlashLoanProvider.sol";
import {ArbitrageBot} from "../../src/flashloans/examples/ArbitrageBot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FlashLoanProviderTest is Test {
    FlashLoanProvider public flashLoanProvider;
    ArbitrageBot public arbitrageBot;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public liquidityProvider = makeAddr("liquidityProvider");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        flashLoanProvider = new FlashLoanProvider();
        token = new MockERC20("Test Token", "TEST");
        arbitrageBot = new ArbitrageBot(address(flashLoanProvider));

        // Setup initial state
        token.mint(liquidityProvider, 1000000 * 10 ** 18);
        token.mint(user, 100000 * 10 ** 18);

        vm.stopPrank();
    }

    function test_addAsset() public {
        vm.prank(owner);
        flashLoanProvider.addAsset(address(token), 30); // 0.3% fee

        assertTrue(flashLoanProvider.supportedAssets(address(token)));
        assertEq(flashLoanProvider.flashLoanFees(address(token)), 30);
    }

    function test_depositLiquidity() public {
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        token.approve(address(flashLoanProvider), 100000 * 10 ** 18);
        flashLoanProvider.depositLiquidity(address(token), 100000 * 10 ** 18);
        vm.stopPrank();

        assertEq(flashLoanProvider.availableLiquidity(address(token)), 100000 * 10 ** 18);
    }

    function test_flashLoan() public {
        // Setup
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30); // 0.3% fee
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        token.approve(address(flashLoanProvider), 100000 * 10 ** 18);
        flashLoanProvider.depositLiquidity(address(token), 100000 * 10 ** 18);
        vm.stopPrank();

        // Setup arbitrage bot with enough tokens to cover loan + fee
        // For 10000 loan at 0.3% fee = 30 tokens fee, so we need 10030 total
        vm.startPrank(user);
        token.transfer(address(arbitrageBot), 15000 * 10 ** 18); // Extra buffer
        vm.stopPrank();

        // Setup mock prices for arbitrage (owner sets prices)
        vm.startPrank(owner);
        // Price difference: Exchange A = 100, Exchange B = 110 (10% difference)
        arbitrageBot.updatePrices(address(token), 100, 110);
        // Execute arbitrage as owner
        arbitrageBot.executeArbitrage(address(token), 10000 * 10 ** 18, 0);
        vm.stopPrank();

        // Check that flash loan was successful (no revert means success)
        assertTrue(true);
    }

    function test_getMaxFlashLoan() public {
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        token.approve(address(flashLoanProvider), 50000 * 10 ** 18);
        flashLoanProvider.depositLiquidity(address(token), 50000 * 10 ** 18);
        vm.stopPrank();

        assertEq(flashLoanProvider.getMaxFlashLoan(address(token)), 50000 * 10 ** 18);
    }

    function test_getFlashLoanFee() public {
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30); // 0.3%
        vm.stopPrank();

        uint256 fee = flashLoanProvider.getFlashLoanFee(address(token), 10000 * 10 ** 18);
        assertEq(fee, 30 * 10 ** 18); // 0.3% of 10000 = 30
    }

    function test_revert_invalidAmount() public {
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30);
        vm.stopPrank();

        vm.expectRevert(FlashLoanProvider.InvalidAmount.selector);
        flashLoanProvider.flashLoan(address(arbitrageBot), address(token), 0, "");
    }

    function test_revert_insufficientLiquidity() public {
        vm.startPrank(owner);
        flashLoanProvider.addAsset(address(token), 30);
        vm.stopPrank();

        // Try to borrow more than available
        vm.expectRevert(FlashLoanProvider.InsufficientLiquidity.selector);
        flashLoanProvider.flashLoan(address(arbitrageBot), address(token), 1000 * 10 ** 18, "");
    }
}
