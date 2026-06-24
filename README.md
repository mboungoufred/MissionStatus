# MissionStatus — Salesforce Technical Test

Apex solution that automatically deactivates contacts and syncs them with an external API when their linked accounts' missions are canceled.

---

## Project structure

```
force-app/main/default/
├── triggers/
│   └── AccountMissionStatusTrigger.trigger   # Entry point (before + after update)
├── classes/
│   ├── AccountMissionStatusHandler.cls       # Business logic
│   ├── AccountMissionStatusHandlerTest.cls   # Test class
│   └── ContactSyncService.cls               # External API callout
└── objects/
    ├── Account/fields/
    │   ├── MissionStatus__c.field-meta.xml   # Picklist: active / canceled
    │   └── MissionCanceledDate__c.field-meta.xml
    └── Contact/fields/
        └── IsActive__c.field-meta.xml        # Checkbox
```

---

## Setup

### 1. Enable Contacts to Multiple Accounts

The trigger relies on `AccountContactRelation` to check all accounts linked to a contact. This requires the **Contacts to Multiple Accounts** feature to be enabled in your org.

1. Go to **Setup** → search for **Account Settings**
2. Check **Allow users to relate a contact to multiple accounts**
3. Click **Save**

Without this setting, `AccountContactRelation` records cannot be queried and the contact deactivation logic will not work.

---

### 2. Add the API URL to Remote Site Settings

Salesforce blocks all outbound HTTP calls by default. The external sync API must be whitelisted before the callout can succeed.

1. Go to **Setup** → search for **Remote Site Settings**
2. Click **New Remote Site**
3. Fill in the fields:

| Field | Value |
|---|---|
| Remote Site Name | `ContactSyncAPI` |
| Remote Site URL | `https://fxyozmgb2xs5iogcheotxi6hoa0jdhiz.lambda-url.eu-central-1.on.aws` |
| Active | checked |

4. Click **Save**

Without this step, the `@future` callout in `ContactSyncService` will throw a `System.CalloutException`.

---

### 3. Deploy the metadata

```bash
sf project deploy start --manifest manifest/package.xml --target-org <your-org-alias>
```

---

### 4. Run tests

```bash
sf apex run test --class-names AccountMissionStatusHandlerTest --target-org <your-org-alias> --result-format human
```

---

### 5. Seed test data (optional)

Creates 200 accounts and 500 contacts to test bulk behavior:

```bash
sf apex run --file scripts/apex/createTestData.apex --target-org <your-org-alias>
```

---

## How it works

When `MissionStatus__c` on an Account is updated to `"canceled"`:

1. **`MissionCanceledDate__c`** is set to today (in `before update`, no extra DML).
2. All contacts linked to that account via `AccountContactRelation` are checked. A contact becomes **inactive** (`IsActive__c = false`) only if **every** account it is linked to is canceled.
3. Contacts whose status changed are **synced** to the external API via an asynchronous `@future` callout (required because Salesforce does not allow callouts in the same transaction as a DML operation).

### API reference

```
PATCH https://fxyozmgb2xs5iogcheotxi6hoa0jdhiz.lambda-url.eu-central-1.on.aws
Authorization: salesforceAuthToken
Content-Type: application/json

[{ "id": "<ContactId>", "is_active": false }, ...]
```

| Status | Meaning |
|---|---|
| 200 | Sync successful |
| 400 | Bad payload — must be an array of `{ id, is_active }` |
| 401 | Missing or invalid Authorization header |
| 404 | Wrong HTTP method — must be PATCH |
