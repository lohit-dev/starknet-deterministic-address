pub mod events;
pub mod sn_domain;
pub mod struct_hash;
use starknet::ContractAddress;
use crate::htlc::HTLC::Order;

#[starknet::interface]
pub trait IHTLC<TContractState> {
    fn token(self: @TContractState) -> ContractAddress;

    fn get_order(self: @TContractState, order_id: felt252) -> Order;

    fn initiate(
        ref self: TContractState,
        redeemer: ContractAddress,
        timelock: u128,
        amount: u256,
        secret_hash: [u32; 8],
    );

    fn initiate_on_behalf(
        ref self: TContractState,
        initiator: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        amount: u256,
        secret_hash: [u32; 8],
    );

    fn initiate_on_behalf_with_destination_data(
        ref self: TContractState,
        initiator: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        amount: u256,
        secret_hash: [u32; 8],
        destination_data: Array<felt252>,
    );

    fn initiate_with_signature(
        ref self: TContractState,
        initiator: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        amount: u256,
        secret_hash: [u32; 8],
        signature: Array<felt252>,
    );

    fn redeem(ref self: TContractState, order_id: felt252, secret: Array<u32>);

    fn refund(ref self: TContractState, order_id: felt252);

    fn instant_refund(ref self: TContractState, order_id: felt252, signature: Array<felt252>);
}

pub trait IMessageHash<T> {
    fn get_message_hash(self: @T, chain_id: felt252, signer: ContractAddress) -> felt252;
}

pub trait IStructHash<T> {
    fn get_struct_hash(self: @T) -> felt252;
}


#[starknet::interface]
pub trait IUniqueDepositAddress<TContractState> {
    fn initialize(
        ref self: TContractState,
        htlc_address: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        secret_hash: [u32; 8],
        amount: u256,
        destination_data: Span<felt252>,
    );

    fn recover_token(ref self: TContractState, token: ContractAddress);
    fn recover_stark(ref self: TContractState); // not sure if this is needed
}


#[starknet::interface]
pub trait IRegistry<TContractState> {
    fn create_erc20_swap_address(
        ref self: TContractState,
        token: ContractAddress,
        refund_address: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        secret_hash: [u32; 8],
        amount: u256,
        destination_data: Span<felt252>,
    ) -> ContractAddress;

    fn create_native_swap_address(
        ref self: TContractState,
        refund_address: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        secret_hash: [u32; 8],
        amount: u256,
        destination_data: Span<felt252>,
    ) -> ContractAddress;

    fn get_erc20_address(
        self: @TContractState,
        token: ContractAddress,
        refund_address: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        secret_hash: [u32; 8],
        amount: u256,
        destination_data: Span<felt252>,
    ) -> ContractAddress;

    fn get_native_address(
        self: @TContractState,
        refund_address: ContractAddress,
        redeemer: ContractAddress,
        timelock: u128,
        secret_hash: [u32; 8],
        amount: u256,
        destination_data: Span<felt252>,
    ) -> ContractAddress;

    // HTLC Management
    fn add_htlc(ref self: TContractState, htlc: ContractAddress, token: ContractAddress);
    fn add_native_htlc(ref self: TContractState, htlc: ContractAddress);

    // Implementation Management
    fn set_impl_uda(ref self: TContractState, impl_address: ContractAddress);
    fn set_impl_native_uda(ref self: TContractState, impl_address: ContractAddress);

    // Getters
    fn get_htlc_for_token(self: @TContractState, token: ContractAddress) -> ContractAddress;
    fn get_native_htlc(self: @TContractState) -> ContractAddress;
    fn get_impl_uda(self: @TContractState) -> ContractAddress;
    fn get_impl_native_uda(self: @TContractState) -> ContractAddress;
    fn get_owner(self: @TContractState) -> ContractAddress;
}

