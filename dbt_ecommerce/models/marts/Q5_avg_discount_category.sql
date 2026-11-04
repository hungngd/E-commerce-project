-- Q5: Average discount by category
SELECT
    p.category,
    CAST(
        AVG(s.discount) * 100.0 
        AS DECIMAL(5,2)
    ) AS avg_discount
FROM {{ref ('stg_ecom_sales') }} s
JOIN {{ref ('stg_product') }} p
    ON s.product_code = p.product_code
GROUP BY p.category
ORDER BY avg_discount DESC