

module legato_addr::vault {

    // use std::debug::print;

    use std::signer; 
    use std::string::{Self, String};
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::delegation_pool as dp;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability}; 
    // use aptos_std::type_info;
    use aptos_std::table::{Self, Table};
    use legato_addr::epoch;

    // ======== Constants ========

    const MIN_APT_TO_STAKE: u64 = 100000000;

    // ======== Errors ========

    const E_VAULT_EXISTS: u64 = 1;
    const E_INVALID_MATURITY: u64 = 2;
    const E_INVALID_VAULT: u64 = 3;
    const E_VAULT_MATURED: u64 = 4;
    const E_MIN_THRESHOLD: u64 = 5;
    const E_UNAUTHORIZED: u64 = 6;
    const E_INSUFFICIENT_AMOUNT: u64 = 7;
    const E_VAULT_NOT_MATURED: u64 = 8;
    const E_INVALID_STAKER: u64 = 9;

    // ======== Structs =========

    // represent the future value at maturity date
    struct PT_TOKEN<phantom P> has drop {}

    struct PoolReserve<phantom P> has key {
        pt_locked: Coin<PT_TOKEN<P>>,
        pt_mint: MintCapability<PT_TOKEN<P>>,
        pt_burn: BurnCapability<PT_TOKEN<P>>,
        apt_locked: Coin<AptosCoin>,
        vault_apy: u64,
        unlock_time_secs: u64,
        debt_balance: u64,
        pending_unlock: Table<address, u64>,
        pending_withdraw: Table<address, u64>
    }

    // ======== Public Functions =========

     #[view]
    // get PT balance from the given account
    public fun get_pt_balance<P>(account: address): u64 {
        coin::balance<PT_TOKEN<P>>(account)
    }

    // locks APT in the timelock vault and mints PT equivalent to the value at the maturity date
    public entry fun mint<P>(sender: &signer, input_amount: u64) acquires PoolReserve {
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);
        assert!(coin::balance<AptosCoin>(signer::address_of(sender)) >= MIN_APT_TO_STAKE, E_MIN_THRESHOLD);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 

        assert!(reserve.unlock_time_secs > timestamp::now_seconds() , E_VAULT_MATURED); 
        
        // // stake APT for the given amount in the delegation pool
        // let pool_address = dp::get_owned_pool_address(validator_address);
        // dp::add_stake(sender, pool_address, input_amount);

        let input_coin = coin::withdraw<AptosCoin>(sender, input_amount);
        // send to deployer
        coin::merge(&mut reserve.apt_locked, input_coin);

        // calculate PT to send out
        let debt_amount = calculate_pt_debt(reserve.vault_apy, timestamp::now_seconds(), reserve.unlock_time_secs, input_amount);

        // Mint PT tokens and deposit into the sender's account
        let pt_coin = coin::mint<PT_TOKEN<P>>(input_amount+debt_amount, &reserve.pt_mint); 
        if (!coin::is_account_registered<PT_TOKEN<P>>(signer::address_of(sender))) {
            coin::register<PT_TOKEN<P>>(sender);
        };
        coin::deposit(signer::address_of(sender), pt_coin);

        reserve.debt_balance = reserve.debt_balance+debt_amount;
    }

    // redeem when the vault reaches its maturity date
    public entry fun redeem<P>(sender: &signer, amount: u64) acquires PoolReserve {
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 

        assert!(timestamp::now_seconds() > reserve.unlock_time_secs, E_VAULT_NOT_MATURED);

        // Withdraw PT tokens from the sender's account
        let pt_coin = coin::withdraw<PT_TOKEN<P>>(sender, amount);
        coin::burn(pt_coin, &reserve.pt_burn);

        // let pool_address = dp::get_owned_pool_address(validator_address);
        // dp::withdraw(validator, pool_address, 50 * ONE_APT);

        if (!table::contains(&reserve.pending_unlock, signer::address_of(sender))) {
            table::add(&mut reserve.pending_unlock, signer::address_of(sender), amount);
        } else { 
            let old_amount = *table::borrow(&reserve.pending_unlock, signer::address_of(sender));
            *table::borrow_mut(&mut reserve.pending_unlock, signer::address_of(sender)) = old_amount+amount;
        };

    }

    
    
    public fun vault_exist<P>(addr: address): bool {
        exists<PoolReserve<P>>(addr)
    }

    public fun calculate_pt_debt(vault_apy: u64, from_timestamp: u64, to_timestamp: u64, amount: u64) : u64 {
        let for_epoch = epoch::to_epoch(to_timestamp)-epoch::to_epoch(from_timestamp);
        let (for_epoch, vault_apy, amount) = ((for_epoch as u128), (vault_apy as u128), (amount as u128));
        let result = (for_epoch*vault_apy*amount) / (36500000000);
        (result as u64)
    }

    // ======== Only Governance =========

    // creates a timelock vault that returns APT at the vault's fixed rate after the maturity date
    public entry fun new_vault<P>(sender: &signer, vault_apy: u64, unlock_time_secs: u64) {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        // Maturity date should not be passed
        assert!(unlock_time_secs > timestamp::now_seconds()+epoch::duration(), E_INVALID_MATURITY);
        // Check if the vault already exists 
        assert!(!vault_exist<P>(@legato_addr), E_VAULT_EXISTS);

        // FIXME: generate symbol name from type
        // let symbol = type_info::type_name<P>();
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
                apt_locked: coin::zero<AptosCoin>(),
                vault_apy,
                unlock_time_secs,
                debt_balance: 0,
                pending_unlock: table::new<address, u64>(),
                pending_withdraw:  table::new<address, u64>()
            },
        );

    }

    // manually perform staking for the hackathon, considering using the object the next
    public entry fun internal_process_staking<P>(sender: &signer, validator_address: address) acquires PoolReserve {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);
        
        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 
        let coin_in_reserve = coin::value(&reserve.apt_locked);

        assert!(coin_in_reserve > 0, E_INSUFFICIENT_AMOUNT);

        let coin = coin::extract<AptosCoin>(&mut reserve.apt_locked,coin_in_reserve );

        // Deposit the extracted tokens into the sender's account
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(sender))) {
            coin::register<AptosCoin>(sender);
        };
        coin::deposit(signer::address_of(sender), coin);

        // stake APT from the reserve to the delegation pool
        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::add_stake(sender, pool_address, coin_in_reserve);
    }

    // internal process for unlock
    public entry fun internal_process_unlock<P>(sender: &signer, validator_address: address, staker_address: address) acquires PoolReserve {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 
        assert!(table::contains(&reserve.pending_unlock, staker_address ), E_INVALID_STAKER);

        let unlock_amount = *table::borrow(&reserve.pending_unlock, staker_address);

        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::unlock(sender, pool_address, unlock_amount);

        *table::borrow_mut(&mut reserve.pending_unlock, staker_address) = 0;

        if (!table::contains(&reserve.pending_withdraw, staker_address)) {
            table::add(&mut reserve.pending_withdraw, staker_address, unlock_amount);
        } else { 
            let old_amount = *table::borrow(&reserve.pending_withdraw, staker_address);
            *table::borrow_mut(&mut reserve.pending_withdraw, staker_address ) = old_amount+unlock_amount;
        };
    }

    // internal process for withdraw
    public entry fun internal_process_withdraw<P>(sender: &signer, validator_address: address, staker_address: address) acquires PoolReserve {
        assert!( signer::address_of(sender) == @legato_addr , E_UNAUTHORIZED);
        assert!(exists<PoolReserve<P>>(@legato_addr), E_INVALID_VAULT);

        let reserve = borrow_global_mut<PoolReserve<P>>(@legato_addr); 
        assert!(table::contains(&reserve.pending_withdraw, staker_address ), E_INVALID_STAKER);
    
        let withdraw_amount = *table::borrow(&reserve.pending_withdraw, staker_address );

        let pool_address = dp::get_owned_pool_address(validator_address);
        dp::withdraw(sender, pool_address, withdraw_amount);

        let apt_coin = coin::withdraw<AptosCoin>(sender, withdraw_amount-100);
        coin::deposit(staker_address, apt_coin);

        *table::borrow_mut(&mut reserve.pending_withdraw, staker_address) = 0;
    }

}