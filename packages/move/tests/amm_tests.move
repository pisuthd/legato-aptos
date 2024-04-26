

#[test_only]
module legato_addr::amm_tests { 
      
    use std::string::utf8;
    use std::signer;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability};
    
    use legato_addr::amm::{Self, LP};

    struct BTC {}

    struct USDT {}

    const ERR_UNKNOWN: u64 = 0;

    #[test_only]
    const USDT_AMOUNT : u64 = 20_000_000_000; // 20,000 USDT at 20%

    #[test_only]
    const BTC_AMOUNT: u64 = 160_000_000;  // 1.6 BTC at 80%

    #[test(deployer = @legato_addr, lp_provider = @0xdead, user = @0xbeef )]
    fun test_register_pools(deployer: &signer, lp_provider: &signer, user: &signer) {

        // 50,000 BTC/USD
        register_pools(deployer, lp_provider, user);
        
        // Add 10% from total liquidity.
        add_liquidity( lp_provider, BTC_AMOUNT/10, USDT_AMOUNT/10);

    }

    #[test(deployer = @legato_addr, lp_provider = @0xdead, user = @0xbeef )]
    fun test_swap(deployer: &signer, lp_provider: &signer, user: &signer) {

        // 50,000 BTC/USD
        register_pools(deployer, lp_provider, user);
        
        amm::swap<USDT, BTC>(user, 20_000_000, 1); // 20 USDT

        let user_address = signer::address_of(user);
        
        assert!(coin::balance<BTC>(user_address) == 39575, ERR_UNKNOWN); // 0.00039575 BTC at 50536.955148452
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
        coin::register<BTC>(deployer);
        coin::register<BTC>(lp_provider);
        coin::register<BTC>(user);
        let xbtc_mint_cap = register_coin<BTC>(deployer, b"BTC", b"BTC", 8);
        coin::deposit(deployer_address, coin::mint<BTC>(BTC_AMOUNT, &xbtc_mint_cap));
        coin::deposit(lp_provider_address, coin::mint<BTC>(BTC_AMOUNT, &xbtc_mint_cap));
        coin::destroy_mint_cap(xbtc_mint_cap);
        assert!(coin::balance<BTC>(deployer_address) == BTC_AMOUNT, 2);

        amm::register_pool<BTC, USDT>(deployer, 8000, 2000, 8, 6);

        amm::add_liquidity<BTC, USDT>(
            deployer,
            BTC_AMOUNT,
            1,
            USDT_AMOUNT,
            1
        );

        assert!(coin::balance<BTC>(deployer_address) == 0, ERR_UNKNOWN);
        assert!(coin::balance<USDT>(deployer_address) == 0, ERR_UNKNOWN);
        
        assert!(coin::balance<LP<BTC, USDT>>(deployer_address) == 71_554_175_278_993, 3);

    }

    #[test_only]
    public fun add_liquidity(lp_provider: &signer, x_amount: u64, y_amount: u64) {
        
        let lp_provider_address = signer::address_of(lp_provider);

        amm::add_liquidity<BTC, USDT>(
            lp_provider,
            x_amount,
            1,
            y_amount,
            1
        );
 
        assert!(coin::balance<LP<BTC, USDT>>(lp_provider_address) == 1_684_807_902_915, 3);

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
