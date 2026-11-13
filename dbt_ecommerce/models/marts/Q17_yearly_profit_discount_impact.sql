-- Q17: Split yearly profit into deep-discount lines (discount > 20%) and the rest.
-- Explains why profit fell in 2023 while sales kept growing.
WITH yearly AS (
    SELECT
        YEAR(order_date) AS order_year,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit,
        SUM(CASE WHEN discount > 0.2 THEN sales ELSE 0 END) AS deep_discount_sales,
        SUM(CASE WHEN discount > 0.2 THEN profit ELSE 0 END) AS deep_discount_profit,
        SUM(CASE WHEN discount <= 0.2 THEN profit ELSE 0 END) AS other_profit
    FROM {{ ref('stg_ecom_sales') }}
    GROUP BY YEAR(order_date)
)

SELECT
    order_year,
    total_sales,
    total_profit,
    deep_discount_profit,
    other_profit,
    CAST(
        100.0 * total_profit / NULLIF(total_sales, 0) AS DECIMAL(5, 2)
    ) AS profit_margin,
    CAST(
        100.0 * deep_discount_sales / NULLIF(total_sales, 0) AS DECIMAL(5, 2)
    ) AS pct_sales_deep_discount,
    total_profit - LAG(total_profit) OVER (ORDER BY order_year) AS profit_change,
    deep_discount_profit
    - LAG(deep_discount_profit) OVER (ORDER BY order_year) AS deep_discount_profit_change
FROM yearly
ORDER BY order_year
