WITH RECURSIVE input_values_single AS (
    -- We do a hardcoded query with 5 as the input value, but this could come
    -- from anywhere.
    SELECT 0 AS input_set_id, 1 AS input_node_idx, 5 AS input_value
),
-- We make sure we have a separate input_value entry for each model in the
-- database by doing a cross join.
input_values AS (
    SELECT m.id AS model_id, input_set_id, input_node_idx, input_value
    FROM input_values_single
    CROSS JOIN model m
),
input_nodes AS (
    SELECT
        model_id,
        id,
        -- We add a PARTITION BY to make sure the row number increments
        -- separately per model.
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
        -- Add the model ID for disambiguation.
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
    -- Join on the correct input value.
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
        -- And add the model ID to the output as well, so we know which model
        -- gave each value.
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
-- Include some model metadata
SELECT m.name, t.value AS output_value
FROM model m
JOIN t_out t ON t.model_id = m.id;
