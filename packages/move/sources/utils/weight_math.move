

module legato_addr::weighted_math {
 
    use aptos_std::math128;
    use aptos_std::fixed_point64::{Self, FixedPoint64}; 
    use aptos_std::math_fixed64; 

    const WEIGHT_SCALE: u64 = 10000;
    const HALF_WEIGHT_SCALE: u64 = 5000;

    // Calculate the output amount according to the pool weight
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        weight_in: u64,
        scaling_factor_in: u64,
        reserve_out: u64,
        weight_out: u64,
        scaling_factor_out: u64
    ) : u64 {

        /********************************************************************************************** 
        // aO = amountOut                                                                            //
        // bO = balanceOut                                                                           //
        // bI = balanceIn              /      /            bI             \    (wI / wO) \           //
        // aI = amountIn    aO = bO * |  1 - | --------------------------  | ^            |          //
        // wI = weightIn               \      \       ( bI + aI )         /              /           //
        // wO = weightOut                                                                            //
        **********************************************************************************************/

        // Scale the amount to adjust for the provided scaling factor of the asset
        let amount_in_after_scaled = scale_amount(amount_in, scaling_factor_in);
        let reserve_in_after_scaled = scale_amount(reserve_in, scaling_factor_in);
        let reserve_out_after_scaled  = scale_amount(reserve_out, scaling_factor_out);

        if (weight_in == weight_out) {
            let denominator = reserve_in_after_scaled+amount_in_after_scaled; 
            let base = fixed_point64::create_from_rational(reserve_in_after_scaled , denominator);
            let amount_out = fixed_point64::multiply_u128( reserve_out_after_scaled, fixed_point64::sub(fixed_point64::create_from_u128(1), base ) );

            (amount_out as u64) / scaling_factor_out
        }  else {

            let denominator = reserve_in_after_scaled+amount_in_after_scaled; 
            let base = fixed_point64::create_from_rational(reserve_in_after_scaled , denominator);
            let exponent = fixed_point64::create_from_rational((weight_in as u128), (weight_out as u128));
 
            let power = pow(base, exponent);
            let amount_out = fixed_point64::multiply_u128( reserve_out_after_scaled , fixed_point64::sub(fixed_point64::create_from_u128(1), power ) );

            (amount_out as u64) / scaling_factor_out
        }
 
    }

    // Computes initial LP amount
    public fun compute_initial_lp(
        weight_x: u64,
        weight_y: u64,
        scaling_factor_x: u64,
        scaling_factor_y: u64,
        amount_x: u64,
        amount_y: u64
    ): u64 {
        let amount_x_after_scaled = scale_amount(amount_x, scaling_factor_x);
        let amount_y_after_scaled = scale_amount(amount_y, scaling_factor_y);
        // 10000 * 10000 never exceeds u64.
        (math128::sqrt( (amount_x_after_scaled * (weight_x as u128)) * ( amount_y_after_scaled * ( weight_y as u128)) ) as u64)
    }

    // Computes LP when it's set
    public fun compute_derive_lp(
        lp_supply: u64,
        amount: u64,
        scaling_factor: u64,
        reserve: u64
    ): u128 {
        let amount_after_scaled = scale_amount(amount, scaling_factor);
        let reserve_after_scaled = scale_amount(reserve, scaling_factor);

        let multiplier = fixed_point64::create_from_rational( (lp_supply as u128), reserve_after_scaled );
        fixed_point64::multiply_u128( amount_after_scaled , multiplier )
    }

    fun scale_amount(amount: u64, scaling_factor: u64): u128 {
        ((amount as u128)*(scaling_factor as u128))
    }

    fun apply_weighting(amount: u128, weight_in: u64, weight_out: u64): u128 {
        let weight_factor = fixed_point64::create_from_rational((weight_out as u128), (weight_in as u128) );
        fixed_point64::multiply_u128( amount, weight_factor )
    } 
  
    // Return the value of n raised to power e in fixed point
    public fun pow(n: FixedPoint64, e: FixedPoint64): FixedPoint64 {
        // Check if the exponent is 0, return 1 if it is
        if (fixed_point64::equal(e, fixed_point64::create_from_u128(0)) ) {
            fixed_point64::create_from_u128(1)
        } else if (fixed_point64::equal(e, fixed_point64::create_from_u128(1))) {
            // If the exponent is 1, return the base value n
            n
        } else { 
            
            // Split the exponent into integer and fractional parts
            let integerPart = fixed_point64::floor( e );
            let fractionalPart = fixed_point64::sub(e, fixed_point64::create_from_u128(integerPart));

            // Calculate the integer power using math_fixed64 power function
            let result = math_fixed64::pow( n, (integerPart as u64) );
            // Calculate the fractional using internal nth root function
            let fractionalResult =  nth_root( n , fractionalPart );
            
            // Combine the integer and fractional powers using multiplication
            math_fixed64::mul_div( result, fractionalResult,  fixed_point64::create_from_u128(1)  )
        }

    }
 

    // Helper function to calculate  x^n, where n is fractional using binary search
    public fun nth_root( x: FixedPoint64, n: FixedPoint64): FixedPoint64 {
        if ( fixed_point64::equal(  fixed_point64::create_from_u128(0), n ) ) {
            fixed_point64::create_from_u128(1)
        } else {
            let nth = math_fixed64::mul_div( fixed_point64::create_from_u128(1), fixed_point64::create_from_u128(1), n );
            let nth_rounded = fixed_point64::round(nth); 
            
            let left = fixed_point64::create_from_u128(1); // Lower bound for the root
            let right = x; // Upper bound for the root

            if (fixed_point64::less_or_equal( x,  fixed_point64::create_from_u128(1))) {
                left = x;
                right = fixed_point64::create_from_u128(1);
            };

            let epsilon = fixed_point64::create_from_rational( 1, 100000000 );

            // Do binary search
            let guess = fixed_point64::create_from_raw_value( (fixed_point64::get_raw_value( left )+fixed_point64::get_raw_value(right))/2 );

            while ( fixed_point64::greater_or_equal( abs(  math_fixed64::pow( guess, (nth_rounded as u64) ) , x ) ,  epsilon ) ) {
                if ( fixed_point64::greater( math_fixed64::pow( guess, (nth_rounded as u64) ) , x) ) {
                    right = guess;
                } else {
                    left = guess;
                };
                guess = fixed_point64::create_from_raw_value( (fixed_point64::get_raw_value( left )+fixed_point64::get_raw_value(right))/2 );
            };
            guess
        }

    }

    fun abs( first_value: FixedPoint64, second_value:  FixedPoint64 ) : FixedPoint64 {
        if (fixed_point64::greater_or_equal(first_value, second_value)) { 
            fixed_point64::sub(first_value, second_value)
        } else {
            fixed_point64::sub(second_value, first_value)
        }
    }

    public fun get_fee_to_treasury(current_fee: u64, input: u64): (u64,u64) {
        let multiplier = fixed_point64::create_from_rational( (current_fee as u128) , (WEIGHT_SCALE as u128) );
        let fee = (fixed_point64::multiply_u128( (input as u128) , multiplier ) as u64);
        return ( input-fee,fee)
    }

    #[test(user = @0x123)]
    public entry fun test_pow(user: &signer) {

        let output_1 = pow( fixed_point64::create_from_u128(2), fixed_point64::create_from_u128(3));
        assert!( fixed_point64::round(output_1) == 8 , 0); // 8

        let output_2 = pow( fixed_point64::create_from_u128(2), fixed_point64::create_from_rational(5, 2));
        assert!( fixed_point64::floor(output_2) == fixed_point64::floor(fixed_point64::create_from_rational(28, 5)) , 1); // 5.6 

        let output_3 = pow( fixed_point64::create_from_u128(5), fixed_point64::create_from_u128(2));
        assert!( fixed_point64::round(output_3) == 25 , 2); // 25

        let output_4 = pow( fixed_point64::create_from_u128(10), fixed_point64::create_from_u128(0)); 
        assert!( fixed_point64::round(output_4) == 1 , 3); // 1

        let output_5 = pow( fixed_point64::create_from_u128(2), fixed_point64::create_from_u128(10));
        assert!( fixed_point64::round(output_5) == 1024 , 4); // 1024

        let output_6 = pow( fixed_point64::create_from_u128(9), fixed_point64::create_from_u128(5)); 
        assert!( fixed_point64::round(output_6) == 59049 , 5); // 59049
 
    }

}