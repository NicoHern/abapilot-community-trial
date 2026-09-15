CLASS zcl_abp_trial_license DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS validate
      IMPORTING
        io_request      TYPE REF TO if_http_request
      RETURNING
        VALUE(rv_error) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS get_json_number
      IMPORTING
        iv_json         TYPE string
        iv_name         TYPE string
      RETURNING
        VALUE(rv_value) TYPE i.

    CLASS-METHODS portal_post
      IMPORTING
        iv_path         TYPE string
        iv_license_key  TYPE string
        iv_body         TYPE string
      EXPORTING
        ev_status       TYPE i
        ev_response     TYPE string.
ENDCLASS.

CLASS zcl_abp_trial_license IMPLEMENTATION.
  METHOD validate.
    DATA lv_key TYPE string.
    DATA lv_status TYPE i.
    DATA lv_status_text TYPE c LENGTH 12.
    DATA lv_response TYPE string.
    DATA lv_usage_body TYPE string.
    DATA lv_request_body TYPE string.
    DATA lv_endpoint TYPE string.
    DATA lv_used TYPE i.
    DATA lv_limit TYPE i.

    lv_key = io_request->get_header_field( name = 'X-ABAPilot-License-Key' ).
    IF lv_key IS INITIAL.
      rv_error = 'ABAPilot Portal license key is required'.
      RETURN.
    ENDIF.

    lv_endpoint = io_request->get_header_field( name = '~path_info' ).
    REPLACE ALL OCCURRENCES OF '"' IN lv_endpoint WITH ''.
    CONCATENATE '{"server_version":"0.4.0",'
      '"hostname":"sap-community-trial",'
      '"feature":"community_trial","sap_endpoint":"'
      lv_endpoint '","channel":"sap"}' INTO lv_request_body.

    portal_post(
      EXPORTING
        iv_path        = '/api/v1/mcp/license/consume'
        iv_license_key = lv_key
        iv_body        = lv_request_body
      IMPORTING
        ev_status      = lv_status
        ev_response    = lv_response ).

    IF lv_status = 404.
      portal_post(
        EXPORTING
          iv_path        = '/api/v1/mcp/license/validate'
          iv_license_key = lv_key
          iv_body        = '{"server_version":"0.4.0","hostname":"sap-community-trial"}'
        IMPORTING
          ev_status      = lv_status
          ev_response    = lv_response ).
    ELSEIF lv_status = 200 AND lv_response CS '"valid":true'.
      RETURN.
    ENDIF.

    IF lv_status <> 200 OR lv_response NS '"valid":true'.
      WRITE lv_status TO lv_status_text.
      CONCATENATE 'Portal validation failed, HTTP' lv_status_text
        INTO rv_error SEPARATED BY space.
      RETURN.
    ENDIF.

    lv_used = get_json_number( iv_json = lv_response
      iv_name = 'queries_used' ).
    lv_limit = get_json_number( iv_json = lv_response
      iv_name = 'queries_limit' ).
    IF lv_limit <= 0.
      rv_error = 'No finite Community Trial allowance is assigned'.
      RETURN.
    ENDIF.
    IF lv_used >= lv_limit.
      rv_error = 'Community Trial allowance is exhausted'.
      RETURN.
    ENDIF.

    CONCATENATE '{"events":[{"event_type":"tool_call",'
      '"feature":"community_trial","sap_endpoint":"trial_request",'
      '"status":"accepted","channel":"sap"}]}' INTO lv_usage_body.
    portal_post(
      EXPORTING
        iv_path        = '/api/v1/mcp/telemetry/events'
        iv_license_key = lv_key
        iv_body        = lv_usage_body
      IMPORTING
        ev_status      = lv_status
        ev_response    = lv_response ).
    IF lv_status <> 200.
      rv_error = 'Portal could not record trial usage'.
    ENDIF.
  ENDMETHOD.

  METHOD get_json_number.
    DATA lv_pattern TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_offset TYPE i.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_number TYPE string.

    CONCATENATE '"' iv_name '"' INTO lv_pattern.
    FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_offset = lv_offset + strlen( lv_pattern ).
    lv_rest = iv_json+lv_offset.
    FIND ':' IN lv_rest MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_offset = lv_offset + 1.
    lv_rest = lv_rest+lv_offset.
    SHIFT lv_rest LEFT DELETING LEADING space.
    WHILE lv_rest IS NOT INITIAL.
      lv_char = lv_rest(1).
      IF lv_char CO '0123456789'.
        CONCATENATE lv_number lv_char INTO lv_number.
        lv_rest = lv_rest+1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    rv_value = lv_number.
  ENDMETHOD.

  METHOD portal_post.
    CONSTANTS lc_default_portal TYPE string VALUE
      'https://abapilot-portal.kindwater-835c4d5f.westeurope.azurecontainerapps.io'.
    DATA lv_portal TYPE string.
    DATA lv_configured_portal TYPE tvarvc-low.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_url TYPE string.
    DATA lv_reason TYPE string.
    DATA lv_auth TYPE string.
    DATA lv_error_code TYPE sysubrc.

    CLEAR: ev_status, ev_response.
    SELECT SINGLE low FROM tvarvc INTO lv_configured_portal
      WHERE name = 'ZABAPILOT_TRIAL_PORTAL_URL'
        AND type = 'P'.
    IF sy-subrc = 0 AND lv_configured_portal IS NOT INITIAL.
      lv_portal = lv_configured_portal.
    ELSE.
      lv_portal = lc_default_portal.
    ENDIF.
    CONCATENATE lv_portal iv_path INTO lv_url.
    CALL METHOD cl_http_client=>create_by_url
      EXPORTING
        url                = lv_url
      IMPORTING
        client             = lo_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4.
    IF sy-subrc <> 0 OR lo_client IS INITIAL.
      ev_status = sy-subrc.
      ev_response = 'CREATE_BY_URL failed'.
      RETURN.
    ENDIF.

    CONCATENATE 'Bearer' iv_license_key INTO lv_auth SEPARATED BY space.
    lo_client->request->set_method( 'POST' ).
    lo_client->request->set_header_field(
      name = 'Authorization' value = lv_auth ).
    lo_client->request->set_header_field(
      name = 'Content-Type' value = 'application/json' ).
    lo_client->request->set_cdata( iv_body ).
    lo_client->send( EXCEPTIONS http_communication_failure = 1
      http_invalid_state = 2 http_processing_failed = 3 OTHERS = 4 ).
    IF sy-subrc <> 0.
      ev_status = sy-subrc.
      cl_http_client=>get_last_error(
        IMPORTING code = lv_error_code message = ev_response ).
      IF lv_error_code <> 0.
        ev_status = lv_error_code.
      ENDIF.
      lo_client->close( ).
      RETURN.
    ENDIF.
    IF sy-subrc = 0.
      lo_client->receive( EXCEPTIONS http_communication_failure = 1
        http_invalid_state = 2 http_processing_failed = 3 OTHERS = 4 ).
    ENDIF.
    IF sy-subrc <> 0.
      ev_status = sy-subrc.
      cl_http_client=>get_last_error(
        IMPORTING code = lv_error_code message = ev_response ).
      IF lv_error_code <> 0.
        ev_status = lv_error_code.
      ENDIF.
      lo_client->close( ).
      RETURN.
    ENDIF.
    IF sy-subrc = 0.
      lo_client->response->get_status(
        IMPORTING code = ev_status reason = lv_reason ).
      ev_response = lo_client->response->get_cdata( ).
    ENDIF.
    lo_client->close( ).
  ENDMETHOD.
ENDCLASS.
