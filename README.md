<img width="1200" alt="Labs" src="https://user-images.githubusercontent.com/99700157/213291931-5a822628-5b8a-4768-980d-65f324985d32.png">

<p>
 <h3 align="center">Chainstack is the leading suite of services connecting developers with Web3 infrastructure</h3>
</p>

<p align="center">
  • <a target="_blank" href="https://chainstack.com/">Homepage</a> •
  <a target="_blank" href="https://chainstack.com/protocols/">Supported protocols</a> •
  <a target="_blank" href="https://chainstack.com/blog/">Chainstack blog</a> •
  <a target="_blank" href="https://docs.chainstack.com/quickstart/">Blockchain API reference</a> • <br> 
  • <a target="_blank" href="https://console.chainstack.com/user/account/create">Start for free</a> •
</p>

# HyperCore prices on Elysium

> **Experimental.** A testnet proof of concept, not audited. Do not use it in production.

Contracts on HyperEVM can read HyperCore prices through precompiles. Contracts on Elysium
cannot. This repository delivers those prices to Elysium without Elysium precompiles, using the
parent-to-child messaging built into every Arbitrum Nitro chain.

A working pair is live on testnet, and the [quick start](#quick-start) reads it with no key or
funds. There is no mainnet deployment. New to these chains? See [terms](#terms) at the end.

## Why Elysium can't read HyperCore

HyperEVM contracts read HyperCore through
[precompiles](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore):
a `staticcall` to address `0x807` with a market index returns that market's oracle price. This
works because every HyperEVM node also runs HyperCore and answers from its own copy.

Elysium nodes run Nitro, not HyperCore, so the same call on Elysium has nothing to answer it.
Kinetiq [plans a HyperCore precompile](https://elysium.kinetiq.xyz/docs/what-is-elysium) about four
weeks after Elysium's mainnet launch.

## How it works

Every Nitro chain has a
[delayed inbox](https://docs.arbitrum.io/how-arbitrum-works/deep-dives/l1-to-l2-messaging#transacting-via-the-delayed-inbox):
a queue on the parent chain for messages to the child chain. Deposits arrive this way, and any
contract can use it:

1. A contract on the parent chain calls `createRetryableTicket` on the chain's
   [Inbox](https://github.com/OffchainLabs/nitro-contracts/blob/main/src/bridge/Inbox.sol).
2. The sequencer waits until the parent-chain block holding the message is safe from
   reorganisation, then includes it. That wait is sequencer configuration
   ([`delayed-sequencer`](https://github.com/OffchainLabs/nitro/blob/master/arbnode/delayed_sequencer.go)):
   65–78 s on Elysium testnet. Mainnet may differ, so measure it there before relying on it.
3. The child chain runs the message as a transaction, a
   [retryable ticket](https://docs.arbitrum.io/how-arbitrum-works/deep-dives/l1-to-l2-messaging#retryable-tickets),
   with gas the sender paid upfront on the parent chain.
4. On the child chain, `msg.sender` is the sender's address plus
   `0x1111000000000000000000000000000000001111`
   ([address aliasing](https://docs.arbitrum.io/how-arbitrum-works/deep-dives/l1-to-l2-messaging#address-aliasing)),
   so a receiving contract can accept messages from one parent-chain contract only.

Elysium uses this part of Nitro unchanged, so Arbitrum's docs and tools apply as written.

This repo puts one contract on each side:

```
HyperEVM                                        Elysium
HyperCore ──read──► Beacon ──Inbox (bridge)──► Receiver ──priceOf()──► consumer
                      ▲
                anyone calls push()
```

`Beacon.push()` reads prices from the HyperCore precompiles and sends them through the Inbox in
the same transaction. Anyone can call it and pay the fees; nobody can change the prices.

`Receiver` accepts messages only from the Beacon's aliased address. It stores each price with
the HyperCore block, the HyperEVM time it was read and the Elysium time it arrived, and refuses
anything not newer than what it holds.

No server, signer or admin key is needed for the prices to be correct. Trust rests on HyperEVM
and the bridge.

## Trade-offs

| | Native precompile | This repo |
|---|---|---|
| Freshness | Live | Last push + bridge delay (65–78 s on testnet) |
| Who pays | Reader, in gas | Pusher, in HYPE on HyperEVM |
| Data | All of HyperCore | Perp oracle prices; more needs code |
| Updates | Always current | Only when someone pushes |

It fits slow values like funding or staking rates, not trading. Lido uses the same pattern for
its [wstETH rate on Optimism](https://docs.lido.fi/guides/verify-steth-on-optimism-upgrade-manual).

Nobody pushes the demo pair on a schedule, so its prices are usually old. An application that
reads these prices runs the pushes itself, for example `script/push.sh` on a timer. Failure
cases and every error are in [`src/TROUBLESHOOTING.md`](src/TROUBLESHOOTING.md).

## Quick start

Install [Foundry](https://getfoundry.sh/introduction/installation) (`forge` builds and deploys,
`cast` reads the chains and sends transactions) and [`jq`](https://jqlang.org/download/). Then
clone and run the tests. They fake HyperCore and the bridge, so they need no chain; the first
run downloads the Solidity compiler:

```bash
git clone https://github.com/chainstacklabs/elysium-hypercore-reads.git
cd elysium-hypercore-reads
forge test
```

Run everything below from this folder: `foundry.toml` names the public testnet RPCs
`hyperevm_testnet` and `elysium_testnet`. Outputs change with every run.

**Read prices on HyperEVM.** `read` shows what a push would send right now:

```bash
BEACON=0xA6Cc483A5257DFec4b7705468622aCCA2a4521d1    # HyperEVM testnet
RECEIVER=0x12DdFB5e2Bf3544B5BE0Ac5aC9437d3c81fAdF47  # Elysium testnet

cast call $BEACON "read(uint32[])(uint64[],uint64)" "[0,1]" -r hyperevm_testnet
# [1014550 [1.014e6], 7167]    prices of markets 0 and 1
# 746303906 [7.463e8]          HyperCore block they were read at
```

`cast` adds hints like `[1.014e6]`; ignore them.

**Convert to dollars.** HyperCore keeps a perp price with `6 - szDecimals` decimal places
([tick and lot size](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/tick-and-lot-size)).
The market list gives each market's index (its position) and `szDecimals`:

```bash
curl -s https://api.hyperliquid-testnet.xyz/info -H 'Content-Type: application/json' \
  -d '{"type":"meta"}' | jq -r '.universe | to_entries[] | "\(.key) \(.value.name) \(.value.szDecimals)"'
# 0 SOL 2
# 1 APT 2
# ...
```

On testnet market 0 is SOL with `szDecimals` 2, so `1014550 / 10^4` = 101.455 USD. Mainnet has
a different list (`https://api.hyperliquid.xyz/info`), where market 0 is BTC.

**Read the same market on Elysium.**

```bash
cast call $RECEIVER "readingOf(uint32)((uint64,uint64,uint64,uint64))" 0 -r elysium_testnet
# (1019050, 746187272, 1792829003, 1792829077)   price, HyperCore block, read at, arrived at

cast call $RECEIVER "priceOf(uint32,uint64)(uint64)" 0 300 -r elysium_testnet
# Error: execution reverted: TooOld(0, 7514, 300)
```

The last two numbers of `readingOf` are Unix seconds; their difference, 74 s, is that push's
bridge delay. `priceOf` refuses the demo price because it is 7514 s old and the call allows 300.
[Push](#push-and-deploy) to get a fresh one.

**Check the wiring.** The Beacon names the Receiver, and the Receiver names the Beacon's aliased
address, the only sender it accepts:

```bash
cast call $BEACON "receiver()(address)" -r hyperevm_testnet  # 0x12DdFB5e…F47
cast call $RECEIVER "beacon()(address)" -r elysium_testnet   # 0xB7dd483a…2E2 = Beacon + 0x1111…1111
```

## Use it from a contract

Call `priceOf(uint32 perp, uint64 maxAge)` on the Receiver. It returns the raw `uint64` price;
divide it by `10^(6 - szDecimals)` as above. Take the index and `szDecimals` from the market list
of the network in use; the contracts do not store them.

`maxAge` is in seconds and counts from when HyperEVM read the price, so it includes the bridge
delay. Set it above the push interval plus that delay: with a push every 60 s, 5 minutes leaves
room for one missed push.

`priceOf` never returns a stale or empty value. It reverts with `TooOld` or
`NothingForThisMarket`, and so does the consumer's call, so decide which actions should stop
while prices are stale. For a custom age check, `readingOf(perp)` returns all four stored
numbers with none applied.

## Push and deploy

**Key and funds.** Create a key, then request testnet HYPE for its address from the
[Chainstack faucet](https://faucet.chainstack.com/) (Hyperliquid testnet):

```bash
cast wallet new deployer                # create the key, protected by a password
export ETH_KEYSTORE_ACCOUNT=deployer    # cast, forge and push.sh sign with it
cast wallet address --account deployer  # the address to fund
```

**Push.** The script works out the fees and calls `push()`; `cast` asks for the key's password.
After the bridge delay, `readingOf` shows the new price. Add `INTERVAL=60` to push every 60 s:

```bash
HYPEREVM_RPC=hyperevm_testnet ELYSIUM_RPC=elysium_testnet \
  BEACON=$BEACON PERPS=0,1 script/push.sh
```

The fee buys Elysium's acceptance of the message and the Elysium gas for `Receiver.update`. The
script adds margins for fee changes; the unused part is refunded to the same address on Elysium.

**Deploy a new pair.** The Receiver goes on Elysium, so first bridge some HYPE there through the
same delayed inbox:

```bash
H=hyperevm_testnet E=elysium_testnet
INBOX=0x11178Df40CBf87a4343f4B3F8B09B366ceFA8Ec0  # Elysium's Inbox on HyperEVM testnet
ME=$(cast wallet address --account deployer)

cast send $INBOX "depositEth()" --value 0.005ether -r $H
cast balance $ME -r $E  # wait until this is not 0
```

Each contract needs the other's address, so predict the Beacon's from the key's next HyperEVM
nonce. Send nothing else from this key on HyperEVM until the Beacon is deployed:

```bash
BEACON=$(cast compute-address $ME --nonce $(cast nonce $ME -r $H) | awk '{print $NF}')

RECEIVER=$(forge create src/Receiver.sol:Receiver -r $E --broadcast --json \
  --constructor-args $BEACON | jq -r .deployedTo)

forge create src/Beacon.sol:Beacon -r $H --broadcast \
  --constructor-args $INBOX $RECEIVER  # must print "Deployed to: $BEACON"
```

`BEACON` and `RECEIVER` now hold the new pair, so the commands above work on it unchanged.

**Dedicated nodes.** The public RPCs are rate limited. An AI coding agent with the
[Chainstack MCP server](https://docs.chainstack.com/docs/chainstack-mcp-server) and an
[API key](https://console.chainstack.com/user/settings/api-keys) can request testnet HYPE and
deploy dedicated HyperEVM and Elysium nodes. Use their URLs in place of `hyperevm_testnet` and
`elysium_testnet`, with `/evm` appended to the Hyperliquid node's URL.

```bash
claude mcp add --transport http chainstack https://mcp.chainstack.com/mcp \
  --header "Authorization: Bearer <API key>"
```

## Terms

| Term | What it is |
|---|---|
| [Hyperliquid](https://hyperliquid.gitbook.io/hyperliquid-docs) | A blockchain built around a trading exchange. It runs HyperCore and HyperEVM under one consensus |
| HyperCore | The exchange part: order books, balances and prices. Not an EVM, and has its own block numbers |
| [HyperEVM](https://hyperliquid.gitbook.io/hyperliquid-docs/hyperevm) | The smart-contract part of Hyperliquid. Coin HYPE, testnet chain ID 998 |
| [Precompile](https://www.evm.codes/precompiled) | A built-in contract at a fixed address, implemented by the chain itself |
| [Perp](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/perpetual-assets) | A perpetual futures market on HyperCore, numbered by its index in the market list |
| [Oracle price](https://hyperliquid.gitbook.io/hyperliquid-docs/hypercore/oracle) | The price HyperCore's validators publish per perp every 3 seconds, from large exchanges. The price this repo carries |
| [Elysium](https://elysium.kinetiq.xyz/docs/what-is-elysium) | Kinetiq's Arbitrum Nitro chain with HyperEVM as its parent. Gas in HYPE, testnet chain ID 99801 |
| [Arbitrum Nitro](https://docs.arbitrum.io/welcome/arbitrum-gentle-introduction) | The software behind Arbitrum and many other chains. Each settles to a parent chain and takes messages from it |
| [Sequencer](https://docs.arbitrum.io/how-arbitrum-works/sequencer) | The node that orders a Nitro chain's transactions. Elysium's is run by Conduit |

## License

Apache 2.0. See [LICENSE](LICENSE).
