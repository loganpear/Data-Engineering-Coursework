### **Day 3: Graph Data Modeling - Lecture Notes**

---

### **Additive vs. Non-Additive Dimensions**  
- **Additive Dimensions:** Values can be summed without duplication.  
  **Example:**  
  - Total number of students by age (e.g., 5-year-olds + 6-year-olds = total students).  
- **Non-Additive Dimensions:** Values can't be summed directly due to overlaps.  
  **Example:**  
  - Total active users ≠ (phone users + computer users + tablet users) because users may have multiple devices.

---

### **When to Use Enums (Enumerated Fields)**  
- **Best Use Cases:** When categories are **limited and fixed**.  
  **Example:**  
  ```sql
  CREATE TYPE vertex_type AS ENUM('player', 'team', 'game');
  ```
- **Pros:**
  1. **Data Validation:** The database rejects invalid values.  
  2. **Documentation:** Lists all possible values in the schema.  
  3. **Partitioning:** Allows splitting data into **manageable chunks** based on categories.  

- **Limitations:** Avoid Enums for datasets with **>50 categories** (e.g., countries) as maintaining them becomes difficult.

---

### **Flexible Schema (JSON or MAP)**  
- **Pros:**
  - Schema changes are **easier**—new properties can be added without altering table structure.
  - Reduces **NULL values** by only storing fields that are needed.  
  **Example:**  
  ```sql
  json_build_object('pts_home', pts_home, 'pts_away', pts_away)
  ```
- **Cons:**
  - **Worse Compression:** JSON headers are repeated in each row.  
  - **Query Complexity:** Extracting data requires parsing JSON keys.  
  **Example:**
  ```sql
  SELECT properties->>'player_name' FROM vertices;
  ```

---

### **Graph Data Modeling**  
- **Focus:** Relationships between entities rather than individual entities.  
- **Schema Pattern:**  
  1. **Identifier:** Unique ID for the node.  
  2. **Type:** Node category (e.g., player, team, game).  
  3. **Properties:** Flexible key-value pairs storing node details.

---

### **Nodes and Edges (Lab 3 Examples)**  

1. **Vertices (Nodes):** Represent entities like players, teams, and games.  
   **Example: Create Vertices Table**  
   ```sql
   CREATE TABLE vertices (
       identifier TEXT,
       type vertex_type,
       properties JSON,
       PRIMARY KEY(identifier, type)
   );
   ```

2. **Edges (Relationships):** Represent connections between entities, such as players **playing in** a game or **sharing a team**.  
   **Example: Create Edges Table**  
   ```sql
   CREATE TABLE edges (
       subject_identifier TEXT,
       subject_type vertex_type,
       object_identifier TEXT,
       object_type vertex_type,
       edge_type edge_type,
       properties JSON,
       PRIMARY KEY(subject_identifier, subject_type, object_identifier, object_type, edge_type)
   );
   ```

---

### **Graph Queries (Examples)**  

1. **Insert Nodes (Players):**  
   ```sql
   INSERT INTO vertices
   SELECT
       player_id AS identifier,
       'player'::vertex_type AS type,
       json_build_object(
           'player_name', player_name,
           'total_points', sum(pts)
       ) AS properties
   FROM game_details
   GROUP BY player_id, player_name;
   ```

2. **Insert Edges (Relationships):**  
   ```sql
   INSERT INTO edges
   SELECT
       player_id AS subject_identifier,
       'player'::vertex_type AS subject_type,
       game_id AS object_identifier,
       'game'::vertex_type AS object_type,
       'plays_in'::edge_type AS edge_type,
       json_build_object('points', pts) AS properties
   FROM game_details;
   ```

3. **Query Example: Players with the Most Points:**  
   ```sql
   SELECT
       v.properties->>'player_name',
       MAX(CAST(e.properties->>'points' AS INTEGER)) AS max_points
   FROM vertices v
   JOIN edges e
   ON e.subject_identifier = v.identifier AND e.subject_type = v.type
   GROUP BY v.properties->>'player_name'
   ORDER BY max_points DESC;
   ```

4. **Query Example: Average Points Per Game:**  
   ```sql
   SELECT
       v.properties->>'player_name',
       CAST(v.properties->>'total_points' AS REAL) /
       CAST(v.properties->>'number_of_games' AS REAL) AS avg_points
   FROM vertices v
   WHERE v.type = 'player'::vertex_type;
   ```

---

### **Key Takeaways from Lab 3**  
- **Node Representation:** Entities like players, teams, and games are stored as **vertices** with flexible properties in JSON format.  
- **Edge Representation:** Relationships between entities (e.g., **plays in**, **shares team**) are modeled as **edges** with properties defining the relationship.  
- **Graph Queries:** Allow complex queries like finding **top scorers** or **average performance metrics** using relationships between nodes and edges.
