use starknet::ContractAddress;

use types252::i256;
use sphinx::types::{MarketInfo, MarketState, LimitOrder, OrderBatch}; // not yet public

#[starknet::interface]
trait IStrategy<TContractState> {
    fn market_manager(self: @TContractState) -> ContractAddress;
    fn market_id(self: @TContractState) -> felt252;
    fn update_positions(ref self: TContractState);
    fn cleanup(ref self: TContractState);
}

#[starknet::interface]
trait IMarketManager<TContractState> {
    fn order(self: @TContractState, order_id: felt252) -> LimitOrder;
    fn batch(self: @TContractState, batch_id: felt252) -> OrderBatch;
    fn market_info(self: @TContractState, market_id: felt252) -> MarketInfo;
    fn market_state(self: @TContractState, market_id: felt252) -> MarketState;
    fn curr_limit(self: @TContractState, market_id: felt252) -> u32;
    fn curr_price(self: @TContractState, market_id: felt252) -> u256;

    fn modify_position(
        ref self: TContractState, market_id: felt252, start_limit: u32, end_limit: u32, liquidity_delta: i256,
    ) -> (i256, i256, u256, u256);
    fn create_order(ref self: TContractState, market_id: felt252, is_bid: bool, amount: u256, limit: u32) -> (felt252, felt252);
    fn collect_order(ref self: TContractState, order_id: felt252) -> (u256, u256);
    fn swap(
        ref self: TContractState, market_id: felt252, is_buy: bool, amount: u256, exact_input: bool, threshold_limit: u32,
    ) -> (u256, u256, u256);
}


#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;

    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: u256) -> bool;
    fn decrease_allowance(ref self: TContractState, spender: ContractAddress, subtracted_value: u256) -> bool;
}