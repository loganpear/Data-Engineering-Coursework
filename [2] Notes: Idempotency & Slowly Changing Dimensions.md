### **Day 2: Dimensional Data Modeling**  

---

## **Idempotency**  
**Definition:**  
Idempotency ensures a data pipeline produces the **same results** whether it runs **once** or **multiple times** (in production or backfill). It prevents data duplication or inconsistencies caused by repeated executions.  

**Key Issue:**  
Non-idempotent pipelines may **overwrite data**, generate **duplicates**, or produce **non-reproducible results**.  

**Best Practices:**  
- **Avoid `INSERT INTO`** unless paired with a **`TRUNCATE`** step beforehand.  
- **Use `MERGE` or `INSERT OVERWRITE`** to ensure data consistency.  

**Example (Non-Idempotent):**  
```sql
INSERT INTO players
SELECT * FROM player_seasons WHERE season = 2023;
```
- Running this multiple times will **duplicate rows**.  

**Example (Idempotent):**  
```sql
MERGE INTO players AS target
USING (SELECT * FROM player_seasons WHERE season = 2023) AS source
ON target.player_name = source.player_name
WHEN MATCHED THEN UPDATE SET target.season_stats = source.season_stats
WHEN NOT MATCHED THEN INSERT (player_name, season_stats) VALUES (source.player_name, source.season_stats);
```
- This **updates existing rows** or **inserts new rows** without duplication.

---

## **Slowly Changing Dimensions (SCDs)**  
**Definition:**  
SCDs track **historical changes** in dimension data. They allow analysis of **how attributes evolve** over time (e.g., job titles or team assignments).  

---

### **Types of SCDs**  

1. **Type 0: Fixed Attributes**  
   - **No changes allowed.** Data is static.  
   - **Example:** Birthdate or Employee ID.  
   - **Use Case:** Rarely updated dimensions.  

2. **Type 1: Overwrite Changes (Not Recommended)**  
   - **Stores only the latest value.**  
   - **Pro:** Simple.  
   - **Con:** **Not idempotent**—loses history.  
   - **Use Case:** Suitable for **OLTP (transactional systems)** but **not for analytics.**  

   **Example:**  
   ```sql
   UPDATE players
   SET height = '6-9'
   WHERE player_name = 'Michael Jordan';
   ```
   - Overwrites the value, losing the previous data.

3. **Type 2: Historical Changes (Gold Standard)**  
   - **Stores historical data with effective date ranges.**  
   - **Pro:** Tracks changes and is **idempotent**.  
   - **Con:** Requires **more storage** and careful data modeling.  

   **Example (Lab Code):**  
   ```sql
   SELECT
       player_name,
       scoring_class,
       is_active,
       min(current_season) AS start_season,
       max(current_season) AS end_season
   FROM with_streaks
   GROUP BY player_name, scoring_class, is_active
   ORDER BY player_name;
   ```
   - Tracks historical changes and identifies start and end seasons for each state.

4. **Type 3: Limited History**  
   - **Stores only the current and previous values.**  
   - **Pro:** Requires **less storage**.  
   - **Con:** **Not idempotent**—loses intermediate history.  

   **Example:**  
   ```sql
   ALTER TABLE players ADD COLUMN previous_height text;
   UPDATE players
   SET previous_height = height, height = '6-9'
   WHERE player_name = 'Michael Jordan';
   ```
   - Keeps **one prior value** but loses the **full history** between changes.

---

## **Loading Type 2 SCDs**  
1. **Full Reload (Inefficient but Simple)**  
   - Loads **all historical data** in one query.  
   - Suitable for **small datasets** or **initial loads**.  

   **Example:**  
   ```sql
   INSERT INTO players_scd
   SELECT player_name, scoring_class, is_active, start_season, end_season
   FROM players;
   ```

2. **Incremental Load (Efficient but Complex)**  
   - Processes **new or changed data** after the initial load.  
   - Uses **lag()** and **window functions** to track changes.  

   **Example (Lab Code):**  
   ```sql
   SELECT
       player_name,
       scoring_class,
       is_active,
       lag(scoring_class, 1) OVER (PARTITION BY player_name ORDER BY current_season) AS previous_scoring_class,
       lag(is_active, 1) OVER (PARTITION BY player_name ORDER BY current_season) AS previous_is_active
   FROM players
   WHERE current_season <= 2022;
   ```

---

## **Key SQL Features Used**  

1. **ARRAY[] and ROW():**  
   - Used to store **complex data structures** like nested attributes or historical records.  

   **Example (Lab Code):**  
   ```sql
   ARRAY[ROW(
       ts.scoring_class,
       ts.is_active,
       ts.current_season,
       ts.current_season
   )::scd_type]
   ```
   - Creates an **array of rows** to model changes over time.

2. **COALESCE:**  
   - Fills in **missing values** from another source.  

   **Example (Lab Code):**  
   ```sql
   coalesce(t.height, y.height) as height
   ```
   - Uses the **latest non-null value** for each player’s height.

3. **Window Functions:**  
   - Tracks **changes over time** using `lag()`.  

   **Example (Lab Code):**  
   ```sql
   LAG(scoring_class, 1) OVER (PARTITION BY player_name ORDER BY current_season)
   ```
   - Compares the current value to the **previous season** to detect changes.

4. **<> Operator:**  
   - Equivalent to `!=` in Python; checks for **inequality**.  

   **Example (Lab Code):**  
   ```sql
   WHEN scoring_class <> previous_scoring_class THEN 1
   ```
   - Flags rows where the **scoring class changes**.
