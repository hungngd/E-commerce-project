-- Q8: Identify the top 50 customers based on their total lifetime spend and calculate the number of days since their last order. 
-- Only include customers who have not placed an order in the last 180 days.
WITH customer_summary AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        SUM(s.sales) AS total_lifetime_spend,
        MAX(s.order_date) AS last_order_date_customer
    FROM {{ ref('stg_customer') }} c
    JOIN {{ ref('stg_ecom_sales') }} s 
        ON c.customer_id = s.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
    ORDER BY total_lifetime_spend DESC
    LIMIT 50
), bound AS (
    SELECT
        MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
)
SELECT
    cs.first_name || ' ' || cs.last_name AS customer_name,
    cs.total_lifetime_spend,
    cs.last_order_date_customer,
    DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) AS days_since_last_order
FROM customer_summary cs
CROSS JOIN bound b
WHERE DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) >= 180
ORDER BY total_lifetime_spend DESC