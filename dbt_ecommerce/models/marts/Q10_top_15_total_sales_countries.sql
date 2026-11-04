-- Q10: Top 15 couties by total sales, along with the number of active regions and total customers and orders in each country.
SELECT
    r.country,
    COUNT(DISTINCT r.region_code) AS region_active,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT s.order_id) AS total_orders,
    SUM(s.sales) AS total_sales
FROM {{ ref('stg_ecom_sales') }} s
JOIN {{ ref('stg_region') }} r
    ON s.region_code = r.region_code
GROUP BY r.country
ORDER BY total_sales DESC
LIMIT 15