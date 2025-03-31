WITH RECURSIVE input_values AS (
    SELECT 0 AS input_set_id, 1 AS input_node_idx, 195.4724 AS input_value
),
input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
output_nodes AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (SELECT src FROM edge)
),
tx AS (
    -- Base case (t1)
    SELECT
        v.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS value,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN node n ON e.dst = n.id
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    GROUP BY e.dst, n.bias, v.input_set_id

    UNION ALL

    -- Recursive case
    SELECT
        tx.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * tx.value)
        ) AS value,
        e.dst AS id
    FROM edge e
    JOIN tx ON tx.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
),
-- As the last step, repeat the calculation for the output nodes, but omit the
-- ReLU this time (per definition)
t_out AS (
    SELECT
        tx.input_set_id AS input_set_id,
        n.bias + SUM(e.weight * tx.value) AS value,
        e.dst AS id
    FROM edge e
    JOIN output_nodes o ON e.dst = o.id
    JOIN node n ON o.id = n.id
    JOIN tx ON tx.id = e.src
    GROUP BY e.dst, n.bias, tx.input_set_id
)
SELECT * FROM t_out ORDER BY id;
