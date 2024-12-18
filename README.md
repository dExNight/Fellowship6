# Solution explanation

## Vault
Are you serious?

## Proxy
Important to know:
- Each etherium contract has its own storage, represented as array with 2^256 slots each of 32 bytes

Proxy contract uses predefined slot in its storage to store `_logic` address. It's slot:

**_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc**

Executor contract has two slots:
- 0 slot: owner address
- 1 slot: player address

### 1. Proxy creation
In proxy constructor `constructor(address _logic, address _player)` contract writes **_logic** into its **_IMPLEMENTATION_SLOT**, then delegate calls **_logic**'s `initialize` function with **_player** parameter. After that Proxy contract's storage became:
- 0: someone who deployed it
- 1: player address (my)
- _IMPLEMENTATION_SLOT: _logic address

### 2. Note about proxy usage
When we call any function that does not exist in `Proxy`, it goes to `fallback()` that идеально копирует вызванную функцию, делегирует ее вызов имплементации и так же идеально возращает данные

### 3. Exploit
Main goal - to change `_logic` address, which is stored in _IMPLEMENTATION_SLOT, with our contract `isSolved() -> true`. If this is done, any Proxy call of `isSolved` will return true!

#### - Verify that `_logic` address is stored at _IMPLEMENTATION_SLOT using web3.js
![alt text](assets/proxy1.png)

#### - Deploy Executor contract with modified isSolved function (`AttackHelper.sol`)

#### - Call `execute` function of Proxy through `Attack.sol`