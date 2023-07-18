use traits::Into;

use sphinx::libraries::math::{liquidity_math, math}; // not yet public
use types252::{UD47x28, UD47x28Trait, ONE};
use types252::{i256, I256Trait};

////////////////////////////////
// DESCRIPTION
////////////////////////////////

// The Allevaneda & Stoikov market making model defines a market making strategy given by a reservation price
// and an optimal spread, which in combination define a set of optimal bid and ask prices. 

// The reservation price `r` is given by:  r = s - q * y * σ^2
//
//   where: 
//     s = current market price
//     q = delta between inventory of quote asset and optimal (+ve means we are overexposed, -ve means under)
//     y = risk aversion parameter (optimal value is 0.1 based on statistical modelling)
//     σ = volatility of the asset

// The optimal spread `D` is given by:  D = y * σ^2 + (2 / y) * ln(1 + y / k)
//
//   where:
//     k = order arrival intensity parameter

// This original formula includes a parameter (T - t) which refers to the assumed time to expiry for the trading
// session. For this example we have set the paramter to 1 to signify continuous trading, but a more precise
// approximation would be to use the modified formula assuming an infinite trading horizon (TODO).

////////////////////////////////
// FUNCTIONS
////////////////////////////////

// Computes the reservation price `r` from a given set of parameters.
// All params are encoded as UD47x28 fixed point numbers.
//
// # Arguments
// * `curr_price` - the current market price (s)
// * `inventory_delta` - the delta between the current inventory of quote assets and the optimal (q)
// * `volatility_sq` - the volatility of the asset squared (σ^2)
// * `risk_aversion` - the risk aversion parameter (y)
//
// # Returns
// * `r` - the reservation price
fn reservation_price(
    curr_price: u256,
    inventory_delta: i256,
    volatility_sq: u256,
    risk_aversion: u256,
) -> u256 {
    let s = UD47x28Trait::new(curr_price);
    let q_abs = UD47x28Trait::new(inventory_delta.val);
    let sig2 = UD47x28Trait::new(volatility_sq);
    let y = UD47x28Trait::new(risk_aversion);

    let r = if inventory_delta.sign { s + q_abs * y * sig2 } else { s - q_abs * y * sig2 };
    r.val.into()
}

// Computes the optimal spread `D` from a given set of parameters.
// All params are encoded as UD47x28 fixed point numbers.
//
// # Arguments
// * `volatility_sq` - the volatility of the asset squared (σ^2)
// * `risk_aversion` - the risk aversion parameter (y)
// * `arrival_intensity` - the order arrival intensity parameter (k)
//
// # Returns
// * `r` - the reservation price
fn optimal_spread(
    volatility_sq: u256,
    risk_aversion: u256,
    arrival_intensity: u256,
) -> u256 {
    let sig2 = UD47x28Trait::new(volatility_sq);
    let y = UD47x28Trait::new(risk_aversion);
    let k = UD47x28Trait::new(arrival_intensity);

    // Currently using log2(), replace with ln() once implemented 
    let D = y * sig2 + (UD47x28Trait::new(2 * ONE) / y) * (UD47x28Trait::one() + y / k).log2();
    D.val.into()
}

// Computes q, the inventory delta between the current inventory of quote assets and the optimal.
//
// # Arguments
// * `curr_price` - the current market price
// * `width` - the current width of the order book
// * `base_amount` - the current inventory of base assets, including reserves and open orders
// * `quote_amount` - the current inventory of quote assets, including reserves and open orders
// * `target_inventory_ratio` - the target ratio of quote assets to total assets
//
// # Returns
// * `q` - the inventory delta (+ve means we are overexposed to quote asset, -ve means under)
fn inventory_delta(
    curr_price: u256,
    width: u32,
    base_amount: u256,
    quote_amount: u256,
    target_inventory_ratio: u256,
) -> i256 {
    let base_amount_equiv = liquidity_math::base_to_quote(base_amount, curr_limit, width);
    let target_quote_amount = math::mul_div(target_inventory_ratio, base_amount_equiv + quote_amount, ONE);
    I256Trait::new(quote_amount, false) - I256Trait::new(target_quote_amount, false)
}
