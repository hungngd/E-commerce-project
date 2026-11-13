-- Q16: Profit margin by discount band.
-- At which discount level do order lines start to lose money?
WITH banded AS (
    SELECT
        order_id,
        sales,
        profit,
        CASE
            WHEN discount = 0 THEN '1. 0%'
            WHEN discount <= 0.1 THEN '2. 1-10%'
            WHEN discount <= 0.2 THEN '3. 11-20%'
            WHEN discount <= 0.4 THEN '4. 21-40%'
            ELSE '5. >40%'
        END AS discount_band
    FROM {{ ref('stg_ecom_sales') }}
)

SELECT
    discount_band,
    COUNT(*) AS total_lines,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,
    CAST(
        100.0 * SUM(profit) / NULLIF(SUM(sales), 0) AS DECIMAL(6, 2)
    ) AS profit_margin,
    CAST(
        100.0 * SUM(sales) / SUM(SUM(sales)) OVER () AS DECIMAL(5, 2)
    ) AS pct_of_total_sales,
    CAST(
        100.0 * SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 2)
    ) AS pct_loss_lines
FROM banded
GROUP BY discount_band
ORDER BY discount_band
