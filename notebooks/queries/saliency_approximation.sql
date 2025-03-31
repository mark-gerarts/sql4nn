WITH RECURSIVE input_nodes AS (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node n
    WHERE NOT EXISTS (
        SELECT 1 FROM edge e WHERE e.dst = n.id
    )
),
output_nodes AS (
    SELECT
        id,
        bias
    FROM node n
    WHERE NOT EXISTS (
        SELECT 1 FROM edge e WHERE e.src = n.id
    )
),
input_values AS (
    SELECT
        input_set_id,
        input_node_idx,
        input_value
    FROM input
    WHERE input_set_id = 0 -- TODO
),
first_layer_activations AS (
    SELECT
        e.dst,
        v.input_set_id,
        i.id AS input_node_id,
        e.weight * v.input_value AS weighted_input
    FROM edge e
    INNER JOIN input_nodes i ON i.id = e.src
    INNER JOIN input_values v ON i.input_node_idx = v.input_node_idx
),
first_layer_grouped AS (
    SELECT
        dst,
        input_set_id,
        SUM(weighted_input) AS total_weighted_input
    FROM first_layer_activations
    GROUP BY dst, input_set_id
),
tx AS (
    SELECT
        f.input_set_id,
        GREATEST(0, n.bias + f.total_weighted_input) AS value,
        f.dst AS id
    FROM first_layer_grouped f
    INNER JOIN node n ON f.dst = n.id

    UNION ALL

    SELECT
        tx.input_set_id,
        GREATEST(0, n.bias + SUM(e.weight * tx.value)) AS value,
        e.dst AS id
    FROM edge e
    INNER JOIN tx ON tx.id = e.src
    INNER JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
),
base_output AS (
    SELECT
        tx.input_set_id,
        o.id AS output_node_id,
        o.bias + SUM(e.weight * tx.value) AS value
    FROM edge e
    INNER JOIN output_nodes o ON e.dst = o.id
    INNER JOIN tx ON tx.id = e.src
    GROUP BY o.id, o.bias, tx.input_set_id
),
input_contributions AS (
    SELECT
        f.input_set_id,
        f.input_node_id,
        f.dst,
        n.bias,
        f.weighted_input,
        CASE
            WHEN n.bias + flg.total_weighted_input > 0 THEN f.weighted_input / NULLIF(flg.total_weighted_input, 0)
            ELSE 0
        END AS contribution_factor
    FROM first_layer_activations f
    INNER JOIN first_layer_grouped flg ON f.dst = flg.dst AND f.input_set_id = flg.input_set_id
    INNER JOIN node n ON f.dst = n.id
),
saliency AS (
    SELECT
        b.input_set_id,
        i.id AS removed_neuron_id,
        b.value AS eval,
        b.value - (
            SELECT SUM(ic.contribution_factor * tx2.value)
            FROM input_contributions ic
            INNER JOIN tx tx2 ON ic.dst = tx2.id
            WHERE ic.input_node_id = i.id
            AND ic.input_set_id = b.input_set_id
        ) AS eval_prime,
        ABS(b.value - (
            b.value - (
                SELECT SUM(ic.contribution_factor * tx2.value)
                FROM input_contributions ic
                INNER JOIN tx tx2 ON ic.dst = tx2.id
                WHERE ic.input_node_id = i.id
                AND ic.input_set_id = b.input_set_id
            )
        )) AS saliency,
        b.output_node_id
    FROM base_output b
    CROSS JOIN input_nodes i
)
SELECT * FROM saliency
ORDER BY removed_neuron_id, output_node_id;
