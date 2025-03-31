WITH input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node n
    WHERE NOT EXISTS (
        SELECT 1 FROM edge e WHERE e.dst = n.id
    )
),
input_edges AS (
    SELECT src, dst, weight
    FROM input_nodes i
    JOIN edge e ON e.src = i.id
),
total_weight_sum AS (
    SELECT SUM(ABS(weight)) AS total_weight
    FROM input_edges
),
input_weights AS (
    SELECT
        src AS input_node_id,
        SUM(ABS(e.weight)) / t.total_weight AS weighted_weight,
    FROM input_edges e
    CROSS JOIN total_weight_sum t
    GROUP BY e.src, t.total_weight

)
SELECT * FROM input_weights ORDER BY input_node_id;
