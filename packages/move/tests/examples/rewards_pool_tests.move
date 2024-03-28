

#[test_only]
module legato_addr::rewards_pool_tests {

    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_std::simple_map;
    use legato_addr::rewards_pool::{Self, RewardsPool};
    use legato_addr::test_helpers;
    use legato_addr::epoch;
    use std::signer;
    use std::vector;

    #[test(claimer_1 = @0xdead, claimer_2 = @0xbeef, claimer_3 = @0xfeed)]
    fun test_e2e(claimer_1: &signer, claimer_2: &signer, claimer_3: &signer) {
        test_helpers::set_up();
        // Create a rewards pool with 1 native fungible asset and 1 coin.
        let asset_rewards_1 = test_helpers::create_fungible_asset_and_mint(claimer_1, b"test1", 1000);
        let asset_rewards_2 = test_helpers::create_fungible_asset_and_mint(claimer_1, b"test2", 2000);

        let asset_1 = fungible_asset::asset_metadata(&asset_rewards_1);
        let asset_2 = fungible_asset::asset_metadata(&asset_rewards_2);

        let rewards_pool = rewards_pool::create(vector[asset_1, asset_2]);
        assert!(rewards_pool::reward_tokens(rewards_pool) == vector[asset_1, asset_2], 0);

        // First epoch, claimers 1 and 2 split the rewards.
        increase_allocation(claimer_1, rewards_pool, 60);
        increase_allocation(claimer_2, rewards_pool, 40);

        epoch::fast_forward(1);

        add_rewards(rewards_pool, &mut asset_rewards_1, &mut asset_rewards_2, 50, 100);
        add_rewards(rewards_pool, &mut asset_rewards_1, &mut asset_rewards_2, 50, 100);

        verify_claimer_shares_percentage(claimer_1, rewards_pool, 100, 60);
        verify_claimer_shares_percentage(claimer_2, rewards_pool, 100, 40);

        claim_and_verify_rewards(claimer_1, rewards_pool, 100, vector[60, 120]);
        claim_and_verify_rewards(claimer_2, rewards_pool, 100, vector[40, 80]);
        // Claimers have claimed their rewards, so their shares are now 0.
        verify_claimer_shares_percentage(claimer_1, rewards_pool, 100, 0);
        verify_claimer_shares_percentage(claimer_2, rewards_pool, 100, 0);

        // Second epoch, there are 3 claimers, one of them has allocation decreased.
        increase_allocation(claimer_1, rewards_pool, 30);
        increase_allocation(claimer_2, rewards_pool, 50);
        increase_allocation(claimer_3, rewards_pool, 30);
        decrease_allocation(claimer_3, rewards_pool, 10);

        verify_claimer_shares_percentage(claimer_1, rewards_pool, 101, 30);
        verify_claimer_shares_percentage(claimer_2, rewards_pool, 101, 50);
        verify_claimer_shares_percentage(claimer_3, rewards_pool, 101, 20);

        epoch::fast_forward(1);

        add_rewards(rewards_pool, &mut asset_rewards_1, &mut asset_rewards_2, 100, 200);
        claim_and_verify_rewards(claimer_1, rewards_pool,101, vector[30, 60]);
        claim_and_verify_rewards(claimer_2, rewards_pool, 101, vector[50, 100]);
        claim_and_verify_rewards(claimer_3, rewards_pool, 101, vector[20, 40]);
        // Claimers have claimed their rewards, so their shares are now 0.
        verify_claimer_shares_percentage(claimer_1, rewards_pool, 101, 0);
        verify_claimer_shares_percentage(claimer_2, rewards_pool, 101, 0);

        test_helpers::clean_up(vector[asset_rewards_1, asset_rewards_2]);
    }   

    fun increase_allocation(claimer: &signer, pool: Object<RewardsPool>, amount: u64) {
        rewards_pool::increase_allocation(signer::address_of(claimer), pool, amount);
    }

    fun add_rewards(
        pool: Object<RewardsPool>,
        rewards_1: &mut FungibleAsset,
        rewards_2: &mut FungibleAsset,
        amount_1: u64,
        amount_2: u64,
    ) {
        rewards_pool::add_rewards(
            pool,
            vector[fungible_asset::extract(rewards_1, amount_1), fungible_asset::extract(rewards_2, amount_2)],
            epoch::now() - 1,
        );
    }

    fun verify_claimer_shares_percentage(
        claimer_1: &signer,
        rewards_pool: Object<RewardsPool>,
        epoch: u64,
        expected_shares: u64,
    ) {
        let (shares, _) = rewards_pool::claimer_shares(signer::address_of(claimer_1), rewards_pool, epoch);
        assert!(shares == expected_shares, 0);
    }
    
    fun claim_and_verify_rewards(
        claimer: &signer,
        pool: Object<RewardsPool>,
        epoch: u64,
        expected_amounts: vector<u64>,
    ) {
        let claimer_addr = signer::address_of(claimer);
        let (non_zero_reward_tokens, claimable_rewards) = rewards_pool::claimable_rewards(claimer_addr, pool, epoch);
        let claimable_map = simple_map::new_from(non_zero_reward_tokens, claimable_rewards);
        let rewards = rewards_pool::claim_rewards(claimer, pool, epoch);
        vector::zip(rewards, expected_amounts, |reward, expected_amount| {
            let reward_metadata = fungible_asset::asset_metadata(&reward);
            let claimable_amount = if (simple_map::contains_key(&claimable_map, &reward_metadata)) {
                *simple_map::borrow(&claimable_map, &reward_metadata)
            } else {
                0
            };
            assert!(fungible_asset::amount(&reward) == claimable_amount, 0);
            assert!(fungible_asset::amount(&reward) == expected_amount, 0);
            primary_fungible_store::deposit(claimer_addr, reward);
        });
    }

    fun decrease_allocation(claimer: &signer, pool: Object<RewardsPool>, amount: u64) {
        rewards_pool::decrease_allocation(signer::address_of(claimer), pool, amount);
    }

}