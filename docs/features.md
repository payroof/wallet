# Features

A self-custody EVM wallet for macOS and iOS. Keys are generated, encrypted and used
on the device. An optional [Payroof server](https://github.com/payroof/payroof) connection
discovers payment addresses and lets the wallet approve integrations such as
[Stor](https://github.com/payroof/stor).

```text
Recovery words ──▶ encrypted local vault ──▶ local signing ──▶ the network's RPC
                          │
                          └── optional Payroof API: public watch root + recovery key
```

- **Accounts and addresses**: BIP-39 recovery words, BIP-44 accounts
  (`m/44'/60'/{account}'/0/{index}`), new, exact-index or exact-path addresses. A
  Payroof project's payment addresses have their own branch,
  `m/44'/60'/{account}'/1/{index}`, so money sent to the account's own addresses is
  never taken for a customer's payment.
- **Send and receive**: exact atomic amounts, reviewed recipient, network and maximum
  fee, local signing. Receipts tracked automatically. QR codes on Receive.
- **Your configuration**: networks, RPC endpoints (the others are fallbacks),
  tokens, block explorers and USD price sources are ordinary, editable settings.
- **Portfolio**: balances per address, read from the chain. One USD total from
  the price sources you configure.
- **Activity**: incoming and outgoing transfers of your own addresses and assets, found
  on the device from the chain (optional provider keys or the RPC). The API
  never lists payments.
- **Provider keys**: optional Alchemy, Infura, Ankr and Etherscan keys, kept only in the
  encrypted vault, add provider endpoints and faster history. A key is verified with
  the provider before it is saved. Built-in keys serve the main networks until you add
  your own.
- **Project** (Payroof API): connect each account to one project (recovered
  automatically when the account already has one), create its Stor stores (any
  number, each from its own Google Sheet), find its addresses, approve and revoke
  integrations through pairing.
- **Security**: Argon2id-wrapped vault, six-digit PIN or passcode, optional Face ID
  / Touch ID, auto-lock. Recovery words are shown again only with the PIN (Security), to copy (the clipboard clears in a minute), save to a file or show as a
  QR code. Opening a wallet can scan that QR code on another device.

Only EVM chains are supported. The API is never needed to derive, check balances
or sign.
