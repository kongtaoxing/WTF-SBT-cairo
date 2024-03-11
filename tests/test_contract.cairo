use starknet::{ContractAddress, contract_address_const, get_caller_address};
use core::option::OptionTrait;

use snforge_std::{declare, ContractClassTrait, start_prank, CheatTarget};

use debug::PrintTrait;

use wtf_sbt::erc1155::IWTFSBT1155SafeDispatcher;
use wtf_sbt::erc1155::IWTFSBT1155SafeDispatcherTrait;
use wtf_sbt::erc1155::IWTFSBT1155Dispatcher;
use wtf_sbt::erc1155::IWTFSBT1155DispatcherTrait;

const MESSAGE_HASH: felt252 = 0xde2653c1df7977466a56941930a7b3b04c50011a46ec93f2dacc592bc9d33a;
const SIG_R: felt252 = 1416359803914146846654857048746954189017143364909180972482536755577398109151;
const SIG_S: felt252 = 1815054143752800481403014976568430150901385333474638620073401981379008901813;

fn deploy_contract(name: felt252, name_: felt252, symbol: felt252, uri_: ByteArray, treasury: ContractAddress, signer: ContractAddress) -> ContractAddress {
    let contract = declare(name);
    let args = array![
        name_,
        symbol,
        symbol,
        treasury.into(),
        signer.into()
    ];
    contract.deploy(@args).unwrap()
}

#[test]
fn test_message_hash() {
    let contract_address = deploy_contract('WTFSBT1155', 'Test SBT', 'TestSBT', "https://api.wtf.academy/token", get_caller_address(), get_caller_address());

    let dispatcher = IWTFSBT1155Dispatcher { contract_address: contract_address };
    let soulId: u256 = 10;

    let message_hash = dispatcher.message_hash(
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        soulId,
    );
    // println!("message_hash: {}", message_hash);
    assert(message_hash == MESSAGE_HASH, message_hash);
}

// #[test]
// fn test_verify_signature() {
//     let contract_address = deploy_contract('WTFSBT1155');

//     let dispatcher = IWTFSBT1155Dispatcher { contract_address };

//     let is_valid_signature = dispatcher.verify_signature(
//         // contract_address_try_from_felt252(0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb).unwrap(),
//         contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
//         // contract_address_try_from_felt252(0x7cffe72748da43594c5924129b4f18bffe643270a96b8760a6f2e2db49d9732).unwrap(),
//         contract_address_const::<0x7cffe72748da43594c5924129b4f18bffe643270a96b8760a6f2e2db49d9732>(),
//         'Hello, Vitalik!',
//         array![
//             SIG_R,
//             SIG_S
//         ]
//     );
//     assert(is_valid_signature == true, 'Invalid signature');
// }