-- Q4: Calculate total customer per gender (Male, female and unknown gender) and occupation.
SELECT
    occupation,
    SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) AS male,
    SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) AS female,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS unknown_gender,
    COUNT(*) AS total_customers
FROM {{ ref('stg_customer') }}
GROUP BY occupation
ORDER BY total_customers DESC