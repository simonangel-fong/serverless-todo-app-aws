# Serverless Todo App — API Design

[Back](../README.md)

- [Serverless Todo App — API Design](#serverless-todo-app--api-design)
  - [1. Auth model](#1-auth-model)
    - [Ownership rule](#ownership-rule)
  - [2. Response envelope](#2-response-envelope)
  - [3. Data model (reference — see `project.md` for the DynamoDB definition)](#3-data-model-reference--see-projectmd-for-the-dynamodb-definition)
  - [4. Routes](#4-routes)
    - [GET /items](#get-items)
    - [POST /items](#post-items)
    - [GET /items/{id}](#get-itemsid)
    - [PUT /items/{id}](#put-itemsid)
    - [DELETE /items/{id}](#delete-itemsid)
  - [5. CORS](#5-cors)
  - [6. Resolution of "known contract issues"](#6-resolution-of-known-contract-issues)
  - [7. Status-code summary](#7-status-code-summary)

---

## 1. Auth model

The API sits behind a **Cognito authorizer** on API Gateway (REST). No route is public.

- Every request must carry a valid Cognito **ID token** in the `Authorization` header:
  `Authorization: <id-token>`.
- API Gateway validates the token before the Lambda is invoked. An invalid/missing/expired
  token is rejected by the **gateway** with **401** — the Lambda never runs.
- The Lambda reads the caller identity from the authorizer claims, **never** from the request body:

  ```python
  owner_id = event["requestContext"]["authorizer"]["claims"]["sub"]
  ```

- `owner_id` is the Cognito `sub` (a stable UUID). It is stamped on every created item and used
  to scope every read/update/delete.

### Ownership rule

For any `/items/{id}` route, if the target item exists but its `owner_id` ≠ the caller's `sub`,
the API returns **404** (not 403). Rationale: a 403 would leak that the id exists. From the
caller's perspective, an item they don't own is indistinguishable from an item that doesn't exist.

`owner_id` is **always** taken from the token. If a request body includes `owner_id`, it is ignored.

---

## 2. Response envelope

All responses (success and error) are JSON with this shape:

```jsonc
{
  "message": "human-readable string",  // always present
  "data":    {} | [],                  // present on success responses that return a resource
  "error":   "detail string"           // present only on error responses
}
```

Standard response headers on **every** Lambda response:

```
Content-Type: application/json
Access-Control-Allow-Origin: <frontend-origin>   // see §5, not "*"
```

---

## 3. Data model (reference — see `project.md` for the DynamoDB definition)

Table `todo-app-table`, PK = `id` (UUID), GSI `owner-index` on `owner_id`.

```jsonc
{
  "id": "<uuid>", // server-generated on create; PK
  "owner_id": "<cognito-sub>", // from token; GSI PK; never from body
  "task_name": "string", // required on create
  "task_priority": "High | Medium | Low", // default "Medium"
  "task_status": "Pending | In Progress | Completed", // default "Pending"
  "due_date": "ISO-8601 string | null",
  "created_at": "ISO-8601 string", // server-set on create; immutable
}
```

**Field validation:**

- `task_name` — required, non-empty string.
- `task_priority` — if provided, must be one of `High | Medium | Low`; else `400`.
- `task_status` — if provided, must be one of `Pending | In Progress | Completed`; else `400`.
- `due_date` — if provided, must be a valid ISO-8601 date string or `null`; else `400`.
- **Immutable / ignored on write:** `id`, `owner_id`, `created_at`. If present in a request body
  they are silently ignored (server owns them).

---

## 4. Routes

Base path served by API Gateway. Routes: `/items` and `/items/{id}`.
Every route requires a valid token (§1); the `401` column below is implicit on all routes and
enforced by the gateway.

| Method | Route         | Behavior                                             | Success     | Errors          |
| ------ | ------------- | ---------------------------------------------------- | ----------- | --------------- |
| GET    | `/items`      | list caller's items (`query` on `owner-index`)       | 200 + array | 401             |
| POST   | `/items`      | create; body requires `task_name`; stamps `owner_id` | 201 + item  | 400 / 401       |
| GET    | `/items/{id}` | fetch one; must belong to caller                     | 200 + item  | 401 / 404       |
| PUT    | `/items/{id}` | update mutable fields; must belong to caller         | 200 + item  | 400 / 401 / 404 |
| DELETE | `/items/{id}` | delete; must belong to caller                        | 200         | 401 / 404       |

### GET /items

- Uses `query` on `owner-index` with `owner_id = <caller sub>`. **Never `scan`.**
- Returns `200` with `data` = array of the caller's items (empty array if none — not a 404).

```jsonc
// 200
{ "message": "Retrieved all items", "data": [ { /* item */ }, ... ] }
```

### POST /items

- Body must contain non-empty `task_name`. Optional: `task_priority`, `task_status`, `due_date`.
- Server generates `id`, `created_at`; stamps `owner_id` from token; applies defaults.

```jsonc
// 201
{ "message": "Item created", "data": { /* full item incl. id, owner_id, created_at */ } }
// 400
{ "message": "Missing required field(s): task_name", "error": "task_name is required" }
```

### GET /items/{id}

- Fetch by `id`; then enforce ownership rule (§1). Not found **or** not owned → `404`.

```jsonc
// 200
{ "message": "Item retrieved", "data": { /* item */ } }
// 404
{ "message": "Item not found", "error": "No item exists with ID '<id>'" }
```

### PUT /items/{id}

- **Must 404 first** if the item doesn't exist or isn't owned by the caller — no blind upsert.
- Updates only mutable fields present in the body: `task_name`, `task_priority`, `task_status`, `due_date`.
- Empty update set (no mutable fields) → `400`.
- **Returns the updated item** in `data` (use `ReturnValues="ALL_NEW"` on `update_item`).

```jsonc
// 200
{ "message": "Item updated", "data": { /* updated item */ } }
// 400
{ "message": "No fields provided to update", "error": "..." }
// 404
{ "message": "Item not found", "error": "No item exists with ID '<id>'" }
```

### DELETE /items/{id}

- Existence + ownership check first (§1) → `404` if missing/not owned.
- **Returns `200` with the response envelope** (not `204`). Decision: keep the uniform
  `{ message }` wrapper so the frontend always parses a body; no special-casing an empty response.

```jsonc
// 200
{ "message": "Item <id> deleted" }
// 404
{ "message": "Item not found", "error": "No item exists with ID '<id>'" }
```

---

## 5. CORS

**Preflight (OPTIONS):** handled at **API Gateway** via a **MOCK integration** on each resource.
The Lambda never sees `OPTIONS` requests — the handler stays focused on business logic.
The MOCK integration returns the CORS headers below with `200` and no body.

**Origin policy:** `Access-Control-Allow-Origin` is set to the **frontend origin** (the
CloudFront distribution domain, or custom domain when configured) — **not `*`**. A wildcard is
incompatible with credentialed/authenticated flows and is too permissive for an authed API.

The origin is a Terraform variable (e.g. `frontend_origin`) wired into both the gateway MOCK
integration and the Lambda response headers so the two never drift.

CORS headers (both on the OPTIONS MOCK response and on Lambda responses):

```
Access-Control-Allow-Origin:  <frontend-origin>
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
```

---

## 6. Resolution of "known contract issues"

| Issue (from `project.md`)                     | Resolution                                                                           |
| --------------------------------------------- | ------------------------------------------------------------------------------------ |
| DELETE returns 200, not 204                   | **Keep 200** with the `{ message }` envelope (§4 DELETE). Documented as intentional. |
| PUT does not 404 on missing id (blind upsert) | **Add existence + ownership check before update** (§4 PUT).                          |
| PUT success response omits `data`             | **Return updated item** via `ReturnValues="ALL_NEW"` (§4 PUT).                       |
| No CORS preflight (OPTIONS) handling          | **API Gateway MOCK integration** handles OPTIONS (§5).                               |
| GET /items must not `scan`                    | **`query` on `owner-index`** scoped to caller's `owner_id` (§4 GET /items).          |

Additional decisions locked in this phase:

- Origin is **restricted to the frontend domain**, not `*` (§5).
- `owner_id`, `id`, `created_at` are **server-owned and ignored on write** (§3).
- Enum fields (`task_priority`, `task_status`) are **validated** with `400` on bad values (§3).
- Empty list is `200 + []`, not `404` (§4 GET /items).

---

## 7. Status-code summary

| Code | When                                                                              |
| ---- | --------------------------------------------------------------------------------- |
| 200  | successful GET (one/list), PUT, DELETE                                            |
| 201  | successful POST (create)                                                          |
| 400  | validation failure (missing/empty `task_name`, bad enum, invalid JSON, empty PUT) |
| 401  | missing/invalid/expired token — **rejected by API Gateway**, Lambda not invoked   |
| 404  | item not found **or** not owned by caller (ownership rule, §1)                    |
| 405  | method not allowed on the resource                                                |
| 500  | unexpected server error (caught; returns `{ error }`)                             |
