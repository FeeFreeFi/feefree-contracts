# [FeeFree](https://app.feefree.fi/)
FeeFree aims to build a RobinHood-Style DEX in blockchain industry, enable every individual in the world to participate in DeFi!

In the Ethereum ecosystem, Uniswap is the leading DEX, but it charges fees ranging from 0.05% to 1% on LPs.FeeFree adopts a unique zero-fee swapping model. The revenue strategy is to charge a slight flat gas-fee per transaction (< 0.1usd/txn) regardless of the transaction volume instead of charging transaction volume-based fees like most DEXs.

## Objectives
Our goal is to provide zero-fee transactions to each user of the world.

We believe that there is currently a lack of zero-fee DEX in the market and we aim to have more than 10,000 active users. We primarily focus on zero-fee transactions for DEX. How do we achieve zero-fee transactions? We set the fee rate of liquidity pool to zero.

While, what incentives do LPs have to provide liquidity? We plan to use the funding we receive to add initial liquidity and may set a certain lock-up period. We will also use all the transaction gas-fee received from FeeFree to reward the liquidity providers.

Additionally, we intend to use a portion of the funding to reward the initial liquidity providers, attracting more participants to provide liquidity during the initial phase.

## Usage
```shell
cp .env.example .env

forge install foundry-rs/forge-std transmissions11/solmate Openzeppelin/openzeppelin-contracts

forge build

source .env

# forge script script/xxx.s.sol:xxx --broadcast -vvvv --rpc-url $XXX_RPC_URL
```

## Reference
[Uniswap/v4-core](https://github.com/Uniswap/v4-core)

[transmissions11/solmate](https://github.com/transmissions11/solmate)

[Openzeppelin/openzeppelin-contracts](https://github.com/Openzeppelin/openzeppelin-contracts)

## LICENSE
FeeFree Contracts is released under the [MIT License](LICENSE).

Copyright ©2024 [FeeFree](https://github.com/FeeFreeFi)