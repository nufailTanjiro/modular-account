// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";

import {WalletXModularAccountFactory} from "../src/factory/WalletXModularAccountFactory.sol";
import {SingleSignerValidationModule} from "../src/modules/validation/SingleSignerValidationModule.sol";
import {ModularAccount} from "../src/account/ModularAccount.sol";

contract Deploy is Script {
    // load entrypoint from env
    address public entryPointAddr = vm.envAddress("ENTRYPOINT");
    IEntryPoint public entryPoint = IEntryPoint(payable(entryPointAddr));

    // Load factory owner from env
    address public factoryOwner = vm.envAddress("FACTORY_OWNER");

    // Deployer Key from env
    uint256 deployer = vm.envUint("OWNER");

    // Implementation contract
    address public accountImpl = vm.envOr("ACCOUNT_IMPL", payable(address(0)));

    // Validation module
    address public validationModule =
        vm.envOr("VALIDATION_MODULE", payable(address(0)));

    function run() public {
        console.log("******** Deploying *********");
        console.log("Chain: ", block.chainid);
        console.log("EP: ", entryPointAddr);
        console.log("Factory owner: ", factoryOwner);

        vm.startBroadcast(deployer);

        if (accountImpl == address(0)) {
            accountImpl = address(new ModularAccount(entryPoint));
            console.log("Account Impl: ", accountImpl);
        }

        if (validationModule == address(0)) {
            validationModule = address(new SingleSignerValidationModule());
            console.log("Validation Module: ", validationModule);
        }

        // Deploy factory
        address factory = address(
            new WalletXModularAccountFactory(
                IEntryPoint(entryPointAddr),
                ModularAccount(payable(accountImpl)),
                validationModule,
                factoryOwner
            )
        );

        console.log("Factory: ", factory);

        console.log("******** Deploy Done! *********");

        vm.stopBroadcast();
    }

    function _addStakeForFactory(
        address factoryAddr,
        IEntryPoint anEntryPoint
    ) internal {
        uint32 unstakeDelaySec = uint32(
            vm.envOr("UNSTAKE_DELAY_SEC", uint32(86400))
        );
        uint256 requiredStakeAmount = vm.envUint("REQUIRED_STAKE_AMOUNT");
        uint256 currentStakedAmount = IEntryPoint(address(anEntryPoint))
            .getDepositInfo(factoryAddr)
            .stake;
        uint256 stakeAmount = requiredStakeAmount - currentStakedAmount;
        // since all factory share the same addStake method, it does not matter which contract we use to cast the
        // address
        WalletXModularAccountFactory(payable(factoryAddr)).addStake{
            value: stakeAmount
        }(unstakeDelaySec);
        console.log("******** Add Stake Verify *********");
        console.log("Staked factory: ", factoryAddr);
        console.log(
            "Stake amount: ",
            IEntryPoint(address(anEntryPoint)).getDepositInfo(factoryAddr).stake
        );
        console.log(
            "Unstake delay: ",
            IEntryPoint(address(anEntryPoint))
                .getDepositInfo(factoryAddr)
                .unstakeDelaySec
        );
        console.log("******** Stake Verify Done *********");
    }
}

/*

  ******** Deploying *********
  Chain:  80002
  EP:  0x0000000071727De22E5E9d8BAf0edAc6f37da032
  Factory owner:  0x6B127667C864862B05acCa75fF066BE7Bd77fBA5
  Account Impl:  0x2c7d002FA0b01206F10bf926A312Be3cd5ef969E
  Validation Module:  0xCA531fBC129C9CfCA4c5f54d9Bf3D2E248552c1A        
  Factory:  0xa8072A1e6CC45D80C8002D4A26A8dEA99e0Ff37f
  ******** Deploy Done! *********
*/
