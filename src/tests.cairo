use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use starknet::ClassHash;
use starknet::eth_address::EthAddress;
use crate::registry::{IRegistryDispatcher, IRegistryDispatcherTrait};

const ADMIN: ContractAddress = 0x1111.try_into().unwrap();


fn deploy_contract(name: ByteArray, calldata: @Array<felt252>) -> (ContractAddress, ClassHash) {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(calldata).unwrap();
    (contract_address, *contract.class_hash)
}


fn setup() -> (IRegistryDispatcher, ClassHash) {
    let (registry_address, registry_class_hash) = deploy_contract("registry", @array![]);
    let (uda_address, uda_class_hash) = deploy_contract("uda", @array!['peper']);
    let registry_disp = IRegistryDispatcher { contract_address: registry_address };

    (registry_disp, uda_class_hash)
}

#[test]
fn test__deploy() {
    let (registry_disp, uda_class_hash) = setup();
}

const OWNER: ContractAddress = 0x123.try_into().unwrap();

#[test]
fn test__addresses() {
    let (registry_disp, uda_class_hash) = setup();
        

    let addr0 = registry_disp.create_address('NAME', OWNER, uda_class_hash);
    let addr1 = registry_disp.get_address('NAME', OWNER, uda_class_hash, registry_disp.contract_address);

    println!("0x{:x}", addr0);
    println!("0x{:x}", addr1);

    assert!(addr0 == addr1, "not matching")
}
