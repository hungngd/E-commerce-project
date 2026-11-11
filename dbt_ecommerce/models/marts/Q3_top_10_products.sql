-- Q3: Identify the top 10 best-selling products.
SELECT
    s.product_code,
    p.product,
    SUM(s.quantity) AS total_quantity_sold
FROM {{ ref('stg_ecom_sales') }} AS s
INNER JOIN {{ ref('stg_product') }} AS p
    ON s.product_code = p.product_code
GROUP BY s.product_code, p.product
ORDER BY total_quantity_sold DESC
LIMIT 10
