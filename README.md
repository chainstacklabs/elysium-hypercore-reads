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

> **Experimental.** A proof of concept, deployed on testnet only and not audited. Do not use it in
> production.

Contracts on [Elysium](https://elysium.kinetiq.xyz/docs/what-is-elysium) cannot read HyperCore,
Hyperliquid's exchange. This repo delivers HyperCore oracle prices to Elysium through Elysium's own
bridge. No signer, keeper or admin key is involved: anyone can trigger an update, but the Beacon
reads the values from HyperCore itself, so nobody can change them.

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
3. The bridge delivers the message from the Beacon's address plus a fixed offset (Arbitrum's
   address aliasing, see `src/Alias.sol`). `Receiver` accepts messages from that address only.
4. `Receiver` stores each price with its HyperCore block, refuses data older than what it holds,
   and serves a price only within the age the reader asks for.

**Delay:** the bridge delivers in 65–78 s on testnet. Prices on Elysium trail HyperCore by over a
minute, so this fits slow data (funding, staking rates, settlement), not trading.

## Try it

The testnet deployment is live, and reading it needs no wallet. Run from this folder, so
cast finds the public RPCs named in `foundry.toml`:

```bash
# What push() would send right now: prices for markets 0 and 1 (SOL and APT on testnet; BTC
# is 3), and the HyperCore block
cast call 0xA6Cc483A5257DFec4b7705468622aCCA2a4521d1 "read(uint32[])(uint64[],uint64)" "[0,1]" \
  --rpc-url hyperevm_testnet

# The last SOL price delivered: (price, HyperCore block, read at, arrived at)
cast call 0x12DdFB5e2Bf3544B5BE0Ac5aC9437d3c81fAdF47 \
  "readingOf(uint32)((uint64,uint64,uint64,uint64))" 0 --rpc-url elysium_testnet
```

## Reading a price from a contract

```solidity
Receiver receiver = Receiver(0x12DdFB5e2Bf3544B5BE0Ac5aC9437d3c81fAdF47); // Elysium testnet

// Reverts if the market was never delivered or the price is older than 5 minutes.
uint64 px = receiver.priceOf(perp, 5 minutes);
```

- `perp` is the market's index in HyperCore's market list, and `px` is a raw integer: divide it
  by `10^(6 - szDecimals)`. HyperCore's `meta` query lists both: market `perp` is
  `universe[perp]`, with its `szDecimals`. Send `{"type":"meta"}` to the `/info` endpoint of a
  Chainstack Hyperliquid node or of `https://api.hyperliquid-testnet.xyz`.
- Age counts from the HyperEVM read, so it includes the bridge trip. A `maxAge` shorter than the
  delay always reverts.
- `readingOf(perp)` returns the stored reading with no age check, for readers that judge age
  themselves.

## Set up with Chainstack

The quickest setup is an AI coding agent with the
[Chainstack MCP server](https://docs.chainstack.com/docs/chainstack-mcp-server). With an API key,
the agent deploys your RPC nodes and tops up a testnet wallet, so you can deploy and push without
leaving the editor.

1. [Sign up](https://console.chainstack.com/user/account/create) and create an API key at
   [console.chainstack.com/user/settings/api-keys](https://console.chainstack.com/user/settings/api-keys).
2. Add the server. For Claude Code:

   ```bash
   claude mcp add --transport http chainstack https://mcp.chainstack.com/mcp -s user \
     --header "Authorization: Bearer <API key>"
   ```

   For Cursor, Codex, Gemini CLI, VS Code and others, see the
   [setup page](https://docs.chainstack.com/docs/chainstack-mcp-server).
3. Ask the agent:

   > Deploy Chainstack Global nodes on hyperliquid-testnet and elysium-testnet, give me their
   > RPC URLs, and top up `<your address>` with testnet HYPE on hyperevm.

Use the Hyperliquid node's URL with `/evm` appended as `HYPEREVM_RPC`, and the Elysium node's
URL as `ELYSIUM_RPC`. The faucet tops an address up to a fixed cap, once per network every 24
hours.

HYPE on HyperEVM is all a push needs, because the Beacon pays Elysium's gas from it. Deploying
your own Receiver also needs a little HYPE on Elysium. Bridge it over from the same address:

```bash
cast send 0x11178Df40CBf87a4343f4B3F8B09B366ceFA8Ec0 "depositEth()" --value 0.005ether \
  --rpc-url $HYPEREVM_RPC
```

It arrives at the same address on Elysium after the bridge delay.

## Files

| File | Chain | Role |
|---|---|---|
| `src/HyperCore.sol` | HyperEVM | Reads oracle prices and the HyperCore block number |
| `src/Beacon.sol` | HyperEVM | Reads prices and sends them to Elysium. No state, no owner |
| `src/Receiver.sol` | Elysium | Accepts the Beacon's messages only, serves prices with an age check |
| `src/Alias.sol` | Elysium | The address offset the bridge applies to a sender |
| `src/IInbox.sol` | HyperEVM | The two Inbox functions the Beacon calls |
| `src/IReceiver.sol` | both | The message format |
| `script/push.sh` | off-chain | Optional: works out the fees and calls `push()` |
| `test/` | local | The round trip and the Receiver's checks, with HyperCore and the bridge faked |

## Build and test

Needs [Foundry](https://getfoundry.sh). No other dependencies.

```bash
forge build
forge test
```

## Deploy

Each contract needs the other's address, so predict the Beacon's first. Run in bash, with a key
from `cast wallet new` or `cast wallet import`. Bridge HYPE to Elysium before step 1 (see
[Set up with Chainstack](#set-up-with-chainstack)): the deposit is a HyperEVM transaction, and
step 2 needs the funds.

```bash
HYPEREVM_RPC=hyperevm_testnet ELYSIUM_RPC=elysium_testnet   # from foundry.toml, or node URLs
DEPLOYER=<your address>
INBOX=0x11178Df40CBf87a4343f4B3F8B09B366ceFA8Ec0   # from Conduit's chain config, linked below
KEY=(--keystore <keystore file> --password-file <password file> --broadcast)

# 1. The address the deployer's next contract on HyperEVM will get
BEACON=$(cast compute-address $DEPLOYER --nonce $(cast nonce $DEPLOYER --rpc-url $HYPEREVM_RPC) \
  | awk '{print $NF}')

# 2. Receiver on Elysium, trusting that address
forge create src/Receiver.sol:Receiver --rpc-url $ELYSIUM_RPC "${KEY[@]}" --constructor-args $BEACON

# 3. Beacon on HyperEVM, with the Receiver address printed by step 2
forge create src/Beacon.sol:Beacon --rpc-url $HYPEREVM_RPC "${KEY[@]}" \
  --constructor-args $INBOX <receiver address>
```

Send nothing else from the deployer on HyperEVM between steps 1 and 3. Step 3 must print
`Deployed to: $BEACON`; any other address means the Receiver trusts the wrong sender, so
deploy both again.

Conduit's chain config for Elysium testnet, with the Inbox address:
[elysium-testnet](https://api.conduit.xyz/file/v1/arbitrum/chaininfo/elysium-testnet).

## Push

```bash
export ETH_KEYSTORE=<keystore file> ETH_PASSWORD=<password file>
HYPEREVM_RPC=<url> ELYSIUM_RPC=<url> BEACON=<address> PERPS=0,1 script/push.sh
```

`ETH_KEYSTORE_ACCOUNT=<name>` works instead of `ETH_KEYSTORE` for a key in
`~/.foundry/keystores`. Set `INTERVAL=<seconds>` to repeat. The script pays twice the quoted
fees; Elysium refunds the unused part to the sender. It stops on the first error. Needs `jq`.

## Testnet deployment

| Contract | Chain | Address |
|---|---|---|
| Beacon | HyperEVM testnet (998) | `0xA6Cc483A5257DFec4b7705468622aCCA2a4521d1` |
| Receiver | Elysium testnet (99801) | `0x12DdFB5e2Bf3544B5BE0Ac5aC9437d3c81fAdF47` |
| Inbox | HyperEVM testnet (998) | `0x11178Df40CBf87a4343f4B3F8B09B366ceFA8Ec0` |

## Limits

- Only perpetual oracle prices. `src/HyperCore.sol` is where another read precompile would go.
- A push is all or nothing. If any market in it is not newer than what the Receiver holds, the
  Receiver refuses the whole push, so a push that lands after a newer one fails.
- A delivery that fails on Elysium (refused as above, out of gas, or `maxFeePerGas` below
  Elysium's base fee) is not retried. As with any Nitro retryable, anyone can redeem it within
  7 days, using the ticket id from the `TicketCreated` log on Elysium (not the Beacon's
  `messageNumber`):

  ```bash
  cast send 0x000000000000000000000000000000000000006E "redeem(bytes32)" <ticket id> \
    --rpc-url $ELYSIUM_RPC
  ```

  A late redeem cannot overwrite newer prices, and its age still counts from the HyperEVM read.

## License

Apache 2.0. See [LICENSE](LICENSE).
