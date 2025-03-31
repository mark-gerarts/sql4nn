WITH input_values AS (
    SELECT 1 AS input_value
),
input_nodes AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (
        SELECT dst FROM edge
    )
),
t1 AS (
    SELECT
        MAX(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS t1,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN node n ON e.dst = n.id
    CROSS JOIN input_values v
    GROUP BY e.dst, n.bias
),
t2 AS (
    SELECT
        MAX(
            0,
            n.bias + SUM(e.weight * t1.t1)
        ) AS t2,
        e.dst AS id
    FROM edge e
    JOIN t1 ON t1.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias
),
outputs AS (
    SELECT
        n.bias + SUM(e.weight * t2.t2) AS output_value,
        e.dst AS output_node_id
    FROM edge e
    JOIN t2 ON t2.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias
)
SELECT * FROM outputs;
