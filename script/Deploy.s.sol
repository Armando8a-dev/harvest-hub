// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HarvestHub} from "../src/HarvestHub.sol";
import {FarmToken} from "../src/FarmToken.sol";

/// @notice Deploys the full HarvestHub demo:
///         - HRV reward token, funded into the hub
///         - Two stake tokens (SEED, CORN) with open faucets
///         - The hub + two pools at different emission rates
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // Reward token, minted straight into the hub as the reward pot.
        FarmToken reward = new FarmToken("Harvest", "HRV");
        FarmToken seed = new FarmToken("Seed", "SEED");
        FarmToken corn = new FarmToken("Corn", "CORN");

        HarvestHub hub = new HarvestHub(address(reward));
        reward.mint(address(hub), 1_000_000 ether); // reward pot

        // Two pools at different rates so the multi-pool UI has variety.
        bytes32 poolSeed = hub.createPool(address(seed), 0.001 ether); // slower pool
        bytes32 poolCorn = hub.createPool(address(corn), 0.005 ether); // faster pool

        vm.stopBroadcast();

        console.log("HarvestHub :", address(hub));
        console.log("HRV reward :", address(reward));
        console.log("SEED stake :", address(seed));
        console.log("CORN stake :", address(corn));
        console.log("poolSeed id:");
        console.logBytes32(poolSeed);
        console.log("poolCorn id:");
        console.logBytes32(poolCorn);
    }
}
