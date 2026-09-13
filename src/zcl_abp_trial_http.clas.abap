CLASS zcl_abp_trial_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.
    TYPES ty_source_line TYPE c LENGTH 255.
    TYPES tt_source TYPE STANDARD TABLE OF ty_source_line WITH DEFAULT KEY.

    METHODS get_json_value
      IMPORTING
        iv_json       TYPE string
        iv_name       TYPE string
      RETURNING
        VALUE(rv_value) TYPE string.

    METHODS get_json_number
      IMPORTING
        iv_json         TYPE string
        iv_name         TYPE string
      RETURNING
        VALUE(rv_value) TYPE i.

    METHODS escape_json
      IMPORTING
        iv_value      TYPE string
      RETURNING
        VALUE(rv_value) TYPE string.

    METHODS send_json
      IMPORTING
        io_response TYPE REF TO if_http_response
        iv_status   TYPE i
        iv_body     TYPE string.

    METHODS handle_ping
      IMPORTING io_response TYPE REF TO if_http_response.

    METHODS handle_read_code
      IMPORTING
        io_request  TYPE REF TO if_http_request
        io_response TYPE REF TO if_http_response.

    METHODS handle_read_table_structure
      IMPORTING
        io_request  TYPE REF TO if_http_request
        io_response TYPE REF TO if_http_response.

    METHODS handle_read_table_data
      IMPORTING
        io_request  TYPE REF TO if_http_request
        io_response TYPE REF TO if_http_response.

    METHODS check_table_auth
      IMPORTING
        iv_table_name TYPE tabname
      RETURNING
        VALUE(rv_authorized) TYPE abap_bool.

    METHODS validate_trial
      IMPORTING
        io_request      TYPE REF TO if_http_request
      RETURNING
        VALUE(rv_error) TYPE string.

    METHODS portal_post
      IMPORTING
        iv_path         TYPE string
        iv_license_key  TYPE string
        iv_body         TYPE string
      EXPORTING
        ev_status       TYPE i
        ev_response     TYPE string.
ENDCLASS.

CLASS zcl_abp_trial_http IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    DATA lv_path TYPE string.
    DATA lv_license_error TYPE string.

    lv_path = server->request->get_header_field( name = '~path_info' ).
    TRANSLATE lv_path TO LOWER CASE.

    lv_license_error = validate_trial( server->request ).
    IF lv_license_error IS NOT INITIAL.
      lv_license_error = escape_json( lv_license_error ).
      CONCATENATE '{"success":false,"error":"' lv_license_error '"}'
        INTO lv_license_error.
      send_json( io_response = server->response iv_status = 403
        iv_body = lv_license_error ).
      RETURN.
    ENDIF.

    CASE lv_path.
      WHEN '' OR '/' OR '/ping'.
        handle_ping( server->response ).
      WHEN '/read_code'.
        handle_read_code(
          io_request  = server->request
          io_response = server->response ).
      WHEN '/read_table_structure'.
        handle_read_table_structure(
          io_request  = server->request
          io_response = server->response ).
      WHEN '/read_table_data'.
        handle_read_table_data(
          io_request  = server->request
          io_response = server->response ).
      WHEN OTHERS.
        send_json(
          io_response = server->response
          iv_status   = 404
          iv_body     = '{"success":false,"error":"Unknown trial endpoint"}' ).
    ENDCASE.
  ENDMETHOD.

  METHOD validate_trial.
    DATA lv_key TYPE string.
    DATA lv_status TYPE i.
    DATA lv_response TYPE string.
    DATA lv_usage_body TYPE string.
    DATA lv_used TYPE i.
    DATA lv_limit TYPE i.

    lv_key = io_request->get_header_field( name = 'X-ABAPilot-License-Key' ).
    IF lv_key IS INITIAL.
      rv_error = 'ABAPilot Portal license key is required'.
      RETURN.
    ENDIF.

    portal_post(
      EXPORTING
        iv_path        = '/api/v1/mcp/license/validate'
        iv_license_key = lv_key
        iv_body        = '{"server_version":"0.1.0","hostname":"sap-community-trial"}'
      IMPORTING
        ev_status      = lv_status
        ev_response    = lv_response ).

    IF lv_status <> 200 OR lv_response NS '"valid":true'.
      rv_error = 'Trial inactive, expired, or Portal unavailable'.
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
    CONSTANTS lc_portal TYPE string VALUE
      'https://abapilot-portal.kindwater-835c4d5f.westeurope.azurecontainerapps.io'.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_url TYPE string.
    DATA lv_reason TYPE string.
    DATA lv_auth TYPE string.

    CLEAR: ev_status, ev_response.
    CONCATENATE lc_portal iv_path INTO lv_url.
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
    IF sy-subrc = 0.
      lo_client->receive( EXCEPTIONS http_communication_failure = 1
        http_invalid_state = 2 http_processing_failed = 3 OTHERS = 4 ).
    ENDIF.
    IF sy-subrc = 0.
      lo_client->response->get_status(
        IMPORTING code = ev_status reason = lv_reason ).
      ev_response = lo_client->response->get_cdata( ).
    ENDIF.
    lo_client->close( ).
  ENDMETHOD.

  METHOD handle_read_table_data.
    DATA lv_json TYPE string.
    DATA lv_name TYPE tabname.
    DATA lv_max_rows TYPE i.
    DATA lv_max_rows_text TYPE string.
    DATA lr_data TYPE REF TO data.
    DATA lt_fields TYPE STANDARD TABLE OF dd03p.
    DATA ls_field TYPE dd03p.
    DATA lv_body TYPE string.
    DATA lv_rows TYPE i.
    DATA lv_rows_text TYPE string.
    DATA lv_first_row TYPE abap_bool.
    DATA lv_first_field TYPE abap_bool.
    DATA lv_fieldname TYPE fieldname.
    DATA lv_field_value TYPE string.
    DATA lx_error TYPE REF TO cx_root.

    FIELD-SYMBOLS <lt_data> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <ls_data> TYPE any.
    FIELD-SYMBOLS <lv_value> TYPE any.

    lv_json = io_request->get_cdata( ).
    lv_name = get_json_value( iv_json = lv_json iv_name = 'table_name' ).
    TRANSLATE lv_name TO UPPER CASE.

    IF lv_name IS INITIAL.
      send_json( io_response = io_response iv_status = 400
        iv_body = '{"success":false,"error":"Missing table_name"}' ).
      RETURN.
    ENDIF.

    IF lv_name NP 'Z*' AND lv_name NP 'Y*'.
      send_json( io_response = io_response iv_status = 403
        iv_body = '{"success":false,"error":"Trial access is limited to Z and Y tables"}' ).
      RETURN.
    ENDIF.

    IF check_table_auth( lv_name ) = abap_false.
      send_json( io_response = io_response iv_status = 403
        iv_body = '{"success":false,"error":"S_TABU_DIS display authorization required"}' ).
      RETURN.
    ENDIF.

    lv_max_rows = get_json_value( iv_json = lv_json iv_name = 'max_rows' ).
    IF lv_max_rows <= 0.
      lv_max_rows = 10.
    ENDIF.
    IF lv_max_rows > 20.
      lv_max_rows = 20.
    ENDIF.

    TRY.
        CREATE DATA lr_data TYPE TABLE OF (lv_name).
        ASSIGN lr_data->* TO <lt_data>.

        CALL FUNCTION 'DDIF_TABL_GET'
          EXPORTING
            name          = lv_name
            langu         = sy-langu
          TABLES
            dd03p_tab     = lt_fields
          EXCEPTIONS
            illegal_input = 1
            OTHERS        = 2.
        IF sy-subrc <> 0.
          send_json( io_response = io_response iv_status = 404
            iv_body = '{"success":false,"error":"Table not found"}' ).
          RETURN.
        ENDIF.

        SELECT * FROM (lv_name)
          INTO TABLE <lt_data>
          UP TO lv_max_rows ROWS.

        DESCRIBE TABLE <lt_data> LINES lv_rows.
        lv_rows_text = lv_rows.
        lv_max_rows_text = lv_max_rows.
        CONDENSE lv_rows_text NO-GAPS.
        CONDENSE lv_max_rows_text NO-GAPS.
        CONCATENATE '{"success":true,"row_count":' lv_rows_text ',"max_rows":'
          lv_max_rows_text ',"data":[' INTO lv_body.

        lv_first_row = abap_true.
        LOOP AT <lt_data> ASSIGNING <ls_data>.
          IF lv_first_row = abap_false.
            CONCATENATE lv_body ',' INTO lv_body.
          ENDIF.
          lv_first_row = abap_false.
          CONCATENATE lv_body '{' INTO lv_body.
          lv_first_field = abap_true.

          LOOP AT lt_fields INTO ls_field.
            IF ls_field-fieldname CP '.INCLUDE*'.
              CONTINUE.
            ENDIF.
            lv_fieldname = ls_field-fieldname.
            ASSIGN COMPONENT lv_fieldname OF STRUCTURE <ls_data> TO <lv_value>.
            IF sy-subrc <> 0.
              CONTINUE.
            ENDIF.
            IF lv_first_field = abap_false.
              CONCATENATE lv_body ',' INTO lv_body.
            ENDIF.
            lv_first_field = abap_false.
            CLEAR lv_field_value.
            MOVE <lv_value> TO lv_field_value.
            CONDENSE lv_field_value.
            lv_field_value = escape_json( lv_field_value ).
            CONCATENATE lv_body '"' lv_fieldname '":"' lv_field_value '"' INTO lv_body.
          ENDLOOP.
          CONCATENATE lv_body '}' INTO lv_body.
        ENDLOOP.
        CONCATENATE lv_body ']}' INTO lv_body.
        send_json( io_response = io_response iv_status = 200 iv_body = lv_body ).
      CATCH cx_root INTO lx_error.
        lv_field_value = lx_error->get_text( ).
        lv_field_value = escape_json( lv_field_value ).
        CONCATENATE '{"success":false,"error":"' lv_field_value '"}' INTO lv_body.
        send_json( io_response = io_response iv_status = 400 iv_body = lv_body ).
    ENDTRY.
  ENDMETHOD.

  METHOD check_table_auth.
    DATA lv_group TYPE tddat-cclass.

    SELECT SINGLE cclass FROM tddat INTO lv_group
      WHERE tabname = iv_table_name.
    IF sy-subrc <> 0 OR lv_group IS INITIAL.
      lv_group = '&NC&'.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'S_TABU_DIS'
      ID 'DICBERCLS' FIELD lv_group
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc = 0.
      rv_authorized = abap_true.
    ELSE.
      rv_authorized = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD handle_ping.
    DATA lv_body TYPE string.
    DATA lv_user TYPE string.
    DATA lv_system TYPE string.
    DATA lv_client TYPE string.

    lv_user = sy-uname.
    lv_system = sy-sysid.
    lv_client = sy-mandt.
    lv_user = escape_json( lv_user ).
    lv_system = escape_json( lv_system ).
    lv_client = escape_json( lv_client ).
    CONCATENATE '{"success":true,"edition":"community-trial","read_only":true,'
                '"system":"' lv_system '","client":"' lv_client
                '","user":"' lv_user '"}' INTO lv_body.
    send_json( io_response = io_response iv_status = 200 iv_body = lv_body ).
  ENDMETHOD.

  METHOD handle_read_code.
    DATA lv_json TYPE string.
    DATA lv_name TYPE progname.
    DATA lv_line TYPE ty_source_line.
    DATA lt_source TYPE tt_source.
    DATA lv_body TYPE string.
    DATA lv_first TYPE abap_bool.
    DATA lv_escaped TYPE string.

    lv_json = io_request->get_cdata( ).
    lv_name = get_json_value( iv_json = lv_json iv_name = 'object_name' ).
    TRANSLATE lv_name TO UPPER CASE.

    IF lv_name IS INITIAL.
      send_json( io_response = io_response iv_status = 400
        iv_body = '{"success":false,"error":"Missing object_name"}' ).
      RETURN.
    ENDIF.

    IF lv_name NP 'Z*' AND lv_name NP 'Y*'.
      send_json( io_response = io_response iv_status = 403
        iv_body = '{"success":false,"error":"Trial access is limited to Z and Y reports"}' ).
      RETURN.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'S_DEVELOP'
      ID 'DEVCLASS' DUMMY
      ID 'OBJTYPE' FIELD 'PROG'
      ID 'OBJNAME' FIELD lv_name
      ID 'P_GROUP' DUMMY
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      send_json( io_response = io_response iv_status = 403
        iv_body = '{"success":false,"error":"S_DEVELOP display authorization required"}' ).
      RETURN.
    ENDIF.

    READ REPORT lv_name INTO lt_source.
    IF sy-subrc <> 0.
      send_json( io_response = io_response iv_status = 404
        iv_body = '{"success":false,"error":"Active report not found"}' ).
      RETURN.
    ENDIF.

    lv_body = '{"success":true,"object_type":"PROG","lines":['.
    lv_first = abap_true.
    LOOP AT lt_source INTO lv_line.
      IF lv_first = abap_false.
        CONCATENATE lv_body ',' INTO lv_body.
      ENDIF.
      lv_first = abap_false.
      lv_escaped = lv_line.
      lv_escaped = escape_json( lv_escaped ).
      CONCATENATE lv_body '"' lv_escaped '"' INTO lv_body.
    ENDLOOP.
    CONCATENATE lv_body ']}' INTO lv_body.
    send_json( io_response = io_response iv_status = 200 iv_body = lv_body ).
  ENDMETHOD.

  METHOD handle_read_table_structure.
    DATA lv_json TYPE string.
    DATA lv_name TYPE tabname.
    DATA lt_fields TYPE STANDARD TABLE OF dd03p.
    DATA ls_field TYPE dd03p.
    DATA lv_body TYPE string.
    DATA lv_first TYPE abap_bool.
    DATA lv_length TYPE string.
    DATA lv_decimals TYPE string.
    DATA lv_fieldname TYPE string.
    DATA lv_rollname TYPE string.
    DATA lv_datatype TYPE string.
    DATA lv_description TYPE string.

    lv_json = io_request->get_cdata( ).
    lv_name = get_json_value( iv_json = lv_json iv_name = 'table_name' ).
    TRANSLATE lv_name TO UPPER CASE.

    IF lv_name IS INITIAL.
      send_json( io_response = io_response iv_status = 400
        iv_body = '{"success":false,"error":"Missing table_name"}' ).
      RETURN.
    ENDIF.

    IF lv_name NP 'Z*' AND lv_name NP 'Y*'.
      send_json( io_response = io_response iv_status = 403
        iv_body = '{"success":false,"error":"Trial access is limited to Z and Y DDIC objects"}' ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING
        name          = lv_name
        langu         = sy-langu
      TABLES
        dd03p_tab     = lt_fields
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.
    IF sy-subrc <> 0.
      send_json( io_response = io_response iv_status = 404
        iv_body = '{"success":false,"error":"DDIC object not found"}' ).
      RETURN.
    ENDIF.

    lv_body = '{"success":true,"fields":['.
    lv_first = abap_true.
    LOOP AT lt_fields INTO ls_field.
      IF ls_field-fieldname CP '.INCLUDE*'.
        CONTINUE.
      ENDIF.
      IF lv_first = abap_false.
        CONCATENATE lv_body ',' INTO lv_body.
      ENDIF.
      lv_first = abap_false.
      lv_length = ls_field-leng.
      lv_decimals = ls_field-decimals.
      lv_fieldname = ls_field-fieldname.
      lv_rollname = ls_field-rollname.
      lv_datatype = ls_field-datatype.
      lv_description = ls_field-ddtext.
      lv_fieldname = escape_json( lv_fieldname ).
      lv_rollname = escape_json( lv_rollname ).
      lv_datatype = escape_json( lv_datatype ).
      lv_description = escape_json( lv_description ).
      CONDENSE lv_length.
      CONDENSE lv_decimals.
      CONCATENATE lv_body '{"name":"' lv_fieldname
        '","data_element":"' lv_rollname
        '","datatype":"' lv_datatype
        '","length":' lv_length ',"decimals":' lv_decimals
        ',"description":"' lv_description '"}' INTO lv_body.
    ENDLOOP.
    CONCATENATE lv_body ']}' INTO lv_body.
    send_json( io_response = io_response iv_status = 200 iv_body = lv_body ).
  ENDMETHOD.

  METHOD get_json_value.
    DATA lv_pattern TYPE string.
    DATA lv_rest TYPE string.
    DATA lv_offset TYPE i.
    DATA lv_end TYPE i.

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
    IF lv_rest(1) <> '"'.
      RETURN.
    ENDIF.
    lv_rest = lv_rest+1.
    FIND '"' IN lv_rest MATCH OFFSET lv_end.
    IF sy-subrc = 0.
      rv_value = lv_rest(lv_end).
    ENDIF.
  ENDMETHOD.

  METHOD escape_json.
    rv_value = iv_value.
    REPLACE ALL OCCURRENCES OF '\' IN rv_value WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_value WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_value WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_value WITH '\n'.
  ENDMETHOD.

  METHOD send_json.
    DATA lv_reason TYPE string.
    CASE iv_status.
      WHEN 200. lv_reason = 'OK'.
      WHEN 400. lv_reason = 'Bad Request'.
      WHEN 403. lv_reason = 'Forbidden'.
      WHEN 404. lv_reason = 'Not Found'.
      WHEN OTHERS. lv_reason = 'Error'.
    ENDCASE.
    io_response->set_status( code = iv_status reason = lv_reason ).
    io_response->set_content_type( content_type = 'application/json; charset=utf-8' ).
    io_response->set_cdata( data = iv_body ).
  ENDMETHOD.
ENDCLASS.
