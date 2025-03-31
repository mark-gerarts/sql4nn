WITH input_node AS (
    SELECT id FROM node WHERE layer = 0
),
input_value AS (
    -- "1" here is a hardcoded input value.
    SELECT SUM(e.value * 1) AS weight_times_value, e.dst
    FROM edge e
    JOIN input_node i ON i.id = e.src
    GROUP BY e.dst
),
t1 AS (
    SELECT
        MAX(
            (
                SELECT weight_times_value
                FROM input_value i
                WHERE i.dst = n.id
            )
            + n.value,
            0
        ) AS t1_value,
        n.id
    FROM node n
),
t1_sums AS (
    SELECT
        SUM(
            e.value *
            (
                SELECT t1_value
                FROM t1
                WHERE t1.id = e.src
            )
        )
    FROM edge e
    WHERE e.dst = n.id
)

SELECT
    n.value +
    (SELECT * FROM t1_sums)
FROM node n
WHERE n.layer = 2 -- output layer (only 1)
