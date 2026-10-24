// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// The address change a Nitro chain applies to messages from its parent chain.
/// Arbitrum calls this address aliasing.
///
/// Elysium runs on top of HyperEVM and accepts messages from it. When a contract on
/// HyperEVM sends one, it does not arrive under its own address: Elysium adds a fixed
/// offset first. This stops a contract on one chain from impersonating the contract
/// holding the same address on the other.
///
/// So a contract checking "did this message come from my counterpart" must compare
/// against the shifted address, not the original one.
library Alias {
    uint160 internal constant OFFSET = uint160(0x1111000000000000000000000000000000001111);

    /// How a parent-chain sender appears on this chain.
    function fromParent(address parentSender) internal pure returns (address) {
        unchecked {
            return address(uint160(parentSender) + OFFSET);
        }
    }

    /// The parent-chain address behind a shifted one. The inverse of fromParent.
    function toParent(address shifted) internal pure returns (address) {
        unchecked {
            return address(uint160(shifted) - OFFSET);
        }
    }
}
