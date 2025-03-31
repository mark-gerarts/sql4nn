WITH input_node AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
output_node AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (SELECT src FROM edge)
),
hidden_nodes AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (
        SELECT * FROM input_node
        UNION
        SELECT * FROM output_node
    )
),
break_x AS (
    SELECT
        n.id,
        (-n.bias) / e.weight AS break_x, -- -b(u) / w(in1, u)
        ROW_NUMBER() OVER (ORDER BY (-n.bias) / e.weight) AS row_number
    FROM node n
    JOIN edge e ON e.dst = n.id
    JOIN input_node i ON e.src = i.id
    JOIN hidden_nodes h ON h.id = n.id
    WHERE e.weight <> 0
    ORDER BY break_x
),
-- The possible inputs we'll evaluate on for this query.
vals AS (
    SELECT break_x AS val FROM break_x
),
weight_times_input_value AS (
    SELECT
        SUM(e.weight * v.val) AS weight_times_value,
        e.dst AS id,
        v.val AS input_value
    FROM edge e
    JOIN input_node i ON i.id = e.src
    CROSS JOIN vals v
    GROUP BY e.dst, v.val
),
t1 AS (
    SELECT
        GREATEST(weight_times_value + n.bias, 0) AS t1_value,
        input_value,
        n.id
    FROM node n
    JOIN weight_times_input_value i ON i.id = n.id
),
t1_sums AS (
    SELECT
        SUM(
            e.weight *
            t1.t1_value
        ) AS sum,
        t1.input_value,
        e.dst
    FROM edge e
    JOIN t1 ON t1.id = e.src
    GROUP BY t1.input_value, e.dst
),
eval AS (
    SELECT
        t.input_value,
        n.bias + t.sum AS final_output
    FROM node n
    JOIN t1_sums t ON t.dst = n.id
    JOIN output_node o ON o.id = n.id
),
breaks AS (
    SELECT
        u1.break_x AS u1_break_x,
        u2.break_x AS u2_break_x,
        e1.final_output AS u1_break_y,
        e2.final_output AS u2_break_y
    FROM break_x u1
    JOIN break_x u2 ON u1.row_number = u2.row_number - 1
    JOIN eval e1 ON u1.break_x = e1.input_value
    JOIN eval e2 ON u2.break_x = e2.input_value
),
areas AS (
    SELECT
        0.5 * (u1_break_y + u2_break_y) * (u2_break_x - u1_break_x) AS area
    FROM breaks
)

SELECT SUM(area) AS integral FROM areas
