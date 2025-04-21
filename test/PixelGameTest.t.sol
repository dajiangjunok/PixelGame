// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PixelGame} from "../src/PixelGame.sol";
import {DeployPixelGame} from "../script/DeployPixelGame.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract PixelGameTest is Test {
    PixelGame pixelGame;
    DeployPixelGame deployer;
    VRFCoordinatorV2_5Mock vrfCoordinatorMock;
    MockV3Aggregator priceFeedMock;

    address public PLAYER = makeAddr("player");
    address public PLAYER2 = makeAddr("player2");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant PIXEL_PRICE_USD = 2; // $2
    uint256 public constant PIXEL_PRICE_ETH = 0.001 ether; // 假设1 ETH = $2000，则$2 = 0.001 ETH

    // 测试事件
    event PixelPurchased(
        address indexed player,
        uint256 indexed pixelIndex,
        uint256 indexed pixelColor
    );

    event RequestedRaffleWinner(uint256 indexed requestId);
    event RequestFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords,
        uint256 indexed winnerIndex
    );

    function setUp() public {
        deployer = new DeployPixelGame();
        (pixelGame, ) = deployer.run();

        // 给测试用户一些ETH
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        vm.deal(PLAYER2, STARTING_USER_BALANCE);
    }

    /////////////////////////
    // purchasePixel Tests //
    /////////////////////////

    function testPurchasePixelEmitsEvent() public {
        // 准备
        uint256 pixelIndex = 0;
        uint256 pixelColor = 123456; // 一个颜色值
        vm.prank(PLAYER);

        // 期望事件被发出
        vm.expectEmit(true, true, true, false);
        emit PixelPurchased(PLAYER, pixelIndex, pixelColor);

        // 执行
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, pixelColor);
    }

    function testPurchasePixelUpdatesPixelArray() public {
        // 准备
        uint256 pixelIndex = 1;
        uint256 pixelColor = 654321;
        vm.prank(PLAYER);

        // 执行
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, pixelColor);

        // 验证
        uint256[] memory pixelArray = pixelGame.getPixelArray();
        assertEq(
            pixelArray[pixelIndex],
            pixelColor,
            "Pixel color should be updated"
        );
    }

    function testPurchasePixelUpdatesPixelMapping() public {
        // 准备
        uint256 pixelIndex = 2;
        uint256 pixelColor = 987654;
        vm.prank(PLAYER);

        // 执行
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, pixelColor);

        // 验证
        (
            address player,
            uint256 index,
            uint256 color,
            bool isPurchased
        ) = pixelGame.pixelMapping(pixelIndex);
        assertEq(player, PLAYER, "Player address should be updated");
        assertEq(index, pixelIndex, "Pixel index should be correct");
        assertEq(color, pixelColor, "Pixel color should be updated");
        assertTrue(isPurchased, "Pixel should be marked as purchased");
    }

    function testCannotPurchaseAlreadyPurchasedPixel() public {
        // 准备 - 先购买一个像素
        uint256 pixelIndex = 3;
        uint256 pixelColor = 111111;
        vm.prank(PLAYER);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, pixelColor);

        // 尝试再次购买同一个像素
        vm.prank(PLAYER2);
        vm.expectRevert(PixelGame.PixelGame__PixelAlreadyPurchased.selector);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, 222222);
    }

    function testCannotPurchasePixelWithInsufficientETH() public {
        // 准备
        uint256 pixelIndex = 4;
        uint256 pixelColor = 333333;
        uint256 insufficientValue = PIXEL_PRICE_ETH / 2; // 不足的ETH

        // 尝试用不足的ETH购买
        vm.prank(PLAYER);
        vm.expectRevert(PixelGame.PixelGame__NotEnoughETH.selector);
        pixelGame.purchasePixel{value: insufficientValue}(
            pixelIndex,
            pixelColor
        );
    }

    function testCannotPurchasePixelWithInvalidIndex() public {
        // 准备
        uint256 invalidIndex = 25; // 超出范围的索引（0-24有效）
        uint256 pixelColor = 444444;

        // 尝试购买无效索引的像素
        vm.prank(PLAYER);
        vm.expectRevert(PixelGame.PixelGame__PixelIndexOutOfBounds.selector);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(
            invalidIndex,
            pixelColor
        );
    }

    ///////////////////////////
    // Random Winner Tests //
    ///////////////////////////

    function testRequestRandomWordsWhenAllPixelsPurchased() public {
        // 购买所有像素
        for (uint256 i = 0; i < 25; i++) {
            vm.prank(PLAYER);
            pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(i, i * 1000);
        }

        // 验证VRF协调器被调用
        // 注意：这里我们不能直接验证requestRandomWords被调用，
        // 但我们可以检查是否有相关事件被发出
        // 这需要在合约中添加事件监听
    }

    // function testFulfillRandomWordsResetsPixels() public {
    //     // 购买一些像素
    //     for (uint256 i = 0; i < 5; i++) {
    //         vm.prank(PLAYER);
    //         pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(i, i * 1000);
    //     }

    //     // 模拟VRF回调
    //     uint256 requestId = 1;
    //     uint256[] memory randomWords = new uint256[](1);
    //     randomWords[0] = 123; // 随机数

    //     // 这里需要先设置请求状态，因为fulfillRandomWords会检查请求是否存在
    //     // 但由于s_requests是private的，我们无法直接设置
    //     // 在实际测试中，我们可能需要修改合约或使用其他方法来测试这部分

    //     // 检查像素是否被重置
    //     // 注意：由于上述限制，这个测试可能无法完全执行
    // }

    function testGetPixelArray() public {
        // 初始状态下，所有像素应该都是0
        uint256[] memory pixelArray = pixelGame.getPixelArray();
        assertEq(pixelArray.length, 25, "Pixel array should have 25 elements");

        for (uint256 i = 0; i < pixelArray.length; i++) {
            assertEq(pixelArray[i], 0, "Initial pixel color should be 0");
        }

        // 购买一个像素后，对应位置的值应该更新
        uint256 pixelIndex = 10;
        uint256 pixelColor = 555555;
        vm.prank(PLAYER);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(pixelIndex, pixelColor);

        pixelArray = pixelGame.getPixelArray();
        assertEq(
            pixelArray[pixelIndex],
            pixelColor,
            "Pixel color should be updated after purchase"
        );
    }

    ///////////////////////////
    // Integration Tests //
    ///////////////////////////

    function testFullGameCycle() public {
        // 1. 购买几个像素
        vm.startPrank(PLAYER);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(0, 111111);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(1, 222222);
        vm.stopPrank();

        vm.prank(PLAYER2);
        pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(2, 333333);

        // 2. 验证像素状态
        uint256[] memory pixelArray = pixelGame.getPixelArray();
        assertEq(pixelArray[0], 111111);
        assertEq(pixelArray[1], 222222);
        assertEq(pixelArray[2], 333333);

        // 3. 购买剩余像素，触发随机数请求
        for (uint256 i = 3; i < 25; i++) {
            vm.prank(i % 2 == 0 ? PLAYER : PLAYER2);
            pixelGame.purchasePixel{value: PIXEL_PRICE_ETH}(i, i * 10000);
        }

        // 4. 模拟VRF回调（如果可能）
        // 注意：由于合约设计限制，这部分可能无法完全测试

        // 5. 验证游戏重置
        // 同样，由于上述限制，这部分可能无法完全测试
    }
}
