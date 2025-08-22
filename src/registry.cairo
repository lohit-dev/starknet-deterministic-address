use starknet::class_hash::ClassHash;
use starknet::contract_address::ContractAddress;
#[starknet::interface]
pub trait IRegistry<TContractState> {
    fn create_address(
        ref self: TContractState, name: felt252, owner: ContractAddress, class_hash: ClassHash,
    ) -> ContractAddress;

    fn get_address(
        self: @TContractState,
        name: felt252,
        owner: ContractAddress,
        class_hash: ClassHash,
        deployer_address: ContractAddress,
    ) -> ContractAddress;
}

#[starknet::contract]
mod registry {
    use core::array::ArrayTrait;
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use core::traits::Into;
    use starknet::SyscallResultTrait;
    use starknet::syscalls::deploy_syscall;
    use super::*;

    const CONTRACT_ADDRESS_PREFIX: felt252 = 'STARKNET_CONTRACT_ADDRESS';


    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UdaDeployed: UdaDeployed,
    }

    #[derive(Drop, starknet::Event)]
    struct UdaDeployed {
        #[key]
        name: felt252,
        #[key]
        owner: ContractAddress,
        #[key]
        class_hash: ClassHash,
        deployed_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn create_address(
            ref self: ContractState, name: felt252, owner: ContractAddress, class_hash: ClassHash,
        ) -> ContractAddress {
            let salt = PedersenTrait::new(0).update(name).update(owner.into()).finalize();

            let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
            constructor_calldata.append(owner.into());

            let (deployed_address, _) = deploy_syscall(
                class_hash, salt, constructor_calldata.span(), false,
            )
                .unwrap_syscall();

            self.emit(UdaDeployed { name, owner, class_hash, deployed_address });

            deployed_address
        }

        fn get_address(
            self: @ContractState,
            name: felt252,
            owner: ContractAddress,
            class_hash: ClassHash,
            deployer_address: ContractAddress,
        ) -> ContractAddress {
            let salt = PedersenTrait::new(0).update(name).update(owner.into()).finalize();

            let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
            constructor_calldata.append(owner.into());

            let constructor_calldata_hash = PedersenTrait::new(0)
                .update(*constructor_calldata.span().at(0))
                .update(1)
                .finalize();

            let contract_address_hash = PedersenTrait::new(0)
                .update(CONTRACT_ADDRESS_PREFIX)
                .update(deployer_address.into())
                .update(salt)
                .update(class_hash.into())
                .update(constructor_calldata_hash)
                .update(5)
                .finalize();

            contract_address_hash.try_into().unwrap()
        }
    }
}

#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use core::poseidon::poseidon_hash_span;

    // Test parameters
    const TEST_NAME: felt252 = 'TEST_UDA';
    const TEST_OWNER: felt252 = 123;
    const TEST_CLASS_HASH: felt252 = 456;

    // Constants needed for testing
    const TEST_CONTRACT_ADDRESS_PREFIX: felt252 = 'STARKNET_CONTRACT_ADDRESS';

    #[test]
    // #[available_gas(2000000000)]
    fn test_salt_calculation() {
        // Test that the salt calculation is deterministic
        let salt1 = PedersenTrait::new(0).update(TEST_NAME).update(TEST_OWNER).finalize();
        let salt2 = PedersenTrait::new(0).update(TEST_NAME).update(TEST_OWNER).finalize();

        // Same inputs should produce same salt
        assert(salt1 == salt2, 'this salt is bad');

        // Different inputs should produce different salts
        let salt3 = PedersenTrait::new(0).update(TEST_NAME).update(789).finalize();
        assert(salt1 != salt3, 'salt same bro...');
    }

    #[test]
    // #[available_gas(2000000000)]
    fn test_calldata_hash_calculation() {
        // Test that the calldata hash calculation is deterministic
        let mut calldata1: Array<felt252> = ArrayTrait::new();
        calldata1.append(TEST_OWNER);

        let mut calldata2: Array<felt252> = ArrayTrait::new();
        calldata2.append(TEST_OWNER);

        // Same calldata should produce same hash
        let hash1 = poseidon_hash_span(calldata1.span());
        let hash2 = poseidon_hash_span(calldata2.span());

        assert(hash1 == hash2, 'hash wrong bro...');
    }

    #[test]
    // #[available_gas(2000000000)]
    fn test_address_calculation_components() {
        // Test individual components of the address calculation
        let salt = PedersenTrait::new(0).update(TEST_NAME).update(TEST_OWNER).finalize();
        let mut calldata: Array<felt252> = ArrayTrait::new();
        calldata.append(TEST_OWNER);
        let calldata_hash = poseidon_hash_span(calldata.span());

        // Test that all components are non-zero
        assert(salt != 0, 'Salt is zero');
        assert(calldata_hash != 0, 'Calldata hash is zero');
        assert(TEST_CLASS_HASH != 0, 'Class hash is zero');

        // Test that the final address calculation produces a non-zero result
        let deployer_address: felt252 = 123; // Test deployer address

        let contract_address_hash = PedersenTrait::new(TEST_CONTRACT_ADDRESS_PREFIX)
            .update(deployer_address)
            .update(salt)
            .update(TEST_CLASS_HASH)
            .update(calldata_hash)
            .finalize();

        assert(contract_address_hash != 0, 'Final address hash is zero');
    }
}

