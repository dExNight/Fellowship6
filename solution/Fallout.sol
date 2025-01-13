// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../contracts/Fallout.sol";

contract Attack {
    Fallout public immutable fallout;
    Vault public immutable vault;
    uint256 public immutable P;  // Порядок поля
    uint256 public immutable Gx;
    uint256 public immutable Gy;
    uint256 public immutable Qx;
    uint256 public immutable Qy;

    constructor(address falloutAddress) {
        fallout = Fallout(falloutAddress);
        
        vault = Vault(fallout.vault());
        
        P = vault.p();
        Gx = vault.gx();
        Gy = vault.gy();
        Qx = fallout.Qx();
        Qy = fallout.Qy();
    }

    function inverseMod(uint u, uint m) internal pure returns (uint) {
        if (u == 0 || u == m || m == 0)
            return 0;
        if (u > m)
            u = u % m;

        int t1;
        int t2 = 1;
        uint r1 = m;
        uint r2 = u;
        uint q;

        while (r2 != 0) {
            q = r1 / r2;
            (t1, t2, r1, r2) = (t2, t1 - int(q) * t2, r2, r1 - q * r2);
        }

        if (t1 < 0)
            return (m - uint(-t1));

        return uint(t1);
    }

    function getHash(address recipient, uint256 amount) public pure returns (bytes32, uint256) {
        bytes32 hash = keccak256(abi.encode(recipient, amount));
        return (hash, uint(hash));
    }

    function generateSignature(
        uint256 privateKey,
        uint256 messageHash,
        uint256 k
    ) public view returns (
        uint256 r,
        uint256 s
    ) {
        require(k != 0, "k cannot be 0");
        
        // Вычисляем R = k * G
        (uint256 Rx,) = vault.multiplyScalar(Gx, Gy, k);
        
        // r = x-координата точки R (mod p)
        r = Rx % P;
        require(r != 0, "r cannot be 0");
        
        // s = k^(-1)(message + r*d) mod P
        uint256 kInv = inverseMod(k, P);
        s = mulmod(kInv, addmod(messageHash, mulmod(r, privateKey, P), P), P);
        
        require(s != 0, "s cannot be 0");
    }

    // Main function
    function getMintSignature(
        uint256 amount,
        uint256 k,
        uint256 privateKey
    ) public view returns (
        bytes32 messageHash,
        uint256 messageHashNum,
        uint256 r,
        uint256 s
    ) {
        address recipient = fallout.player();
        
        (messageHash, messageHashNum) = getHash(recipient, amount);
        
        (r, s) = generateSignature(privateKey, messageHashNum, k);
    }
}