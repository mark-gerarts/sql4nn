WITH RECURSIVE input_values AS (
    -- Fetch input values from an existing table
    SELECT input_set_id, input_node_idx, input_value FROM input
),
input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node n
    WHERE NOT EXISTS
    (SELECT 1 FROM edge WHERE dst = n.id)
),
output_nodes AS (
    SELECT id
    FROM node n
    WHERE NOT EXISTS
    (SELECT 1 FROM edge WHERE src = n.id)
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
    -- JOIN order matters for performance!
    FROM input_nodes i
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    JOIN edge e ON i.id = e.src
    JOIN node n ON e.dst = n.id
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
    FROM tx
    JOIN edge e ON tx.id = e.src
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
    FROM output_nodes o
    JOIN edge e ON e.dst = o.id
    JOIN tx ON tx.id = e.src
    JOIN node n ON o.id = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
)
SELECT * FROM t_out ORDER BY input_set_id, id;
