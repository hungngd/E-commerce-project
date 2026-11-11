-- Q1: Calculate the total revenue and profit for the entire dataset.
SELECT
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }}
