import pandas as pd
import sqlite3

con = sqlite3.connect("dbs/network.sqlite.db")


def load_pytorch_model_into_db(model):
    con.execute("DROP TABLE IF EXISTS edge")
    con.execute("DROP TABLE IF EXISTS node")

    con.execute(
        """
        CREATE TABLE node(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bias REAL,
            name TEXT
        )"""
    )
    con.execute(
        """
        CREATE TABLE edge(
            src INTEGER,
            dst INTEGER,
            weight REAL,
            FOREIGN KEY (src) REFERENCES node(id),
            FOREIGN KEY (dst) REFERENCES node(id)
        )"""
    )

    state_dict = model.state_dict()

    # First, insert the input nodes.

    # Retrieves the input x weights matrix
    input_weights = list(state_dict.items())[0][1].tolist()
    num_input_nodes = len(input_weights[0])

    # We keep the node IDs per layer in memory so we can insert the edges later on.
    node_ids = [[]]

    for i in range(0, num_input_nodes):
        result = con.execute(
            "INSERT INTO node (bias, name) VALUES (0, $name) RETURNING (id)",
            {"name": f"input.{i}"},
        )

        (inserted_id,) = result.fetchone()
        node_ids[0].append(inserted_id)

    layer = 0
    # In the first pass, insert all nodes with their biases
    for name, values in state_dict.items():
        # state_dict alternates between weight and bias tensors.
        if not "bias" in name:
            continue

        node_ids.append([])

        layer += 1
        for i, bias in enumerate(values.tolist()):
            result = con.execute(
                "INSERT INTO node (bias, name) VALUES ($bias, $name) RETURNING (id)",
                {"bias": bias, "name": f"{name}.{i}"},
            )

            (inserted_id,) = result.fetchone()
            node_ids[layer].append(inserted_id)

    # In the second pass, insert all edges and their weights. This assumes a fully
    # connected network.
    layer = 0
    for name, values in state_dict.items():
        # state_dict alternates between weight and bias tensors.
        if not "weight" in name:
            continue

        # Each weight tensor has a list for each node in the next layer. The
        # elements of this list correspond to the nodes of the current layer.
        weight_tensor = values.tolist()
        for from_index, from_node in enumerate(node_ids[layer]):
            for to_index, to_node in enumerate(node_ids[layer + 1]):
                weight = weight_tensor[to_index][from_index]

                con.execute(
                    """
                    INSERT INTO edge (src, dst, weight)
                    VALUES
                    (
                        $from_id,
                        $to_id,
                        $weight
                    )
                    """,
                    {
                        "from_id": from_node,
                        "to_id": to_node,
                        "weight": weight,
                    },
                )

        layer += 1

    con.commit()


def print_db_contents():
    df = pd.read_sql_query("SELECT name, bias FROM node", con)
    print(df)

    df = pd.read_sql_query(
        """
        SELECT s.name as src, d.name as dst, e.weight
        FROM edge e
        JOIN node s ON e.src = s.id
        JOIN node d ON e.dst = d.id
        """,
        con,
    )
    print(df)
