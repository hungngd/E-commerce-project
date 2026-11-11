-- Q12: Top 3 products by profit in each category
WITH sale_products AS (
    SELECT
        p.category,
        p.product,
        p.product_code,
        SUM(s.profit) AS total_profit
    FROM {{ ref('stg_ecom_sales') }} AS s
    INNER JOIN {{ ref('stg_product') }} AS p
        ON s.product_code = p.product_code
    GROUP BY p.product, p.category, p.product_code
),

ranked_products AS (
    SELECT
        category,
        product,
        product_code,
        total_profit,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_profit DESC, product_code ASC) AS rank_in_category
    FROM sale_products
)

SELECT
    category,
    product,
    product_code,
    total_profit,
    rank_in_category
FROM ranked_products
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category
