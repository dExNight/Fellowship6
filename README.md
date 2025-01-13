# Solution explanation

<details open>

<summary><strong>Vault</strong></summary>

^_^

</details>

<details>

<summary><strong>Proxy</strong></summary>

Proxy contract uses predefined slot in its storage to store `_logic` address:

**_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc**

**Goal:** change `_logic` address with exploit contract that returns `isSolved() -> true`

**Step 1:** Deploy Executor contract with modified isSolved function (`AttackHelper.sol`)

**Step 2:** Call `execute` function of Proxy through `Attack.sol`

</details>

<details>

<summary><strong>Lending</strong></summary>

### Initial state

**TokenA** (collateral token):
- Lending = 0
- Me = 100
- Pair = 500

**TokenB** (borrow token):
- Lending = 5000
- Me = 0 
- Pair = 500

**Vulnerability:** Lending contract uses current spot price from Uniswap V2 pool, which can be easily manipulated with flash loans

**Step 1:** Deposit all TokenA as collateral

**Step 2:** Do flash loan to manipulate TokenB price

**Step 3:** Update reserves to use new manipulated price

**Step 4:** Borrow all TokenB using manipulated low price

</details>

<details>

<summary><strong>Yield</strong></summary>

Yield contract that stakes user's deposits in UniswapV3 pool

**Vulnerability:** Contract does not immediately add user tokens to the liquidity. They remain in the inactive pool until the next rebalance. However, when user withdraws liquidity, Yield returns him `inactiveAmount * userShares/totalShares + activeAmount * userShares/totalShares`. Therefore if activeAmount is large enough, user can withdraw more than he deposited

Step 1: Deposit all tokens to Yield contract

Step 2: Burn all shares, receive more tokens than were deposited

Step 3: Repeat

</details>