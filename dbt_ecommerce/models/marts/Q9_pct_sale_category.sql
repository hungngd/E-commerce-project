-- Q9: Calculate the percentage of sales by customer segment for each product category
WITH total_sale_category AS (
    SELECT
        p.category,
        SUM(CASE WHEN s.segment = 'Consumer' THEN s.sales ELSE 0 END) AS consumer_sales,
        SUM(CASE WHEN s.segment = 'Corporate' THEN s.sales ELSE 0 END) AS corporate_sales,
        SUM(CASE WHEN s.segment = 'Self-Employed' THEN s.sales ELSE 0 END) AS self_employed_sales,
        SUM(s.sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }} AS s
    INNER JOIN {{ ref('stg_product') }} AS p
        ON s.product_code = p.product_code
    GROUP BY p.category
)

SELECT
    category,
    CAST(
        100.0
        * consumer_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_consumer,
    CAST(
        100.0
        * corporate_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_corporate,
    CAST(
        100.0
        * self_employed_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_self_employed,
    total_sales
FROM total_sale_category
ORDER BY category
