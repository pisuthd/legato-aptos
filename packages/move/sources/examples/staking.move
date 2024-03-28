
module legato_addr::staking {

    use std::signer;
    use aptos_framework::account;
    
    use legato_addr::mock_token;

    /// Error codes
    const EINSUFFICIENT_STAKE: u64 = 0;
    const EALREADY_STAKED: u64 = 1;
    const EINVALID_UNSTAKE_AMOUNT: u64 = 2;
    const EINVALID_REWARD_AMOUNT: u64 = 3;
    const EINVALID_APY: u64 = 4;
    const EINSUFFICIENT_BALANCE: u64 = 5;
    const DEFAULT_APY:u64 = 1000;//10% APY per year

    struct StakedBalance has store, key {
        staked_balance: u64
    }

    public fun stake(acc_own: &signer,amount: u64) {
        let from = signer::address_of(acc_own);
        let balance = mock_token::balance_of(from);
        assert!(balance >= amount, EINSUFFICIENT_BALANCE);
        assert!(!exists<StakedBalance>(from), EALREADY_STAKED);

        mock_token::withdraw(from, amount);

        let staked_balance = StakedBalance {
            staked_balance: amount
        };
        move_to(acc_own, staked_balance);
    }

     public fun unstake(acc_own: &signer,amount: u64) acquires StakedBalance {
        let from = signer::address_of(acc_own);
        let staked_balance = borrow_global_mut<StakedBalance>(from);
        let staked_amount = staked_balance.staked_balance;
        assert!(staked_amount >= amount, EINVALID_UNSTAKE_AMOUNT);
        let coins = mock_token::createCoin(staked_amount);
        mock_token::deposit(from, coins);
        staked_balance.staked_balance = staked_balance.staked_balance - amount;
    }

    public fun claim_rewards(acc_own: &signer) acquires StakedBalance {
        let from = signer::address_of(acc_own);
        let staked_balance = borrow_global_mut<StakedBalance>(from);
        let staked_amount = staked_balance.staked_balance;
        assert!(staked_amount > 0, EINSUFFICIENT_STAKE);
        let apy = DEFAULT_APY;
        let reward_amount = (staked_amount * apy) / (10000);
        let coins = mock_token::createCoin(reward_amount);
        mock_token::deposit(from, coins);
    }

    #[test(alice=@0x11,bob=@0x2)]
    public entry fun test_staking(alice : signer, bob : signer)  acquires StakedBalance{
        account::create_account_for_test(signer::address_of(&alice));
        account::create_account_for_test(signer::address_of(&bob));

        // Publish balance for Alice and Bob
        mock_token::publish_balance(&alice);
        mock_token::publish_balance(&bob);
    
        // Mint some tokens to Alice
        mock_token::mint<legato_addr::mock_token::Coin>(signer::address_of(&bob), 1000);
        mock_token::mint<legato_addr::mock_token::Coin>(signer::address_of(&alice), 1000);

        // Alice stakes some tokens
        stake(&alice, 500);

        // Check that Alice's staked balance is correct
        let alice_resource = borrow_global<StakedBalance>(signer::address_of(&alice));
        assert!(alice_resource.staked_balance == 500, 100);

        // Alice unstakes some tokens
        unstake(&alice, 200);

        // Check that Alice's staked balance is correct
        let alice_resource = borrow_global<StakedBalance>(signer::address_of(&alice));
        assert!(alice_resource.staked_balance == 300, 100);

        // Alice claims rewards
        claim_rewards(&alice);
    }

}