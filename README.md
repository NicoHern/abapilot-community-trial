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

## Install with abapGit

1. Install or run `ZABAPGIT_STANDALONE` in a development or sandbox system.
2. Create an online repository pointing to this repository URL.
3. Select package `ZABAPILOT_TRIAL` and pull.
4. Create an SICF node such as `/sap/bc/zabapilot_trial` with handler class
   `ZCL_ABP_TRIAL_HTTP`.
5. Activate the node and require HTTPS and SAP authentication.
6. Test `GET /sap/bc/zabapilot_trial/ping` before configuring an MCP client.

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
- SICF access, SAP authorizations, network exposure, and AI-provider data
  handling remain the evaluator's responsibility.

## Compatibility validation

The release process validates source first on REM, the ECC compatibility
baseline, and then on S1H. A successful sandbox check is not a guarantee for
every SAP release or customer configuration.
