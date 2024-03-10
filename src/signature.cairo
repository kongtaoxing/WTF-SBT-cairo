use starknet::ContractAddress;

#[starknet::interface]
trait IMessageContract<TContractState> {
    fn get_keccak(self: @TContractState) -> felt252;
    fn verify_signature(self: @TContractState, account: ContractAddress, address: ContractAddress, message: felt252, signature: Array<felt252>) -> bool;
    fn message_hash(self: @TContractState, account: ContractAddress, address: ContractAddress, message: felt252) -> felt252;
    fn hash_domain(self: @TContractState) -> felt252;
    fn calc_domain_hash(self: @TContractState) -> felt252;
}

#[starknet::contract]
mod MessageContract {

    use core::hash::HashStateTrait;
    use core::pedersen;
    use starknet::{ContractAddress, get_tx_info};
    use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};

    // sn_keccak('StarkNetDomain(name:felt,version:felt,chainId:felt)')
    const STARKNET_DOMAIN_TYPE_HASH: felt252 = 0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288;
    // selector!("SendMessage(address:felt,message:felt)")
    const SEND_MESSAGE_TYPE_HASH: felt252 = 0x3f7bee502f3e9d15bbb7c9e0a8c272b671fa51cd46c8da5cbb9a2b88f4f245f;
    const LOCK_AND_DELEGATE_TYPE_HASH: felt252 = 0x2ab9656e71e13c39f9f290cc5354d2e50a410992032118a1779539be0e4e75;
    const STARKNET_MESSAGE: felt252 = 'StarkNet Message';
    const NAME: felt252 = 'MessageContract';
    const VERSION: felt252 = 1;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MessageContractImpl of super::IMessageContract<ContractState> {
        fn get_keccak(self: @ContractState) -> felt252 {
            return SEND_MESSAGE_TYPE_HASH;
        }

        fn verify_signature(self: @ContractState, account: ContractAddress, address: ContractAddress, message: felt252, signature: Array<felt252>) -> bool {
            let hash = self.message_hash(account, address, message);
            let is_valid_signature_felt = AccountABIDispatcher { contract_address: account }
                .is_valid_signature(:hash, :signature);
        
            // Check either 'VALID' or True for backwards compatibility.
            is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1
        }

        fn message_hash(self: @ContractState, account: ContractAddress, address: ContractAddress, message: felt252) -> felt252 {
            let mut send_message_inputs = array![
                SEND_MESSAGE_TYPE_HASH,
                address.into(),  // address in signature
                message
            ].span();
            let send_message_hash = pedersen_hash_span(elements: send_message_inputs);
            let domain = self.calc_domain_hash();
            let mut message_inputs = array![
                STARKNET_MESSAGE,
                domain,
                account.into(),  // signer's address
                send_message_hash
            ].span();
            pedersen_hash_span(elements: message_inputs)
        }

        fn hash_domain(self: @ContractState) -> felt252 {
            let mut hash = pedersen::pedersen(0, STARKNET_DOMAIN_TYPE_HASH);
            hash = pedersen::pedersen(hash, NAME);
            hash = pedersen::pedersen(hash, VERSION);
            hash = pedersen::pedersen(hash, get_tx_info().unbox().chain_id);
            pedersen::pedersen(hash, 4)
        }

        fn calc_domain_hash(self: @ContractState) -> felt252 {
            let mut domain_state_inputs = array![
                STARKNET_DOMAIN_TYPE_HASH, NAME, VERSION, get_tx_info().unbox().chain_id
            ].span();
            pedersen_hash_span(elements: domain_state_inputs)
        }
    }

    fn pedersen_hash_span(mut elements: Span<felt252>) -> felt252 {
        let number_of_elements = elements.len();
        assert(number_of_elements > 0, 'Requires at least one element');
    
        // Pad with 0.
        let mut current: felt252 = 0;
        loop {
            // Pop elements and apply hash.
            match elements.pop_front() {
                Option::Some(next) => { current = pedersen::pedersen(current, *next); },
                Option::None(()) => { break; },
            };
        };
        // Hash with number of elements.
        pedersen::pedersen(current, number_of_elements.into())
    }
 }
