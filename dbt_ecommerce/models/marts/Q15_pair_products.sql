-- Q15: Find top 15 best seller pair products.
WITH order_products AS (
    SELECT DISTINCT
        order_id,
        product_code
    FROM {{ ref('stg_ecom_sales') }}
),

self_joined AS (
    SELECT
        a.order_id,
        a.product_code AS product_code_a,
        b.product_code AS product_code_b
    FROM order_products AS a
    INNER JOIN order_products AS b
        ON a.order_id = b.order_id AND a.product_code < b.product_code
)

SELECT
    pa.product AS product_a,
    pb.product AS product_b,
    COUNT(*) AS pair_count
FROM self_joined AS sj
INNER JOIN {{ ref('stg_product') }} AS pa
    ON sj.product_code_a = pa.product_code
INNER JOIN {{ ref('stg_product') }} AS pb
    ON sj.product_code_b = pb.product_code
GROUP BY product_a, product_b
ORDER BY pair_count DESC
LIMIT 15
