

#[test_only]
module legato_addr::amm_tests {

    use std::string::utf8;
    use std::signer;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability};
    
    use legato_addr::amm::{Self, LP};

    struct XBTC {}

    struct USDT {}

    const ERR_UNKNOWN: u64 = 0;

    // When setting up a 90/10 pool of ~$100k
    // Initial allocation at 1 BTC = 50,000 USDT

    #[test_only]
    const USDT_AMOUNT : u64 = 10_000_000_000; // 10,000 USDT at 10%

    #[test_only]
    const BTC_AMOUNT: u64 = 180_000_000;  // 1.8 BTC at 90%

    #[test(deployer = @legato_addr, lp_provider = @0xdead, user = @0xbeef )]
    fun test_register_pools(deployer: &signer, lp_provider: &signer, user: &signer) {

        register_pools(deployer, lp_provider, user);
 
        add_remove_liquidity(deployer,  lp_provider );

    }

    #[test(deployer = @legato_addr, lp_provider = @0xdead, user = @0xbeef )]
    fun test_swap(deployer: &signer, lp_provider: &signer, user: &signer) {

        register_pools(deployer, lp_provider, user);
        
        amm::swap<USDT, XBTC>(user, 20_000_000, 1); // 20 USDT

        let user_address = signer::address_of(user);
        
        assert!(coin::balance<XBTC>(user_address) == 39754, ERR_UNKNOWN); // 0.00039754 BTC at ~50,536 BTC/USDT
    }

    #[test_only]
    public fun register_pools(deployer: &signer, lp_provider: &signer, user: &signer) {
        
        amm::init_module_for_testing(deployer);

        let deployer_address = signer::address_of(deployer);
        let lp_provider_address = signer::address_of(lp_provider);
        let user_address = signer::address_of(user);

        account::create_account_for_test(lp_provider_address);  
        account::create_account_for_test(deployer_address); 
        account::create_account_for_test(user_address); 
        account::create_account_for_test( amm::get_config_object_address() ); 

        // USDT
        coin::register<USDT>(deployer);
        coin::register<USDT>(lp_provider);
        coin::register<USDT>(user);
        let usdt_mint_cap = register_coin<USDT>(deployer, b"USDT", b"USDT", 6);
        coin::deposit(deployer_address, coin::mint<USDT>(USDT_AMOUNT, &usdt_mint_cap));
        coin::deposit(lp_provider_address, coin::mint<USDT>(USDT_AMOUNT, &usdt_mint_cap));
        coin::deposit(user_address, coin::mint<USDT>(USDT_AMOUNT, &usdt_mint_cap));
        coin::destroy_mint_cap(usdt_mint_cap);
        assert!(coin::balance<USDT>(deployer_address) == USDT_AMOUNT, ERR_UNKNOWN);

        // BTC
        coin::register<XBTC>(deployer);
        coin::register<XBTC>(lp_provider);
        coin::register<XBTC>(user);
        let xbtc_mint_cap = register_coin<XBTC>(deployer, b"BTC", b"BTC", 8);
        coin::deposit(deployer_address, coin::mint<XBTC>(BTC_AMOUNT, &xbtc_mint_cap));
        coin::deposit(lp_provider_address, coin::mint<XBTC>(BTC_AMOUNT, &xbtc_mint_cap));
        coin::destroy_mint_cap(xbtc_mint_cap);
        assert!(coin::balance<XBTC>(deployer_address) == BTC_AMOUNT, 2);

        amm::register_pool<USDT, XBTC>(deployer, 1000, 9000);

        amm::add_liquidity<USDT, XBTC>(
            deployer,
            USDT_AMOUNT,
            1,
            BTC_AMOUNT,
            1
        );

        assert!(coin::balance<XBTC>(deployer_address) == 0, ERR_UNKNOWN);
        assert!(coin::balance<USDT>(deployer_address) == 0, ERR_UNKNOWN);
        
        assert!(coin::balance<LP<USDT, XBTC>>(deployer_address) == 268_994_649, 3);

    }

    #[test_only]
    public fun add_remove_liquidity(deployer: &signer, lp_provider: &signer) {
        
        let lp_provider_address = signer::address_of(lp_provider);

        amm::add_liquidity<USDT, XBTC>(
            lp_provider,
            USDT_AMOUNT/20, // 500 USDT
            1,
            BTC_AMOUNT/20, // 0.09 XBTC
            1
        );

        let lp_amount = coin::balance<LP<USDT, XBTC>>(lp_provider_address);

        assert!(lp_amount == 13_390_722, ERR_UNKNOWN);

        // Transfer tokens out from the LP provider
        let usdt_amount = coin::balance<USDT>(lp_provider_address); 
        coin::transfer<USDT>( lp_provider, signer::address_of(deployer),usdt_amount);

        let xbtc_amount = coin::balance<XBTC>(lp_provider_address); 
        coin::transfer<XBTC>( lp_provider, signer::address_of(deployer),xbtc_amount);

        amm::remove_liquidity<USDT, XBTC>(
            lp_provider,
            lp_amount
        );

        usdt_amount = coin::balance<USDT>(lp_provider_address); 
        assert!( usdt_amount == 487416859, ERR_UNKNOWN); // 487 USDT

        xbtc_amount = coin::balance<XBTC>(lp_provider_address); 
        assert!(xbtc_amount == 8940828, ERR_UNKNOWN); // 0.089 XBTC

    }

    #[test_only]
    fun register_coin<CoinType>(
        coin_admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8
    ): MintCapability<CoinType> {
        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<CoinType>(
                coin_admin,
                utf8(name),
                utf8(symbol),
                decimals,
                true);
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_burn_cap(burn_cap);

        mint_cap
    }

     

}