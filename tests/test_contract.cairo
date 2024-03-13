use starknet::{ContractAddress, contract_address_const, get_caller_address, get_block_number};
// use core::option::OptionTrait;

use snforge_std::{declare, ContractClassTrait, start_prank, CheatTarget, start_warp, stop_prank};

use debug::PrintTrait;

use wtf_sbt::erc1155::IWTFSBT1155SafeDispatcher;
use wtf_sbt::erc1155::IWTFSBT1155SafeDispatcherTrait;
use wtf_sbt::erc1155::IWTFSBT1155Dispatcher;
use wtf_sbt::erc1155::IWTFSBT1155DispatcherTrait;
use wtf_sbt::ethereum::IEthereumDispatcher;
use wtf_sbt::ethereum::IEthereumDispatcherTrait;

use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};

const MESSAGE_HASH: felt252 = 0xde2653c1df7977466a56941930a7b3b04c50011a46ec93f2dacc592bc9d33a;    // got from `sign.js`
const PUBLIC_KEY: felt252 = 0x49a1ecb78d4f98eea4c52f2709045d55b05b9c794f7423de504cc1d4f7303c3;
const SIG_R: felt252 = 1416359803914146846654857048746954189017143364909180972482536755577398109151;
const SIG_S: felt252 = 1815054143752800481403014976568430150901385333474638620073401981379008901813;

fn deploy_account(address: ContractAddress) {
    let contract = declare('Account');
    let args = array![PUBLIC_KEY];
    let _address = contract.deploy_at(@args, address);
}

fn deploy_ethereum() -> IEthereumDispatcher {
    let contract = declare('Ethereum');
    let ethereum_address = contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>();
    let args: Array<felt252> = array!['minter_address'];
    let ethereum_contract_address = contract.deploy_at(@args, ethereum_address);
    IEthereumDispatcher { contract_address: ethereum_contract_address.unwrap() }
}

fn deploy_contract(name: felt252, name_: felt252, symbol: felt252, uri_: ByteArray, treasury: ContractAddress, signer: ContractAddress) -> ContractAddress {
    let contract = declare(name);
    let mut args: Array<felt252> = array![
        name_,
        symbol,
    ];
    uri_.serialize(ref args);
    args.append(treasury.into());
    args.append(signer.into());
    contract.deploy(@args).unwrap()
}

fn set_up() -> IWTFSBT1155Dispatcher {
    let contract_address = deploy_contract(
        'WTFSBT1155',
        'Test SBT',
        'TestSBT',
        "https://api.wtf.academy/token",
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>()
    );

    let dispatcher = IWTFSBT1155Dispatcher { contract_address: contract_address };
    dispatcher.createSoul('test01', "test 01", 0, 0, 0);
    dispatcher.createSoul('test02', "test 02", 10, get_block_number(), get_block_number() + 100);

    dispatcher
}

#[test]
fn test_message_hash() {
    let contract_address = deploy_contract(
        'WTFSBT1155',
        'Test SBT',
        'TestSBT',
        "https://api.wtf.academy/token",
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>()
    );

    let dispatcher = IWTFSBT1155Dispatcher { contract_address: contract_address };
    let soulId: u256 = 10;

    let message_hash = dispatcher.message_hash(
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        soulId,
    );
    assert(message_hash == MESSAGE_HASH, message_hash);
}

#[test]
fn test_verify_signature() {
    let contract_address = deploy_contract(
        'WTFSBT1155',
        'Test SBT',
        'TestSBT',
        "https://api.wtf.academy/token",
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>(),
        contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>()
    );
    let address = contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>();
    deploy_account(address);

    let dispatcher = IWTFSBT1155Dispatcher { contract_address };

    let is_valid_signature = dispatcher.verify_signature(
        address,
        10,
        array![
            SIG_R,
            SIG_S
        ]
    );
    assert(is_valid_signature == true, 'Invalid signature');
}

#[test]
fn test_created() {
    let dispatcher = set_up();
    assert(dispatcher.isCreated(0), 'Soul 01 should be created');
    assert(dispatcher.isCreated(1), 'Soul 02 should be created');
    assert(!dispatcher.isCreated(2), 'Soul 03 should not be created');
}

#[test]
fn test_mint_with_zero_price() {
    let dispatcher = set_up();
    let caller = contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>();
    let ethereum_dispatcher = deploy_ethereum();
    let soulId: u256 = 0;
    let minter = contract_address_const::<'minter_address'>();
    dispatcher.addMinter(minter);
    start_prank(CheatTarget::One(dispatcher.contract_address), minter);
    ethereum_dispatcher.mint();
    let price = dispatcher.getSoulMinPrice(soulId);
    ethereum_dispatcher.approve(ethereum_dispatcher.contract_address, price);
    dispatcher.minterMint(caller, soulId, 0);
    assert(dispatcher.balance_of(caller, soulId) == 1, 'Invalid balance');
}

#[test]
fn test_mint_with_price() {
    let dispatcher = set_up();
    let caller = contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>();
    let ethereum_dispatcher = deploy_ethereum();
    let soulId: u256 = 1;
    let minter = contract_address_const::<'minter_address'>();
    dispatcher.addMinter(minter);
    start_prank(CheatTarget::One(dispatcher.contract_address), minter);
    start_warp(CheatTarget::All, get_block_number() + 50);
    ethereum_dispatcher.mint_amount(minter, 1000);
    'minter\' eth balance'.print();
    ethereum_dispatcher.balance_of(minter).print();
    let price = dispatcher.getSoulMinPrice(soulId);
    'price'.print();
    price.print();
    ethereum_dispatcher.approve(ethereum_dispatcher.contract_address, price);
    'allowance'.print();
    ethereum_dispatcher.allowance(minter, ethereum_dispatcher.contract_address).print();
    dispatcher.minterMint(caller, soulId, price);
    stop_prank(CheatTarget::One(dispatcher.contract_address));
    assert(dispatcher.balance_of(caller, soulId) == 1, 'Invalid balance');
}

#[test]
fn test_mint_with_signature() {
    let dispatcher = set_up();
    let caller = contract_address_const::<0x05c6accc31f3689571cdf595828163bcfa0e5da7513cbd81d2d65e21e0dbbacb>();
    let ethereum_dispatcher = deploy_ethereum();
    let soulId: u256 = 1;
    let minter = contract_address_const::<'minter_address'>();
    dispatcher.addMinter(minter);
    start_prank(CheatTarget::One(dispatcher.contract_address), minter);
    start_warp(CheatTarget::All, get_block_number() + 50);
    ethereum_dispatcher.mint_amount(minter, 1000);
    let price = dispatcher.getSoulMinPrice(soulId);
    ethereum_dispatcher.approve(ethereum_dispatcher.contract_address, price);
    let message_hash = dispatcher.message_hash(
        ethereum_dispatcher.contract_address,
        minter,
        soulId,
    );
    let signature = array![
        SIG_R,
        SIG_S
    ];
    dispatcher.minterMintWithSignature(caller, soulId, price, message_hash, signature);
    stop_prank(CheatTarget::One(dispatcher.contract_address));
    assert(dispatcher.balance_of(caller, soulId) == 1, 'Invalid balance');
}