// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelpConfig.s.sol";
import {PixelGame} from "../src/PixelGame.sol";

import {CreateSubscription, FundSubscription, FundConsumer} from "./Interactions.s.sol";

contract DeployPixelGame is Script {
    function run() external returns (PixelGame, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address _vrfCoordinator,
            bytes32 _gasLane,
            uint256 _subscriptionId,
            uint32 _callbackGasLimit,
            address _link,
            uint256 _deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (_subscriptionId == 0) {
            // we are going to need to create a subscription
            // on the vrf coordinator and add the local wallet as a consumer
            // and then come back and update the subscriptionId here
            CreateSubscription createSubscription = new CreateSubscription();
            _subscriptionId = createSubscription.createSubscription(
                _vrfCoordinator,
                _deployerKey
            );

            // Fund it!
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                _vrfCoordinator,
                _subscriptionId,
                _link,
                _deployerKey
            );
        }

        vm.startBroadcast(_deployerKey);
        PixelGame pixelGame = new PixelGame(
            _vrfCoordinator,
            _gasLane,
            _subscriptionId,
            _callbackGasLimit
        );
        vm.stopBroadcast();

        FundConsumer addConsumer = new FundConsumer();
        addConsumer.addConsumer(
            address(pixelGame),
            _vrfCoordinator,
            _subscriptionId,
            _deployerKey
        );

        return (pixelGame, helperConfig);
    }
}
