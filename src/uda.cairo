#[starknet::contract]
mod uda {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[starknet::interface]
    pub trait IUda<TContractState> {
        fn get_owner(self: @TContractState) -> ContractAddress;
        fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
        fn renounce_ownership(ref self: TContractState);
    }

    #[storage]
    struct Storage {
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnerChanged: OwnerChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnerChanged {
        #[key]
        old_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl UdaImpl of IUda<ContractState> {
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let caller = get_caller_address();
            let current_owner = self.owner.read();
            assert(caller == current_owner, 'Only owner can transfer');
            let old_owner = current_owner;
            self.owner.write(new_owner);
            self.emit(OwnerChanged { old_owner, new_owner });
        }

        fn renounce_ownership(ref self: ContractState) {
            let caller = get_caller_address();
            let current_owner = self.owner.read();
            assert(caller == current_owner, 'Only owner can renounce');
            let old_owner = current_owner;
            let new_owner: ContractAddress = 0.try_into().unwrap();
            self.owner.write(new_owner);
            self.emit(OwnerChanged { old_owner, new_owner });
        }
    }
}
