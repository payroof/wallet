# Payroof API client contract

All authenticated requests use an origin-pinned `Authorization: Bearer …`.
Redirects and ambient HTTP proxies are disabled.

| Resource | Method · route |
|---|---|
| Proof | `GET /v1/altcha?purpose=project` (also `pairing`, `recovery`) |
| Project | `POST /v1/projects` · `GET /v1/projects/{project}` |
| Reference | `PUT /v1/projects/{project}/references/{reference}` (empty body, allocate/read) |
| Paths | `GET /v1/projects/{project}/paths?scope=confirmed&limit=200` |
| Access | `GET /v1/projects/{project}/access` (live only) · `DELETE …/access/{acc_…}` (204) |
| Webhooks | `GET/POST /v1/projects/{project}/webhooks` · `DELETE …/webhooks/{id}` |
| Pairing URL | `GET /v1/pairings/{id}` metadata · **bodyless** `PUT` approval |
| Pairing retrieval | Requester `POST /v1/pairings/{id}/token` with its poll secret |
| Recovery | `POST /v1/recovery` begin · `PUT /v1/recovery/{id}` complete |

Tokens carry up to four permissions: **`references`, `paths`, `webhooks`, `access`**.
The API does not list payments. The wallet finds them itself. Approval infers the Project from the Wallet bearer.
Dismissing a request is local. Approval requires explicit user confirmation.

Registration body (replace placeholders with locally derived public values and
a solved ALTCHA payload):

```json
{
  "project": "my-project",
  "recovery_key": {"algorithm": "ed25519", "public_key": "<base64url public key>"},
  "watch_roots": [{"family": "eip155", "path": "m/44'/60'/0'/1", "key": {"algorithm": "bip32-secp256k1", "public_key": "<base64url SEC1 key>", "chain_code": "<base64url chain code>"}}],
  "altcha": {"challenge": "<challenge object>", "solution": "<solution object>"}
}
```

Recovery begins with the same `recovery_key` object and an ALTCHA payload for
`recovery`. The key alone selects its one Project. It returns `id`, `challenge`,
`expires_in`. Wallet signs the origin/challenge-bound message locally and completes
with:

```json
{"signature":"<base64url signature>","name":"Recovered wallet"}
```

**Recovery Key** is an independent recovery identity, not a spending key.
Only its `algorithm` and `public_key` leave Wallet. Its private part stays local.
Recover with the same mnemonic, passphrase and Project slot. The signature binds
the challenge to its API origin. The challenge binds the Project, whose name the
completion returns. Connect registers first and recovers when the API answers `409`
(the account already has a Project), so one action covers both.

## Stor stores

`stor_info(stor)` asks a Stor server what a new store needs: the account a sheet is
shared with and the stores' address pattern. `create_store(origin, project, stor,
subdomain, sheet)` creates the store for a connected project in one request. The core issues a credential named `Stor <subdomain>`
with `references`, `paths` and `webhooks` only, solves Stor's `store` proof of work, and
posts `{"subdomain","source","payments":{"url":"<origin>/v1/projects/<project>","key"},"altcha"}`
to that server. The default configuration's `storOrigin` (the local stack's `:8081` in
local development) is only the suggestion the app fills in. It returns `{"url"}`, or
Stor's refusal as `{"error":code}`, in which case the credential is revoked again.

The full contract is the Payroof API's [HTTP reference](https://github.com/payroof/payroof/blob/main/docs/http-api.md).
