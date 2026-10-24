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

> **Experimental.** A demo. Do not use it in production.

Contracts on [Elysium](https://elysium.kinetiq.xyz/docs/what-is-elysium) cannot read HyperCore,
Hyperliquid's exchange. This repo delivers HyperCore oracle prices to Elysium through Elysium's own
bridge. No signer, keeper or admin key is involved: anyone can trigger an update, and nobody can
change the prices.

## How it works

```
HyperEVM                                        Elysium
HyperCore ──read──► Beacon ──Inbox (bridge)──► Receiver ──priceOf()──► your contract
                      ▲
                anyone calls push()
```

1. `Beacon` on HyperEVM reads oracle prices from HyperCore's read precompiles (built-in contracts
   at fixed addresses).
2. In the same transaction it sends them to Elysium through Elysium's Inbox.
3. The bridge delivers the message from the Beacon's address plus a fixed offset. `Receiver`
   accepts messages from that address only.
4. `Receiver` stores each price with its HyperCore block, refuses data older than what it holds,
   and serves a price only within the age the reader asks for.

The caller of `push()` picks only the moment. The values come from HyperCore inside the same
transaction.

**Delay:** the bridge delivers in 65–78 s on testnet. Prices on Elysium trail HyperCore by about a
minute, so this fits slow data (funding, staking rates, settlement), not trading.

## Reading a price

```solidity
// Reverts if the market was never delivered or the price is older than 5 minutes.
uint64 px = receiver.priceOf(perpIndex, 5 minutes);
```

`px` is HyperCore's raw integer. Divide by `10^(6 - szDecimals)`, where `szDecimals` comes from
Hyperliquid's market metadata.

## Files

| File | Chain | Role |
|---|---|---|
| `src/HyperCore.sol` | HyperEVM | Reads oracle prices and the HyperCore block number |
| `src/Beacon.sol` | HyperEVM | Reads prices and sends them to Elysium. No state, no owner |
| `src/Receiver.sol` | Elysium | Accepts the Beacon's messages only, serves prices with an age check |
| `src/Alias.sol` | Elysium | The address offset the bridge applies to a sender |
| `src/IInbox.sol` | HyperEVM | The two Inbox functions the Beacon calls |
| `src/IReceiver.sol` | both | The message format |
| `script/push.sh` | off-chain | Optional: computes the fees and calls `push()` |

## Build and test

```bash
forge build
forge test
```

No dependencies.

## Deploy

The two contracts reference each other:

1. Predict the Beacon's address: `cast compute-address <deployer> --nonce <nonce on HyperEVM>`.
2. Deploy `Receiver` on Elysium with that address.
3. Deploy `Beacon` on HyperEVM with Elysium's Inbox and the Receiver's address.

The Inbox address is in Conduit's chain config:
[testnet](https://api.conduit.xyz/file/v1/arbitrum/chaininfo/elysium-testnet).

## Push

```bash
export ETH_KEYSTORE_ACCOUNT=<keystore name> ETH_PASSWORD=<password file>
HYPEREVM_RPC=<url> ELYSIUM_RPC=<url> BEACON=<address> PERPS=0,1 script/push.sh
```

Set `INTERVAL=<seconds>` to repeat. The script pays twice the quoted fees; Elysium refunds the
unused part to the sender. It stops on the first error.

## Testnet deployment

| Contract | Chain | Address |
|---|---|---|
| Beacon | HyperEVM testnet (998) | `0xA6Cc483A5257DFec4b7705468622aCCA2a4521d1` |
| Receiver | Elysium testnet (99801) | `0x12DdFB5e2Bf3544B5BE0Ac5aC9437d3c81fAdF47` |
| Inbox | HyperEVM testnet (998) | `0x11178Df40CBf87a4343f4B3F8B09B366ceFA8Ec0` |
