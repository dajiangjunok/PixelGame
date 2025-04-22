// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PixelGame is ReentrancyGuard {
    ////////////
    // errors //
    ////////////
    error PixelGame__NotEnoughETH(); // 付款不足
    error PixelGame__PixelAlreadyPurchased(); // 像素格子已经被购买
    error PixelGame__PixelIndexOutOfBounds(); // 像素格子索引超出范围
    error PixelGame__TransferFailed(); // 链上向胜利者转账失败

    uint256 constant PIXEL_PRICE = 0.002 ether; // 0.002 mon

    // 用于跟踪随机数请求状态的结构体
    struct RequestStatus {
        bool fulfilled; // 请求是否已完成
        bool exists; // 请求ID是否存在
        uint256[] randomWords; // 存储接收到的随机数
    }

    // 像素格子结构体
    struct Pixel {
        address player; // 玩家地址
        uint256 pixelIndex; // 格子索引
        uint256 pixelColor; // 格子颜色
        bool isPurchased; // 是否已被购买
        string pixelImage; // 像素格子图片
    }

    address public prevWinnerAddress; // 上一个中奖的玩家;
    uint256[] public pixelArray = new uint256[](25);
    mapping(uint256 index => Pixel pixel) public pixelMapping;

    /////////////
    // events  //
    /////////////
    // 当像素格子被购买时触发此事件
    event PixelPurchased(
        address indexed player, // 购买者地址
        uint256 indexed pixelIndex, // 像素格子索引
        uint256 pixelColor // 像素格子颜色
    );

    // 当随机数请求完成时触发此事件
    // event RequestFulfilled(
    //     address indexed prevWinnerAddress // 中奖格子索引
    // );

    event PixelWinner(address indexed prevWinnerAddress);

    constructor() {}

    /////////////
    // modifier //
    /////////////
    modifier verifyPrice(uint256 pixelIndex) {
        if (pixelIndex >= pixelArray.length) {
            revert PixelGame__PixelIndexOutOfBounds();
        }

        if (pixelMapping[pixelIndex].isPurchased) {
            revert PixelGame__PixelAlreadyPurchased();
        }

        if (msg.value < PIXEL_PRICE) {
            revert PixelGame__NotEnoughETH();
        }
        _;
    }

    /**
     * @notice 购买像素格子的函数
     * @param pixelIndex 像素格子的索引
     * @param pixelColor 像素格子的颜色
     * @dev 这个函数允许用户通过支付ETH来购买并设置像素格子的颜色
     * 要求:
     * 1. 支付足够的ETH (价值2美元)
     * 2. 像素格子未被购买过
     * 3. 像素格子索引在有效范围内
     */
    function purchasePixel(
        uint256 pixelIndex,
        uint256 pixelColor,
        string memory pixelImage
    ) public payable verifyPrice(pixelIndex) nonReentrant {
        pixelArray[pixelIndex] = pixelColor;
        pixelMapping[pixelIndex] = Pixel(
            msg.sender,
            pixelIndex,
            pixelColor,
            true,
            pixelImage
        );
        // 发送事件
        emit PixelPurchased(msg.sender, pixelIndex, pixelColor);

        // 检测是否所有格子都被购买
        bool allPixelsPurchased = checkAllPixelsPurchased();
        if (allPixelsPurchased) {
            // 触发随机函数，寻找中奖格子
            uint256 randomness = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.number,
                        msg.sender,
                        address(this)
                    )
                )
            );
            uint256 prevWinnerIndex = randomness % pixelArray.length;

            // 链上资金发送给中奖的玩家
            prevWinnerAddress = pixelMapping[prevWinnerIndex].player;

            uint256 prize = address(this).balance;
            (bool success, ) = prevWinnerAddress.call{value: prize}("");
            if (!success) {
                revert PixelGame__TransferFailed();
            } else {
                // 重置所有格子的颜色
                resetPixels();
                emit PixelWinner(prevWinnerAddress);
            }
        }
    }

    // 重制像素格子
    function resetPixels() private {
        for (uint256 i = 0; i < pixelArray.length; i++) {
            pixelArray[i] = 0;
            pixelMapping[i] = Pixel(address(0), i, 0, false, "");
        }
    }

    // 检测所有格子是否填满
    function checkAllPixelsPurchased() internal view returns (bool) {
        for (uint256 i = 0; i < pixelArray.length; i++) {
            if (!pixelMapping[i].isPurchased) {
                return false;
            }
        }
        return true;
    }

    ///////////////////////////
    // view & pure functions //
    ///////////////////////////
    // 获取整个像素数组
    function getPixelArray() public view returns (Pixel[] memory) {
        // return pixelArray;
        Pixel[] memory pixels = new Pixel[](pixelArray.length);
        for (uint256 i = 0; i < pixelArray.length; i++) {
            pixels[i] = pixelMapping[i];
        }
        return pixels;
    }

    // 获取单个格子购买者信息
    function getPixelInfo(
        uint256 pixelIndex
    ) public view returns (Pixel memory) {
        Pixel memory pixel = pixelMapping[pixelIndex];
        return pixel;
    }

    function getPrevWinnerAddress() public view returns (address) {
        return prevWinnerAddress;
    }
}
