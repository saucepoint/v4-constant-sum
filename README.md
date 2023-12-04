# v4-constant-sum
### **Constant-sum swap on Uniswap v4 🦄**

> **This repo is not production ready, and only serves as an example for custom curves on v4**

With [recent changes](https://github.com/Uniswap/v4-core/pull/404) to v4, Hooks can swap on custom curves!

`v4-constant-sum` implements constant-sum swaps (*x + y = k*), allowing for an exact 1:1 swap everytime

---

## Methodology

1. To faciliate a custom curve, we need to skip the concentrated liquidity swap. We'll use the [NoOp](https://www.v4-by-example.org/hooks/no-op) pattern, allowing us to implement the constant-sum swap.

2. The hook will hold its own token balances (as liquidity for the constant-sum curve)

3. The `beforeSwap` hook will handle the constant-sum curve:
    1. inbound tokens are taken from the PoolManager
        * this creates a debt, that is paid for by the swapper via the swap router
        * the inbound token is added to the hook's reserves
    2. an *equivalent* number of outbound tokens is sent from the hook to the PoolManager
        * the outbound token is removed from the hook's reserves
        * this creates a credit -- the swap router claims it and sends it to the swapper

---

NOTE: The tests are dependent on [v4-core#430](https://github.com/Uniswap/v4-core/pull/430)

---

Additional resources:

[v4-template](https://github.com/uniswapfoundation/v4-template) provides a minimal template and environment for developing v4 hooks

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

