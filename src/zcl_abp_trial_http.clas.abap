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

    METHODS handle_read_table_data
      IMPORTING
        io_request  TYPE REF TO if_http_request
        io_response TYPE REF TO if_http_response.

    METHODS handle_diagnose_error
      IMPORTING
        io_request  TYPE REF TO if_http_request
        io_response TYPE REF TO if_http_response.

    METHODS check_table_auth
      IMPORTING
        iv_table_name TYPE tabname
      RETURNING
        VALUE(rv_authorized) TYPE abap_bool.

ENDCLASS.

CLASS zcl_abp_trial_http IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    DATA lv_path TYPE string.
    DATA lv_license_error TYPE string.

    lv_path = server->request->get_header_field( name = '~path_info' ).
    TRANSLATE lv_path TO LOWER CASE.

    lv_license_error = zcl_abp_trial_license=>validate( server->request ).
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
      WHEN '/diagnose_error'.
        handle_diagnose_error(
          io_request  = server->request
          io_response = server->response ).
      WHEN OTHERS.
        send_json(
          io_response = server->response
          iv_status   = 404
          iv_body     = '{"success":false,"error":"Unknown trial endpoint"}' ).
    ENDCASE.
  ENDMETHOD.

  METHOD handle_diagnose_error.
    TYPES: BEGIN OF ty_message,
             arbgb TYPE t100-arbgb,
             msgnr TYPE t100-msgnr,
             text  TYPE t100-text,
             score TYPE i,
           END OF ty_message.
    TYPES tt_messages TYPE STANDARD TABLE OF ty_message WITH DEFAULT KEY.
    TYPES tt_programs TYPE STANDARD TABLE OF progname WITH DEFAULT KEY.
    TYPES: BEGIN OF ty_program_detail,
             name TYPE trdir-name,
             udat TYPE trdir-udat,
           END OF ty_program_detail.
    TYPES tt_program_details TYPE STANDARD TABLE OF ty_program_detail WITH DEFAULT KEY.
    TYPES tt_words TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    DATA lv_json TYPE string.
    DATA lv_message_id TYPE t100-arbgb.
    DATA lv_message_number TYPE t100-msgnr.
    DATA lv_message_text TYPE t100-text.
    DATA lv_input_text TYPE string.
    DATA lv_screenshot_text TYPE string.
    DATA lv_normalized TYPE string.
    DATA lv_candidate_text TYPE string.
    DATA lv_word TYPE string.
    DATA lv_anchor TYPE string.
    DATA lv_second_anchor TYPE string.
    DATA lv_word_length TYPE i.
    DATA lv_anchor_length TYPE i.
    DATA lv_second_anchor_length TYPE i.
    DATA lv_first_character TYPE c LENGTH 1.
    DATA lv_anchor_tail TYPE string.
    DATA lv_score_text TYPE string.
    DATA lv_language TYPE sylangu.
    DATA lv_program TYPE progname.
    DATA lv_transaction TYPE tstc-tcode.
    DATA lv_search_pattern TYPE string.
    DATA lv_search_pattern_lower TYPE string.
    DATA lv_search_pattern_title TYPE string.
    DATA lv_second_pattern TYPE string.
    DATA lv_second_pattern_lower TYPE string.
    DATA lv_second_pattern_title TYPE string.
    DATA lv_message_id_text TYPE string.
    DATA lv_id_pattern TYPE string.
    DATA lv_default_pattern TYPE string.
    DATA lv_number_pattern TYPE string.
    DATA lv_line TYPE ty_source_line.
    DATA lv_upper_line TYPE string.
    DATA lv_body TYPE string.
    DATA lv_escaped TYPE string.
    DATA lv_line_number TYPE i.
    DATA lv_line_text TYPE string.
    DATA lv_hit_count TYPE i.
    DATA lv_candidate_count TYPE i.
    DATA lv_programs_read TYPE i.
    DATA lv_auth_skipped TYPE i.
    DATA lv_programs_read_text TYPE string.
    DATA lv_auth_skipped_text TYPE string.
    DATA lv_first TYPE abap_bool.
    DATA lv_default_message_id TYPE abap_bool.
    DATA lv_scoped_program TYPE abap_bool.
    DATA lt_messages TYPE tt_messages.
    DATA lt_ranked_messages TYPE tt_messages.
    DATA ls_message TYPE ty_message.
    DATA ls_search_message TYPE ty_message.
    DATA lt_words TYPE tt_words.
    DATA lt_programs TYPE tt_programs.
    DATA lt_program_details TYPE tt_program_details.
    DATA ls_program_detail TYPE ty_program_detail.
    DATA lt_source TYPE tt_source.

    lv_json = io_request->get_cdata( ).
    lv_message_id = get_json_value( iv_json = lv_json iv_name = 'message_id' ).
    lv_message_number = get_json_value( iv_json = lv_json iv_name = 'message_number' ).
    lv_input_text = get_json_value( iv_json = lv_json iv_name = 'message_text' ).
    lv_screenshot_text = get_json_value( iv_json = lv_json iv_name = 'screenshot_text' ).
    IF lv_input_text IS INITIAL.
      lv_input_text = lv_screenshot_text.
    ENDIF.
    lv_language = get_json_value( iv_json = lv_json iv_name = 'language' ).
    lv_program = get_json_value( iv_json = lv_json iv_name = 'program_name' ).
    lv_transaction = get_json_value( iv_json = lv_json iv_name = 'transaction' ).
    TRANSLATE lv_message_id TO UPPER CASE.
    TRANSLATE lv_program TO UPPER CASE.
    TRANSLATE lv_transaction TO UPPER CASE.
    IF lv_language IS INITIAL.
      lv_language = sy-langu.
    ENDIF.
    TRANSLATE lv_language TO UPPER CASE.

    IF lv_program IS INITIAL AND lv_transaction IS NOT INITIAL.
      SELECT SINGLE pgmna FROM tstc INTO lv_program
        WHERE tcode = lv_transaction.
    ENDIF.

    IF lv_message_id IS INITIAL OR lv_message_number IS INITIAL.
      IF lv_input_text IS INITIAL.
        send_json( io_response = io_response iv_status = 400
          iv_body = '{"success":false,"error":"Provide message_id and message_number, or message_text"}' ).
        RETURN.
      ENDIF.
      lv_normalized = lv_input_text.
      TRANSLATE lv_normalized TO UPPER CASE.
      REPLACE ALL OCCURRENCES OF '.' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF ',' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF ':' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF ';' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF '(' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF ')' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF '/' IN lv_normalized WITH ' '.
      REPLACE ALL OCCURRENCES OF '-' IN lv_normalized WITH ' '.
      CONDENSE lv_normalized.
      SPLIT lv_normalized AT space INTO TABLE lt_words.
      LOOP AT lt_words INTO lv_word.
        lv_word_length = strlen( lv_word ).
        IF lv_word_length < 4 OR lv_word CO '0123456789'.
          DELETE lt_words.
          CONTINUE.
        ENDIF.
        IF lv_word_length > lv_anchor_length.
          lv_second_anchor = lv_anchor.
          lv_second_anchor_length = lv_anchor_length.
          lv_anchor = lv_word.
          lv_anchor_length = lv_word_length.
        ELSEIF lv_word_length > lv_second_anchor_length.
          lv_second_anchor = lv_word.
          lv_second_anchor_length = lv_word_length.
        ENDIF.
      ENDLOOP.
      IF lv_anchor IS INITIAL.
        send_json( io_response = io_response iv_status = 400
          iv_body = '{"success":false,"error":"The error text does not contain enough stable words to search T100"}' ).
        RETURN.
      ENDIF.
      CONCATENATE '%' lv_anchor '%' INTO lv_search_pattern.
      TRANSLATE lv_anchor TO LOWER CASE.
      CONCATENATE '%' lv_anchor '%' INTO lv_search_pattern_lower.
      lv_first_character = lv_anchor+0(1).
      TRANSLATE lv_first_character TO UPPER CASE.
      lv_anchor_tail = lv_anchor+1.
      CONCATENATE lv_first_character lv_anchor_tail INTO lv_anchor.
      CONCATENATE '%' lv_anchor '%' INTO lv_search_pattern_title.
      CONCATENATE '%' lv_second_anchor '%' INTO lv_second_pattern.
      TRANSLATE lv_second_anchor TO LOWER CASE.
      CONCATENATE '%' lv_second_anchor '%' INTO lv_second_pattern_lower.
      lv_first_character = lv_second_anchor+0(1).
      TRANSLATE lv_first_character TO UPPER CASE.
      lv_anchor_tail = lv_second_anchor+1.
      CONCATENATE lv_first_character lv_anchor_tail INTO lv_second_anchor.
      CONCATENATE '%' lv_second_anchor '%' INTO lv_second_pattern_title.
      SELECT arbgb msgnr text FROM t100 INTO TABLE lt_messages
        UP TO 100 ROWS
        WHERE sprsl = lv_language
          AND ( text LIKE lv_search_pattern
             OR text LIKE lv_search_pattern_lower
             OR text LIKE lv_search_pattern_title )
          AND ( text LIKE lv_second_pattern
             OR text LIKE lv_second_pattern_lower
             OR text LIKE lv_second_pattern_title ).
      LOOP AT lt_messages INTO ls_message.
        lv_candidate_text = ls_message-text.
        TRANSLATE lv_candidate_text TO UPPER CASE.
        CLEAR ls_message-score.
        LOOP AT lt_words INTO lv_word.
          IF lv_candidate_text CS lv_word.
            ls_message-score = ls_message-score + 1.
          ENDIF.
        ENDLOOP.
        MODIFY lt_messages FROM ls_message.
      ENDLOOP.
      SORT lt_messages BY score DESCENDING arbgb ASCENDING msgnr ASCENDING.
      CLEAR lt_ranked_messages.
      LOOP AT lt_messages INTO ls_message FROM 1 TO 5.
        APPEND ls_message TO lt_ranked_messages.
      ENDLOOP.
      lt_messages = lt_ranked_messages.
      READ TABLE lt_messages INTO ls_message INDEX 1.
      IF sy-subrc <> 0.
        send_json( io_response = io_response iv_status = 404
          iv_body = '{"success":false,"error":"No T100 candidate matched the stable words in the supplied error text"}' ).
        RETURN.
      ENDIF.
      lv_message_id = ls_message-arbgb.
      lv_message_number = ls_message-msgnr.
      lv_message_text = ls_message-text.
    ELSE.
      SELECT SINGLE text FROM t100 INTO lv_message_text
        WHERE sprsl = lv_language
          AND arbgb = lv_message_id
          AND msgnr = lv_message_number.
      IF sy-subrc <> 0.
        send_json( io_response = io_response iv_status = 404
          iv_body = '{"success":false,"error":"Message class and number not found in T100"}' ).
        RETURN.
      ENDIF.
      CLEAR lt_messages.
      ls_message-arbgb = lv_message_id.
      ls_message-msgnr = lv_message_number.
      ls_message-text = lv_message_text.
      ls_message-score = 100.
      APPEND ls_message TO lt_messages.
    ENDIF.

    IF lv_program IS NOT INITIAL.
      IF lv_program CP 'Z*' OR lv_program CP 'Y*'.
        lv_scoped_program = abap_true.
        APPEND lv_program TO lt_programs.
      ENDIF.
    ELSE.
      SELECT name udat FROM trdir INTO TABLE lt_program_details
        UP TO 5000 ROWS
        WHERE name LIKE 'Z%'
        ORDER BY name ASCENDING.
      LOOP AT lt_program_details INTO ls_program_detail.
        APPEND ls_program_detail-name TO lt_programs.
      ENDLOOP.
      CLEAR lt_program_details.
      SELECT name udat FROM trdir INTO TABLE lt_program_details
        UP TO 5000 ROWS
        WHERE name LIKE 'Y%'
        ORDER BY name ASCENDING.
      LOOP AT lt_program_details INTO ls_program_detail.
        APPEND ls_program_detail-name TO lt_programs.
      ENDLOOP.
    ENDIF.

    lv_message_id_text = lv_message_id.
    CONDENSE lv_message_id_text NO-GAPS.
    lv_number_pattern = lv_message_number.
    CONDENSE lv_number_pattern NO-GAPS.

    lv_escaped = lv_message_id_text.
    lv_escaped = escape_json( lv_escaped ).
    lv_body = '{"success":true,"message":{"id":"'.
    CONCATENATE lv_body lv_escaped '","number":"' lv_message_number
      '","text":"' INTO lv_body.
    lv_escaped = lv_message_text.
    lv_escaped = escape_json( lv_escaped ).
    CONCATENATE lv_body lv_escaped '"},"t100_candidates":[' INTO lv_body.
    lv_first = abap_true.
    LOOP AT lt_messages INTO ls_message.
      IF lv_first = abap_false.
        CONCATENATE lv_body ',' INTO lv_body.
      ENDIF.
      lv_first = abap_false.
      lv_candidate_count = lv_candidate_count + 1.
      lv_escaped = ls_message-text.
      lv_escaped = escape_json( lv_escaped ).
      lv_score_text = ls_message-score.
      CONDENSE lv_score_text NO-GAPS.
      CONCATENATE lv_body '{"id":"' ls_message-arbgb
        '","number":"' ls_message-msgnr '","text":"'
        lv_escaped '","score":' lv_score_text '}' INTO lv_body.
    ENDLOOP.
    CONCATENATE lv_body '],"custom_code_hits":[' INTO lv_body.

    lv_first = abap_true.
    LOOP AT lt_programs INTO lv_program.
      AUTHORITY-CHECK OBJECT 'S_DEVELOP'
        ID 'DEVCLASS' DUMMY
        ID 'OBJTYPE' FIELD 'PROG'
        ID 'OBJNAME' FIELD lv_program
        ID 'P_GROUP' DUMMY
        ID 'ACTVT' FIELD '03'.
      IF sy-subrc <> 0.
        lv_auth_skipped = lv_auth_skipped + 1.
        CONTINUE.
      ENDIF.

      CLEAR lt_source.
      READ REPORT lv_program INTO lt_source.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      lv_programs_read = lv_programs_read + 1.

      LOOP AT lt_messages INTO ls_search_message.
        lv_message_id_text = ls_search_message-arbgb.
        CONDENSE lv_message_id_text NO-GAPS.
        lv_number_pattern = ls_search_message-msgnr.
        CONDENSE lv_number_pattern NO-GAPS.
        CONCATENATE '(' lv_message_id_text ')' INTO lv_id_pattern.
        CONCATENATE 'MESSAGE-ID ' lv_message_id_text INTO lv_default_pattern.

        lv_default_message_id = abap_false.
        LOOP AT lt_source INTO lv_line.
          lv_upper_line = lv_line.
          TRANSLATE lv_upper_line TO UPPER CASE.
          IF lv_upper_line CS lv_default_pattern.
            lv_default_message_id = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.

        CLEAR lv_line_number.
        LOOP AT lt_source INTO lv_line.
          lv_line_number = lv_line_number + 1.
          lv_upper_line = lv_line.
          TRANSLATE lv_upper_line TO UPPER CASE.
          IF lv_upper_line NS 'MESSAGE'.
            CONTINUE.
          ENDIF.
          IF lv_upper_line NS lv_number_pattern.
            CONTINUE.
          ENDIF.
          IF lv_upper_line NS lv_id_pattern
             AND lv_default_message_id = abap_false.
            CONTINUE.
          ENDIF.

          IF lv_first = abap_false.
            CONCATENATE lv_body ',' INTO lv_body.
          ENDIF.
          lv_first = abap_false.
          lv_hit_count = lv_hit_count + 1.
          lv_line_text = lv_line_number.
          CONDENSE lv_line_text NO-GAPS.
          lv_escaped = lv_line.
          lv_escaped = escape_json( lv_escaped ).
          CONCATENATE lv_body '{"program":"' lv_program
            '","line":' lv_line_text ',"source":"' lv_escaped
            '","message_id":"' ls_search_message-arbgb
            '","message_number":"' ls_search_message-msgnr
            '","match_basis":"explicit message class or program MESSAGE-ID"}'
            INTO lv_body.
          IF lv_hit_count >= 5.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_hit_count >= 5.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_hit_count >= 5.
        EXIT.
      ENDIF.
    ENDLOOP.

    lv_programs_read_text = lv_programs_read.
    lv_auth_skipped_text = lv_auth_skipped.
    CONDENSE lv_programs_read_text NO-GAPS.
    CONDENSE lv_auth_skipped_text NO-GAPS.
    CONCATENATE lv_body '],"scope":{"read_only":true,'
      '"source_exposure":"Z/Y only","max_hits":5,'
      '"max_programs_scanned":10000,"programs_read":' lv_programs_read_text
      ',"authorization_skipped":' lv_auth_skipped_text
      '},"guidance":"Use the resolved T100 message and custom-code locations to explain the triggering condition. Standard SAP source is not exposed by the trial."}'
      INTO lv_body.
    send_json( io_response = io_response iv_status = 200 iv_body = lv_body ).
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
    IF sy-subrc <> 0 OR lt_fields IS INITIAL.
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
      SHIFT lv_length LEFT DELETING LEADING '0'.
      SHIFT lv_decimals LEFT DELETING LEADING '0'.
      IF lv_length IS INITIAL.
        lv_length = '0'.
      ENDIF.
      IF lv_decimals IS INITIAL.
        lv_decimals = '0'.
      ENDIF.
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
