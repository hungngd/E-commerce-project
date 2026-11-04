-- Q2: Calculate the total revenue and profit for each segment.
SELECT
    segment,
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }}
GROUP BY segment
ORDER BY total_revenue DESC