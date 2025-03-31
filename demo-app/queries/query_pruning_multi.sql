WITH num_input_nodes AS (
  SELECT model_id, COUNT(id) AS num_input_nodes
  FROM node
  WHERE id NOT IN (SELECT dst FROM edge)
  GROUP BY model_id
),
num_output_nodes AS (
  SELECT model_id, COUNT(id) AS num_output_nodes
  FROM node
  WHERE id NOT IN (SELECT src FROM edge)
  GROUP BY model_id
),
num_total_nodes AS (
  SELECT model_id, COUNT(id) AS num_nodes
  FROM node
  GROUP BY model_id
),
num_hidden_nodes AS (
  SELECT
    t.model_id,
    t.num_nodes - i.num_input_nodes - o.num_output_nodes AS num_hidden_nodes
  FROM num_total_nodes t
  JOIN num_input_nodes i ON i.model_id = t.model_id
  JOIN num_output_nodes o ON o.model_id = t.model_id
  GROUP BY t.model_id, t.num_nodes, i.num_input_nodes, o.num_output_nodes
),
prunable_nodes AS (
  SELECT
    model_id,
    src AS id_to_prune
  FROM edge
  GROUP BY model_id, src
  HAVING MAX(ABS(weight)) <= 0.04
),
num_prunable_nodes AS (
  SELECT
    m.id AS model_id,
    m.name,
    COUNT(p.id_to_prune) AS num_prunable_nodes
  FROM model m
  JOIN prunable_nodes p ON p.model_id = m.id
  GROUP BY m.id, m.name
  ORDER BY m.id
)
SELECT
  m.id,
  m.name,
  h.num_hidden_nodes,
  p.num_prunable_nodes,
  ROUND(p.num_prunable_nodes * 100 / h.num_hidden_nodes, 2) AS percentage_prunable
FROM model m
JOIN num_hidden_nodes h ON h.model_id = m.id
JOIN num_prunable_nodes p ON p.model_id = m.id
ORDER BY m.id;
