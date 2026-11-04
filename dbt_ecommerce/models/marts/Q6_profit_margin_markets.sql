-- Q6: Profit margin by market
SELECT
    r.market,
    CAST(SUM(s.sales) AS DECIMAL(10,2)) as total_sales,
    CAST(SUM(s.profit) AS DECIMAL(10,2)) as total_profit,
    CAST(
        100.0 * 
        SUM(s.profit) / NULLIF(SUM(s.sales), 0)  
        AS DECIMAL(5,2)
    ) AS profit_margin
FROM {{ref ('stg_ecom_sales') }} s
JOIN {{ref ('stg_region') }} r
    ON s.region_code = r.region_code
GROUP BY r.market
HAVING COUNT(DISTINCT s.order_id) >= 100
ORDER BY profit_margin DESC