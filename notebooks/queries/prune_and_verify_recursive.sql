CREATE OR REPLACE TEMP MACRO prune_and_verify(number_of_nodes_to_prune) AS TABLE
WITH original_input_node_ids AS (
    SELECT id
    FROM node
    WHERE id NOT IN (SELECT dst FROM edge)
),
original_output_node_ids AS (
    SELECT id
    FROM node
    WHERE id NOT IN (SELECT src FROM edge)
),
node_ids_to_keep AS (
    SELECT id
    FROM
    (
        SELECT
            src AS id,
            ROW_NUMBER() OVER (ORDER BY MAX(ABS(weight))) AS rownum
        FROM edge
        -- Exclude input nodes from pruning
        WHERE src NOT IN (SELECT id FROM original_input_node_ids)
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
    OR id IN (SELECT id FROM original_input_node_ids)
    OR id IN (SELECT id FROM original_output_node_ids)
),
input_nodes AS (
    SELECT id
    FROM nodes_to_keep
    WHERE id NOT IN (SELECT dst FROM edge)
),
output_nodes AS (
    SELECT id
    FROM nodes_to_keep
    WHERE id NOT IN (SELECT src FROM edge)
),
hidden_nodes AS (
    SELECT id
    FROM nodes_to_keep
    WHERE id NOT IN
    (
        SELECT * FROM input_nodes
        UNION
        SELECT * FROM output_nodes
    )
),
breakpoint_values AS (
    SELECT
        DISTINCT (-n.bias) / e.weight AS break_x,
    FROM nodes_to_keep n
    JOIN edge e ON e.dst = n.id
    JOIN hidden_nodes h ON h.id = n.id
    WHERE e.weight <> 0
    GROUP BY break_x, n.id
    ORDER BY break_x
),
breakpoints_unordered AS (
    (SELECT break_x FROM breakpoint_values)
    UNION
    (SELECT MIN(break_x) - 1.0 AS break_x FROM breakpoint_values)
    UNION
    (SELECT MAX(break_x) + 1.0 AS break_x FROM breakpoint_values)
),
breakpoints AS (
    SELECT
        break_x,
        ROW_NUMBER() OVER (ORDER BY break_x) AS row_number
    FROM breakpoints_unordered
),
input_values AS (
    SELECT break_x AS input_value FROM breakpoints
),
t1 AS (
    SELECT
        v.input_value,
        GREATEST(
            0,
            n.bias + SUM(e.weight * v.input_value)
        ) AS t1,
        e.dst AS id
    FROM edge e
    JOIN input_nodes i ON i.id = e.src
    JOIN nodes_to_keep n ON e.dst = n.id
    CROSS JOIN input_values v
    GROUP BY v.input_value, e.dst, n.bias
),
output_values AS (
    SELECT
        t1.input_value,
        n.bias + SUM(e.weight * t1.t1) AS output_value,
        e.dst AS output_node_id
    FROM edge e
    JOIN t1 ON t1.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY t1.input_value, e.dst, n.bias
),
breakpoint_pairs AS (
    SELECT
        u1.break_x AS u1_break_x,
        u2.break_x AS u2_break_x,
        e1.output_value AS u1_break_y,
        e2.output_value AS u2_break_y
    FROM breakpoints u1
    JOIN breakpoints u2 ON u1.row_number = u2.row_number - 1
    JOIN output_values e1 ON u1.break_x = e1.input_value
    JOIN output_values e2 ON u2.break_x = e2.input_value
),
points_and_slopes AS (
    SELECT
        u1_break_x AS x,
        u1_break_y AS y,
        (u2_break_y - u1_break_y) / (u2_break_x - u1_break_x) AS slope
    FROM breakpoint_pairs
),
all_points AS (
    SELECT x, y FROM points_and_slopes

    UNION ALL

    -- Left part of range
    SELECT -6, (-6 - x) * slope + y AS y
    FROM points_and_slopes
    WHERE x = (SELECT MAX(x) FROM points_and_slopes WHERE x < -6)

    UNION ALL

    -- Right part of range
    SELECT 6, (6 - x) * slope + y AS y
    FROM points_and_slopes
    WHERE x = (SELECT MIN(x) FROM points_and_slopes WHERE x > 6)
)
SELECT NOT EXISTS (
    SELECT 1
    FROM points_and_slopes
    -- Closest breakpoint left of minimum input value
    WHERE x > (SELECT MAX(x)
               FROM points_and_slopes
               WHERE x < -1)
    AND x < 1
    AND slope <= 0
) AS monotonic;

WITH RECURSIVE pruned_models AS (
    SELECT
        0 AS number_of_pruned_nodes,
        (SELECT monotonic FROM prune_and_verify(number_of_pruned_nodes)) AS monotonic

    UNION ALL

    SELECT
        number_of_pruned_nodes + 100,
        (SELECT monotonic FROM prune_and_verify(number_of_pruned_nodes)) AS monotonic
    FROM pruned_models
    WHERE monotonic
)
SELECT * FROM pruned_models;
