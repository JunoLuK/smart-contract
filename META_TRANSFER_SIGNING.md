# Meta Transfer - Guía de Firma de Transacciones

## ¿Qué es un Meta Transfer?

Un meta transfer permite transferir tokens AKDD **en nombre de otro usuario** sin que ese usuario tenga que enviar la transacción directamente a la blockchain. En lugar de eso, el usuario firma un mensaje off-chain (fuera de la blockchain) con su clave privada, y un tercero autorizado (con rol `TRANSFERRERS`) envía la transacción al contrato.

Esto es útil porque:
- El usuario no necesita tener ETH/MATIC para pagar gas.
- El sistema centralizado puede ejecutar la transacción en el momento adecuado.
- La firma garantiza criptográficamente que el usuario autorizó la transferencia.

---

## Contexto: Token AKDD

- **Tipo**: ERC-20 (Ethereum/Polygon)
- **Decimales**: 2 (ej: `1000` = 10.00 AKDD)
- **Estándar de firma**: EIP-712 (Typed Structured Data)
- **Función**: `metaTransfer(signature, sender, recipient, amount, deadline, transactionInformation)`

---

## Proceso de Firma (EIP-712)

La firma sigue el estándar [EIP-712](https://eips.ethereum.org/EIPS/eip-712), que permite firmar datos estructurados de forma segura y legible.

### Paso a paso

```
Aliado (off-chain)                                  Smart Contract (on-chain)
  │                                                        │
  │  1. Obtener el nonce actual del sender                 │
  │     contractInstance.nonces(senderAddress) ───────────>│
  │  <──────────────────────────────────── nonce ──────────│
  │                                                        │
  │  2. Construir el dominio EIP-712                       │
  │  3. Construir el struct Permit                         │
  │  4. Generar el digest (hash tipado)                    │
  │  5. Firmar el digest con la clave privada              │
  │     del sender (ECDSA secp256k1)                       │
  │                                                        │
  │  6. Llamar metaTransfer con la firma ─────────────────>│
  │                                                        │
  │                          7. Verifica firma vs sender   │
  │                          8. Incrementa nonce           │
  │                          9. Transfiere tokens          │
  │                         10. Emite evento               │
  │                                                        │
  │  <──────────────────── tx receipt ─────────────────────│
```

### 1. Dominio EIP-712

```javascript
const domain = {
  name: "AKDD",
  version: "1",
  chainId: 137,                    // Polygon Mainnet (80002 para Amoy testnet)
  verifyingContract: CONTRACT_ADDRESS // Dirección del contrato AKDD desplegado
};
```

### 2. Tipo del struct

```javascript
const types = {
  Permit: [
    { name: "owner", type: "address" },
    { name: "recipient", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" }
  ]
};
```

### 3. Valores del mensaje

```javascript
const value = {
  owner: senderAddress,       // Dirección que posee los tokens y firma
  recipient: recipientAddress, // Dirección que recibe los tokens
  amount: 1000,               // Cantidad en unidades mínimas (2 decimales: 1000 = 10.00 AKDD)
  nonce: currentNonce,        // Nonce actual del sender (obtenido del contrato)
  deadline: Math.floor(Date.now() / 1000) + 3600 // Unix timestamp, ej: 1 hora desde ahora
};
```

### 4. Firmar

Con la clave privada del sender, se firma el digest EIP-712. El resultado es una firma de 65 bytes (r: 32 bytes, s: 32 bytes, v: 1 byte).

### 5. Llamar metaTransfer

La firma se envía junto con los parámetros al contrato:

```solidity
function metaTransfer(
    bytes calldata signature,          // Firma EIP-712 (65 bytes)
    address sender,                    // Dueño de los tokens
    address recipient,                 // Destinatario
    uint256 amount,                    // Cantidad
    uint256 deadline,                  // Expiración de la firma (unix timestamp)
    InternalTransactionInformation calldata transactionInformation
) public onlyTransferrers returns (bool)
```

El campo `transactionInformation` es metadata interna:

```solidity
struct InternalTransactionInformation {
    string userUid;          // UID del usuario
    string transactionId;    // ID de la transacción interna
    string currentState;     // Estado actual (ej: "PENDING")
    string transactionType;  // Tipo (ej: "BUY", "SELL", "TRANSFER")
}
```

---

## Reglas de Validación

| Regla | Descripción |
|---|---|
| **Rol TRANSFERRERS** | Solo cuentas con rol `TRANSFERRERS` pueden llamar `metaTransfer` |
| **Firma válida** | Si `msg.sender != sender`, la firma debe ser válida y corresponder al `sender` |
| **Sin firma si es el mismo** | Si `msg.sender == sender`, no se valida la firma (puede ser cualquier valor) |
| **Nonce incremental** | Cada firma consume un nonce. Una firma no puede reutilizarse |
| **Deadline** | `block.timestamp` debe ser menor que `deadline`, o la transacción revierte |
| **Amount > 0** | El monto debe ser mayor a 0 |
| **Addresses no-zero** | Ni sender ni recipient pueden ser `address(0)` |

---

## Ejemplo de Implementación (JavaScript / ethers.js)

### Dependencias

```bash
npm install ethers
```

### Firmar y ejecutar un Meta Transfer

```javascript
const { ethers } = require("ethers");

// Configuración
const CHAIN_ID = 137; // Polygon Mainnet
const CONTRACT_ADDRESS = "0x..."; // Dirección del contrato AKDD
const AKDD_ABI = [
  "function metaTransfer(bytes signature, address sender, address recipient, uint256 amount, uint256 deadline, tuple(string userUid, string transactionId, string currentState, string transactionType) transactionInformation) returns (bool)",
  "function nonces(address) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)"
];

// Dominio EIP-712
const domain = {
  name: "AKDD",
  version: "1",
  chainId: CHAIN_ID,
  verifyingContract: CONTRACT_ADDRESS,
};

// Tipos EIP-712
const types = {
  Permit: [
    { name: "owner", type: "address" },
    { name: "recipient", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

/**
 * Firma un meta transfer off-chain.
 *
 * @param {ethers.Wallet} senderWallet - Wallet del dueño de los tokens
 * @param {string} recipientAddress - Dirección del destinatario
 * @param {number} amount - Cantidad en unidades mínimas (2 decimales)
 * @param {number} nonce - Nonce actual del sender
 * @param {number} deadline - Unix timestamp de expiración
 * @returns {string} Firma en hex (65 bytes)
 */
async function signMetaTransfer(senderWallet, recipientAddress, amount, nonce, deadline) {
  const value = {
    owner: senderWallet.address,
    recipient: recipientAddress,
    amount: amount,
    nonce: nonce,
    deadline: deadline,
  };

  const signature = await senderWallet.signTypedData(domain, types, value);
  return signature;
}

/**
 * Ejecuta un meta transfer en el contrato.
 *
 * @param {ethers.Wallet} executorWallet - Wallet con rol TRANSFERRERS (paga el gas)
 * @param {string} signature - Firma EIP-712 del sender
 * @param {string} senderAddress - Dirección del dueño de los tokens
 * @param {string} recipientAddress - Dirección del destinatario
 * @param {number} amount - Cantidad
 * @param {number} deadline - Unix timestamp de expiración
 * @param {object} txInfo - Información interna de la transacción
 */
async function executeMetaTransfer(
  executorWallet,
  signature,
  senderAddress,
  recipientAddress,
  amount,
  deadline,
  txInfo
) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, AKDD_ABI, executorWallet);

  const tx = await contract.metaTransfer(
    signature,
    senderAddress,
    recipientAddress,
    amount,
    deadline,
    txInfo
  );

  const receipt = await tx.wait();
  return receipt;
}

// --- Ejemplo de uso ---
async function main() {
  const provider = new ethers.JsonRpcProvider("https://polygon-rpc.com");

  // Wallet del usuario que posee los tokens (firma off-chain)
  const senderPrivateKey = "0x...";
  const senderWallet = new ethers.Wallet(senderPrivateKey);

  // Wallet del ejecutor con rol TRANSFERRERS (envía la tx on-chain)
  const executorPrivateKey = "0x...";
  const executorWallet = new ethers.Wallet(executorPrivateKey, provider);

  const contract = new ethers.Contract(CONTRACT_ADDRESS, AKDD_ABI, provider);

  const recipientAddress = "0x...";
  const amount = 1000; // 10.00 AKDD (2 decimales)
  const nonce = await contract.nonces(senderWallet.address);
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hora

  // 1. El sender firma off-chain
  const signature = await signMetaTransfer(
    senderWallet,
    recipientAddress,
    amount,
    nonce,
    deadline
  );

  console.log("Firma:", signature);

  // 2. El ejecutor envía la transacción on-chain
  const receipt = await executeMetaTransfer(
    executorWallet,
    signature,
    senderWallet.address,
    recipientAddress,
    amount,
    deadline,
    {
      userUid: "user-123",
      transactionId: "tx-456",
      currentState: "PENDING",
      transactionType: "TRANSFER",
    }
  );

  console.log("Transacción confirmada:", receipt.hash);
}

main();
```

---

## Construcción Manual del Digest (sin ethers.js)

Si necesitas construir el digest EIP-712 manualmente (por ejemplo, para firmar desde un HSM o un enclave):

```javascript
const { keccak256, AbiCoder, solidityPackedKeccak256, toBeHex, getBytes } = require("ethers");

function buildEIP712Digest(contractAddress, chainId, owner, recipient, amount, nonce, deadline) {
  // 1. Domain separator
  const domainSeparator = keccak256(
    AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "bytes32", "bytes32", "uint256", "address"],
      [
        keccak256(
          new TextEncoder().encode(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          )
        ),
        keccak256(new TextEncoder().encode("AKDD")),
        keccak256(new TextEncoder().encode("1")),
        chainId,
        contractAddress,
      ]
    )
  );

  // 2. Struct hash
  const structHash = keccak256(
    AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "address", "address", "uint256", "uint256", "uint256"],
      [
        keccak256(
          new TextEncoder().encode(
            "Permit(address owner,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
          )
        ),
        owner,
        recipient,
        amount,
        nonce,
        deadline,
      ]
    )
  );

  // 3. EIP-712 digest: "\x19\x01" + domainSeparator + structHash
  const digest = keccak256(
    solidityPackedKeccak256(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      ["0x19", "0x01", domainSeparator, structHash]
    )
  );

  return digest;
}
```

Luego se firma el `digest` con ECDSA secp256k1 usando la clave privada del sender. El resultado es `(v, r, s)` que se concatena en 65 bytes: `r (32) + s (32) + v (1)`.

---

## Notas Importantes

1. **Nonces**: Cada dirección tiene un nonce incremental. Antes de firmar, siempre consultar el nonce actual con `contract.nonces(address)`. Si se firma con un nonce incorrecto, la transacción revierte.

2. **Deadline**: Es un unix timestamp en segundos. Si `block.timestamp >= deadline`, la transacción revierte con `"Signature expired"`. Se recomienda usar un deadline razonable (ej: 1 hora).

3. **Replay protection**: La firma incluye el `chainId` y la dirección del contrato en el dominio EIP-712, lo que previene replay attacks entre chains o contratos diferentes. El nonce incremental previene la reutilización de firmas en el mismo contrato.

4. **Decimales**: El token usa 2 decimales. Un `amount` de `1000` equivale a `10.00 AKDD`.

5. **Caso especial: sender == msg.sender**: Si quien llama `metaTransfer` es el mismo sender, no se valida la firma. Esto permite que un usuario con rol `TRANSFERRERS` transfiera sus propios tokens sin necesidad de firmar.

6. **Rol TRANSFERRERS**: Solo cuentas con este rol pueden llamar `metaTransfer`. El rol se otorga por un admin del contrato.
