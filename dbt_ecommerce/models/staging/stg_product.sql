SELECT
    product_code,
    product,
    category,
    subcategory
FROM {{ source('e_com_source', 'product') }}