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

contract PixelGame {
    struct Pixel {
        address player;
        uint256 pixelIndex;
        uint256 pixelColor;
        bool isPurchased;
    }

    uint256[] public pixelArray = new uint256[](25);
    mapping(uint256 => Pixel) public pixelMapping;
}
