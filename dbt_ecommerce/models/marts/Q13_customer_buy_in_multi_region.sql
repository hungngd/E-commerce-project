-- Q13: Identify customers who have made purchases in multiple regions and calculate the percentage of such customers.
WITH customer_details AS (
    SELECT 
        customer_id,
        order_id,
        region_code,
        order_date,
        sales
    FROM {{ ref('stg_ecom_sales') }}
    
), first_region AS (
    SELECT
        customer_id,
        region_code,
        FIRST_VALUE(region_code) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS first_region,
        sales
    FROM customer_details
), flag_customers AS (
    SELECT
        customer_id,
        first_region,
        region_code,
        sales,
        CASE
            WHEN first_region != region_code THEN 1
            ELSE 0
        END AS flag_customers
    FROM first_region
), customer_region_summary AS (
    SELECT
        customer_id,
        first_region,
        SUM(sales) AS total_sales,
        MAX(flag_customers) AS is_multi_region,
        COUNT(DISTINCT region_code) AS region_count
    FROM flag_customers
    GROUP BY customer_id, first_region
), pct_multi_region AS (
    SELECT
        CAST(100.0 * SUM(is_multi_region) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS multi_region_pct
    FROM customer_region_summary
)
SELECT
    crs.customer_id,
    r.city AS first_city,
    r.country,
    crs.total_sales,
    pmr.multi_region_pct
FROM customer_region_summary crs
CROSS JOIN pct_multi_region  pmr
JOIN {{ ref('stg_region') }} AS r
    ON crs.first_region = r.region_code
WHERE crs.is_multi_region = 1
ORDER BY crs.total_sales DESC
LIMIT 20