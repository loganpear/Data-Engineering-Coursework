## Day 1: Data Modeling - Complex Data Types

### Data Structures
- **Array:** A list in a column
  - **Values:** All the same type
  - **Example (Lab 1):**
    ```sql
    CREATE TYPE season_stats AS (
        season INTEGER,
        gp INTEGER,
        pts REAL,
        reb REAL,
        ast REAL
    );

    -- Array of season stats for a player
    CREATE TABLE players (
        player_name TEXT,
        season_stats season_stats[]
    );

    -- Adding stats to the array
    INSERT INTO players (player_name, season_stats)
    VALUES (
        'Michael Jordan',
        ARRAY[ROW(1991, 82, 30.1, 6.4, 5.5)::season_stats]
    );
    ```

- **Struct:** A table within a table
  - **Keys:** Precisely defined
  - **Values:** Can be any data type
  - **Example:** 
    ```sql
    CREATE TYPE player_info AS (
        name TEXT,
        height TEXT,
        college TEXT
    );

    -- Using the struct to represent a player
    SELECT ROW('Michael Jordan', '6-6', 'North Carolina')::player_info;
    ```

- **Map:** Key-value pairs, similar to a dictionary
  - **Keys:** Loosely defined; can have as many as needed
  - **Values:** All the same type
  - **Example (Conceptual):**
    ```sql
    -- SQL doesn't natively support maps, but they can be emulated using JSON
    SELECT '{"name": "Michael Jordan", "height": "6-6"}'::jsonb;
    ```

---

### Dimension: Attribute of an Entity
- **Example:** You are the entity, dimensions would be:
  - Your name, your birthday, the city you live in
- **Two types of dimensions:**
  - **Identifier Dimensions:** Uniquely identify, e.g., `UserID`
  - **Attribute Dimensions:**
    1. **Slowly Changing:** Example: Favorite food
    2. **Fixed Dimension:** Example: Birthday, location of manufacture

---

### Dimensional Data Modeling (3 Types)
1. **OLTP (Online Transaction Processing):**
   - Used in software engineering data modeling
   - Optimized for low-latency, low-volume queries
   - Focused on one user or entity

2. **OLAP (Online Analytical Processing):**
   - Designed for fast, large-volume queries
   - Optimized for `GROUP BY` operations, minimizing `JOINs`
   - **Example (Lab 1):**
     ```sql
     SELECT player_name, AVG(pts) AS avg_points
     FROM players
     WHERE current_season = 2023
     GROUP BY player_name;
     ```

3. **Master Data:**
   - A middle ground between OLTP and OLAP
   - Contains complete definitions and deduped entities

---

### Four Layers of Data Modeling
1. **Production Database Snapshots:**
   - **Example:** For Airbnb, includes hosts, guests, prices, availability settings
2. **Master Data:**
   - Combines all production datasets
3. **OLAP Cubes:**
   - Flattened data with multiple rows per entity
   - Used for `GROUP BY`, "Slice and Dice" operations
   - Preferred by analysts and scientists for quick analysis
4. **Metrics:**
   - **Example:** Average listing price of all Airbnbs

---

### Compactness vs. Usability Tradeoff
- **Most Usable Tables (for analytics):**
  - No complex data types
  - Easy to query with `WHERE` and `GROUP BY`
- **Most Compact Tables (for latency-sensitive systems):**
  - Compressed for minimal size
  - Cannot be directly queried without decoding
- **Middle-Ground Tables (Master Data):**
  - Use complex types like `ARRAY`, `MAP`, and `STRUCT`
  - More compact but harder to query

---

### Run-Length Encoding
- **Example:** Instead of repeating the same value 5 times, record the value once with a count:
  ```text
  [1, 1, 1, 1, 1] -> (1, 5)

