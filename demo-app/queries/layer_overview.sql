WITH RECURSIVE input_nodes AS (
    SELECT
        id,
        ROW_NUMBER() OVER (ORDER BY id) AS input_node_idx
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
nodes_with_layer AS (
    SELECT
        id,
        0 as layer
    FROM input_nodes

    UNION ALL

    SELECT
        n.id,
        nodes_with_layer.layer + 1 as layer
    FROM edge e
    JOIN nodes_with_layer ON nodes_with_layer.id = e.src
    JOIN node n ON e.dst = n.id
    GROUP BY e.dst, n.id, layer
)
SELECT layer, COUNT(id) AS number_of_nodes
FROM nodes_with_layer
GROUP BY layer
ORDER BY layer;
