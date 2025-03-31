import streamlit as st
import settings
import duckdb as db


query_layers_single = """WITH RECURSIVE input_nodes AS (
    SELECT id
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
"""

query_layers_multi = """WITH RECURSIVE input_nodes AS (
    SELECT
        model_id,
        id
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
nodes_with_layer AS (
    SELECT
        model_id,
        id,
        0 as layer
    FROM input_nodes

    UNION ALL

    SELECT
        n.model_id,
        n.id,
        nodes_with_layer.layer + 1 as layer
    FROM edge e
    JOIN nodes_with_layer
      ON nodes_with_layer.id = e.src
      AND nodes_with_layer.model_id = e.model_id
    JOIN node n ON e.dst = n.id
    GROUP BY n.model_id, e.dst, n.id, layer
)
SELECT
  m.id,
  m.name,
  n.layer,
  COUNT(n.id) AS number_of_nodes
FROM model m
JOIN nodes_with_layer n ON n.model_id = m.id
GROUP BY m.id, n.layer, m.name
ORDER BY m.id, n.layer;
"""

query_parameters_single = """WITH input_nodes AS (
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
AS learnable_parameters"""

query_parameters_multi = """WITH input_nodes AS (
    SELECT
      model_id,
      id
    FROM node
    WHERE id NOT IN
    (SELECT dst FROM edge)
),
num_biases AS (
    SELECT model_id, COUNT(bias) AS num_biases
    FROM node
    WHERE id NOT IN (SELECT id FROM input_nodes)
    GROUP BY model_id
),
num_weights AS (
    SELECT model_id, COUNT(weight) AS num_weights
    FROM edge
    GROUP BY model_id
)

SELECT
  m.id,
  m.name,
  nb.num_biases + nw.num_weights
FROM model m
JOIN num_biases nb ON m.id = nb.model_id
JOIN num_weights nw ON m.id = nw.model_id
"""

query_pruning_single = """
SELECT src
FROM edge
GROUP BY src
HAVING MAX(ABS(weight)) <= 0.01
"""

query_pruning_multi = """
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
  HAVING MAX(ABS(weight)) <= ?
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
ORDER BY m.id
"""


@st.cache_resource
def connect_to_db_multi():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_MULTIPLE_SIZES}'")

    return con


@st.cache_resource
def connect_to_db_single():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_SINGLE}'")

    return con


con_single = connect_to_db_single()
con_multi = connect_to_db_multi()


st.title("Model queries")

with st.expander("Intro", expanded=True):
    st.markdown(
        """
  Just being able to query the structure of a model already gives us useful
  information. We'll look at two examples: describing the complexity of a
  network and finding nodes that can likely be pruned. We'll then run them
  against multiple models.
  """
    )


with st.expander("Model complexity"):
    st.markdown(
        f"""
    A first basic set of queries we can perform is to describe the model
    complexity. Some questions are:

    - How many learnable parameters does the model have?
    - How many layers does the model have, with how many nodes each?

    The queries are as follows; for the learnable parameters:
    """
    )

    st.code(query_parameters_single, language="sql")

    st.text("For the model layer information:")
    st.code(query_layers_single, language="sql")

    st.text("Running these queries agains the MNIST CNN results in the following:")

    st.dataframe(con_single.execute(query_parameters_single).df())
    st.dataframe(con_single.execute(query_layers_single).df())


with st.expander("Pruning"):
    st.markdown(
        """
    Another interesting query revolves around model pruning: determining which
    nodes contribute little to the network and can be removed, without loss of
    accuracy.

    One way to do this is to find nodes with low outgoing weights. We can do
    this with the following query:
    """
    )

    st.code(query_pruning_single, language="sql")
    pruning_result = con_single.execute(query_pruning_single).df()
    st.dataframe(pruning_result)

    st.markdown(
        """
    These are the outgoing weights for these nodes (limited to 100 weights):
    """
    )

    query = """
    SELECT src, weight
    FROM edge
    WHERE src IN ?
    """

    src_ids = pruning_result["src"].tolist()
    st.dataframe(con_single.execute(query, [src_ids]).df())

    st.markdown("For reference, this is the average weight:")

    avg_query = """
    SELECT AVG(ABS(weight)) AS avg_weight FROM edge
    """

    st.code(avg_query, language="sql")
    st.dataframe(con_single.execute(avg_query).df())


with st.expander("Multiple models"):
    st.markdown(
        """
    We can also use these queries to compare multiple models. In this example,
    we'll use a set of MNIST classifiers with the same structure, but with
    a different number of hidden units per layer.

    We can compare the number of hidden units per layer:
    """
    )

    st.dataframe(con_multi.execute(query_layers_multi).df())

    st.text("The number of learnable parameters:")
    st.dataframe(con_multi.execute(query_parameters_multi).df())

    st.text("And the number of prunable nodes:")

    value = st.slider("Max weight", min_value=0.01, max_value=0.05, step=0.01)
    st.dataframe(con_multi.execute(query_pruning_multi, [value]).df())
