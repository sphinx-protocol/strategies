///////////////////////////////////////////////////////////////////////////////////////////////
// `Replicating` Strategy for Sphinx AMM                                                     //
///////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                           //
// Replicates the bid and ask spread from an external exchange using a single set of bid     //
// and ask orders, retrieved from an oracle feed. This srategy is ideal for assets that      //
// already trade on liquid markets.                                                          //
//                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////
//                                                             .                             //
//                                                             8                             //
//                                      .cd88888888888b.     .d8b.  .                        //
//                                  .cd888888888888888888b    '8'  .8.                       //
//                                 ———————————————————————-    '    '                        //
//                               d888888888888888888888888.                                  //
//                              d8888888888888 .b.  Y88888b                                  //
//                            .8888888888888   8888. Y88888b                                 //
//                            d888888888888   d88888888888888.                               //
//                           d8888888888888   “888888888888888b                              //
//                          d8888888888888888   Y88888888888888Y                             //
//                         .88888888888888888b  Y88888888888b                                //
//                         d888888888888888888b  Y88888888888b                               //
//                         88888888888888888888Y  Y8888888888b                               //
//                                      Y888888b          Y88b                               //
//                                       ———————           Y888b                             //
//                                       8888888                                             //
//                                       Y8888PY                                             //
//                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////

use starknet::ContractAddress;

#[starknet::interface]
trait IReplicatingStrategy<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn oracle(self: @TContractState) -> ContractAddress;
    fn bid_order_id(self: @TContractState) -> felt252;
    fn ask_order_id(self: @TContractState) -> felt252;
    fn update_interval(self: @TContractState) -> u64;
    fn last_updated(self: @TContractState) -> u64;
    fn get_quote(self: @TContractState) -> (u256, u256);

    fn deposit_initial(ref self: TContractState, base_amount: u256, quote_amount: u256) -> (u256, u256, u256);
    fn deposit(ref self: TContractState, base_amount: u256, quote_amount: u256) -> (u256, u256, u256);
    fn withdraw(ref self: TContractState, shares: u256) -> (u256, u256, u256);
    fn collect_positions(ref self: TContractState);
    fn change_oracle(ref self:TContractState, oracle: ContractAddress, oracle_pair_id: u32);
    fn set_update_interval(ref self: TContractState, update_interval: u64);
    fn set_owner(ref self: TContractState, owner: ContractAddress);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::contract]
mod ReplicatingStrategy {
    use array::SpanTrait;
    use zeroable::Zeroable;
    use integer::BoundedInt;
    use cmp::min;
    use starknet::ContractAddress;
    use starknet::info::get_caller_address;
    use starknet::info::get_contract_address;
    use starknet::info::get_block_number;

    use super::IReplicatingStrategy;
    use common::interfaces::IMarketManagerDispatcher;
    use common::interfaces::IMarketManagerDispatcherTrait;
    use common::interfaces::IStrategy;
    use common::interfaces::IERC20;
    use replicating::interfaces::IOracleDispatcher;
    use replicating::interfaces::IOracleDispatcherTrait;
    use sphinx::libraries::math::{math, price_math, liquidity_math}; // not yet public
    use pragma::Oracle; // placeholder
    use pragma::entry::structs::DataType; // placeholder

    #[storage]
    struct Storage {
        // Immutables
        owner: ContractAddress,
        market_manager: ContractAddress,
        market_id: felt252,

        // Oracle info
        oracle: ContractAddress,
        oracle_pair_id: u32,

        base_reserves: u256,
        quote_reserves: u256,
        
        // Active orders
        bid_order_id: felt252,
        ask_order_id: felt252,
        bid_batch_id: felt252,
        ask_batch_id: felt252,

        // Pool params

        // minimum block interval between updates
        update_interval: u64,
        // last block number when update was processed
        last_updated: u64,
        // whether pool is open for public contribution
        is_public: bool,
        // whether pool is paused
        is_paused: bool,

        // ERC20
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UpdatePositions: UpdatePositions,
        ManualCollectPositions: ManualCollectPositions,
        SetUpdateInterval: SetUpdateInterval,
        ChangeOracle: ChangeOracle,
        ChangeOwner: ChangeOwner,
        Pause: Pause,
        Unpause: Unpause,
        // erc20
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct UpdatePositions {
        bid_limit: u32,
        ask_limit: u32,
        bid_amount: u256,
        ask_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ManualCollectPositions { base_amount: u256, quote_amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct SetUpdateInterval {new_interval: u64}

    #[derive(Drop, starknet::Event)]
    struct ChangeOracle { oracle: ContractAddress, oracle_pair_id: u32 }

    #[derive(Drop, starknet::Event)]
    struct ChangeOwner { new_owner: ContractAddress }

    #[derive(Drop, starknet::Event)]
    struct Pause { }

    #[derive(Drop, starknet::Event)]
    struct Unpause { }

    #[derive(Drop, starknet::Event)]
    struct Transfer { from: ContractAddress, to: ContractAddress, value: u256 }

    #[derive(Drop, starknet::Event)]
    struct Approval { owner: ContractAddress, spender: ContractAddress, value: u256 }

    ////////////////////////////////
    // EXTERNAL
    ////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        market_manager: ContractAddress, 
        market_id: felt252, 
        oracle: ContractAddress,
        oracle_pair_id: u32,
        update_interval: u64,
    ) {
        self.owner.write(get_caller_address());
        self.market_manager.write(market_manager);
        self.market_id.write(market_id);
        self.oracle.write(oracle);
        self.oracle_pair_id.write(oracle_pair_id);
        self.update_interval.write(update_interval);

        self.emit(Event::ChangeOracle(ChangeOracle { oracle, oracle_pair_id }));
    }

    #[external(v0)]
    impl Strategy of IStrategy<ContractState> {
        // Get market manager contract address
        fn market_manager(self: @ContractState) -> ContractAddress { self.market_manager.read() }

        // Get market id
        fn market_id(self: @ContractState) -> felt252 { self.market_id.read() }
        
        // Updates positions. Called by MarketManager upon swap.
        fn update_positions(ref self: ContractState) {
            assert(get_caller_address() == self.market_manager.read(), 'ONLY_MARKET_MANAGER');

            // Positions can be set to update at regular block intervals rather than every block.
            let block = get_block_number();
            if self.last_updated.read() + self.update_interval.read() > block { return (); }
            if self.is_paused.read() { return (); }

            let (bid, ask) = self.get_quote();
            let mut bid_limit = price_math::price_to_limit(bid);
            let mut ask_limit = price_math::price_to_limit(ask);

            let market_manager = IMarketManagerDispatcher{ contract_address: self.market_manager.read() };
            let market_id = self.market_id.read();
            let bid_batch = market_manager.batch(self.bid_batch_id.read());
            let ask_batch = market_manager.batch(self.ask_batch_id.read());

            let curr_limit = market_manager.curr_limit(market_id);
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();

            // Cancel and replace bid orders if order is fully filled. 
            if bid_batch.limit != bid_limit || (bid_batch.limit == bid_limit && bid_batch.quote_amount == 0) {
                // Collect orders
                let (base_amount, quote_amount) = market_manager.collect_order(self.bid_order_id.read());
                base_reserves += base_amount;
                quote_reserves += quote_amount;

                // If bid price crosses the market price, place bid one limit below market price.
                if curr_limit == bid_limit { bid_limit -= 1; }
            }
            // Place new bid order or add to existing.
            if base_reserves > 0 {
                let (bid_order_id, bid_batch_id) = market_manager.create_order(market_id, true, base_reserves, bid_limit);
                self.bid_order_id.write(bid_order_id);
                self.bid_batch_id.write(bid_batch_id);
            }

            // Cancel and replace ask orders if order is fully filled. 
            if ask_batch.limit != ask_limit || (ask_batch.limit == ask_limit && ask_batch.base_amount == 0) {
                // Collect orders
                let (base_amount, quote_amount) = market_manager.collect_order(self.ask_order_id.read());
                base_reserves += base_amount;
                quote_reserves += quote_amount;

                // If ask price crosses the market price, place ask one limit above market price.
                if curr_limit == ask_limit { ask_limit += 1; }
            }
            // Place new ask order or add to existing.
            if quote_reserves > 0 {
                let (ask_order_id, ask_batch_id) = market_manager.create_order(market_id, false, quote_reserves, ask_limit);
                self.ask_order_id.write(ask_order_id);
                self.ask_batch_id.write(ask_batch_id);
            }

            // Commit state updates
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.last_updated.write(block);

            let bid_batch_end = market_manager.batch(self.bid_batch_id.read());
            let ask_batch_end = market_manager.batch(self.ask_batch_id.read());
            let bid_order_end = market_manager.order(self.bid_order_id.read());
            let ask_order_end = market_manager.order(self.ask_order_id.read());

            self.emit(Event::UpdatePositions(UpdatePositions {
                bid_limit: bid_batch_end.limit,
                ask_limit: ask_batch_end.limit,
                bid_amount: bid_order_end.amount_in,
                ask_amount: ask_order_end.amount_in,
            }));
        }

        fn cleanup(ref self: ContractState) {
            return ();
        }
    }

    #[external(v0)]
    impl ReplicatingStrategy of IReplicatingStrategy<ContractState> {
        // Contract owner
        fn owner(self: @ContractState) -> ContractAddress { self.owner.read() }

        // Contract address of oracle feed.
        fn oracle(self: @ContractState) -> ContractAddress { self.oracle.read() }

        // Order id of active bid order
        fn bid_order_id(self: @ContractState) -> felt252 { self.bid_order_id.read() }

        // Order id of active ask order
        fn ask_order_id(self: @ContractState) -> felt252 { self.ask_order_id.read() }

        // Block interval to process update
        fn update_interval(self: @ContractState) -> u64 { self.update_interval.read() }

        // Last block number when update was processed
        fn last_updated(self: @ContractState) -> u64 { self.last_updated.read() }

        // Get bid and ask quote from oracle feed.
        // 
        // # Returns
        // * `bid` - bid price
        // * `ask` - ask price
        fn get_quote(self: @ContractState) -> (u256, u256) {        
            let data_type : DataType = DataType::SpotEntry(self.oracle_pair_id.read());
            let oracle = IOracleDispatcher{ contract_address: self.oracle.read() };
            oracle.get_bid_ask_price(data_type)
        }

        // Deposit initial liquidity to pool.
        //
        // # Arguments
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `base_amount` - base asset deposited
        // * `quote_amount` - quote asset deposited
        // * `shares` - pool shares minted in the form of liquidity, which is always denominated in base asset
        fn deposit_initial(ref self: ContractState, base_amount: u256, quote_amount: u256) -> (u256, u256, u256) {
            let market_manager_addr = self.market_manager.read();
            let caller = get_caller_address();

            if self.is_public.read() { assert(self.owner.read() == caller, 'ONLY_OWNER'); }
            
            let market_manager = IMarketManagerDispatcher{ contract_address: market_manager_addr };
            let market_info = market_manager.market_info(self.market_id.read());
            let curr_limit = market_manager.curr_limit(self.market_id.read());

            // If bid price is valid, place order and collect liquidity.
            let liquidity = min(base_amount, liquidity_math::quote_to_base(quote_amount, curr_limit, market_info.width));

            _mint(ref self, caller, liquidity);

            self.base_reserves.write(base_amount);
            self.quote_reserves.write(quote_amount);

            (base_amount, quote_amount, liquidity)
        }

        // Deposit to strategy and mint pool shares.
        //
        // # Arguments
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `base_amount` - base asset deposited
        // * `quote_amount` - quote asset deposited
        // * `shares` - pool shares minted
        fn deposit(ref self: ContractState, base_amount: u256, quote_amount: u256) -> (u256, u256, u256) {
            let market_manager_addr = self.market_manager.read();
            let caller = get_caller_address();

            if self.is_public.read() { assert(self.owner.read() == caller, 'ONLY_OWNER'); }

            let market_manager = IMarketManagerDispatcher{ contract_address: market_manager_addr };
            let market_info = market_manager.market_info(self.market_id.read());
            let curr_limit = market_manager.curr_limit(self.market_id.read());

            let base_reserves = self.base_reserves.read();
            let quote_reserves = self.quote_reserves.read();

            let liquidity = min(
                math::mul_div(base_amount, total_supply, base_reserves), 
                math::mul_div(quote_amount, total_supply, quote_reserves)
            );

            _mint(ref self, caller, liquidity);

            self.base_reserves.write(base_reserves + base_amount);
            self.quote_reserves.write(quote_reserves + quote_amount);

            (base_amount, quote_amount, liquidity)
        }

        // Burn pool shares and withdraw funds from strategy.
        //
        // # Arguments
        // * `shares` - pool shares to burn
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        // * `shares` - pool shares burned
        fn withdraw(ref self: ContractState, shares: u256) -> (u256, u256, u256) {
            let market_manager = IMarketManagerDispatcher{ contract_address: self.market_manager.read() };
            let market_info = market_manager.market_info(self.market_id.read());
            let curr_limit = market_manager.curr_limit(self.market_id.read());

            let base_reserves = self.base_reserves.read();
            let quote_reserves = self.quote_reserves.read();

            let base_amount = math::mul_div(shares, base_reserves, total_supply);
            let quote_amount = math::mul_div(shares, quote_reserves, total_supply);

            _burn(ref self, get_caller_address(), shares);

            self.base_reserves.write(base_reserves - base_amount);
            self.quote_reserves.write(quote_reserves - quote_amount);

            (base_amount, quote_amount, shares)
        }

        // Manually trigger contract to collect all outstanding positions.
        // Only callable by contract owner.
        //
        // # Returns
        fn collect_positions(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();

            let market_manager = IMarketManagerDispatcher{ contract_address: self.market_manager.read() };
            let (bid_base_amount, bid_quote_amount) = market_manager.collect_order(self.bid_order_id.read());
            let (ask_base_amount, ask_quote_amount) = market_manager.collect_order(self.ask_order_id.read());

            base_reserves += bid_base_amount + ask_base_amount;
            quote_reserves += bid_quote_amount + ask_quote_amount;

            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);

            self.emit(Event::ManualCollectPositions(ManualCollectPositions {
                base_amount: bid_base_amount + ask_base_amount,
                quote_amount: bid_quote_amount + ask_quote_amount,
            }));
        }

        // Change the oracle feed contract and / or pair id.
        fn change_oracle(ref self: ContractState, oracle: ContractAddress, oracle_pair_id: u32) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            self.oracle.write(oracle);
            self.oracle_pair_id.write(oracle_pair_id);
            self.emit(Event::ChangeOracle(ChangeOracle { oracle, oracle_pair_id }));
        }

        // Change block interval for updating positions.
        fn set_update_interval(ref self: ContractState, update_interval: u64) {
            self.update_interval.write(update_interval);
            self.emit(Event::SetUpdateInterval(SetUpdateInterval { new_interval: update_interval }));
        }

        // Change contract owner.
        fn set_owner(ref self: ContractState, owner: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            self.owner.write(owner);
            self.emit(Event::ChangeOwner(ChangeOwner { new_owner: owner }));
        }

        // Pause strategy.
        fn pause(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            self.is_paused.write(true);
            self.emit(Event::Pause(Pause {}));
        }

        // Unpause strategy.
        fn unpause(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            self.is_paused.write(false);
            self.emit(Event::Unpause(Unpause {}));
        }
    }

    impl ERC20Impl of IERC20<ContractState> {

        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            _transfer(ref self, sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            _spend_allowance(ref self, sender, caller, amount);
            _transfer(ref self, sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            _approve(ref self, caller, spender, amount);
            true
        }

        fn increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) -> bool {
            _increase_allowance(ref self, spender, added_value)
        }

        fn decrease_allowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) -> bool {
            _decrease_allowance(ref self, spender, subtracted_value)
        }
    }

    ////////////////////////////////
    // INTERNAL FUNCTIONS
    ////////////////////////////////

    fn initializer(
        ref self: ContractState, name_: felt252, symbol_: felt252, decimals_: u8,
    ) {
        self.name.write(name_);
        self.symbol.write(symbol_);
        self.decimals.write(decimals_);
    }

    fn _increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.allowances.read((caller, spender)) + added_value);
        true
    }

    fn _decrease_allowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.allowances.read((caller, spender)) - subtracted_value);
        true
    }

    fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        self.total_supply.write(self.total_supply.read() + amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        self.emit(Event::Transfer(Transfer { from: Zeroable::zero(), to: recipient, value: amount }));
    }

    fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        self.total_supply.write(self.total_supply.read() - amount);
        self.balances.write(account, self.balances.read(account) - amount);
        self.emit(Event::Transfer(Transfer { from: account, to: Zeroable::zero(), value: amount }));
    }

    fn _approve(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!owner.is_zero(), 'ERC20: approve from 0');
        assert(!spender.is_zero(), 'ERC20: approve to 0');
        self.allowances.write((owner, spender), amount);
        self.emit(Event::Approval(Approval { owner, spender, value: amount }));
    }

    fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        self.balances.write(sender, self.balances.read(sender) - amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
    }

    fn _spend_allowance(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = self.allowances.read((owner, spender));
        if current_allowance != BoundedInt::max() {
            _approve(ref self, owner, spender, current_allowance - amount);
        }
    }
}