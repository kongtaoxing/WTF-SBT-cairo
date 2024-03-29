use starknet::ContractAddress;
use core::pedersen::PedersenTrait;
use core::hash::{HashStateTrait, HashStateExTrait};

#[starknet::interface]
trait IEtherContract<TContractState> {
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IWTFSBT1155<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress, id: u256) -> u256;
    fn balance_of_batch(
        self: @TContractState, accounts: Array<ContractAddress>, ids: Array<u256>
    ) -> Array<u256>;
    fn is_approved_for_all(
        self: @TContractState, account: ContractAddress, operator: ContractAddress
    ) -> bool;

    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    // Span<felt252> here is for bytes in Solidity
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        id: u256,
        amount: u256,
        data: Span<felt252>
    );
    fn safe_batch_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        ids: Array<u256>,
        amounts: Array<u256>,
        data: Span<felt252>
    );
    // fn mint(ref self: TContractState, to: ContractAddress, id: u256, amount: u256);

    fn minterMint(ref self: TContractState, to: ContractAddress, soulId: u256, mintPrice: u256);

    fn mint_batch(
        ref self: TContractState, to: ContractAddress, ids: Array<u256>, amounts: Array<u256>,
    );
    fn uri(self: @TContractState, soulId: u256) -> ByteArray;
    fn createSoul(ref self: TContractState, soulName: felt252, description: ByteArray, mintPrice: u256, startDateTimestamp: u64, endDateTimestamp: u64);
    fn isCreated(self: @TContractState, soulId: u256) -> bool;
    fn recover(ref self: TContractState, oldOwner: ContractAddress, newOwner: ContractAddress);
    fn setbaseURI(ref self: TContractState, base_uri: ByteArray);
    fn locked(self: @TContractState, sbtId: u256) -> bool;
    fn getSoulName(self: @TContractState, soulId: u256) -> felt252;
    fn getSoulDescription(self: @TContractState, soulId: u256) -> ByteArray;
    fn getSoulMinPrice(self: @TContractState, soulId: u256) -> u256;
    fn getSoulRegisteredTimestamp(self: @TContractState, soulId: u256) -> u64;
    fn getSoulStartDateTimestamp(self: @TContractState, soulId: u256) -> u64;
    fn getSoulEndDateTimestamp(self: @TContractState, soulId: u256) -> u64;
    fn isMinter(self: @TContractState, minter: ContractAddress) -> bool;
    fn addMinter(ref self: TContractState, minter: ContractAddress);
    fn removeMinter(ref self: TContractState, minter: ContractAddress);
    fn transferTreasury(ref self: TContractState, newTreasury: ContractAddress);

    fn verify_signature(self: @TContractState, account: ContractAddress, soulId: u256, signature: Array<felt252>) -> bool;
    fn message_hash(self: @TContractState, signer: ContractAddress, account: ContractAddress, soulId: u256) -> felt252;
    fn mint(ref self: TContractState, account: ContractAddress, soulId: u256, mintPrice: u256, signature: Array<felt252>);
}

#[starknet::contract]
mod WTFSBT1155 {
    use core::clone::Clone;
    use core::array::SpanTrait;
    use core::array::ArrayTrait;
    use core::array::ArrayTCloneImpl;
    use core::zeroable::Zeroable;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::get_tx_info;

    use core::hash::HashStateTrait;
    use core::pedersen;
    use core::debug::PrintTrait;
    use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};

    use super::{IEtherContractDispatcher, IEtherContractDispatcherTrait};

    use super::super::erc1155_receiver::ERC1155Receiver;
    use super::super::erc1155_receiver::ERC1155ReceiverTrait;

    // sn_keccak('StarkNetDomain(name:felt,version:felt,chainId:felt)')
    const STARKNET_DOMAIN_TYPE_HASH: felt252 = 0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288;
    // sn_keccak("WTFSBT1155(account:felt,soulId:u256)")
    const SBT_MINT_TYPE_HASH: felt252 = selector!("WTFSBT1155(account:felt,soulId:u256)u256(low:felt,high:felt)");
    const U256_TYPE_HASH: felt252 = selector!("u256(low:felt,high:felt)");
    const STARKNET_MESSAGE: felt252 = 'StarkNet Message';
    const NAME: felt252 = 'WTFSBT1155';
    const VERSION: felt252 = 1;

    #[storage]
    struct Storage {
        _uri: ByteArray,
        _balances: LegacyMap::<(u256, ContractAddress), u256>,
        _operator_approvals: LegacyMap::<(ContractAddress, ContractAddress), bool>,
        treasury: ContractAddress,
        name: felt252,
        symbol: felt252,
        owner: ContractAddress,
        minters: LegacyMap::<ContractAddress, bool>,
        soulIdToSoulContainer: LegacyMap::<u256, SoulContainer>,
        latestUnusedTokenId: u256,
        signer: ContractAddress,
        mintedAddress: LegacyMap::<(ContractAddress, u256), bool>,
    }

    #[derive(Drop, Clone, starknet::Store)]
    struct SoulContainer {
        soulName: felt252,
        description: ByteArray,
        creator: ContractAddress,
        mintPrice: u256,
        registeredTimestamp: u64,
        startDateTimestamp: u64,
        endDateTimestamp: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TransferSingle: TransferSingle,
        TransferBatch: TransferBatch,
        ApprovalForAll: ApprovalForAll,
        URI: URI,
        MinterAdded: MinterAdded,
        MinterRemoved: MinterRemoved,
        TreasureTransferred: TreasureTransferred,
        CreatedSoul: CreatedSoul,
        Donate: Donate,
        SBTMinted: SBTMinted,
        SignerChanged: SignerChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferSingle {
        #[key]
        operator: ContractAddress,
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        id: u256,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferBatch {
        #[key]
        operator: ContractAddress,
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        ids: Array<u256>,
        values: Array<u256>,
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        #[key]
        account: ContractAddress,
        #[key]
        operator: ContractAddress,
        approved: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct URI {
        value: ByteArray,
        id: u256,
    }

    // WTF SBT Event
    #[derive(Drop, starknet::Event)]
    struct MinterAdded {
        #[key]
        newMinter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRemoved {
        #[key]
        oldMinter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct TreasureTransferred {
        #[key]
        user: ContractAddress,
        #[key]
        newTreasury: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatedSoul {
        #[key]
        creator: ContractAddress,
        #[key]
        tokenId: u256,
        soulName: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Donate {
        #[key]
        soulID: u256,
        #[key]
        donator: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SBTMinted {
        #[key]
        account: ContractAddress,
        #[key]
        soulId: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SignerChanged {
        #[key]
        oldSigner: ContractAddress,
        #[key]
        newSigner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, symbol: felt252, uri_: ByteArray, treasury: ContractAddress, signer: ContractAddress) {
        self._set_uri(uri_);
        self.name.write(name);
        self.symbol.write(symbol);
        self.treasury.write(treasury);
        self.owner.write(get_caller_address());
        self.signer.write(signer);
    }

    #[abi(embed_v0)]
    impl IERC1155impl of super::IWTFSBT1155<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            assert(!account.is_zero(), 'query for the zero address');
            self._balances.read((id, account))
        }
        fn balance_of_batch(
            self: @ContractState, accounts: Array<ContractAddress>, ids: Array<u256>
        ) -> Array<u256> {
            assert(accounts.len() == ids.len(), 'accounts and ids len mismatch');
            let mut batch_balances = ArrayTrait::new();

            let mut i: usize = 0;
            loop {
                if i >= accounts.len() {
                    break;
                }
                batch_balances.append(IERC1155impl::balance_of(self, *accounts.at(i), *ids.at(i)));
                i += 1;
            };

            batch_balances
        }
        fn is_approved_for_all(
            self: @ContractState, account: ContractAddress, operator: ContractAddress
        ) -> bool {
            self._operator_approvals.read((account, operator))
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self._set_approval_for_all(get_caller_address(), operator, approved)
        }
        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>
        ) {
            assert(
                (from == get_caller_address())
                    || (IERC1155impl::is_approved_for_all(@self, from, get_caller_address())),
                'caller is not owner | approved'
            );
            self._safe_transfer_from(from, to, id, amount, data);
        }
        fn safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Span<felt252>
        ) {
            assert(
                (from == get_caller_address())
                    || (IERC1155impl::is_approved_for_all(@self, from, get_caller_address())),
                'caller is not owner | approved'
            );
            self._safe_batch_transfer_from(from, to, ids, amounts, data);
        }

        // fn mint(ref self: ContractState, to: ContractAddress, id: u256, amount: u256,) {
        //     self._mint(to, id, amount, ArrayTrait::<felt252>::new().span());
        // }

        fn mint_batch(
            ref self: ContractState, to: ContractAddress, ids: Array<u256>, amounts: Array<u256>,
        ) {
            // self._mint_batch(to, ids, amounts, ArrayTrait::<felt252>::new().span());
        }

        fn minterMint(ref self: ContractState, to: ContractAddress, soulId: u256, mintPrice: u256) {
            assert(self.isMinter(get_caller_address()), 'only minter function');
            assert(self.isCreated(soulId), 'SoulID not created');
            let startDateTimeStamp = self.getSoulStartDateTimestamp(soulId);
            assert(startDateTimeStamp <= get_block_timestamp(), 'mint not started');
            assert(mintPrice >= self.getSoulMinPrice(soulId), 'mint price not enough');
            let endDateTimeStamp = self.getSoulEndDateTimestamp(soulId);
            assert(endDateTimeStamp > get_block_timestamp() || endDateTimeStamp == 0, 'mint ended');

            let ca_ether = contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>();
            let ether_contract = IEtherContractDispatcher { contract_address: ca_ether };
            ether_contract.transferFrom(
                get_caller_address(),
                self.treasury.read(),
                mintPrice
            );
            self.emit(Event::Donate(Donate { soulID: soulId, donator: get_caller_address(), amount: mintPrice }));
            self._mint(to, soulId, 1, ArrayTrait::<felt252>::new().span());
            self.emit(Event::SBTMinted(SBTMinted { account: to, soulId: soulId }));
        }

        fn uri(self: @ContractState, soulId: u256) -> ByteArray {
            assert(self.isCreated(soulId), 'SoulID not created');
            self._uri.read()
        }
        
        fn createSoul(ref self: ContractState, soulName: felt252, description: ByteArray, mintPrice: u256, startDateTimestamp: u64, endDateTimestamp: u64) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            let soulId = self.latestUnusedTokenId.read();
            let soulContainer = SoulContainer {
                soulName,
                description,
                creator: get_caller_address(),
                mintPrice,
                registeredTimestamp: get_block_timestamp(),
                startDateTimestamp,
                endDateTimestamp,
            };
            self.soulIdToSoulContainer.write(soulId, soulContainer);
            self.emit(
                Event::CreatedSoul(
                    CreatedSoul { creator: get_caller_address(), tokenId: soulId, soulName }
                )
            );

            self.latestUnusedTokenId.write(soulId + 1);
        }

        fn isCreated(self: @ContractState, soulId: u256) -> bool {
            if soulId < self.latestUnusedTokenId.read() {
                true
            } else {
                false
            }
        }

        fn recover(ref self: ContractState, oldOwner: ContractAddress, newOwner: ContractAddress) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            let mut addressBalances: Array<u256> = array![];
            let mut soulIdList: Array<u256> = array![];
            let mut i: u256 = 0;
            loop {
                if i >= self.latestUnusedTokenId.read() {
                    break;
                }
                let balance = self._balances.read((i, oldOwner));
                addressBalances.append(balance);
                soulIdList.append(i);
                i += 1;
            };
            self.safe_batch_transfer_from(oldOwner, newOwner, soulIdList, addressBalances, array![].span());
        }

        fn setbaseURI(ref self: ContractState, base_uri: ByteArray) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            self._set_uri(base_uri);
        }

        fn locked(self: @ContractState, sbtId: u256) -> bool {
            assert(self.isCreated(sbtId), 'SoulID not created');
            true
        }
        fn getSoulName(self: @ContractState, soulId: u256) -> felt252 {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).soulName
        }

        fn getSoulDescription(self: @ContractState, soulId: u256) -> ByteArray {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).description
        }

        fn getSoulMinPrice(self: @ContractState, soulId: u256) -> u256 {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).mintPrice
        }

        fn getSoulRegisteredTimestamp(self: @ContractState, soulId: u256) -> u64 {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).registeredTimestamp
        }

        fn getSoulStartDateTimestamp(self: @ContractState, soulId: u256) -> u64 {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).startDateTimestamp
        }

        fn getSoulEndDateTimestamp(self: @ContractState, soulId: u256) -> u64 {
            assert(self.isCreated(soulId), 'SoulID not created');
            self.soulIdToSoulContainer.read(soulId).endDateTimestamp
        }

        fn isMinter(self: @ContractState, minter: ContractAddress) -> bool {
            self.minters.read(minter)
        }

        fn addMinter(ref self: ContractState, minter: ContractAddress) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            self.minters.write(minter, true);
            self.emit(Event::MinterAdded(MinterAdded { newMinter: minter }));
        }

        fn removeMinter(ref self: ContractState, minter: ContractAddress) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            self.minters.write(minter, false);
            self.emit(Event::MinterRemoved(MinterRemoved { oldMinter: minter }));
        }

        fn transferTreasury(ref self: ContractState, newTreasury: ContractAddress) {
            assert(self.owner.read() == get_caller_address(), 'only owner function');
            self.treasury.write(newTreasury);
            self.emit(Event::TreasureTransferred(TreasureTransferred { user: get_caller_address(), newTreasury }));
        }
        
        fn verify_signature(self: @ContractState, account: ContractAddress, soulId: u256, signature: Array<felt252>) -> bool {
            let signer = self.signer.read();
            let hash = self.message_hash(signer, account, soulId);
            let is_valid_signature_felt = AccountABIDispatcher { contract_address: signer }
                .is_valid_signature(:hash, :signature);
        
            // Check either 'VALID' or True for backwards compatibility.
            is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1
        }

        fn message_hash(self: @ContractState, signer: ContractAddress, account: ContractAddress, soulId: u256) -> felt252 {
            let mut send_message_inputs = array![
                SBT_MINT_TYPE_HASH,
                account.into(),  // address in signature
                hash_u256(soulId)
            ].span();
            let send_message_hash = pedersen_hash_span(elements: send_message_inputs);
            let domain = calc_domain_hash();
            let mut message_inputs = array![
                STARKNET_MESSAGE,
                domain,
                signer.into(),  // signer's address
                send_message_hash
            ].span();
            pedersen_hash_span(elements: message_inputs)
        }

        fn mint(ref self: ContractState, account: ContractAddress, soulId: u256, mintPrice: u256, signature: Array<felt252>) {
            assert(!self.mintedAddress.read((account, soulId)), 'Already minted');
            assert(self.verify_signature(account, soulId, signature), 'Invalid signature');
            assert(self.isCreated(soulId), 'SoulID not created');
            let startDateTimeStamp = self.getSoulStartDateTimestamp(soulId);
            assert(startDateTimeStamp <= get_block_timestamp(), 'mint not started');
            assert(mintPrice >= self.getSoulMinPrice(soulId), 'mint price not enough');
            let endDateTimeStamp = self.getSoulEndDateTimestamp(soulId);
            assert(endDateTimeStamp > get_block_timestamp() || endDateTimeStamp == 0, 'mint ended');

            let ca_ether = contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>();
            let ether_contract = IEtherContractDispatcher { contract_address: ca_ether };
            ether_contract.transferFrom(
                get_caller_address(),
                self.treasury.read(),
                mintPrice
            );
            self.emit(Event::Donate(Donate { soulID: soulId, donator: get_caller_address(), amount: mintPrice }));
            self._mint(account, soulId, 1, ArrayTrait::<felt252>::new().span());
            self.mintedAddress.write((account, soulId), true);
            self.emit(Event::SBTMinted(SBTMinted { account, soulId }));
        }
    }

    fn hash_u256(value: u256) -> felt252 {
        let mut inputs = array![U256_TYPE_HASH, value.low.into(), value.high.into()].span();
        pedersen_hash_span(elements: inputs)
    }

    fn calc_domain_hash() -> felt252 {
        let mut domain_state_inputs = array![
            STARKNET_DOMAIN_TYPE_HASH, NAME, VERSION, get_tx_info().unbox().chain_id
        ].span();
        pedersen_hash_span(elements: domain_state_inputs)
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

    #[generate_trait]
    impl StorageImpl of StorageTrait {
        fn _mint(
            ref self: ContractState,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>
        ) {
            assert(!to.is_zero(), 'mint to the zero address');
            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator,
                    contract_address_const::<0>(),
                    to,
                    self._as_singleton_array(id),
                    self._as_singleton_array(amount),
                    data.clone()
                );
            self._balances.write((id, to), self._balances.read((id, to)) + amount);
            self
                .emit(
                    Event::TransferSingle(
                        TransferSingle {
                            operator, from: contract_address_const::<0>(), to, id, value: amount
                        }
                    )
                );
            self
                ._do_safe_transfer_acceptance_check(
                    operator, contract_address_const::<0>(), to, id, amount, data.clone()
                );
        }

        fn _mint_batch(
            ref self: ContractState,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Span<felt252>
        ) {
            assert(!to.is_zero(), 'mint to the zero address');
            assert(ids.len() == amounts.len(), 'length mismatch');

            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator,
                    contract_address_const::<0>(),
                    to,
                    ids.clone(),
                    amounts.clone(),
                    data.clone()
                );

            let mut i: usize = 0;

            let _ids = ids.clone();
            let _amounts = amounts.clone();
            loop {
                if i >= _ids.len() {
                    break;
                }

                self
                    ._balances
                    .write(
                        (*_ids.at(i), to), self._balances.read((*_ids.at(i), to)) + *_amounts.at(i)
                    );

                i += 1;
            };

            let _ids = ids.clone();
            let _amounts = amounts.clone();
            self
                .emit(
                    Event::TransferBatch(
                        TransferBatch {
                            operator,
                            from: contract_address_const::<0>(),
                            to: contract_address_const::<0>(),
                            ids: _ids,
                            values: _amounts
                        }
                    )
                );

            self
                ._do_safe_batch_transfer_acceptance_check(
                    operator,
                    contract_address_const::<0>(),
                    to,
                    ids.clone(),
                    amounts.clone(),
                    data.clone()
                );
        }

        fn _burn(ref self: ContractState, from: ContractAddress, id: u256, amount: u256) {
            assert(!from.is_zero(), 'burn from the zero address');
            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator,
                    from,
                    contract_address_const::<0>(),
                    self._as_singleton_array(id),
                    self._as_singleton_array(amount),
                    ArrayTrait::<felt252>::new().span()
                );

            let from_balance = self._balances.read((id, from));
            assert(from_balance >= amount, 'burn amount exceeds balance');
            self._balances.write((id, from), from_balance - amount);
            self
                .emit(
                    Event::TransferSingle(
                        TransferSingle {
                            operator, from, to: contract_address_const::<0>(), id, value: amount
                        }
                    )
                );
        }

        fn _burn_batch(
            ref self: ContractState, from: ContractAddress, ids: Array<u256>, amounts: Array<u256>
        ) {
            assert(!from.is_zero(), 'burn from the zero address');
            assert(ids.len() == amounts.len(), 'ids and amounts length mismatch');

            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator,
                    from,
                    contract_address_const::<0>(),
                    ids.clone(),
                    amounts.clone(),
                    ArrayTrait::<felt252>::new().span()
                );

            let mut i: usize = 0;
            let _ids = ids.clone();
            let _amounts = amounts.clone();
            loop {
                if i >= _ids.len() {
                    break;
                }
                let id = *_ids.at(i);
                let amount = *_amounts.at(i);

                let from_balance = self._balances.read((id, from));
                assert(from_balance >= amount, 'burn amount exceeds balance');
                self._balances.write((id, from), from_balance - amount);

                i += 1;
            };
            self
                .emit(
                    Event::TransferBatch(
                        TransferBatch {
                            operator, from, to: contract_address_const::<0>(), ids, values: amounts
                        }
                    )
                );
        }

        fn _safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>
        ) {
            assert(!to.is_zero(), 'transfer to the zero address');
            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator,
                    from,
                    to,
                    self._as_singleton_array(id),
                    self._as_singleton_array(amount),
                    data.clone()
                );
            let from_balance = self._balances.read((id, from));
            assert(from_balance >= amount, 'insufficient balance');
            self._balances.write((id, from), from_balance - amount);
            self._balances.write((id, to), self._balances.read((id, to)) + amount);
            self
                .emit(
                    Event::TransferSingle(TransferSingle { operator, from, to, id, value: amount })
                );
            self._do_safe_transfer_acceptance_check(operator, from, to, id, amount, data.clone());
        }

        fn _safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Span<felt252>
        ) {
            assert(ids.len() == amounts.len(), 'length mismatch');
            assert(!to.is_zero(), 'transfer to the zero address');

            let operator = get_caller_address();
            self
                ._beforeTokenTransfer(
                    operator, from, to, ids.clone(), amounts.clone(), data.clone()
                );

            let _ids = ids.clone();
            let _amounts = amounts.clone();
            let mut i: usize = 0;
            loop {
                if i >= _ids.len() {
                    break;
                }

                let id = *_ids.at(i);
                let amount = *_amounts.at(i);

                let from_balance = self._balances.read((id, from));
                assert(from_balance >= amount, 'insufficient balance');
                self._balances.write((id, from), from_balance - amount);
                self._balances.write((id, to), self._balances.read((id, to)) + amount);

                i += 1;
            };

            let _ids = ids.clone();
            let _amounts = amounts.clone();
            self
                .emit(
                    Event::TransferBatch(
                        TransferBatch { operator, from, to, ids: _ids, values: _amounts }
                    )
                );

            self
                ._do_safe_batch_transfer_acceptance_check(
                    operator, from, to, ids, amounts, data.clone()
                )
        }

        fn _set_uri(ref self: ContractState, newuri: ByteArray) {
            self._uri.write(newuri);
        }

        fn _set_approval_for_all(
            ref self: ContractState,
            owner: ContractAddress,
            operator: ContractAddress,
            approved: bool,
        ) {
            assert(owner != operator, 'ERC1155: self approval');
            self._operator_approvals.write((owner, operator), approved);
            self.emit(ApprovalForAll { account: owner, operator, approved });
        }

        fn _beforeTokenTransfer(
            ref self: ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Span<felt252>,
        ) {
            assert(from.is_zero() || to.is_zero() || get_caller_address() == self.owner.read(), 'Non-Transferable!');
        }

        fn _do_safe_transfer_acceptance_check(
            ref self: ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>
        ) {
            ERC1155Receiver { contract_address: to }
                .on_erc1155_received(operator, from, id, amount, data);
        }

        fn _do_safe_batch_transfer_acceptance_check(
            ref self: ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Span<felt252>
        ) {
            ERC1155Receiver { contract_address: to }
                .on_erc1155_batch_received(operator, from, ids, amounts, data);
        }

        fn _as_singleton_array(self: @ContractState, element: u256) -> Array<u256> {
            let mut args = ArrayTrait::new();
            args.append(element);
            args
        }
    }
}