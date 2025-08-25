use core::num::traits::Zero;
use starknet::class_hash::ClassHash;
use starknet::contract_address::ContractAddress;
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};

#[starknet::contract]
mod registry {
    use core::array::ArrayTrait;
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use core::traits::Into;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::event::EventEmitter;
    use starknet::get_contract_address;
    use starknet::syscalls::deploy_syscall;
    use crate::interface::{
        IRegistry, IUniqueDepositAddressDispatcher, IUniqueDepositAddressDispatcherTrait,
    };
    use super::*;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    const CONTRACT_ADDRESS_PREFIX: felt252 = 'STARKNET_CONTRACT_ADDRESS';

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        htlcs: Map<ContractAddress, ContractAddress>, // token -> htlc mapping
        native_htlc: ContractAddress,
        impl_uda: ContractAddress,
        impl_native_uda: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        HTLCAdded: HTLCAdded,
        NativeHTLCAdded: NativeHTLCAdded,
        UDACreated: UDACreated,
        NativeUDACreated: NativeUDACreated,
        UDAImplUpdated: UDAImplUpdated,
        NativeUDAImplUpdated: NativeUDAImplUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct HTLCAdded {
        #[key]
        htlc: ContractAddress,
        #[key]
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NativeHTLCAdded {
        #[key]
        native_htlc: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UDACreated {
        #[key]
        address_uda: ContractAddress,
        #[key]
        refund_address: ContractAddress,
        #[key]
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NativeUDACreated {
        #[key]
        address_native_uda: ContractAddress,
        #[key]
        refund_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UDAImplUpdated {
        #[key]
        impl_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NativeUDAImplUpdated {
        #[key]
        impl_address: ContractAddress,
    }

    pub mod Error {
        pub const INVALID_ADDRESS_PARAMETERS: felt252 = 'Invalid address parameters';
        pub const ZERO_TIMELOCK: felt252 = 'Zero timelock';
        pub const ZERO_AMOUNT: felt252 = 'Zero amount';
        pub const HTLC_ALREADY_EXISTS: felt252 = 'HTLC already exists for token';
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const INSUFFICIENT_FUNDS: felt252 = 'Insufficient funds deposited';
        pub const NO_HTLC_FOR_TOKEN: felt252 = 'No HTLC found for this token';
        pub const NO_NATIVE_HTLC: felt252 = 'No native HTLC found';
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn create_erc20_swap_address(
            ref self: ContractState,
            token: ContractAddress,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            self._validate_params(refund_address, redeemer, timelock, amount);

            let htlc = self.htlcs.read(token);
            assert(!htlc.is_zero(), Error::NO_HTLC_FOR_TOKEN);

            // Check if sufficient funds are deposited
            let predicted_address = self
                ._compute_erc20_address(
                    token,
                    refund_address,
                    redeemer,
                    timelock,
                    secret_hash,
                    amount,
                    destination_data,
                );

            let erc20 = IERC20Dispatcher { contract_address: token };
            let balance = erc20.balance_of(predicted_address);
            assert(balance >= amount, Error::INSUFFICIENT_FUNDS);

            // Deploy UDA if not already deployed
            let deployed_address = self
                ._deploy_uda_if_needed(
                    htlc,
                    refund_address,
                    redeemer,
                    timelock,
                    secret_hash,
                    amount,
                    destination_data,
                    false,
                );

            self.emit(UDACreated { address_uda: deployed_address, refund_address, token });

            deployed_address
        }

        fn create_native_swap_address(
            ref self: ContractState,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            self._validate_params(refund_address, redeemer, timelock, amount);

            let native_htlc = self.native_htlc.read();
            assert(!native_htlc.is_zero(), Error::NO_NATIVE_HTLC);

            // balance check
            let _predicted_address = self
                ._compute_native_address(
                    refund_address, redeemer, timelock, secret_hash, amount, destination_data,
                );

            let deployed_address = self
                ._deploy_native_uda_if_needed(
                    native_htlc,
                    refund_address,
                    redeemer,
                    timelock,
                    secret_hash,
                    amount,
                    destination_data,
                );

            self.emit(NativeUDACreated { address_native_uda: deployed_address, refund_address });

            deployed_address
        }

        fn get_erc20_address(
            self: @ContractState,
            token: ContractAddress,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            self._validate_params(refund_address, redeemer, timelock, amount);

            let htlc = self.htlcs.read(token);
            assert(!htlc.is_zero(), Error::NO_HTLC_FOR_TOKEN);

            self
                ._compute_erc20_address(
                    token,
                    refund_address,
                    redeemer,
                    timelock,
                    secret_hash,
                    amount,
                    destination_data,
                )
        }

        fn get_native_address(
            self: @ContractState,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            self._validate_params(refund_address, redeemer, timelock, amount);

            let native_htlc = self.native_htlc.read();
            assert(!native_htlc.is_zero(), Error::NO_NATIVE_HTLC);

            self
                ._compute_native_address(
                    refund_address, redeemer, timelock, secret_hash, amount, destination_data,
                )
        }

        fn add_htlc(ref self: ContractState, htlc: ContractAddress, token: ContractAddress) {
            self.ownable.assert_only_owner();
            self._validate_contract_address(htlc);

            self.htlcs.write(token, htlc);
            self.emit(HTLCAdded { htlc, token });
        }

        fn add_native_htlc(ref self: ContractState, htlc: ContractAddress) {
            self.ownable.assert_only_owner();
            self._validate_contract_address(htlc);

            self.native_htlc.write(htlc);
            self.emit(NativeHTLCAdded { native_htlc: htlc });
        }

        fn set_impl_uda(ref self: ContractState, impl_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self._validate_contract_address(impl_address);

            self.impl_uda.write(impl_address);
            self.emit(UDAImplUpdated { impl_address });
        }

        fn set_impl_native_uda(ref self: ContractState, impl_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self._validate_contract_address(impl_address);

            self.impl_native_uda.write(impl_address);
            self.emit(NativeUDAImplUpdated { impl_address });
        }

        fn get_htlc_for_token(self: @ContractState, token: ContractAddress) -> ContractAddress {
            self.htlcs.read(token)
        }

        fn get_native_htlc(self: @ContractState) -> ContractAddress {
            self.native_htlc.read()
        }

        fn get_impl_uda(self: @ContractState) -> ContractAddress {
            self.impl_uda.read()
        }

        fn get_impl_native_uda(self: @ContractState) -> ContractAddress {
            self.impl_native_uda.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _validate_params(
            self: @ContractState,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            amount: u256,
        ) {
            assert(
                !redeemer.is_zero() && !refund_address.is_zero() && redeemer != refund_address,
                Error::INVALID_ADDRESS_PARAMETERS,
            );
            assert(timelock > 0, Error::ZERO_TIMELOCK);
            assert(amount > 0, Error::ZERO_AMOUNT);
        }

        fn _validate_contract_address(self: @ContractState, address: ContractAddress) {
            assert(!address.is_zero(), Error::INVALID_ADDRESS);
        }

        fn _compute_erc20_address(
            self: @ContractState,
            token: ContractAddress,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            let htlc = self.htlcs.read(token);
            let salt = self
                ._compute_salt(
                    refund_address, redeemer, timelock, secret_hash, amount, destination_data,
                );

            self._compute_address_from_salt(htlc, refund_address, salt, self.impl_uda.read())
        }

        fn _compute_native_address(
            self: @ContractState,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            let native_htlc = self.native_htlc.read();
            let salt = self
                ._compute_salt(
                    refund_address, redeemer, timelock, secret_hash, amount, destination_data,
                );

            self
                ._compute_address_from_salt(
                    native_htlc, refund_address, salt, self.impl_native_uda.read(),
                )
        }

        fn _compute_salt(
            self: @ContractState,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> felt252 {
            let mut hasher = PedersenTrait::new(0);
            hasher = hasher.update(refund_address.into());
            hasher = hasher.update(redeemer.into());
            hasher = hasher.update(timelock.into());

            // Hash each thing in secret hash until 8 parts [u32; 8] 0 to 7
            for hash_part in secret_hash.span() {
                let hash_int: u32 = *hash_part;
                hasher = hasher.update(hash_int.into());
            }

            hasher = hasher.update(amount.low.into());
            hasher = hasher.update(amount.high.into());

            for data in destination_data {
                hasher = hasher.update(*data);
            }

            hasher.finalize()
        }

        fn _compute_address_from_salt(
            self: @ContractState,
            htlc: ContractAddress,
            owner: ContractAddress,
            salt: felt252,
            class_hash: ContractAddress,
        ) -> ContractAddress {
            let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
            constructor_calldata.append(owner.into());

            let constructor_calldata_hash = PedersenTrait::new(0)
                .update(*constructor_calldata.span().at(0))
                .update(1)
                .finalize();

            let contract_address_hash = PedersenTrait::new(0)
                .update(CONTRACT_ADDRESS_PREFIX)
                .update(get_contract_address().into()) // deployer address
                .update(salt)
                .update(class_hash.into())
                .update(constructor_calldata_hash)
                .update(5)
                .finalize();

            contract_address_hash.try_into().unwrap()
        }

        fn _deploy_uda_if_needed(
            ref self: ContractState,
            htlc: ContractAddress,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
            is_native: bool,
        ) -> ContractAddress {
            let salt = self
                ._compute_salt(
                    refund_address, redeemer, timelock, secret_hash, amount, destination_data,
                );

            let class_hash: ClassHash = if is_native {
                // converting contract address to felt
                let addr_felt: felt252 = self.impl_native_uda.read().into();
                // converting felt to class hash
                addr_felt.try_into().unwrap()
            } else {
                // converting contract address to felt
                let addr_felt: felt252 = self.impl_uda.read().into();
                // converting felt to class hash
                addr_felt.try_into().unwrap()
            };

            let predicted_address = self
                ._compute_address_from_salt(
                    htlc,
                    refund_address,
                    salt,
                    if is_native {
                        self.impl_native_uda.read()
                    } else {
                        self.impl_uda.read()
                    },
                );

            // Try to deploy - if contract already exists, this will fail gracefully
            let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
            constructor_calldata.append(refund_address.try_into().unwrap());

            match deploy_syscall(class_hash, salt, constructor_calldata.span(), false) {
                Result::Ok((
                    deployed_address, _,
                )) => {
                    // Deploy done
                    let uda = IUniqueDepositAddressDispatcher {
                        contract_address: deployed_address,
                    };
                    uda.initialize(htlc, redeemer, timelock, secret_hash, amount, destination_data);
                    deployed_address
                },
                Result::Err(_) => {
                    // Deploy failed, likely because contract already exists
                    // Return the predicted address
                    predicted_address
                },
            }
        }

        fn _deploy_native_uda_if_needed(
            ref self: ContractState,
            native_htlc: ContractAddress,
            refund_address: ContractAddress,
            redeemer: ContractAddress,
            timelock: u128,
            secret_hash: [u32; 8],
            amount: u256,
            destination_data: Span<felt252>,
        ) -> ContractAddress {
            self
                ._deploy_uda_if_needed(
                    native_htlc,
                    refund_address,
                    redeemer,
                    timelock,
                    secret_hash,
                    amount,
                    destination_data,
                    true,
                )
        }
    }
}
