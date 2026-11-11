SELECT
    region_code,
    city,
    state,
    country,
    country_latitude,
    country_longitude,
    region,
    market
FROM {{ source ('e_com_source', 'region') }}
