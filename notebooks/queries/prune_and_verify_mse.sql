CREATE OR REPLACE TEMP MACRO prune_and_verify(number_of_nodes_to_prune) AS TABLE
WITH RECURSIVE input_values AS (
    SELECT input_set_id, input_node_idx, input_value FROM input
),
-- Regular eval
input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN (SELECT dst FROM edge)
),
output_nodes AS (
    SELECT id
    FROM node
    WHERE id NOT IN (SELECT src FROM edge)
),
tx_original AS (
    SELECT
        v.input_set_id AS input_set_id,
        GREATEST(0, n.bias + SUM(e.weight * v.input_value)) AS value,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN node n ON e.dst = n.id
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    GROUP BY e.dst, n.bias, v.input_set_id

    UNION ALL

    SELECT
        tx.input_set_id AS input_set_id,
        GREATEST(0, n.bias + SUM(e.weight * tx.value)) AS value,
        e.dst AS id
    FROM edge e
    JOIN tx_original tx ON tx.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
),
t_out_original AS (
    SELECT
        tx.input_set_id AS input_set_id,
        n.bias + SUM(e.weight * tx.value) AS output_value,
        e.dst AS output_node_id
    FROM edge e
    JOIN output_nodes o ON e.dst = o.id
    JOIN node n ON o.id = n.id
    JOIN tx_original tx ON tx.id = e.src
    GROUP BY e.dst, n.bias, tx.input_set_id
),
-- Pruned eval
node_ids_to_keep AS (
    SELECT id
    FROM
    (
        SELECT
            src AS id,
            ROW_NUMBER() OVER (ORDER BY MAX(ABS(weight))) AS rownum
        FROM edge
        -- Exclude input nodes from pruning
        WHERE src NOT IN (SELECT id FROM input_nodes)
        GROUP BY src
        ORDER BY MAX(ABS(weight))
    )
    -- This is a convoluted way to do a LIMIT, since dynamic LIMITs are not
    -- allowed in correlated subqueries in DuckDB (this is an issue if we use it
    -- in the WITH RECURSIVE later on).
    WHERE rownum > number_of_nodes_to_prune
),
nodes_to_keep AS (
    SELECT *
    FROM node
    WHERE id IN (SELECT id FROM node_ids_to_keep)
    OR id IN (SELECT id FROM input_nodes)
    OR id IN (SELECT id FROM output_nodes)
),
tx_pruned AS (
    SELECT
        v.input_set_id AS input_set_id,
        GREATEST(0, n.bias + SUM(e.weight * v.input_value)) AS value,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN nodes_to_keep n ON e.dst = n.id
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    GROUP BY e.dst, n.bias, v.input_set_id

    UNION ALL

    SELECT
        tx.input_set_id AS input_set_id,
        GREATEST(0, n.bias + SUM(e.weight * tx.value)) AS value,
        e.dst AS id
    FROM edge e
    JOIN tx_pruned tx ON tx.id = e.src
    JOIN nodes_to_keep n ON e.dst = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
),
t_out_pruned AS (
    SELECT
        tx.input_set_id AS input_set_id,
        n.bias + SUM(e.weight * tx.value) AS output_value,
        e.dst AS output_node_id
    FROM edge e
    JOIN output_nodes o ON e.dst = o.id
    JOIN nodes_to_keep n ON o.id = n.id
    JOIN tx_pruned tx ON tx.id = e.src
    GROUP BY e.dst, n.bias, tx.input_set_id
),
both_output_values AS (
    SELECT
        og.input_set_id,
        og.output_node_id,
        og.output_value AS original_output_value,
        p.output_value AS pruned_output_value
    FROM t_out_original og
    JOIN t_out_pruned p ON p.input_set_id = og.input_set_id AND p.output_node_id = og.output_node_id
    ORDER BY og.input_set_id, og.output_node_id
),
MSEs AS (
    SELECT
        input_set_id,
        SUM( (original_output_value - pruned_output_value) ** 2 ) / COUNT(original_output_value) AS MSE
    FROM both_output_values
    GROUP BY input_set_id
)
SELECT AVG(MSE) as average_mse FROM MSEs;
