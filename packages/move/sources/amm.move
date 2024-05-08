// Copyright (c) Tamago Blockchain Labs, Inc.
// SPDX-License-Identifier: MIT

// Legato AMM DEX facilitates trading vault tokens with settlement tokens like USDT or USDC. 
// It's an extension of OmniBTC's AMM swap, enhancing custom weights with math from Balance V2 Lite.

module legato_addr::amm {
 
    use std::option;
    use std::signer;
    use std::vector; 
    use std::string::{Self, String };  
 
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability}; 
    use aptos_framework::object::{Self, ExtendRef};

    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::math128;
    use aptos_std::comparator::{Self, Result};
    use aptos_std::type_info; 
    use aptos_std::fixed_point64::{Self, FixedPoint64};

    use legato_addr::weighted_math;

    // ======== Constants ========
    
    // Default swap fee of 0.5% in fixed-point
    const DEFAULT_FEE: u128 = 92233720368547758; 
    /// Max u64 value.
    const U64_MAX: u64 = 18446744073709551615;
    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / WEIGHT_SCALE
    const MAX_POOL_VALUE: u64 = { 18446744073709551615 / 10000 };
    /// Minimal liquidity.
    const MINIMAL_LIQUIDITY: u64 = 1000; 

    const WEIGHT_SCALE: u64 = 10000;
    // Minimum APT required to stake.
    const MIN_APT_TO_STAKE: u64 = 100_000_000; // 1 APT
    
    const SYMBOL_PREFIX_LENGTH: u64 = 4;

    // ======== Errors ========

    const ERR_UNAUTHORIZED: u64 = 101;
    const ERR_INVALID_ADDRESS: u64 = 102;
    const ERR_INVALID_FEE: u64 = 103;
    const ERR_MUST_BE_ORDER: u64 = 104;
    const ERR_THE_SAME_COIN: u64 = 105;
    const ERR_NOT_COIN: u64 = 106;
    const ERR_POOL_EXISTS: u64 = 107;
    const ERR_WEIGHTS_SUM: u64 = 108;
    const ERR_INSUFFICIENT_X_AMOUNT: u64 = 109;
    const ERR_INSUFFICIENT_Y_AMOUNT: u64 = 110;
    const ERR_POOL_FULL: u64 = 111;
    const ERR_LP_NOT_ENOUGH: u64 = 112;
    const ERR_OVERLIMIT_X: u64 = 113;
    const ERR_U64_OVERFLOW: u64 = 114;
    const ERR_RESERVES_EMPTY: u64 = 115;
    const ERR_COIN_OUT_NUM_LESS_THAN_EXPECTED_MINIMUM: u64 = 116;

    // ======== Structs =========

    /// The Pool token that will be used to mark the pool share
    /// of a liquidity provider. The parameter `X` and `Y` is for the
    /// coin held in the pool.
    struct LP<phantom X, phantom Y> has drop, store {}

    /// Improved liquidity pool with custom weighting
    struct Pool<phantom X, phantom Y> has key {
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        weight_x: u64, // 50% using 5000
        weight_y: u64, // 50% using 5000
        min_liquidity: Coin<LP<X, Y>>,
        swap_fee: FixedPoint64,
        lp_mint: MintCapability<LP<X, Y>>,
        lp_burn: BurnCapability<LP<X, Y>>
    }

    // Represents the global state of the AMM. 
    struct AMMConfig has key { 
        pool_list: SmartVector<String>, // all pools in the system
        whitelist: SmartVector<address>, // who can setup a new pool
        extend_ref: ExtendRef,
        treasury_address: address // where all fees from all pools will be sent for further LP staking
    }

    // Constructor for this module.
    fun init_module(sender: &signer) {
        
        let constructor_ref = object::create_object(signer::address_of(sender));
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        let whitelist = smart_vector::new();
        smart_vector::push_back(&mut whitelist, signer::address_of(sender));

        move_to(sender, AMMConfig { 
            whitelist , 
            pool_list: smart_vector::new(), 
            extend_ref,
            treasury_address: signer::address_of(sender)
        });
    }

    // ======== Entry Points =========


    // Allows only authorized users to create liquidity with custom weights
    public entry fun register_pool<X, Y>(
        sender: &signer,
        weight_x: u64,
        weight_y: u64
    ) acquires AMMConfig {
        let is_order = is_order<X, Y>();
        assert!(is_order, ERR_MUST_BE_ORDER);
        assert!(coin::is_coin_initialized<X>(), ERR_NOT_COIN);
        assert!(coin::is_coin_initialized<Y>(), ERR_NOT_COIN);

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        // Ensure that the call is on the whitelist
        assert!( smart_vector::contains(&config.whitelist, &(signer::address_of(sender))) , ERR_UNAUTHORIZED);
        // Ensure that the normalized weights sum up to 100%
        assert!( weight_x+weight_y == 10000, ERR_WEIGHTS_SUM); 

        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let (lp_name, lp_symbol) = generate_lp_name_and_symbol<X, Y>();

        let (lp_burn_cap, lp_freeze_cap, lp_mint_cap) = coin::initialize<LP<X, Y>>(sender, lp_name, lp_symbol, 8, true);
        coin::destroy_freeze_cap(lp_freeze_cap);

        // Registers X and Y if not already registered
        if (!coin::is_account_registered<X>(signer::address_of(&config_object_signer))) {
            coin::register<X>(&config_object_signer)
        };

        if (!coin::is_account_registered<Y>(signer::address_of(&config_object_signer))) {
            coin::register<Y>(&config_object_signer)
        };

        let pool = Pool<X, Y> {
            coin_x: coin::zero<X>(),
            coin_y: coin::zero<Y>(), 
            lp_mint: lp_mint_cap,
            lp_burn: lp_burn_cap,
            weight_x,
            weight_y,
            min_liquidity: coin::zero<LP<X,Y>>(),
            swap_fee: fixed_point64::create_from_raw_value( DEFAULT_FEE )
        };
        move_to(&config_object_signer, pool);

        smart_vector::push_back(&mut config.pool_list, lp_symbol);

        // TODO: emit event

    }

    /// Entrypoint for the `add_liquidity` method.
    /// Sends `LP<X,Y>` to the transaction sender.
    public entry fun add_liquidity<X, Y>(
        lp_provider: &signer, 
        coin_x_amount: u64,
        coin_x_min: u64,
        coin_y_amount: u64,
        coin_y_min: u64
    ) acquires AMMConfig, Pool {
        let is_order = is_order<X, Y>();
        assert!(is_order, ERR_MUST_BE_ORDER);

        assert!(coin::is_coin_initialized<X>(), ERR_NOT_COIN);
        assert!(coin::is_coin_initialized<Y>(), ERR_NOT_COIN);

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);

        let (optimal_x, optimal_y) = calc_optimal_coin_values<X, Y>(
            coin_x_amount,
            coin_y_amount
        );

        let (reserves_x, reserves_y) = get_reserves_size<X, Y>();
        
        assert!(optimal_x >= coin_x_min, ERR_INSUFFICIENT_X_AMOUNT);
        assert!(optimal_y >= coin_y_min, ERR_INSUFFICIENT_Y_AMOUNT);

        let coin_x_opt = coin::withdraw<X>(lp_provider, optimal_x);
        let coin_y_opt = coin::withdraw<Y>(lp_provider, optimal_y);

        let lp_coins = mint_lp<X, Y>(
            lp_provider, 
            coin_x_opt,
            coin_y_opt,
            optimal_x,
            optimal_y,
            reserves_x,
            reserves_y
        );

        let lp_provider_address = signer::address_of(lp_provider);
        if (!coin::is_account_registered<LP<X, Y>>(lp_provider_address)) {
            coin::register<LP<X, Y>>(lp_provider);
        };
        coin::deposit(lp_provider_address, lp_coins);

        // TODO: emit event
    }

    /// Entrypoint for the `remove_liquidity` method.
    /// Transfers Coin<X> and Coin<Y> to the sender.
    public entry fun remove_liquidity<X, Y>( 
        lp_provider: &signer, 
        lp_amount: u64
    ) acquires AMMConfig, Pool {
        let is_order = is_order<X, Y>();
        assert!(is_order, ERR_MUST_BE_ORDER);

        assert!(coin::is_coin_initialized<LP<X,Y>>(), ERR_NOT_COIN);

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);
        
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);
        assert!(exists<Pool<X, Y>>(pool_address), ERR_POOL_EXISTS);

        let (reserves_x, reserves_y) = get_reserves_size<X, Y>();
        let lp_coins_total = option::extract(&mut coin::supply<LP<X, Y>>());
        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);

        let (coin_x_out, coin_y_out) = weighted_math::compute_withdrawn_coins( 
            lp_amount, 
            (lp_coins_total as u64), 
            reserves_x, 
            reserves_y, 
            pool.weight_x, 
            pool.weight_y
        ); 

        // TODO: complete this


    }

    /// Entry point for the `swap` method.
    /// Sends swapped Coin to the sender.
    public entry fun swap<X, Y>(
        sender: &signer, 
        coin_in: u64,
        coin_out_min: u64
    ) acquires Pool, AMMConfig {
        let is_order = is_order<X, Y>();
        assert!(coin::is_coin_initialized<X>(), ERR_NOT_COIN);
        assert!(coin::is_coin_initialized<Y>(), ERR_NOT_COIN);

        if (is_order) {
            let (reserve_x, reserve_y) = get_reserves_size<X, Y>();

            swap_out_y<X, Y>(sender, coin_in, coin_out_min, reserve_x, reserve_y);
        } else {
            let (reserve_y, reserve_x) = get_reserves_size<Y, X>();

            swap_out_x<Y, X>(sender, coin_in, coin_out_min, reserve_x, reserve_y);
        };

    }


    // ======== Public Functions =========
    
    /// Generate LP coin name and symbol for pair `X`/`Y`.
    /// ```
    /// name = "LP-" + symbol<X>() + "-" + symbol<Y>();
    /// symbol = symbol<X>()[0:4] + "-" + symbol<Y>()[0:4];
    /// ```
    /// For example, for `LP<BTC, USDT>`,
    /// the result will be `(b"LP-BTC-USDT", b"BTC-USDT")`
    public fun generate_lp_name_and_symbol<X, Y>(): (String, String) {
        let lp_name = string::utf8(b"");
        string::append_utf8(&mut lp_name, b"LP-");
        string::append(&mut lp_name, coin::symbol<X>());
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, coin::symbol<Y>());

        let lp_symbol = string::utf8(b"");
        string::append(&mut lp_symbol, coin_symbol_prefix<X>());
        string::append_utf8(&mut lp_symbol, b"-");
        string::append(&mut lp_symbol, coin_symbol_prefix<Y>());

        (lp_name, lp_symbol)
    }

    /// Calculate amounts needed for adding new liquidity for both `X` and `Y`.
    /// * `x_desired` - desired value of coins `X`.
    /// * `y_desired` - desired value of coins `Y`.
    /// Returns both `X` and `Y` coins amounts.
    public fun calc_optimal_coin_values<X, Y>(
        x_desired: u64,
        y_desired: u64
    ): (u64, u64) acquires Pool, AMMConfig   {
        let (reserves_x, reserves_y) = get_reserves_size<X, Y>();

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);
        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);

        if (reserves_x == 0 && reserves_y == 0) {
            return (x_desired, y_desired)
        } else {
            
            let y_returned = weighted_math::compute_optimal_value(x_desired, reserves_x, reserves_y, pool.weight_y);

            if (y_returned <= y_desired) {
                return (x_desired, y_returned)
            } else {
                let x_returned =  weighted_math::compute_optimal_value(y_desired, reserves_y, reserves_x, pool.weight_x);
                assert!(x_returned <= x_desired, ERR_OVERLIMIT_X);
                return (x_returned, y_desired)
            }
        }
    }

    public fun get_reserves_size<X, Y>(): (u64, u64) acquires Pool, AMMConfig {
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);

        assert!(exists<Pool<X, Y>>(pool_address), ERR_POOL_EXISTS);

        let pool = borrow_global<Pool<X, Y>>(pool_address);

        let x_reserve = coin::value(&pool.coin_x);
        let y_reserve = coin::value(&pool.coin_y);

        (x_reserve, y_reserve)
    }

    public fun swap_out_y<X, Y>(
        sender: &signer,
        coin_in_value: u64,
        coin_out_min_value: u64,
        reserve_in: u64,
        reserve_out: u64,
    ) acquires Pool, AMMConfig {

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);
        
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);

        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);

        let (coin_x_after_fees, coin_x_fee) = weighted_math::get_fee_to_treasury( pool.swap_fee , coin_in_value);

        let coin_y_out = weighted_math::get_amount_out(
            coin_x_after_fees,
            reserve_in,
            pool.weight_x,
            reserve_out,
            pool.weight_y
        );
        assert!(
            coin_y_out >= coin_out_min_value,
            ERR_COIN_OUT_NUM_LESS_THAN_EXPECTED_MINIMUM
        );

        let coin_in = coin::withdraw<X>(sender, coin_in_value);
        let fee_in = coin::extract(&mut coin_in, coin_x_fee);

        coin::deposit( config.treasury_address, fee_in);

        coin::merge(&mut pool.coin_x, coin_in);

        let out_swapped = coin::extract(&mut pool.coin_y, coin_y_out);
        coin::deposit(signer::address_of(sender), out_swapped);

        // emit event
    }

    public fun swap_out_x<X, Y>(
        sender: &signer,
        coin_in_value: u64,
        coin_out_min_value: u64,
        reserve_in: u64,
        reserve_out: u64,
    ) acquires Pool, AMMConfig {

        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);
        
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);

        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);

        let (coin_y_after_fees, coin_y_fee) =  weighted_math::get_fee_to_treasury( pool.swap_fee , coin_in_value);

        let coin_x_out = weighted_math::get_amount_out(
            coin_y_after_fees,
            reserve_in,
            pool.weight_y,
            reserve_out,
            pool.weight_x
        );

        assert!(
            coin_x_out >= coin_out_min_value,
            ERR_COIN_OUT_NUM_LESS_THAN_EXPECTED_MINIMUM
        );

        let coin_in = coin::withdraw<Y>(sender, coin_in_value);
        let fee_in = coin::extract(&mut coin_in, coin_y_fee);

        coin::deposit( config.treasury_address, fee_in);

        coin::merge(&mut pool.coin_y, coin_in);

        let out_swapped = coin::extract(&mut pool.coin_x, coin_x_out);
        coin::deposit(signer::address_of(sender), out_swapped);

        // emit event
    }

    #[view]
    public fun get_config_object_address() : address  acquires AMMConfig  {
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        signer::address_of(&config_object_signer)
    }

    // ======== Only Governance =========

    // add whitelist
    public entry fun add_whitelist(sender: &signer, whitelist_address: address) acquires AMMConfig {
        assert!( signer::address_of(sender) == @legato_addr , ERR_UNAUTHORIZED);
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        assert!( !smart_vector::contains(&config.whitelist, &whitelist_address) , ERR_INVALID_ADDRESS);
        smart_vector::push_back(&mut config.whitelist, whitelist_address);
    }

    // remove whitelist
    public entry fun remove_whitelist(sender: &signer, whitelist_address: address) acquires AMMConfig {
        assert!( signer::address_of(sender) == @legato_addr , ERR_UNAUTHORIZED);
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let (found, idx) = smart_vector::index_of<address>(&config.whitelist, &whitelist_address);
        assert!(  found , ERR_INVALID_ADDRESS);
        smart_vector::swap_remove<address>(&mut config.whitelist, idx );
    }

    // update treasury address
    public entry fun update_treasury_address(sender: &signer, new_address: address) acquires AMMConfig {
        assert!( signer::address_of(sender) == @legato_addr , ERR_UNAUTHORIZED);
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        config.treasury_address = new_address;
    }

    // update fee 
    public entry fun update_fee<X,Y>(sender: &signer, fee_numerator: u128, fee_denominator: u128) acquires AMMConfig, Pool {
        let is_order = is_order<X, Y>();
        assert!(is_order, ERR_MUST_BE_ORDER);
        assert!( signer::address_of(sender) == @legato_addr , ERR_UNAUTHORIZED);

        let config = borrow_global_mut<AMMConfig>(@legato_addr); 

        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);
        
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer); 

        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);
        pool.swap_fee = fixed_point64::create_from_rational( fee_numerator, fee_denominator );
    }

    // update weights
    public entry fun update_weights<X,Y>(sender: &signer, weight_x: u64, weight_y: u64) acquires AMMConfig, Pool {
        let is_order = is_order<X, Y>();
        assert!(is_order, ERR_MUST_BE_ORDER);
        assert!( signer::address_of(sender) == @legato_addr , ERR_UNAUTHORIZED);
        assert!( weight_x+weight_y == 10000, ERR_WEIGHTS_SUM); 

        let config = borrow_global_mut<AMMConfig>(@legato_addr); 

        let (_, lp_symbol) = generate_lp_name_and_symbol<X, Y>();
        assert!( smart_vector::contains(&config.pool_list, &lp_symbol) , ERR_POOL_EXISTS);
        
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer); 

        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);
        pool.weight_x = weight_x;
        pool.weight_y = weight_y;
    }


    // ======== Internal Functions =========

    /// Compare two coins, 'X' and 'Y'.
    fun compare<X, Y>(): Result {
        let x_info = type_info::type_of<X>();
        let x_compare = &mut type_info::struct_name(&x_info);
        vector::append(x_compare, type_info::module_name(&x_info));

        let y_info = type_info::type_of<Y>();
        let y_compare = &mut type_info::struct_name(&y_info);
        vector::append(y_compare, type_info::module_name(&y_info));

        let comp = comparator::compare(x_compare, y_compare);
        if (!comparator::is_equal(&comp)) return comp;

        let x_address = type_info::account_address(&x_info);
        let y_address = type_info::account_address(&y_info);
        comparator::compare(&x_address, &y_address)
    }

    fun is_order<X, Y>(): bool {
        let comp = compare<X, Y>();
        assert!(!comparator::is_equal(&comp), ERR_THE_SAME_COIN);

        if (comparator::is_smaller_than(&comp)) {
            true
        } else {
            false
        }
    }

    // mint LP tokens
    fun mint_lp<X, Y>(
        lp_provider: &signer, 
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        optimal_x: u64,
        optimal_y: u64,
        coin_x_reserve: u64,
        coin_y_reserve: u64
    ): Coin<LP<X, Y>>  acquires Pool, AMMConfig {
        let config = borrow_global_mut<AMMConfig>(@legato_addr);
        let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
        let pool_address = signer::address_of(&config_object_signer);

        assert!(exists<Pool<X, Y>>(pool_address), ERR_POOL_EXISTS);

        let pool = borrow_global_mut<Pool<X, Y>>(pool_address);

        let x_provided_val = coin::value<X>(&coin_x);
        let y_provided_val = coin::value<Y>(&coin_y);

        // Retrieves total LP coins supply
        let lp_coins_total = option::extract(&mut coin::supply<LP<X, Y>>());

        // Computes provided liquidity
        let provided_liq = if (0 == lp_coins_total) { 
            let initial_liq = weighted_math::compute_initial_lp( pool.weight_x,  pool.weight_y, x_provided_val, y_provided_val);
            assert!(initial_liq > MINIMAL_LIQUIDITY, ERR_LP_NOT_ENOUGH);

            coin::merge(&mut pool.min_liquidity, coin::mint<LP<X, Y>>(MINIMAL_LIQUIDITY, &pool.lp_mint) );

            initial_liq - MINIMAL_LIQUIDITY
        } else {

            let (x_liq, y_liq) = weighted_math::compute_derive_lp( optimal_x, optimal_y, pool.weight_x, pool.weight_y, coin_x_reserve, coin_y_reserve, (lp_coins_total as u64) );
    
            (x_liq + y_liq)    
        };

        // Merges provided coins into pool
        coin::merge(&mut pool.coin_x, coin_x);
        coin::merge(&mut pool.coin_y, coin_y);

        assert!(coin::value(&pool.coin_x) < MAX_POOL_VALUE, ERR_POOL_FULL);
        assert!(coin::value(&pool.coin_y) < MAX_POOL_VALUE, ERR_POOL_FULL);

        // Mints LP tokens
        coin::mint<LP<X, Y>>(provided_liq, &pool.lp_mint)
    }

    fun coin_symbol_prefix<CoinType>(): String {
        let symbol = coin::symbol<CoinType>();
        let prefix_length = SYMBOL_PREFIX_LENGTH;
        if (string::length(&symbol) < SYMBOL_PREFIX_LENGTH) {
            prefix_length = string::length(&symbol);
        };
        string::sub_string(&symbol, 0, prefix_length)
    }

    // ======== Test-related Functions =========

    #[test_only] 
    public fun init_module_for_testing(deployer: &signer) {
        init_module(deployer)
    }
}