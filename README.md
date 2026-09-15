# ABAPilot Community Trial

A time-boxed evaluation of AI-assisted ABAP work on your own SAP ECC or on-premise S/4HANA sandbox. The trial is designed to answer three buying questions with real evidence:

1. Can your network and security model support ABAPilot?
2. Can an MCP assistant understand your authorized custom ABAP and diagnose a real SAP error?
3. Can it complete a small syntax-check, change, activation, and test loop inside a tightly isolated Z report?

The full product has a much broader tool catalog. This package deliberately keeps repository and data access bounded and limits persistent changes to one resettable laboratory report.

## Evaluation workflow

The connector exposes 13 tools:

| Capability | MCP tools | Boundary |
| --- | --- | --- |
| Connectivity | `sap_ping` | Identifies the connected SAP system and user |
| Repository reading | `sap_read_code`, `sap_read_object` | Authorized `Z*`/`Y*` reports, includes, classes, function modules and function groups; maximum 2,000 source lines per call |
| DDIC inspection | `sap_read_table_structure` | `Z*`/`Y*` tables and structures |
| Bounded custom data | `sap_read_table_data`, `sap_query_custom_table` | `Z*`/`Y*` tables, `S_TABU_DIS`, maximum 20 or 50 rows; projected fields and one validated filter only |
| Error diagnosis | `sap_diagnose_error` | Resolves pasted or screenshot-transcribed text through T100 and finds matching calls in authorized custom code; standard SAP source is never returned |
| Change planning | `sap_analyze_change` | Reads bounded active source and direct include relationships without modifying SAP |
| In-memory validation | `sap_syntax_check` | Syntax-checks candidate ABAP without saving it |
| Isolated change loop | `sap_trial_lab_status`, `sap_trial_lab_apply`, `sap_trial_lab_test`, `sap_trial_lab_reset` | May change only `ZABP_TRIAL_LAB`; blocks database writes, transactions, files, function/method calls and object creation; always resettable |

The laboratory is a product-evaluation mechanism, not a general write API. It demonstrates the interaction model while preventing changes to customer business programs.

## Install with abapGit

1. Install or run `ZABAPGIT_STANDALONE` in a development or sandbox system.
2. Pull `https://github.com/NicoHern/abapilot-community-trial` into package `ZABAPILOT_TRIAL`.
3. Create an SICF node such as `/sap/bc/zabapilot_trial` with handler class `ZCL_ABP_TRIAL_HTTP`.
4. Activate the node and require SAP authentication. Use HTTPS whenever the SAP landscape supports it.
5. Allow outbound HTTPS from SAP to the ABAPilot Portal and import the Portal certificate chain in `STRUST`.
6. In `STVARV`, set `ZABAPILOT_TRIAL_PORTAL_URL` only when SAP must use an approved proxy or custom Portal hostname.

## Configure the MCP connector

Crimson Consulting creates an individual Portal user and Community Trial key for each evaluator. That key authenticates the trial entitlement; it does not replace the evaluator's SAP user.

The customer supplies the SAP URL, client, user and password for its own sandbox. SAP continues to enforce `S_DEVELOP`, `S_TABU_DIS` and SICF access.

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

Generate a configuration template without writing real secrets:

```shell
npx -y -p @abapilot/community-trial abapilot-trial-configure
```

`ABAPILOT_PORTAL_URL` is optional. A tool call goes to the customer SAP endpoint once. The SAP handler then validates and consumes one trial allowance through the Portal before dispatch. Source, request payloads and table rows are never sent to the Portal. Version 0.4 uses one atomic Portal call when the deployed Portal supports it and falls back to the older validation path during rollout.

## Recommended buying-decision test

Use a sandbox and budget 60 to 90 minutes:

1. Run `sap_ping` to prove the identity and network path.
2. Read one representative Z class or function group with `sap_read_object`.
3. Diagnose an error your developer already understands using `sap_diagnose_error`; compare the returned T100 identity and custom-code locations with the known answer.
4. Ask the assistant to inspect `ZABP_TRIAL_LAB`, propose a small discount-rule change, syntax-check it, apply it and run the fixed functional tests.
5. Reset the lab and verify its baseline.
6. If the workflow is useful, request a time-boxed paid-product PoC against a real sandbox change including the broader ATC, ABAP Unit, transport and activation capabilities.

## Security boundaries

- Install only in a development or sandbox SAP system.
- Repository and DDIC reads accept only `Z*` and `Y*` names.
- Source reading requires `S_DEVELOP` activity `03`.
- Custom table reads require `S_TABU_DIS` activity `03`; missing authorization groups use `&NC&`.
- Table filters are assembled only after the field and operator are validated against DDIC metadata. Free-form SQL is not accepted.
- Persistent changes require `S_DEVELOP` activity `02` and are restricted to `ZABP_TRIAL_LAB`.
- The lab rejects business-data writes, transactions, dynamic execution, files, function modules, method calls and object creation.
- Trial expiry disables access through Portal validation. Customer-owned SAP objects are not deleted automatically.
- Portal telemetry records an accepted endpoint counter and never records ABAP source or table contents.

## Compatibility validation

Every release is activated and exercised first on REM, the ECC compatibility baseline, and then checked on S1H. SAP release level, installed components and customer authorization design can still affect individual systems.
