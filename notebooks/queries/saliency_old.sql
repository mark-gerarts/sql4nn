WITH RECURSIVE input_values AS (
    -- Fetch input values from an existing table
    SELECT input_set_id, input_node_idx, input_value FROM input
),
input_nodes AS MATERIALIZED (
    SELECT
        id,
        bias,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
output_nodes AS MATERIALIZED (
    SELECT id
    FROM node
    WHERE id NOT IN
    (SELECT src FROM edge)
),
tx AS (
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
t_out AS MATERIALIZED (
    SELECT
        tx.input_set_id AS input_set_id,
        n.bias + SUM(e.weight * tx.value) AS value,
        e.dst AS output_node_id
    FROM edge e
    JOIN output_nodes o ON e.dst = o.id
    JOIN node n ON o.id = n.id
    JOIN tx ON tx.id = e.src
    GROUP BY e.dst, n.bias, tx.input_set_id
),
saliency AS (
    SELECT
        input_set_id,
        removed_neuron_id,
        ABS(eval - eval_prime) AS saliency
    FROM
    (
        SELECT
            t_out.input_set_id,
            i_to_remove.id AS removed_neuron_id,
            t_out.value AS eval,
            (
                WITH RECURSIVE tx_prime AS (
                    SELECT
                        v.input_set_id AS input_set_id,
                        GREATEST(
                            0,
                            n.bias + SUM(e.weight * v.input_value)
                        ) AS value,
                        e.dst AS id
                    FROM edge e
                    -- Filter out the input node
                    JOIN input_nodes i ON i.id = e.src AND i.id <> i_to_remove.id
                    JOIN node n ON e.dst = n.id
                    JOIN input_values v ON i.input_node_idx = v.input_node_idx
                    GROUP BY i.id, e.dst, n.bias, v.input_set_id

                    UNION ALL

                    SELECT
                        tx_prime.input_set_id AS input_set_id,
                        GREATEST(
                            0,
                            n.bias + SUM(e.weight * tx_prime.value)
                        ) AS value,
                        e.dst AS id
                    FROM edge e
                    JOIN tx_prime ON tx_prime.id = e.src
                    JOIN node n ON e.dst = n.id
                    GROUP BY e.dst, n.bias, tx_prime.input_set_id
                ),
                t_out_prime AS (
                    SELECT
                        tx_prime.input_set_id AS input_set_id,
                        n.bias + SUM(e.weight * tx_prime.value) AS value,
                        e.dst AS output_node_id
                    FROM edge e
                    JOIN output_nodes o ON e.dst = o.id
                    JOIN node n ON o.id = n.id
                    JOIN tx_prime ON tx_prime.id = e.src
                    GROUP BY e.dst, n.bias, tx_prime.input_set_id
                )

                SELECT t_out_prime.value FROM t_out_prime
            ) AS eval_prime
        FROM t_out, input_nodes i_to_remove
    )
)
-- TODO: when this query is executed with multiple input_sets, the results are
-- no longer correct. Fix this! Look at useless neurons as well then.
SELECT * FROM saliency where input_set_id = 0;
