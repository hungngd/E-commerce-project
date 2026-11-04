# E-commerce Data Platform – End-to-End Workflow

Dự án xây dựng một **Modern Data Stack** nhằm đưa dữ liệu từ hệ thống nguồn SQL Server vào Data Warehouse, xử lý và mô hình hóa dữ liệu theo các bài toán kinh doanh, sau đó trực quan hóa kết quả bằng Power BI.

## Overall Architecture

```text
SQL Server
    ↓
   dlt
    ↓
Snowflake
    ↓
   dbt
    ↓
 Airflow
    ↓
Power BI
```

---

## 1. Setup Python Environment & GitHub Project

Đầu tiên, tạo project và môi trường Python riêng để quản lý các package cần thiết cho pipeline.

### Virtual Environment

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
```

Virtual environment giúp các package của project được tách biệt với Python global trên máy, tránh xung đột version giữa các project khác nhau.

### GitHub Repository

Project được quản lý bằng Git/GitHub để:

- lưu version của code;
- theo dõi thay đổi;
- dễ chia sẻ hoặc triển khai lại project;
- lưu documentation cho toàn bộ pipeline.

Cấu trúc project hiện tại:

```text
E-commerce-project/
├── dlt_ingestion/
│   └── sqlserver_to_snowflake.py
├── snowflake/
│   └── setup_snowflake.sql
├── dbt_ecommerce/
│   ├── dbt_project.yml
│   └── models/
│       ├── staging/
│       │   ├── e_com_source.yml
│       │   ├── stg_customer.sql
│       │   ├── stg_ecom_sales.sql
│       │   ├── stg_product.sql
│       │   └── stg_region.sql
│       └── marts/
│           ├── Q1_total_rev_profit.sql
│           ├── ... (Q2 đến Q14)
│           └── Q15_pair_products.sql
├── .dlt/
│   └── secrets.toml              # Không đưa lên GitHub
├── .venv/                        # Không đưa lên GitHub
├── .gitignore
├── README.md
└── Step_By_Step.md
```

---

## 2. Connect dlt to SQL Server

### dlt là gì?

`dlt` là một **data ingestion / data loading framework viết bằng Python**.

Thay vì phải tự viết toàn bộ logic để:

```text
Connect database
→ Extract data
→ Infer schema
→ Normalize data
→ Create destination tables
→ Load data
→ Track pipeline state
```

dlt cung cấp sẵn các abstraction giúp thực hiện những bước này bằng code Python ngắn gọn hơn.

Trong project này:

```text
SQL Server = Source
dlt        = Data ingestion tool
Snowflake  = Destination
```

### SQL Server Source

Source database:

```text
Database: xomdata_dataset
Schema:   e_commerce
```

Các bảng:

```text
customer
ecom_sales
product
region
```

Khai báo source:

```python
from dlt.sources.sql_database import sql_database

source = sql_database(
    schema="e_commerce"
)
```

Sau khi connect thành công:

```python
print(source.resources.keys())
```

kết quả:

```text
dict_keys(['customer', 'ecom_sales', 'product', 'region'])
```

Điều này xác nhận dlt đã kết nối được SQL Server và nhận diện đúng các bảng nguồn.

---

## 3. Store Credentials Securely

Thông tin đăng nhập không được viết trực tiếp trong Python code.

Tạo:

```text
.dlt/secrets.toml
```

để lưu các thông tin như:

```text
SQL Server username
SQL Server password
SQL Server host
Snowflake username
Snowflake password
Snowflake account
Database
Warehouse
Role
```

### `.gitignore`

Tạo thêm:

```text
.gitignore
```

và thêm:

```gitignore
.venv/
.dlt/secrets.toml
```

Mục đích:

> Không đưa virtual environment và các thông tin đăng nhập/private credentials lên GitHub.

---

## 4. Prepare Snowflake

Sau khi source SQL Server đã hoạt động, chuẩn bị Snowflake làm **Data Warehouse**.

Trong Snowflake cần phân biệt:

```text
DATABASE  = nơi tổ chức/lưu dữ liệu

SCHEMA    = nhóm các table bên trong database

WAREHOUSE = compute resource dùng để chạy query/load data
```

### Create Database

```sql
CREATE DATABASE IF NOT EXISTS ECOMMERCE_DB;
```

### Create Warehouse

```sql
CREATE WAREHOUSE IF NOT EXISTS ECOMMERCE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

`XSMALL` đủ cho project học tập và tiết kiệm Snowflake credits.

`AUTO_SUSPEND = 60` giúp warehouse tự tắt khi không hoạt động.

`AUTO_RESUME = TRUE` cho phép warehouse tự bật lại khi pipeline cần chạy.

---

## 5. Create Role for dlt

Không nên cho pipeline sử dụng trực tiếp `ACCOUNTADMIN`.

Thay vào đó, tạo một custom role riêng:

```text
DLT_LOADER_ROLE
```

Role có thể hiểu là:

> Một tập hợp các quyền mà pipeline được phép sử dụng.

```sql
CREATE ROLE IF NOT EXISTS DLT_LOADER_ROLE;

GRANT USAGE
ON WAREHOUSE ECOMMERCE_WH
TO ROLE DLT_LOADER_ROLE;

GRANT USAGE
ON DATABASE ECOMMERCE_DB
TO ROLE DLT_LOADER_ROLE;

GRANT CREATE SCHEMA
ON DATABASE ECOMMERCE_DB
TO ROLE DLT_LOADER_ROLE;

GRANT ROLE DLT_LOADER_ROLE
TO ROLE SYSADMIN;
```

Role này cho phép dlt:

```text
Use ECOMMERCE_WH
        ↓
Có compute để chạy load/query

Access ECOMMERCE_DB
        ↓
Truy cập database đích

Create Schema
        ↓
Có thể tạo RAW_ECOMMERCE
```

Đây là nguyên tắc **least privilege**:

> Pipeline chỉ được cấp những quyền cần thiết cho nhiệm vụ ingestion, thay vì quyền admin toàn hệ thống.

---

## 6. Create Snowflake User for dlt

Role chỉ định **được làm gì**, nhưng vẫn cần một user để xác định:

> Ai đang đăng nhập?

Tạo:

```text
DLT_LOADER_USER
```

và gán:

```text
DLT_LOADER_USER
        ↓
DLT_LOADER_ROLE
        ↓
ECOMMERCE_WH + ECOMMERCE_DB
```

Ví dụ:

```sql
CREATE USER IF NOT EXISTS DLT_LOADER_USER
    PASSWORD = '<YOUR_PASSWORD>'
    DEFAULT_ROLE = DLT_LOADER_ROLE
    DEFAULT_WAREHOUSE = ECOMMERCE_WH
    DEFAULT_NAMESPACE = ECOMMERCE_DB;

GRANT ROLE DLT_LOADER_ROLE
TO USER DLT_LOADER_USER;
```

Password thật không được lưu trong SQL file trên GitHub.

Credentials của user được lưu trong:

```text
.dlt/secrets.toml
```

---

## 7. Configure Snowflake Destination

Trong `secrets.toml`, khai báo Snowflake destination:

```toml
[destination.snowflake.credentials]

username = "DLT_LOADER_USER"
password = "<PASSWORD>"
host = "<SNOWFLAKE_ACCOUNT_IDENTIFIER>"
database = "ECOMMERCE_DB"
warehouse = "ECOMMERCE_WH"
role = "DLT_LOADER_ROLE"
```

Lúc này dlt đã có đầy đủ:

```text
Source credentials       → SQL Server
Destination credentials  → Snowflake
```

---

## 8. Create the dlt Pipeline

Pipeline có thể hiểu là **toàn bộ tuyến vận chuyển dữ liệu**.

```python
pipeline = dlt.pipeline(
    pipeline_name="ecommerce_pipeline",
    destination="snowflake",
    dataset_name="raw_ecommerce"
)
```

Trong đó:

```text
pipeline_name
= tên pipeline để dlt quản lý state và metadata

destination
= nơi dữ liệu được load tới

dataset_name
= schema đích trong Snowflake
```

Vì:

```python
dataset_name="raw_ecommerce"
```

nên destination cuối cùng là:

```text
ECOMMERCE_DB.RAW_ECOMMERCE
```

---

## 9. Load Data from SQL Server to Snowflake

Pipeline được thực thi bằng:

```python
pipeline.run(source)
```

Bản chất bên trong:

```text
SQL Server
    ↓
EXTRACT
    ↓
NORMALIZE
    ↓
LOAD
    ↓
Snowflake
```

Sau lần load đầu tiên, Snowflake tự động có:

```text
ECOMMERCE_DB
└── RAW_ECOMMERCE
    ├── CUSTOMER
    ├── ECOM_SALES
    ├── PRODUCT
    ├── REGION
    ├── _DLT_LOADS
    ├── _DLT_PIPELINE_STATE
    └── _DLT_VERSION
```

Các bảng `_DLT_*` được dlt sử dụng để quản lý metadata, schema version, load history và pipeline state.

---

## 10. Choose the Loading Strategy

Kiểm tra source `ecom_sales`:

```text
Minimum order date: 2020-01-01
Maximum order date: 2023-12-31
Total rows:         51,290
```

Dataset được xem là một **historical/static snapshot** trong phạm vi project.

Vì vậy, không cần thiết kế incremental loading phức tạp.

Sử dụng:

```python
load_info = pipeline.run(
    source,
    write_disposition="replace"
)

print(load_info)
```

### Why `replace`?

Nếu sử dụng `append` với một static dataset:

```text
Run 1 → 51,290 rows
Run 2 → 102,580 rows
Run 3 → 153,870 rows
```

có thể tạo duplicate data.

`replace` sẽ full refresh lại RAW tables:

```text
SQL Server snapshot
        ↓
replace
        ↓
Snowflake RAW
```

Nhờ đó Snowflake luôn phản ánh đúng trạng thái hiện tại của source.

---

## 11. Validate Loaded Data

Sau khi load, đối chiếu row count giữa source và destination.

| Table | SQL Server | Snowflake | Status |
|---|---:|---:|---|
| `customer` | 17,415 | 17,415 | ✅ |
| `ecom_sales` | 51,290 | 51,290 | ✅ |
| `product` | 28,356 | 28,356 | ✅ |
| `region` | 3,828 | 3,828 | ✅ |

Tất cả row counts đều khớp.

Do đó:

```text
SQL Server
    ↓
   dlt
    ↓
Snowflake RAW
```

**Ingestion phase completed successfully.**

---

## 12. Transform Data with dbt

Sau khi nạp dữ liệu vào `ECOMMERCE_DB.RAW_ECOMMERCE` bằng dlt, dùng dbt để quản lý nguồn dữ liệu, kiểm tra chất lượng và xây dựng các SQL models phục vụ phân tích.

**Cấu trúc sử dụng trong project:**

```text
SQL Server (e_commerce)
    ↓ dlt
Snowflake: ECOMMERCE_DB.RAW_ECOMMERCE
    ↓ dbt source() / staging views
Snowflake: ECOMMERCE_DB.DBT_DEV.STG_*
    ↓ dbt ref() / marts
Snowflake: ECOMMERCE_DB.DBT_DEV.Q1_* ... Q15_*
```

### 12.1. Full dlt ingestion script

**Đường dẫn:** `dlt_ingestion/sqlserver_to_snowflake.py`

Đây là file Python đã dùng để khai báo nguồn, cấu hình pipeline và thực hiện `replace` load. Cấu hình kết nối riêng tư nằm trong `.dlt/secrets.toml` (không commit).

```python
import dlt
from dlt.sources.sql_database import sql_database

source = sql_database(
    schema="e_commerce"
)

pipeline = dlt.pipeline(
    pipeline_name="ecommerce_pipeline",
    destination="snowflake",
    dataset_name="raw_ecommerce"
)

load_info = pipeline.run(
    source,
    write_disposition="replace"
)

print(load_info)
```

### 12.2. dbt project configuration

**Đường dẫn:** `dbt_ecommerce/dbt_project.yml`

`name` đặt tên project; `profile` liên kết với cấu hình Snowflake trong `~/.dbt/profiles.yml`; các cấu hình `materialized` quy định loại object dbt tạo trong Snowflake.

Dưới đây là **nội dung nguyên bản của file đã cung cấp**, không tự ý chỉnh sửa:

```yaml

# Name your project! Project names should contain only lowercase characters
# and underscores. A good package name should reflect your organization's
# name or the intended use of these models
name: 'dbt_ecommerce'
version: '1.0.0'

# This setting configures which "profile" dbt uses for this project.
profile: 'dbt_ecommerce'

# These configurations specify where dbt should look for different types of files.
# The `model-paths` config, for example, states that models in this project can be
# found in the "models/" directory. You probably won't need to change these!
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:         # directories to be removed by `dbt clean`
  - "target"
  - "dbt_packages"


# Configuring models
# Full documentation: https://docs.getdbt.com/docs/configuring-models

# In this example config, we tell dbt to build all models in the example/
# directory as views. These settings can be overridden in the individual model
# files using the `{{ config(...) }}` macro.
models:
  dbt_ecommerce:
    staging:
      +materialized: view
    mart:
      +materialized: table
```

> **Kiểm tra trước khi chạy:** File cấu hình được gửi dùng khóa `mart`, còn thư mục ở repository là `models/marts/`. Nếu đúng là `marts`, cần đặt cấu hình dưới `marts:` để `+materialized: table` được áp dụng. Đây là lưu ý đối chiếu file đã gửi; có thể bạn đã sửa trong project hiện tại.

### 12.3. dbt source definitions & tests

**Đường dẫn:** `dbt_ecommerce/models/staging/e_com_source.yml`

File khai báo bốn bảng RAW và các bài kiểm tra `unique`, `not_null`, `relationships` cho các cột liên quan. `source()` được dùng trong staging để truy xuất raw tables.

```yaml
version: 2

sources:
  - name: e_com_source # Đặt tên cho source
    database: ecommerce_db # Tên database chứa dữ liệu nguồn  
    schema: raw_ecommerce # Tên schema chứa dữ liệu nguồn
    description: "This is the source data for the e-commerce project." # Viết comment cho từng nội dung
    tables:
      - name: customer # Tạo test + description cho từng cột trong bảng
        description: "This table contains customer information."
        columns:
          - name: customer_id
            description: "The unique identifier for each customer."
            tests:
              - unique # Test duplicate values
              - not_null # Test null values

      - name: ecom_sales
        description: "This table contains sales information."
        columns:
          - name: order_id
            description: "The identifier for each order."
            tests:
              - not_null
          - name: customer_id
            description: "The unique identifier for the customer who placed the order."
            tests:
              - relationships: # Set up foreign key relationship to the customers table
                  arguments:
                    to: source('e_com_source', 'customer')
                    field: customer_id
          - name: product_code
            description: "The unique code for the product that was ordered."
            tests:
              - relationships: # Set up foreign key relationship to the products table
                  arguments:
                    to: source('e_com_source', 'product')
                    field: product_code
          - name: region_code
            description: "The code for the region where the order was placed."
            tests:
              - relationships: # Set up foreign key relationship to the regions table
                  arguments:
                    to: source('e_com_source', 'region')
                    field: region_code
          - name: order_date
            description: "The date when the order was placed."
            tests:
              - not_null

      - name: product
        description: "This table contains product information."
        columns:
          - name: product_code
            description: "The unique code for each product."
            tests:
              - unique
              - not_null

      - name: region
        description: "This table contains region information."
        columns:
          - name: region_code
            description: "The unique code for each region."
            tests:
              - unique
              - not_null
```

**Ghi nhận từ quá trình kiểm thử:** Relationship tests ở RAW đã từng phát hiện `RRR0001` không khớp `region_code` và các mã `PPP000010`, `PPP000002` không khớp `product_code`. Đây là lỗi dữ liệu nguồn được xác định trong project, không phải lỗi cú pháp SQL. Phần staging xử lý cụ thể các giá trị đã phát hiện. Test trực tiếp trên RAW có thể tiếp tục fail ngay cả khi dữ liệu staging đã được làm sạch.

### 12.4. Staging models

Các model staging lấy dữ liệu từ `source('e_com_source', ...)` và được cấu hình materialize thành `view`.

#### `stg_customer.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_customer.sql`

```sql
SELECT
    customer_id,
    first_name,
    last_name,
    birth_date,
    marital_status,
    gender,
    email_address,
    annual_income,
    education_level,
    occupation,
    home_owner
FROM {{ source('e_com_source', 'customer') }}
```

#### `stg_ecom_sales.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_ecom_sales.sql`

```sql
SELECT
    row_id,
    order_id,
    order_date,
    customer_id,
    segment,
    CASE
        WHEN region_code = 'RRR0001' THEN 'R0001'
        ELSE region_code
    END AS region_code,
    CASE
        WHEN product_code = 'PPP000010' THEN 'P000010'
        WHEN product_code = 'PPP000002' THEN 'P000002'
        ELSE product_code
    END AS product_code,
    quantity,
    sales,
    discount,
    profit
FROM {{ source('e_com_source', 'ecom_sales') }}
```

#### `stg_product.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_product.sql`

```sql
SELECT
    product_code,
    product,
    category,
    subcategory
FROM {{ source('e_com_source', 'product') }}
```

#### `stg_region.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_region.sql`

```sql
SELECT
    region_code,
    city,
    state,
    country,
    country_latitude,
    country_longitude,
    region,
    market
FROM {{source ('e_com_source', 'region') }}
```

### 12.5. Một số lệnh dbt đã sử dụng

Chạy từ thư mục chứa `dbt_project.yml`, ví dụ:

```powershell
cd dbt_ecommerce

# Kiểm tra kết nối Snowflake và profile
dbt debug

# Đọc và kiểm tra project / dependency
dbt parse

# Build staging trước nếu cần kiểm tra riêng
dbt run --select path:models/staging

# Build tất cả models đang được enable
dbt run

# Chạy bài test đã khai báo
dbt test

# Xem preview một model cụ thể
dbt show -s Q11_yoy_growth_pct --limit 20
```

**Phân biệt:** `dbt run` tạo/cập nhật các view và table; `dbt show` chỉ preview query; `dbt test` chạy kiểm thử. Một model build thành công không đồng nghĩa mọi phép tính nghiệp vụ đều đúng.

---

## 13. Business Mart Models — Q1 đến Q15

Thư mục: `dbt_ecommerce/models/marts/`

Phần SQL dưới đây được chép **đầy đủ theo đúng 15 file đã gửi** để lưu lại code của project. Mình không tự sửa công thức hay lời giải trong các file này. Mỗi câu có một mục để **tự viết ý tưởng, cách làm và diễn giải kết quả** sau này.

### Q1 — `Q1_total_rev_profit.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q1_total_rev_profit.sql`

```sql
-- Q1: Calculate the total revenue and profit for the entire dataset.
SELECT
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }};
```

**Ý tưởng:**

> Tính tổng sales và profit bằng hàm SUM.

### Q2 — `Q2_total_rev_profit_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q2_total_rev_profit_segments.sql`

```sql
-- Q2: Calculate the total revenue and profit for each segment.
SELECT
    segment,
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }}
GROUP BY segment
ORDER BY total_revenue DESC;
```

**Ý tưởng:**

> Do chia theo segment ta sẽ dùng hàm GROUP BY để tính.

### Q3 — `Q3_top_10_products.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q3_top_10_products.sql`

```sql
-- Q3: Identify the top 10 best-selling products.
SELECT 
    s.product_code,
    p.product,
    SUM(s.quantity) AS total_quantity_sold
FROM {{ ref('stg_ecom_sales') }} s
JOIN {{ ref('stg_product') }}  p
    ON s.product_code = p.product_code
GROUP BY s.product_code, p.product
ORDER BY total_quantity_sold DESC
LIMIT 10;
```

**Ý tưởng :**

> Do bài toán muốn chúng ta tìm 10 sản phẩm bán chạy nhất, nên phải JOIN 2 bảng stg_ecom_sales và stg_product lại với nhau để có thể hiện mã + tên sản phẩm cùng với tổng doanh thu, LIMIT 10 để lấy giới hạn 10 sản phẩm sales cao nhất.

### Q4 — `Q4_customer_per_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q4_customer_per_segments.sql`

```sql
-- Q4: Calculate total customer per gender (Male, female and unknown gender) and occupation.
SELECT
    occupation,
    SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) AS male,
    SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) AS female,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS unknown_gender,
    COUNT(*) AS total_customers
FROM {{ ref('stg_customer') }}
GROUP BY occupation
ORDER BY total_customers DESC;
```

**Ý tưởng :**

> Ở đây bài toán yêu cầu ta tìm số lượng khách hàng theo từng giới tính và nghề nghiệp, có thể dùng CASE WHEN lồng vào hàm SUM (Ý nghĩa của nó sẽ là nếu là Male nó sẽ trả về 1 nếu ko sẽ trả về 0 và sẽ cộng hết vào là biết được có bao nhiêu khách hàng là nam).

### Q5 — `Q5_avg_discount_category.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q5_avg_discount_category.sql`

```sql
-- Q5: Average discount by category
SELECT
    p.category,
    CAST(
        AVG(s.discount) * 100.0 
        AS DECIMAL(5,2)
    ) AS avg_discount
FROM {{ref ('stg_ecom_sales') }} s
JOIN {{ref ('stg_product') }} p
    ON s.product_code = p.product_code
GROUP BY p.category
ORDER BY avg_discount DESC;
```

**Ý tưởng :**

> Ta sẽ join category ở bảng stg_product và tính AVG discount ở bảng stg_ecom_sales, dùng CAST(... AS DECIMAL (5,2)) để kết quả trả về dạng số thập phân được làm tròn 2 số sau dấu phẩy.

### Q6 — `Q6_profit_margin_markets.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q6_profit_margin_markets.sql`

```sql
-- Q6: Profit margin by market
SELECT
    r.market,
    CAST(SUM(s.sales) AS DECIMAL(10,2)) as total_sales,
    CAST(SUM(s.profit) AS DECIMAL(10,2)) as total_profit,
    CAST(
        100.0 * 
        SUM(s.profit) / NULLIF(SUM(s.sales), 0)  
        AS DECIMAL(5,2)
    ) AS profit_margin
FROM {{ref ('stg_ecom_sales') }} s
JOIN {{ref ('stg_region') }} r
    ON s.region_code = r.region_code
GROUP BY r.market
HAVING COUNT(DISTINCT s.order_id) >= 100
ORDER BY profit_margin DESC;
```

**Ý tưởng :**

> Ta sẽ tìm profit margin bằng cách tính tổng sales và profit của từng market một, HAVING COUNT dùng để lọc những market có ít nhất 100 đơn hàng (Hàm này dùng sau khi GROUP, phân biệt với hàm WHERE dùng trước khi GROUP), dùng NULLIF cho những phép tính chia để tránh việc có thể chia cho số 0 bị lỗi.

### Q7 — `Q7_loss_order_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q7_loss_order_segments.sql`

```sql
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
ORDER BY loss_order_pct DESC;
```

**Ý tưởng :**

> Ở đây ta sẽ tạo 1 CTE để tính tổng profit cho từng order_id + segment. Sau đó từ CTE đó ta sẽ đếm những order có profit âm, và tính tỷ trọng của chúng so với tổng số order  theo từng segments cùng với tổng loss profit của từng segment.

### Q8 — `Q8_identify_churning_VIP_customers.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q8_identify_churning_VIP_customers.sql`

```sql
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
ORDER BY total_lifetime_spend DESC;
```

**Ý tưởng :**

> Ý tưởng là ta sẽ phải tìm xem những khách nào có mức chi tiêu cao nhất, nhưng đã lâu rồi không mua lại (180 ngày ~ 6 tháng). Đầu tiên tạo 1 CTE lấy ra top 50 khách hàng chi tiêu nhiều nhất cùng với ngày cuối cùng mà họ mua kèm thông tin khách hàng. Tạo 1 CTE dùng để làm biên giới hạn (bound) của ngày cuối cùng có order trong bảng stg_ecom_sales. Sau đó dựa vào 2 CTE đó ta sẽ dùng hàm DATEDIFF để lọc ra những customer có khoảng thời gian cách bound từ 180 ngày trở lên.

### Q9 — `Q9_pct_sale_category.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q9_pct_sale_category.sql`

```sql
-- Q9: Calculate the percentage of sales by customer segment for each product category
WITH total_sale_category AS ( 
    SELECT 
        p.category,
        SUM(CASE WHEN s.segment = 'Consumer' THEN s.sales ELSE 0 END) AS consumer_sales,
        SUM(CASE WHEN s.segment = 'Corporate' THEN s.sales ELSE 0 END) AS corporate_sales,
        SUM(CASE WHEN s.segment = 'Self-Employed' THEN s.sales ELSE 0 END) AS self_employed_sales,
        SUM(s.sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }} s
    JOIN {{ ref('stg_product') }} p
        ON  s.product_code = p.product_code
    GROUP BY p.category
)
SELECT
    category,
    CAST(
        100.0 * 
        consumer_sales / NULLIF(total_sales, 0) 
        AS DECIMAL (5,2)
    ) AS pct_consumer,
    CAST(
        100.0 * 
        corporate_sales / NULLIF(total_sales, 0) 
        AS DECIMAL (5,2)
    ) AS pct_corporate,
    CAST(
        100.0 * 
        self_employed_sales / NULLIF(total_sales, 0) 
        AS DECIMAL (5,2)
    ) AS pct_self_employed,
    total_sales
FROM total_sale_category
ORDER BY category;
```

**Ý tưởng :**

> Idea chính trong câu này sẽ là phải đi tìm tỷ trọng doanh thu của từng segment. Với CTE đầu tiên ta sẽ đi tính tổng doanh thu của từng category, sau đó sẽ dựa vào CTE đó để tính tỷ trọng của từng category một so với tổng doanh thu.

### Q10 — `Q10_top_15_total_sales_countries.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q10_top_15_total_sales_countries.sql`

```sql
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
LIMIT 15;
```

**Ý tưởng :**

> Idea chính sẽ là đi tìm xem top 15 quốc gia có doanh thu lớn nhất, số khu vực hoạt động, Số khách hàng và tổng số đơn hàng cho từng quốc gia. Có một lưu ý là region_active có thể được hiểu là số thành phố trong quốc gia ý hoạt động, chứ không được nhầm lẫn sang cột region của bảng stg_region.

### Q11 — `Q11_yoy_growth_pct.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q11_yoy_growth_pct.sql`

```sql
-- Q11: Calculate the year-over-year growth in sales for the last 24 months.
WITH sale_months AS (
    SELECT
        DATE_TRUNC('month', order_date) AS month,
        SUM(sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }}
    GROUP BY DATE_TRUNC('month', order_date)
), previous_year_sales AS (
    SELECT
        month,
        total_sales,
        LAG(total_sales,12) OVER (ORDER BY month) AS previous_year_sales
    FROM sale_months
), bound AS (
    SELECT
        MAX(month) AS max_month
    FROM sale_months
)
SELECT
    TO_CHAR(month, 'YYYY-MM') AS month,
    total_sales,
    previous_year_sales,
    CAST(100* (total_sales - previous_year_sales) / NULLIF(previous_year_sales, 0) AS DECIMAL(5,2)) AS yoy_growth_pct
FROM previous_year_sales
CROSS JOIN bound
WHERE month >= DATEADD('month', -23, max_month)
ORDER BY month;
```

**Ý tưởng :**

> Ta sẽ tính tăng trưởng theo tháng so với cùng tháng đó năm ngoái (Trong 24 tháng gần nhất). Do là theo tháng nên phải chuyển định dạng order_date về 'YYYY-mm'. Ta sử dụng hàm LAG để trả ra kết quả sale của cùng tháng đó năm ngoái cùng với tạo 1 CTE bound để có giới hạn tháng cuối cùng có order. Và sẽ tạo điều kiện với hàm DATEADD (Hiểu đơn giản là ta sẽ chỉ cho ra những kết quả từ tháng bound và 23 tháng đổ về trước để có tổng là 24 tháng).

### Q12 — `Q12_top3_products_categories.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q12_top3_products_categories.sql`

```sql
-- Q12: Top 3 products by profit in each category
WITH sale_products AS (
    SELECT
        p.category,
        p.product,
        p.product_code,
        SUM(s.profit) AS total_profit
    FROM {{ ref('stg_ecom_sales') }} s
    JOIN {{ ref('stg_product') }} p
        ON s.product_code = p.product_code
    GROUP BY p.product, p.category, p.product_code
), ranked_products AS (
    SELECT
        category,
        product,
        product_code,
        total_profit,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_profit DESC, product_code) AS rank_in_category
    FROM sale_products
)
SELECT
    category,
    product,
    product_code,
    total_profit,
    rank_in_category
FROM ranked_products
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;
```

**Ý tưởng :**

> Ta sẽ tạo 1 CTE tính doanh thu của từng sản trong từng category trước. Sau đó tạo 1 CTE để rank (Lưu ý đề bài bảo top 3 sản phẩm trong mỗi category), ta sẽ sử dụng ROW_NUMBER để đánh dấu rank các sản phẩm theo doanh thu từ cao đến thấp theo từng category. Và cuối cùng sẽ lọc ra những sản phẩm có rank trong khoảng từ 1 đến 3.

### Q13 — `Q13_customer_buy_in_multi_region.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q13_customer_buy_in_multi_region.sql`

```sql
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
LIMIT 20;
```

**Ý tưởng :**

> Idea chính ở đây sẽ là phải đi tìm được số lượng khách hàng mua ở nhiều khu vực khác nhau để có thể tính tỷ trọng. Đầu tiên ta sẽ tạo 1 CTE có các thông tin cơ bản về order của 1 customer. Sau đó ta sẽ tạo 1 CTE để biết được nơi mà khách hàng mua đầu tiền (Dùng hàm FIRST_VALUE), từ CTE này ta sẽ flag những nơi khác nơi đầu tiên khách hàng mua (Nếu khác sẽ trả về 1, nếu ko sẽ trả về 0). Từ đó ta sẽ có thể tính được số % khách hàng có mua ở nhiều khu vực khác nhau.

### Q14 — `Q14_frm_segmentation.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q14_frm_segmentation.sql`

```sql
-- Q14: Customer Segmentation based on RFM (Recency, Frequency, Monetary) analysis
WITH bound AS(
    SELECT
        MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
), customer_details AS (
    SELECT
        s.customer_id,
        MAX(s.order_date) AS last_order_customer,
        DATEDIFF('day', MAX(s.order_date), MAX(b.last_order_date)) AS days_since_last_order,
        COUNT(DISTINCT s.order_id) AS total_orders,
        SUM(s.sales) AS total_spent
    FROM {{ ref('stg_ecom_sales') }} s
    CROSS JOIN bound b
    GROUP BY s.customer_id
), filter_segments AS (
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
LIMIT 20;
```

**Ý tưởng :**

> Ta sẽ phải đi tìm recency, frequency, monetary của từng khách hàng và sau đó tính điểm để xếp hạng. Với recency ta sẽ so sánh với ngày cuối cùng có order (Dùng hàm DATEFDIFF), với frequency ta sẽ dùng hàm count (Lưu ý tránh bị lặp order do 1 order có thể sẽ có nhiều dòng) và với monetary ta sẽ dùng hàm SUM - Tính cho từng customer_id. Sau đó ta sẽ dùng hàm NTILE(5) để giúp chia ra 5 phân khúc điểm khác nhau rồi sau đó cộng lại và xếp hạng top 20.

### Q15 — `Q15_pair_products.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q15_pair_products.sql`

```sql
WITH order_products AS (
    SELECT DISTINCT
        order_id,
        product_code
    FROM {{ ref('stg_ecom_sales') }}
), self_joined AS (
    SELECT
        a.order_id,
        a.product_code AS product_code_a,
        b.product_code AS product_code_b
    FROM order_products a
    JOIN order_products b 
        ON a.order_id = b.order_id AND a.product_code < b.product_code
)
SELECT
    pa.product AS product_a,
    pb.product AS product_b,
    COUNT(*) AS pair_count
FROM self_joined sj
JOIN {{ ref('stg_product') }} pa
    ON sj.product_code_a = pa.product_code
JOIN {{ ref('stg_product') }} pb
    ON sj.product_code_b = pb.product_code
GROUP BY product_a, product_b
ORDER BY pair_count DESC
```

**Ý tưởng :**

> Ý tưởng là ta sẽ phải tạo ra được 1 bảng sao cho có cột product a và cột product b tương ứng với 1 cặp sản phẩm. Ta có thể JOIN 2 bảng trùng nhau lại nhưng phải để ý điều kiện khi JOIN (tránh việc product_code a trùng với product_code b). Khi đã có bảng mới tương ứng với các cặp sản phẩm thì ta sẽ đếm xem các cặp xuất hiện bao nhiêu lần.

---
