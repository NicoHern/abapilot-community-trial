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
ENDCLASS.

CLASS zcl_abp_trial_http IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    DATA lv_path TYPE string.

    lv_path = server->request->get_header_field( name = '~path_info' ).
    TRANSLATE lv_path TO LOWER CASE.

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
      WHEN OTHERS.
        send_json(
          io_response = server->response
          iv_status   = 404
          iv_body     = '{"success":false,"error":"Unknown trial endpoint"}' ).
    ENDCASE.
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
