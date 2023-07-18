use pragma::entry::structs::DataType; // placeholder

// Sample only. Replace with actual Pragma interface once live.
#[starknet::interface]
trait IOracle<TContractState> {
    fn get_bid_ask_price(self : @TContractState, data_type : DataType) -> (u256, u256);
}
