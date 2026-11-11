SELECT
    row_id,
    order_id,
    order_date,
    customer_id,
    segment,
    quantity,
    sales,
    discount,
    profit,
    CASE
        WHEN region_code = 'RRR0001' THEN 'R0001'
        ELSE region_code
    END AS region_code,
    CASE
        WHEN product_code = 'PPP000010' THEN 'P000010'
        WHEN product_code = 'PPP000002' THEN 'P000002'
        ELSE product_code
    END AS product_code
FROM {{ source('e_com_source', 'ecom_sales') }}
