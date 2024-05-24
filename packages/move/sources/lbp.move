// // Copyright (c) Tamago Blockchain Labs, Inc.
// // SPDX-License-Identifier: MIT

// module legato_addr::lbp {

//     use std::option;
//     use std::signer;
//     use std::vector; 
//     use std::string::{Self, String };  
 
//     use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability}; 
//     use aptos_framework::object::{Self, ExtendRef};
//     use aptos_framework::aptos_coin::AptosCoin;
    
//     use aptos_std::smart_vector::{Self, SmartVector};
//     use aptos_std::math128;
//     use aptos_std::comparator::{Self, Result};
//     use aptos_std::type_info; 
//     use aptos_std::fixed_point64::{Self, FixedPoint64};
//     use aptos_std::table::{Self, Table};

//     use legato_addr::weighted_math;
    

//     // ======== Constants ========

//     // Default swap fee of 0.25% for LBP
//     const LBP_FEE: u128 = 46116860184273879;

//     const SYMBOL_PREFIX_LENGTH: u64 = 4;

//     const ERR_NOT_COIN: u64 = 106;

//     const WEIGHT_SCALE: u64 = 10000; 

//     /// The Pool token that will be used to mark the pool share
//     struct LP<phantom Y> has drop, store {}

//     // LBP pool for launching new tokens accepts APT & future staking rewards
//     // Weight automatically shifts until a certain condition is met
//     struct LBP<phantom Y> has key {
//         coin_x: Coin<AptosCoin>,
//         coin_y: Coin<Y>,
//         pending_in_amount: u64,
//         pending_in_table: Table<String, u64>,
//         pending_in_coin_list: SmartVector<String>,
//         start_weight: u64,
//         final_weight: u64,
//         min_liquidity: Coin<LP<Y>>,
//         swap_fee: FixedPoint64,
//         target_amount: u64, // The target amount required to fully shift the weight.
//         total_amount_collected: u64,  // Total amount accumulated in the pool.
//         enable_collect_apt: bool,
//         enable_collect_pt: bool,
//         lp_mint: MintCapability<LP<Y>>,
//         lp_burn: BurnCapability<LP<Y>>
//     }

//     // Represents the global state of the AMM. 
//     struct LBPManager has key { 
//         token_list: SmartVector<String>, // all pools in the system
//         whitelist: SmartVector<address>, // who can setup a new pool
//         extend_ref: ExtendRef,
//         treasury_address: address // where all fees from all pools will be sent for further LP staking
//     }

//     const ERR_UNAUTHORIZED: u64 = 101; 
//     const ERR_INVALID_WEIGHT: u64 = 102;

//     // Constructor for this module.
//     fun init_module(sender: &signer) {
        
//         let constructor_ref = object::create_object(signer::address_of(sender));
//         let extend_ref = object::generate_extend_ref(&constructor_ref);

//         let whitelist = smart_vector::new();
//         smart_vector::push_back(&mut whitelist, signer::address_of(sender));

//         move_to(sender, LBPManager { 
//             whitelist , 
//             token_list: smart_vector::new(), 
//             extend_ref,
//             treasury_address: signer::address_of(sender)
//         });
//     }

//     // ======== Entry Points =========

//     // register LBP pool
//     public entry fun register_pool<Y>(
//         sender: &signer,
//         start_weight: u64,
//         final_weight: u64,
//         target_amount: u64
//     ) acquires LBPManager {
        
//         assert!(coin::is_coin_initialized<Y>(), ERR_NOT_COIN);

//         let config = borrow_global_mut<LBPManager>(@legato_addr);
//         // Ensure that the caller is on the whitelist
//         assert!( smart_vector::contains(&config.whitelist, &(signer::address_of(sender))) , ERR_UNAUTHORIZED);

//         assert!( start_weight >= 5000 && start_weight < WEIGHT_SCALE , ERR_INVALID_WEIGHT); 
//         assert!( final_weight >= 5000 && final_weight < WEIGHT_SCALE, ERR_INVALID_WEIGHT );
//         assert!( start_weight > final_weight, ERR_INVALID_WEIGHT ); 

//         let config_object_signer = object::generate_signer_for_extending(&config.extend_ref);
//         let (lp_name, lp_symbol) = generate_lp_name_and_symbol<Y>();

//         let (lp_burn_cap, lp_freeze_cap, lp_mint_cap) = coin::initialize<LP<Y>>(sender, lp_name, lp_symbol, 8, true);
//         coin::destroy_freeze_cap(lp_freeze_cap);

//         // Registers Y if not already registered
//         if (!coin::is_account_registered<Y>(signer::address_of(&config_object_signer))) {
//             coin::register<Y>(&config_object_signer)
//         };

//         let pool = LBP<Y> {
//             coin_x: coin::zero<AptosCoin>(),
//             coin_y: coin::zero<Y>(), 
//             start_weight,
//             final_weight,
//             lp_mint: lp_mint_cap,
//             lp_burn: lp_burn_cap,
            
//             min_liquidity: coin::zero<LP<X,Y>>(),
//             swap_fee: fixed_point64::create_from_raw_value( DEFAULT_FEE )
//         };
//         move_to(&config_object_signer, pool);

//         smart_vector::push_back(&mut config.pool_list, lp_symbol);
//     }
    
//     public fun generate_lp_name_and_symbol<Y>(): (String, String) {
//         let lp_name = string::utf8(b"");
//         string::append_utf8(&mut lp_name, b"LP-"); 
//         string::append(&mut lp_name, coin::symbol<Y>());

//         let lp_symbol = string::utf8(b"");
//         string::append(&mut lp_symbol, coin_symbol_prefix<Y>());

//         (lp_name, lp_symbol)
//     }

//     fun coin_symbol_prefix<CoinType>(): String {
//         let symbol = coin::symbol<CoinType>();
//         let prefix_length = SYMBOL_PREFIX_LENGTH;
//         if (string::length(&symbol) < SYMBOL_PREFIX_LENGTH) {
//             prefix_length = string::length(&symbol);
//         };
//         string::sub_string(&symbol, 0, prefix_length)
//     }
// }