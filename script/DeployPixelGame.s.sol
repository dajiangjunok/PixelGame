// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PixelGame} from "../src/PixelGame.sol";

contract DeployPixelGame is Script {
    function run() external returns (PixelGame) {
        vm.startBroadcast();
        PixelGame pixelGame = new PixelGame();
        vm.stopBroadcast();

        return (pixelGame);
    }
}
