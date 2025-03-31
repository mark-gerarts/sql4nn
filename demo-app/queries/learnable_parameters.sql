WITH input_nodes AS (
    SELECT id
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
num_biases AS (
    SELECT COUNT(bias) AS num_biases
    FROM node
    WHERE id NOT IN (SELECT id FROM input_nodes)

),
num_weights AS (
    SELECT COUNT(weight) AS num_weights FROM edge
)
SELECT
    (SELECT num_biases FROM num_biases)
    + (SELECT num_weights FROM num_weights)
AS learnable_parameters
