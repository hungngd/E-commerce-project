-- Q7: Loss Order Calculation Segments
WITH order_profit AS ( 
    SELECT
        order_id,
        segment,
        SUM(profit) AS order_profit
    FROM {{ref ('stg_ecom_sales') }} 
    GROUP BY order_id, segment
)
SELECT
    segment,
    COUNT(order_id) AS total_order,
    COUNT(CASE WHEN order_profit < 0 THEN 1 END) AS total_loss_order,
    SUM(CASE WHEN order_profit < 0 THEN order_profit ELSE 0 END ) total_loss_profit,
    CAST(
        100.0 *
        COUNT(CASE WHEN order_profit < 0 THEN 1 END) / NULLIF(COUNT(order_id), 0)
        AS DECIMAL (5,2)
    ) AS loss_order_pct
FROM order_profit
GROUP BY segment
ORDER BY loss_order_pct DESC