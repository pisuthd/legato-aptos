

module legato_addr::vault {

    use std::signer; 
    use std::option;
    use aptos_framework::timestamp;
    use std::string::{Self, String, utf8};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::delegation_pool as dp;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability}; 
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::type_info;   
    use legato_addr::epoch;

    // ======== Constants ========

    const MIN_APT_TO_STAKE: u64 = 100000000;

    // ======== Errors ========

    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_MATURITY: u64 = 2;
    const E_VAULT_EXISTS: u64 = 3;
    const E_VAULT_MATURED: u64 = 4;
    const E_MIN_THRESHOLD: u64 = 5;
    const E_INVALID_VAULT: u64 = 6;
    const E_FULL_VALIDATOR: u64 = 7;
    const E_INSUFFICIENT_APT_LOCKED: u64 = 8;
    const E_VAULT_NOT_MATURED: u64 = 9;

    // ======== Structs =========

    // represent the future value at maturity date
    struct PT_TOKEN<phantom P> has drop {}

    struct PoolReserve<phantom P> has key {
        pt_locked: Coin<PT_TOKEN<P>>,
        pt_mint: MintCapability<PT_TOKEN<P>>,
        pt_burn: BurnCapability<PT_TOKEN<P>>,
        apt_locked: u64,
        pending_withdrawal: u64,
        vault_apy: u64,
        unlock_time_secs: u64,
        debt_balance: u64
    }

    struct Config has key { 
        /// Whitelist of validators
        whitelist: SmartVector<address>,
        extend_ref: ExtendRef
    }


    // constructor
    fun init_module(sender: &signer) {

        let constructor_ref = object::create_object(signer::address_of(sender));
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        move_to(sender, Config { whitelist: smart_vector::new(), extend_ref});
    }
    
    // ======== Public Functions =========

    // locks APT in the timelock vault and mints PT equivalent to the value at the maturity date
    public entry fun mint<P>(sender: &signer, validator_address: address, input_amount: u64) acquires PoolReserve, Config {
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);
        assert!(coin::balance<AptosCoin>(signer::address_of(sender)) >= MIN_APT_TO_STAKE, E_MIN_THRESHOLD);
        assert!(is_whitelisted(validator_address), E_INVALID_VAULT);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 

        assert!(reserve.unlock_time_secs > timestamp::now_seconds() , E_VAULT_MATURED); 

        let config = borrow_global_mut<Config>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        
        // send to object 
        let input_coin = coin::withdraw<AptosCoin>(sender, input_amount);
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&config_object_signer))) {
            coin::register<AptosCoin>(&config_object_signer);
        };
        coin::deposit(signer::address_of(&config_object_signer), input_coin);

        // stake APT for the given amount in the delegation pool
        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::add_stake(&config_object_signer, pool_address, input_amount);

        // calculate PT to send out
        let debt_amount = calculate_pt_debt(reserve.vault_apy, timestamp::now_seconds(), reserve.unlock_time_secs, input_amount);

        // Mint PT tokens and deposit into the sender's account
        let pt_coin = coin::mint<PT_TOKEN<P>>(input_amount+debt_amount, &reserve.pt_mint); 
        if (!coin::is_account_registered<PT_TOKEN<P>>(signer::address_of(sender))) {
            coin::register<PT_TOKEN<P>>(sender);
        };
        coin::deposit(signer::address_of(sender), pt_coin);

        reserve.debt_balance = reserve.debt_balance+debt_amount;
        reserve.apt_locked = reserve.apt_locked+input_amount;
    }

    // redeem when the vault reaches its maturity date
    public entry fun redeem<P>(sender: &signer, validator_address: address,  amount: u64) acquires PoolReserve, Config {
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);
        assert!(is_whitelisted(validator_address), E_INVALID_VAULT);

        let config = borrow_global_mut<Config>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 
        assert!(timestamp::now_seconds() > reserve.unlock_time_secs, E_VAULT_NOT_MATURED);
        assert!(reserve.pending_withdrawal >= amount, E_INSUFFICIENT_APT_LOCKED);

        // Withdraw PT tokens from the sender's account
        let pt_coin = coin::withdraw<PT_TOKEN<P>>(sender, amount);
        coin::burn(pt_coin, &reserve.pt_burn);
        
        // withdraw from dp
        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::withdraw(&config_object_signer, pool_address, amount);

        let apt_coin = coin::withdraw<AptosCoin>(&config_object_signer, amount-100);
        coin::deposit(signer::address_of(sender), apt_coin);

        reserve.pending_withdrawal = reserve.pending_withdrawal-amount;
    }

    #[view]
    // get PT balance from the given account
    public fun get_pt_balance<P>(account: address): u64 {
        coin::balance<PT_TOKEN<P>>(account)
    }

    #[view]
    public fun get_config_object_address() : address  acquires Config  {
        let config = borrow_global_mut<Config>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        signer::address_of(&config_object_signer)
    }

    // ======== Only Governance =========

    // creates a timelock vault 
    public entry fun new_vault<P>(
        sender: &signer,
        vault_apy: u64, 
        unlock_time_secs: u64
    )  {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        // Maturity date should not be passed
        assert!(unlock_time_secs > timestamp::now_seconds()+epoch::duration(), E_INVALID_MATURITY);
        // Check if the vault already exists 
        assert!(!vault_exist<P>(@legato_addr), E_VAULT_EXISTS);

        // let config = borrow_global_mut<Config>(@legato_addr);
        // let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);

        // FIXME: generate symbol name from type
        // let token_symbol = type_info::type_name<P>();
        // let index = string::index_of(&token_symbol, &utf8(b"vault_maturity_dates::"));

        // string::sub_string(&token_symbol, index, string::length(&token_symbol));
        let symbol = string::utf8(b"PT-TOKEN");

        // Initialize vault token 
        let (pt_burn, lp_freeze, pt_mint) = coin::initialize<PT_TOKEN<P>>(
            sender,
            symbol,
            symbol,
            8, // Number of decimal places
            true, // token is fungible
        );

        coin::destroy_freeze_cap(lp_freeze);

        move_to(
            sender,
            PoolReserve<P> {
                pt_locked: coin::zero<PT_TOKEN<P>>(),
                pt_mint,
                pt_burn,
                apt_locked: 0,
                pending_withdrawal: 0,
                vault_apy,
                unlock_time_secs,
                debt_balance: 0
            },
        );

    }

    // add validator
    public entry fun add_whitelist_validator(sender: &signer, validator_address: address) acquires Config {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        let config = borrow_global_mut<Config>(@legato_addr);
        assert!( smart_vector::length(&config.whitelist) == 0 , E_FULL_VALIDATOR); // only 1 validator allowed
        smart_vector::push_back(&mut config.whitelist, validator_address);
    }

    // admin should trigger unlock all APT staked
    public entry fun unlock<P>(sender: &signer, validator_address: address) acquires PoolReserve, Config {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);
        assert!(is_whitelisted(validator_address), E_INVALID_VAULT);
        
        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 
        assert!(timestamp::now_seconds() > reserve.unlock_time_secs, E_VAULT_NOT_MATURED);
        assert!( reserve.apt_locked >= MIN_APT_TO_STAKE, E_INSUFFICIENT_APT_LOCKED );

        let config = borrow_global_mut<Config>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);

        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::unlock(&config_object_signer, pool_address, reserve.apt_locked);

        reserve.pending_withdrawal = reserve.pending_withdrawal+reserve.apt_locked;
        reserve.apt_locked = 0;
    }

    // ======== Internal Functions =========

    /// Returns the signer of the global config object
    fun global_config_signer(): signer acquires Config {
        let global_config = borrow_global<Config>(@legato_addr);
        object::generate_signer_for_extending(&global_config.extend_ref)
    }

    fun vault_exist<P>(addr: address): bool {
        exists<PoolReserve<P>>(addr)
    }

    fun calculate_pt_debt(vault_apy: u64, from_timestamp: u64, to_timestamp: u64, amount: u64) : u64 {
        let for_epoch = epoch::to_epoch(to_timestamp)-epoch::to_epoch(from_timestamp);
        let (for_epoch, vault_apy, amount) = ((for_epoch as u128), (vault_apy as u128), (amount as u128));
        let result = (for_epoch*vault_apy*amount) / (36500000000);
        (result as u64)
    }

    inline fun is_whitelisted(validator_address: address): bool {
        let whitelist = &borrow_global<Config>(@legato_addr).whitelist;
        smart_vector::contains(whitelist, &validator_address)
    }

    #[test_only]
    /// So we can call this from `veiled_coin_tests.move`.
    public fun init_module_for_testing(deployer: &signer) {
        init_module(deployer)
    }

}