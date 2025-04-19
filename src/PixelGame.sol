// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor 构造器
// receive function (if exists)
// fallback function (if exists)
// external  外部调用函数
// public  公共函数
// internal  内部调用函数
// private  私有函数
// view & pure functions  无副作用函数

// 1. 有一个5*5的数组，用来存储每个格子的颜色
// 2. 建立一个映射关系，格子的索引 -> 结构体（结构体存储更改这个格子颜色的老六信息）
// 3. 单个格子只能被购买一次
// 4. 购买格子需要花费 价值$2美元的ETH (chainlink 预言机DataFeeds), 购买的时候防止重入攻击(openzeppelin)
// 5. 当所有格子被填满后，随机其中一个格子地址的玩家获取链上所有的ETH(chainlink 预言机 VRF)
// 6. 所有格子重制，颜色重制
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceCoverter} from "./PriceCoverter.sol";

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

contract PixelGame is VRFConsumerBaseV2Plus, ReentrancyGuard {
    ////////////
    // errors //
    ////////////
    error PixelGame__NotEnoughETH(); // 付款不足
    error PixelGame__PixelAlreadyPurchased(); // 像素格子已经被购买
    error PixelGame__PixelIndexOutOfBounds(); // 像素格子索引超出范围

    using PriceCoverter for uint256; // 导入PriceCoverter库

    AggregatorV3Interface private s_priceFeed; // 价格预言机

    uint256 constant PIXEL_PRICE = 2; // 2美元
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // 请求确认数
    uint32 private constant NUM_WORDS = 1; // 需要几个随机数

    IVRFCoordinatorV2Plus private immutable i_vrfCoordinator; // VRF协调器合约
    bytes32 private immutable i_gasLane; // 决定获取随机数的gas价格上限
    uint256 private immutable i_subscriptionId; // VRF订阅ID
    uint32 private immutable i_callbackGasLimit; // 回调函数的gas限制

    // 用于跟踪随机数请求状态的结构体
    struct RequestStatus {
        bool fulfilled; // 请求是否已完成
        bool exists; // 请求ID是否存在
        uint256[] randomWords; // 存储接收到的随机数
    }

    struct Pixel {
        address player;
        uint256 pixelIndex;
        uint256 pixelColor;
        bool isPurchased;
    }

    uint256 public prevWinnerIndex; // 上一个中奖的玩家;
    uint256[] public pixelArray = new uint256[](25);
    mapping(uint256 index => Pixel pixel) public pixelMapping;
    // 映射：requestID -> 请求状态
    mapping(uint256 => RequestStatus) public s_requests;

    /////////////
    // events  //
    /////////////
    // 当像素格子被购买时触发此事件
    event PixelPurchased(
        address indexed player, // 购买者地址
        uint256 indexed pixelIndex, // 像素格子索引
        uint256 indexed pixelColor // 像素格子颜色
    );

    // 当随机数请求完成时触发此事件
    event RequestFulfilled(
        uint256 indexed requestId, // 随机数请求ID
        uint256[] randomWords, // 生成的随机数数组
        uint256 indexed winnerIndex // 中奖格子索引
    );

    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        i_vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
    }

    /////////////
    // modifier //
    /////////////
    modifier verifyPrice(uint256 pixelIndex) {
        if (pixelIndex >= pixelArray.length) {
            revert PixelGame__PixelIndexOutOfBounds();
        }

        if (pixelArray[pixelIndex] != 0) {
            revert PixelGame__PixelAlreadyPurchased();
        }

        if (msg.value.getConversionRate(s_priceFeed) < PIXEL_PRICE) {
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
        uint256 pixelColor
    ) public payable verifyPrice(pixelIndex) nonReentrant {
        pixelArray[pixelIndex] = pixelColor;
        pixelMapping[pixelIndex] = Pixel(
            msg.sender,
            pixelIndex,
            pixelColor,
            true
        );
        // 发送事件
        emit PixelPurchased(msg.sender, pixelIndex, pixelColor);

        // 检测是否所有格子都被购买
        bool allPixelsPurchased = checkAllPixelsPurchased();
        if (allPixelsPurchased) {
            // 触发随机函数，寻找中奖格子
            requestRandomWords(false);
        }
    }

    // 请求随机数的函数
    // enableNativePayment: true 使用原生代币支付，false 使用 LINK 代币支付
    function requestRandomWords(
        bool enableNativePayment
    ) internal returns (uint256 requestId) {
        // 发送随机数请求
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: enableNativePayment
                    })
                )
            })
        );

        // 发出请求随机数事件
        emit RequestedRaffleWinner(requestId);
    }

    // chainlink VRF 回调函数
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        // 检查请求ID是否存在，如果不存在则回滚交易
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;

        prevWinnerIndex = _randomWords[0] % pixelArray.length;

        // 重置所有格子的颜色
        resetPixels();
        emit RequestFulfilled(_requestId, _randomWords, prevWinnerIndex);
    }

    function resetPixels() private {
        for (uint256 i = 0; i < pixelArray.length; i++) {
            pixelArray[i] = 0;
            pixelMapping[i] = Pixel(address(0), i, 0, false);
        }
    }

    // 检测所有格子是否填满
    function checkAllPixelsPurchased() internal view returns (bool) {
        for (uint256 i = 0; i < pixelArray.length; i++) {
            if (pixelArray[i] == 0) {
                return false;
            }
        }
        return true;
    }
}
