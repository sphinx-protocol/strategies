use starknet::ContractAddress;

#[starknet::interface]
trait IStrategy<TContractState> {
    fn market_manager(self: @TContractState) -> ContractAddress;
    fn market_id(self: @TContractState) -> felt252;
    fn strategy_name(self: @TContractState) -> felt252;
    fn update_positions(ref self: TContractState);
    fn cleanup(ref self: TContractState);
}
