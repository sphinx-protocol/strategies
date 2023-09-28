////////////////////////////////
// IMPORTS
////////////////////////////////

// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use strategies::types::i256::i256;


////////////////////////////////
// TYPES
////////////////////////////////

// Immutable information about a market. 
// 
// * `base_token` - address of base token
// * `quote_token` - address of quote token
// * `width` - width of limits denominated in 1/10 bp
// * `strategy` - liquidity strategy contract
// * `swap_fee_rate` - swap fee denominated in bps (overridden by fee controller)
// * `fee_controller` - fee controller contract, if unset then swap fee is 0.
#[derive(Copy, Drop, Serde)]
struct MarketInfo {
    base_token: ContractAddress,
    quote_token: ContractAddress,
    width: u32,
    strategy: ContractAddress,
    swap_fee_rate: u16,
    fee_controller: ContractAddress,
}

// Mutable state of a market.
//
// * `liquidity` - active liquidity in market (encoded as UD47x28)
// * `curr_limit` - current limit (shifted)
// * `curr_sqrt_price` - current sqrt price of market (encoded as UD47x28)
// * `protocol_share` - protocol share denominated 0.01% shares of swap fees (e.g. 500 = 5%)
// * `base_fee_factor` - accumulated base fees per unit of liquidity (encoded as UD47x28)
// * `quote_fee_factor` - accumulated quote fees per unit of liquidity (encoded as UD47x28)
#[derive(Copy, Drop, Serde, PartialEq)]
struct MarketState {
    liquidity: u256,
    curr_limit: u32,
    curr_sqrt_price: u256,
    protocol_share: u16,
    base_fee_factor: u256,
    quote_fee_factor: u256,
}

// An individual price limit.
//
// * `liquidity` - total liquidity referenced by limit (encoded as UD47x28)
// * `liquidity_delta` - liquidity added or removed from limit when it is traversed (encoded as UD47x28)
// * `base_fee_factor` - as above, but for base fees (encoded as UD47x28)
// * `quote_fee_factor` - cumulative fee factor below or above current price depending on curr price (encoded as UD47x28) 
// * `nonce` - current nonce of limit, used for batching limit orders
#[derive(Copy, Drop, Serde)]
struct LimitInfo {
    liquidity: u256,
    liquidity_delta: i256,
    base_fee_factor: u256,
    quote_fee_factor: u256,
    nonce: u128,
}

// A liquidity position.
//
// * `market_id` - market id of position
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity` - amount of liquidity in position (encoded as UD47x28)
// * `base_fee_factor_last` - base fee factor of position at last update (encoded as UD47x28)
// * `quote_fee_factor_last` - quote fee factor of position at last update (encoded as UD47x28)
#[derive(Copy, Drop, Serde)]
struct Position {
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
    base_fee_factor_last: u256,
    quote_fee_factor_last: u256,
}

// Information about batched limit orders within a nonce.
//
// * `amount_in` - total amount in of limit orders in batch
// * `amount_filled` - total amount filled of limit orders in batch
// * `limit` - limit of batch
// * `is_bid` - whether limit orders are bids or asks
// * `base_amount` - total base amount
// * `quote_amount` - total quote amount
#[derive(Copy, Drop, Serde, PartialEq)]
struct OrderBatch {
    amount_in: u256,
    amount_filled: u256,
    limit: u32,
    is_bid: bool,
    base_amount: u256,
    quote_amount: u256,
}

// A limit order.
//
// * `batch_id` - order batch to which order belongs
// * `amount_in` - amount in of order
#[derive(Copy, Drop, Serde)]
struct LimitOrder {
    batch_id: felt252,
    amount_in: u256,
}

// Information about a partial fill.
//
// * `limit` - limit price
// * `amount_in` - amount swapped in from partial fill, inclusive of fees
// * `amount_out` - amount swapped out from partial fill
// * `is_buy` - whether partial fill is buy or sell
#[derive(Copy, Drop, Serde)]
struct PartialFillInfo {
    limit: u32,
    amount_out: u256,
    amount_in: u256,
    is_buy: bool,
}

// Position info returned for ERC721.
//
// * `base_token` - address of base token
#[derive(Copy, Drop, Serde)]
struct PositionInfo {
    base_token: ContractAddress,
    quote_token: ContractAddress,
    width: u32,
    strategy: ContractAddress,
    swap_fee_rate: u16,
    fee_controller: ContractAddress,
    liquidity: u256,
    base_amount: u256,
    quote_amount: u256,
    base_fee_factor_last: u256,
    quote_fee_factor_last: u256,
}