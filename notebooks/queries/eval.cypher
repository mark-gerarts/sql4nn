WITH [5, 20] AS inputValues

// Match input nodes.
MATCH (inputNode:Node)
WHERE NOT (:Node)-[:EDGE]->(inputNode)

// Connect the input nodes with an index (cfr ROW_NUMBER) so we
// can match them with input values.
WITH inputValues, collect(inputNode) AS inputNodes
UNWIND range(0, size(inputValues) - 1) AS idx
WITH inputValues[idx] AS inputValue, inputNodes[idx] AS inputNode

// Calculate the first layer.
MATCH (inputNode:Node)-[e:EDGE]->(l1:Node)
WITH
    l1,
    CASE SUM(e.weight * inputValue)
    WHEN > 0 THEN SUM(e.weight * inputValue) + l1.bias
    ELSE 0
    END AS value

// If there are more layers, we need to manually add them here.
// Cypher does not allow for recursive constructions (at least
// not without extensions).

// Finally, connect to the output layer.
MATCH (l1:Node)-[e:EDGE]->(l2:Node)
WITH
    l2,
    SUM(e.weight * value) + l2.bias AS value

RETURN l2, value
ORDER BY elementId(l2)
