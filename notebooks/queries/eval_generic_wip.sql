WITH input_values AS (
    SELECT 1 AS input_node_idx, 5 AS input_value
    UNION
    SELECT 2, 20
),
input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN
    (
        SELECT dst FROM edge
    )
    ORDER BY id
),
t1 AS (
    SELECT
        GREATEST(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS t1,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN node n ON e.dst = n.id
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    GROUP BY e.dst, n.bias
),
outputs AS (
    SELECT
        n.bias + SUM(e.weight * t1.t1) AS output_value,
        e.dst AS output_node_id
    FROM edge e
    JOIN t1 ON t1.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias
)
SELECT * FROM outputs ORDER BY output_node_id;
