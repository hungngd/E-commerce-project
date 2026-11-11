-- Q11: Calculate the year-over-year growth in sales for the last 24 months.
WITH sale_months AS (
    SELECT
        DATE_TRUNC('month', order_date) AS month,
        SUM(sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }}
    GROUP BY DATE_TRUNC('month', order_date)
),

previous_year_sales AS (
    SELECT
        month,
        total_sales,
        LAG(total_sales, 12) OVER (ORDER BY month) AS previous_year_sales
    FROM sale_months
),

bound AS (
    SELECT MAX(month) AS max_month
    FROM sale_months
)

SELECT
    pys.total_sales,
    pys.previous_year_sales,
    CAST(
        100 * (pys.total_sales - pys.previous_year_sales)
        / NULLIF(pys.previous_year_sales, 0) AS DECIMAL(5, 2)
    ) AS yoy_growth_pct,
    TO_CHAR(pys.month, 'YYYY-MM') AS month
FROM previous_year_sales AS pys
CROSS JOIN bound AS b
WHERE month >= DATEADD('month', -23, b.max_month)
ORDER BY pys.month
