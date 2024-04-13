#[test_only]
module legato_addr::vault_tests {

    // use std::debug::print;

    use std::features;
    use std::signer;

    use aptos_std::bls12381;
    use aptos_std::stake;
    use aptos_std::vector;

    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::reconfiguration;
    use aptos_framework::delegation_pool as dp;
    use aptos_framework::timestamp;

    use legato_addr::epoch;
    use legato_addr::vault;
    use legato_addr::vault_maturity_dates::{APR_2024};

     #[test_only]
    const EPOCH_DURATION: u64 = 60;

    #[test_only]
    const LOCKUP_CYCLE_SECONDS: u64 = 3600;

    #[test_only]
    const MODULE_EVENT: u64 = 26;

    #[test_only]
    const DELEGATION_POOLS: u64 = 11;

    #[test_only]
    const ONE_APT: u64 = 100000000; // 1x10**8

    #[test_only]
    const VALIDATOR_STATUS_PENDING_ACTIVE: u64 = 1;
    const VALIDATOR_STATUS_ACTIVE: u64 = 2;
    const VALIDATOR_STATUS_PENDING_INACTIVE: u64 = 3;
    const VALIDATOR_STATUS_INACTIVE: u64 = 4;

    #[test(deployer = @legato_addr,aptos_framework = @aptos_framework, validator = @0xdead, user_1 = @0xbeef, user_2 = @0xfeed)]
    fun test_e2e(
        deployer: &signer,
        aptos_framework: &signer,
        validator: &signer, 
        user_1: &signer,
        user_2: &signer
    ) {
        initialize_for_test(aptos_framework);
        let (_sk, pk, pop) = generate_identity();
        initialize_test_validator(&pk, &pop, validator, 100 * ONE_APT, true, true);

        // setup timelock vaults
        setup_vaults(deployer, signer::address_of(validator));

        // mint APT for user_1, user_2
        account::create_account_for_test(signer::address_of(user_1));
        account::create_account_for_test(signer::address_of(user_2)); 
        account::create_account_for_test(signer::address_of(deployer)); 
        account::create_account_for_test( vault::get_config_object_address() ); 

        stake::mint(user_1, 100 * ONE_APT);
        stake::mint(user_2, 200 * ONE_APT); 

        assert!(coin::balance<AptosCoin>(signer::address_of(user_1)) == 100 * ONE_APT, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(user_2)) == 200 * ONE_APT, 1);

        // stake for PT 
        vault::mint<APR_2024>( user_1, signer::address_of(validator), 100 * ONE_APT);
        vault::mint<APR_2024>( user_2, signer::address_of(validator), 200 * ONE_APT);

        // having ~100.41 PT today
        let pt_amount = vault::get_pt_balance<APR_2024>(signer::address_of(user_1));
        assert!( pt_amount == 10041095890, 2);


        // forwards 30 epoch
        let i:u64=1;  
        while(i <= 30) 
        {
            timestamp::fast_forward_seconds(epoch::duration());
            end_epoch();
            i=i+1;  //incrementing the counter
        };

        // check staked amount
        let pool_address = dp::get_owned_pool_address(signer::address_of(validator) );
        let (pool_staked_amount,_,_) = dp::get_stake(pool_address , vault::get_config_object_address() );
        
        assert!( pool_staked_amount == 40035116288, 3);

        // perform admin process
        vault::unlock<APR_2024>( deployer, signer::address_of(validator));

        timestamp::fast_forward_seconds(epoch::duration());
        end_epoch();

        // redeem 
        vault::redeem<APR_2024>( user_1, signer::address_of(validator), pt_amount);

        // verify that the user has staked 100 APT and can now receive 100.41 APT after 30 epochs
        let apt_amount = coin::balance<AptosCoin>(signer::address_of(user_1));
        assert!( apt_amount == 10041095790, 4);

    }

    #[test_only]
    public fun setup_vaults(sender: &signer, validator_address: address) {

        vault::init_module_for_testing(sender);

        // matures in 30 epoch
        let maturity_date = timestamp::now_seconds()+(30*epoch::duration());

        // setup APR_2024 vault /w 5% APY
        vault::new_vault<APR_2024>(sender, 5000000, maturity_date);

        vault::add_whitelist_validator(sender, validator_address);
    }

    #[test_only]
    public fun initialize_for_test(aptos_framework: &signer) {
        initialize_for_test_custom(
            aptos_framework,
            100 * ONE_APT,
            10000 * ONE_APT,
            LOCKUP_CYCLE_SECONDS,
            true,
            1,
            100,
            1000000
        );
    }

    #[test_only]
    public fun end_epoch() {
        stake::end_epoch();
        reconfiguration::reconfigure_for_test_custom();
    }

    #[test_only]
    public fun initialize_for_test_custom(
        aptos_framework: &signer,
        minimum_stake: u64,
        maximum_stake: u64,
        recurring_lockup_secs: u64,
        allow_validator_set_change: bool,
        rewards_rate_numerator: u64,
        rewards_rate_denominator: u64,
        voting_power_increase_limit: u64,
    ) {
        account::create_account_for_test(signer::address_of(aptos_framework));
        stake::initialize_for_test_custom(
            aptos_framework,
            minimum_stake,
            maximum_stake,
            recurring_lockup_secs,
            allow_validator_set_change,
            rewards_rate_numerator,
            rewards_rate_denominator,
            voting_power_increase_limit
        );
        reconfiguration::initialize_for_test(aptos_framework);
        features::change_feature_flags(aptos_framework, vector[DELEGATION_POOLS, MODULE_EVENT], vector[]);
    }

    #[test_only]
    public fun generate_identity(): (bls12381::SecretKey, bls12381::PublicKey, bls12381::ProofOfPossession) {
        let (sk, pkpop) = bls12381::generate_keys();
        let pop = bls12381::generate_proof_of_possession(&sk);
        let unvalidated_pk = bls12381::public_key_with_pop_to_normal(&pkpop);
        (sk, unvalidated_pk, pop)
    }

    #[test_only]
    public fun initialize_test_validator(
        public_key: &bls12381::PublicKey,
        proof_of_possession: &bls12381::ProofOfPossession,
        validator: &signer,
        amount: u64,
        should_join_validator_set: bool,
        should_end_epoch: bool
    ) {
        let validator_address = signer::address_of(validator);
        if (!account::exists_at(signer::address_of(validator))) {
            account::create_account_for_test(validator_address);
        };

        dp::initialize_delegation_pool(validator, 0, vector::empty<u8>());
        validator_address = dp::get_owned_pool_address(validator_address);

        let pk_bytes = bls12381::public_key_to_bytes(public_key);
        let pop_bytes = bls12381::proof_of_possession_to_bytes(proof_of_possession);
        stake::rotate_consensus_key(validator, validator_address, pk_bytes, pop_bytes);

        if (amount > 0) {
            mint_and_add_stake(validator, amount);
        };

        if (should_join_validator_set) {
            stake::join_validator_set(validator, validator_address);
        };
        if (should_end_epoch) {
            end_epoch();
        };
    }

    #[test_only]
    public fun mint_and_add_stake(account: &signer, amount: u64) {
        stake::mint(account, amount);
        dp::add_stake(account, dp::get_owned_pool_address(signer::address_of(account)), amount);
    }

}