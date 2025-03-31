import os
import shutil
import duckdb
import itertools
import pandas as pd


con = duckdb.connect()

EXPORT_DIR = "dbs/network.db"


def _initialize_database():
    if os.path.isdir(EXPORT_DIR):
        shutil.rmtree(EXPORT_DIR)

    con.execute("DROP TABLE IF EXISTS edge")
    con.execute("DROP TABLE IF EXISTS node")
    con.execute("DROP SEQUENCE IF EXISTS seq_node")
    con.execute("DROP TABLE IF EXISTS input")

    con.execute("CREATE SEQUENCE seq_node START 1")
    con.execute(
        """
        CREATE TABLE node(
            id INTEGER PRIMARY KEY DEFAULT NEXTVAL('seq_node'),
            bias REAL,
            name TEXT
        )"""
    )
    # Foreign keys are omitted for performance.
    con.execute(
        """
        CREATE TABLE edge(
            src INTEGER,
            dst INTEGER,
            weight REAL
        )"""
    )

    con.execute(
        """
        CREATE TABLE input(
            input_set_id INTEGER,
            input_node_idx INTEGER,
            input_value REAL
        )"""
    )


def reconnect():
    global con

    try:
        con.close()
    except Exception:
        pass

    con = duckdb.connect()


def load_pytorch_model_into_db(model):
    return load_state_dict_into_db(model.state_dict())


def batch_insert(generator, table, batch_size=8_000_000):
    """
    Inserts data in batches into duckdb, to find a middle ground between
    performance and memory consumption. A batch size of 10M consumes ~4GB RAM.
    """
    while True:
        chunk = list(itertools.islice(generator, batch_size))
        if not chunk:
            break

        df = pd.DataFrame(chunk)
        con.execute(f"INSERT INTO {table} SELECT * FROM df")


def load_state_dict_into_db(state_dict):
    _initialize_database()

    # We keep the node IDs per layer in memory so we can insert the edges later on.
    node_ids = [[]]

    def nodes():
        # First, insert the input nodes.

        # Retrieves the input x weights matrix
        input_weights = list(state_dict.items())[0][1].tolist()
        num_input_nodes = len(input_weights[0])

        id = 0
        for i in range(0, num_input_nodes):
            id += 1
            yield [id, 0, f"input.{i}"]
            node_ids[0].append(id)

        layer = 0
        # In the first pass, insert all nodes with their biases
        for name, values in state_dict.items():
            # state_dict alternates between weight and bias tensors.
            if not "bias" in name:
                continue

            node_ids.append([])

            layer += 1
            for i, bias in enumerate(values.tolist()):
                id += 1
                yield [id, bias, f"{name}.{i}"]
                node_ids[layer].append(id)

    def edges():
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
                    yield [from_node, to_node, weight]

            layer += 1

    batch_insert(nodes(), "node")
    batch_insert(edges(), "edge")
    con.execute(f"EXPORT DATABASE '{EXPORT_DIR}'")


def print_db_contents():
    display(con.sql("SELECT name, bias FROM node"))
    display(
        con.sql(
            """
        SELECT s.name as src, d.name as dst, e.weight
        FROM edge e
        JOIN node s ON e.src = s.id
        JOIN node d ON e.dst = d.id
        """
        )
    )
