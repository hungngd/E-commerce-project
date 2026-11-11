-- Q8: Identify the top 50 customers based on their total lifetime spend
-- and calculate the number of days since their last order.
WITH customer_summary AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        SUM(s.sales) AS total_lifetime_spend,
        MAX(s.order_date) AS last_order_date_customer
    FROM {{ ref('stg_customer') }} AS c
    INNER JOIN {{ ref('stg_ecom_sales') }} AS s
        ON c.customer_id = s.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
    ORDER BY total_lifetime_spend DESC
    LIMIT 50
),

bound AS (
    SELECT MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
)

SELECT
    cs.total_lifetime_spend,
    cs.last_order_date_customer,
    cs.first_name || ' ' || cs.last_name AS customer_name,
    DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) AS days_since_last_order
FROM customer_summary AS cs
CROSS JOIN bound AS b
WHERE DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) >= 180
ORDER BY cs.total_lifetime_spend DESC
