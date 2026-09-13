# ABAPilot Community Trial

A small, read-only ABAP backend that lets an MCP client verify connectivity to
SAP ECC or on-premise SAP S/4HANA before evaluating the full ABAPilot product.

## Scope

The trial exposes four operations through one SICF handler:

| Path | Purpose | Boundary |
| --- | --- | --- |
| `/ping` | Verify the SAP connection and user | No repository or business data |
| `/read_code` | Read active source for a custom report | `Z*` and `Y*` reports only; `S_DEVELOP` display check |
| `/read_table_structure` | Read DDIC fields for a custom table or structure | `Z*` and `Y*` objects only; metadata only |
| `/read_table_data` | Read a small sample from a custom table | `Z*` and `Y*` tables only; `S_TABU_DIS`; maximum 20 rows; no free-form filter |

It does not contain write, activation, execution, transport, business-data,
administration, licence, translation, monitoring, or production support tools.

The downloadable repository also includes a capped MCP connector. It requires
an active ABAPilot Portal account and an individual Portal key. Downloading or
installing the ABAP objects alone does not enable MCP access.

## Install with abapGit

1. Install or run `ZABAPGIT_STANDALONE` in a development or sandbox system.
2. Create an online repository pointing to this repository URL.
3. Select package `ZABAPILOT_TRIAL` and pull.
4. Create an SICF node such as `/sap/bc/zabapilot_trial` with handler class
   `ZCL_ABP_TRIAL_HTTP`.
5. Activate the node and require HTTPS and SAP authentication.
6. Test `GET /sap/bc/zabapilot_trial/ping` before configuring an MCP client.

## Portal-gated MCP connector

Ask Crimson Consulting to add each evaluator as an ABAPilot Portal user and
issue an individual Community Trial key. Each evaluating company is assigned a
finite monthly call allowance in the Portal. The connector validates that key
and checks the server-side allowance before every
SAP call. It never sends SAP response data to the Portal.

The SAP handler independently requires the same Portal key, validates it with
the hosted Portal, and records one usage event before dispatching a request.
This prevents direct SICF calls from bypassing the official connector. Portal
access from SAP must be allowed through the customer's outbound HTTPS policy,
and the Portal certificate chain must be trusted in `STRUST`. The trial fails
closed if validation or usage recording cannot be completed.

Configure an MCP client to run `npx @abapilot/community-trial` with:

```json
{
  "env": {
    "ABAPILOT_LICENSE_KEY": "portal-issued-key",
    "ABAPILOT_TRIAL_URL": "https://sap.example/sap/bc/zabapilot_trial",
    "ABAPILOT_TRIAL_SAP_USER": "ABAPILOT_TRIAL",
    "ABAPILOT_TRIAL_SAP_PASSWORD": "use-your-secret-store",
    "ABAPILOT_TRIAL_SAP_CLIENT": "100"
  }
}
```

`ABAPILOT_PORTAL_URL` is optional and defaults to the hosted ABAPilot Portal.
The connector refuses calls when the
key is missing, inactive, expired, assigned no finite trial allowance, or has
reached its allowance. Portal authentication does not replace SAP
authentication: SAP still enforces the dedicated user's own authorizations.

## Requests

`GET /ping`

`POST /read_code`

```json
{"object_name":"ZMY_REPORT"}
```

`POST /read_table_structure`

```json
{"table_name":"ZMY_TABLE"}
```

`POST /read_table_data`

```json
{"table_name":"ZMY_TABLE","max_rows":"10"}
```

## Security boundaries

- Install only in a development or sandbox system.
- Use HTTPS and a dedicated SAP user.
- The trial rejects non-`Z*`/`Y*` repository and DDIC names.
- Code reading checks `S_DEVELOP` with activity `03`.
- Table-data reading checks `S_TABU_DIS` with activity `03`; tables without a
  maintained authorization group use the standard `&NC&` group.
- Table reads return at most 20 rows and do not accept a free-form WHERE clause.
- No write or business-data endpoint exists in this package.
- Portal telemetry contains an accepted trial-request event only, never ABAP
  source, request parameters, or table rows.
- SICF access, SAP authorizations, network exposure, and AI-provider data
  handling remain the evaluator's responsibility.

## Compatibility validation

The release process validates source first on REM, the ECC compatibility
baseline, and then on S1H. A successful sandbox check is not a guarantee for
every SAP release or customer configuration.
