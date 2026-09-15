REPORT zabp_trial_lab.

FORM calculate_discount
  USING
    iv_customer_type TYPE char10
  CHANGING
    cv_discount      TYPE i.

  CLEAR cv_discount.
  CASE iv_customer_type.
    WHEN 'GOLD'.
      cv_discount = 15.
    WHEN 'STANDARD'.
      cv_discount = 5.
  ENDCASE.
ENDFORM.
