WITH RECURSIVE input_values AS (
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
-- Eval
tx AS (
    SELECT
        v.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS value,
        e.dst AS id
    FROM input_nodes i
    JOIN input_values v ON i.input_node_idx = v.input_node_idx
    JOIN edge e ON i.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, v.input_set_id

    UNION ALL

    SELECT
        tx.input_set_id AS input_set_id,
        GREATEST(
            0,
            n.bias + SUM(e.weight * tx.value)
        ) AS value,
        e.dst AS id
    FROM tx
    -- TODO:
    -- Might it be worth it to first filter the query on node IDs of the
    -- subsequent layer only? Cfr https://openproceedings.org/2023/conf/edbt/paper-7.pdf
    JOIN edge e ON tx.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.bias, tx.input_set_id
),
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
),
-- Softmax
max_value AS (
    SELECT
        input_set_id,
        MAX(value) AS max_val
    FROM t_out
    GROUP BY input_set_id
),
log_sum_exp AS (
    SELECT
        t.input_set_id,
        LN(SUM(EXP(t.value - m.max_val))) AS log_sum_exp
    FROM t_out t
    JOIN max_value m ON t.input_set_id = m.input_set_id
    GROUP BY t.input_set_id
)
SELECT
    t.input_set_id,
    t.id,
    t.value - m.max_val - lse.log_sum_exp AS log_softmax
FROM t_out t
JOIN max_value m ON t.input_set_id = m.input_set_id
JOIN log_sum_exp lse ON t.input_set_id = lse.input_set_id
ORDER BY t.input_set_id, t.id
