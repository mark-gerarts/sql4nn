WITH RECURSIVE
input_values AS (
    SELECT m.id AS model_id, input_set_id, input_node_idx, input_value
    FROM input
    CROSS JOIN model m
),
input_nodes AS (
    SELECT
        model_id,
        id,
        ROW_NUMBER() OVER (PARTITION BY model_id ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
output_nodes AS (
    SELECT model_id, id
    FROM node
    WHERE id NOT IN
    (SELECT src FROM edge)
),
tx AS (
    SELECT
        i.model_id,
        v.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS value,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN node n ON e.dst = n.id
    JOIN input_values v ON i.input_node_idx = v.input_node_idx AND v.model_id = i.model_id
    GROUP BY i.model_id, e.dst, n.bias, v.input_set_id

    UNION ALL

    SELECT
        tx.model_id,
        tx.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * tx.value)
        ) AS value,
        e.dst AS id
    FROM edge e
    JOIN tx ON tx.id = e.src AND tx.model_id = e.model_id
    JOIN node n ON e.dst = n.id
    GROUP BY tx.model_id, e.dst, n.bias, tx.input_set_id
),
t_out AS (
    SELECT
        tx.model_id,
        tx.input_set_id AS input_set_id,
        n.bias + SUM(e.weight * tx.value) AS value,
        e.dst AS id
    FROM edge e
    JOIN output_nodes o ON e.dst = o.id
    JOIN node n ON o.id = n.id
    JOIN tx ON tx.id = e.src AND tx.model_id = e.model_id
    GROUP BY tx.model_id, e.dst, n.bias, tx.input_set_id
)
SELECT
    m.id,
    m.name,
    t.value AS output_value,
    t.id AS output_id
FROM model m
JOIN t_out t ON t.model_id = m.id
ORDER BY m.id, t.id
