-- Q14: Customer Segmentation based on RFM (Recency, Frequency, Monetary) analysis
WITH bound AS (
    SELECT MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
),

customer_details AS (
    SELECT
        s.customer_id,
        MAX(s.order_date) AS last_order_customer,
        DATEDIFF('day', MAX(s.order_date), MAX(b.last_order_date)) AS days_since_last_order,
        COUNT(DISTINCT s.order_id) AS total_orders,
        SUM(s.sales) AS total_spent
    FROM {{ ref('stg_ecom_sales') }} AS s
    CROSS JOIN bound AS b
    GROUP BY s.customer_id
),

filter_segments AS (
    SELECT
        customer_id,
        days_since_last_order AS recency_days,
        total_orders AS frequency,
        total_spent AS monetary,
        NTILE(5) OVER (ORDER BY days_since_last_order DESC) AS n_recency,
        NTILE(5) OVER (ORDER BY total_orders ASC) AS n_orders,
        NTILE(5) OVER (ORDER BY total_spent ASC) AS n_spend
    FROM customer_details
)

SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    n_recency,
    n_orders,
    n_spend,
    n_recency + n_orders + n_spend AS rfm_score
FROM filter_segments
ORDER BY rfm_score DESC
LIMIT 20
