-- We hit some scaling issues:
-- 100: 0.56
-- 200: 2.27
-- 300: 5.36
-- 400: 10
-- And so on. 784 input runs into memory issues.
WITH RECURSIVE inputs AS MATERIALIZED (
    SELECT i.input_set_id, i.input_node_idx, i.input_value, n.id
    FROM input i
    JOIN (
        SELECT
            id,
            bias,
            ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
        FROM node n
        WHERE NOT EXISTS
        (SELECT 1 FROM edge WHERE dst = n.id)
    ) n ON n.input_node_idx = i.input_node_idx
),
output_nodes AS MATERIALIZED (
    SELECT id, bias
    FROM node n
    WHERE NOT EXISTS
    (SELECT 1 FROM edge WHERE src = n.id)
),
tx AS (
    SELECT
        i.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * i.input_value)
        ) AS value,
        e.dst AS id
    FROM inputs i
    JOIN edge e ON i.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, i.input_set_id

    UNION ALL

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
t_out AS MATERIALIZED (
    SELECT
        tx.input_set_id AS input_set_id,
        o.bias + SUM(e.weight * tx.value) AS value,
        e.dst AS id
    FROM output_nodes o
    JOIN edge e ON e.dst = o.id
    JOIN tx ON tx.id = e.src
    GROUP BY e.dst, o.bias, tx.input_set_id
),
tx_prime AS (
    SELECT
        i.input_set_id AS input_set_id,
        i_to_remove.id AS i_to_remove,
        GREATEST(
            0,
            n.bias + SUM(e.weight * i.input_value)
        ) AS value,
        e.dst AS id
    FROM inputs i
    JOIN inputs i_to_remove
        ON i.id <> i_to_remove.id
        AND i.input_set_id = i_to_remove.input_set_id
    JOIN edge e ON i.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY i_to_remove.id, i.input_set_id, e.dst, n.bias

    UNION ALL

    SELECT
        tx_prime.i_to_remove,
        tx_prime.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * tx_prime.value)
        ) AS value,
        e.dst AS id
    FROM tx_prime
    JOIN edge e ON tx_prime.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY tx_prime.i_to_remove, tx_prime.input_set_id, e.dst, n.bias
),
t_out_prime AS (
    SELECT
        tx_prime.i_to_remove,
        tx_prime.input_set_id AS input_set_id,
        o.bias + SUM(e.weight * tx_prime.value) AS value,
        e.dst AS id
    FROM output_nodes o
    JOIN edge e ON e.dst = o.id
    JOIN tx_prime ON tx_prime.id = e.src
    GROUP BY tx_prime.i_to_remove, e.dst, o.bias, tx_prime.input_set_id
),
saliency AS (
    SELECT
        t_out_prime.input_set_id,
        t_out_prime.i_to_remove,
        t_out_prime.id AS output_id,
        ABS(t_out.value - t_out_prime.value) AS saliency
    FROM t_out_prime
    JOIN t_out
        ON t_out.id = t_out_prime.id
        AND t_out.input_set_id = t_out_prime.input_set_id
)
SELECT * FROM saliency
ORDER BY input_set_id, i_to_remove;
