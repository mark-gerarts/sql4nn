import streamlit as st
from torchvision import datasets, transforms
import matplotlib.pyplot as plt
from io import BytesIO
import image
import pandas as pd
import duckdb as db
import settings
import random


@st.cache_resource
def connect_to_db():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_SINGLE}'")

    return con


def random_image(dataset):
    image, label = dataset[random.randint(0, len(dataset) - 1)]

    return image, label


def display_image(img):
    image_np = img.squeeze().numpy()

    fig, ax = plt.subplots(figsize=(1, 1))
    ax.imshow(image_np, cmap="gray")
    ax.axis("off")

    buf = BytesIO()
    fig.savefig(buf, format="png")
    st.image(buf)


eval_query = image.get_eval_query()
con = connect_to_db()
model = image.get_model()


st.title("Model evaluation")


dataset = datasets.MNIST("../data", train=False, transform=transforms.ToTensor())

with st.expander("ReLU-FNNs", expanded=True):
    st.markdown(
        """
    Our work focuses on *ReLU-FNNs*: fully connected feed-forward neural networks with
    ReLU activation functions. These networks can be represented by a simple
    directed graph. Each edge has a weight value, and each node has a bias value.
    """
    )

    st.image(
        "assets/Simple ReLUFNN.png",
        caption="ReLU-FNN",
    )

with st.expander("Database schema"):
    st.markdown(
        """
    Such a network can be described using the following database schema:
    """
    )

    st.image("assets/db_diagram.png", caption="Database schema")

    st.markdown(
        """
    The node's *name* property is purely informative. The *input* table is used
    to store the model's input when it is evaluated.
    """
    )

with st.expander("MNIST classifier"):
    st.markdown(
        """
    Let's take the MNIST model from the [PyTorch
    examples](https://github.com/pytorch/examples/tree/main/mnist). It takes
    inputs of handwritten digits, like this...
    """
    )

    dataset = datasets.MNIST("../data", train=False, transform=transforms.ToTensor())
    img, label = dataset[1]
    display_image(img)

    st.markdown(
        """
    ...and classifies them. The classifier is actually a convolutional neural
    network, which we translated to a ReLU-FNN and stored in a database - DuckDB
    in this case.

    To make things more clear, let's see how the network is stored in the
    database:
    """
    )

    output = "SELECT * FROM node ORDER BY RANDOM() LIMIT 5;\n"
    output += str(con.sql("SELECT * FROM node ORDER BY RANDOM() LIMIT 5"))
    output += "SELECT * FROM edge ORDER BY RANDOM() LIMIT 5;\n"
    output += str(con.sql("SELECT * FROM edge ORDER BY RANDOM() LIMIT 5"))
    st.code(output)

    """
    To show that the network is nontrivial, let's query the nodes and edges:
    """

    st.code(
        con.sql(
            """
        SELECT
        (SELECT COUNT(*) FROM node) AS num_nodes,
        (SELECT COUNT(*) FROM edge) AS num_edges
    """
        )
    )


with st.expander("The eval query"):
    st.markdown(
        """
    The `eval`-query calculates the value of the output nodes for one or more
    inputs. Specific for this example, we also implemented a log softmax at the
    end.
    """
    )

    st.code(eval_query, language="sql")


def eval_random_image():
    img, _ = random_image(dataset)
    result_df, prediction = image.eval_image_sql(con, img.unsqueeze(0))

    col1, col2 = st.columns([1, 4])
    with col1:
        display_image(img)
        st.text(f"Prediction: {prediction}")

    with col2:
        st.dataframe(result_df["log_softmax"].T)


def eval_multiple_images(images):
    try:
        con.execute("BEGIN TRANSACTION")
    except db.TransactionException:
        con.execute("ROLLBACK")
        con.execute("BEGIN TRANSACTION")

    con.execute("TRUNCATE input")

    rows = []
    for input_set_id, img in enumerate(images):
        for i, pixel in enumerate(img.flatten()):
            rows.append([input_set_id, i + 1, pixel.item()])

    df = pd.DataFrame(rows)
    con.execute("INSERT INTO input SELECT * FROM df")

    eval_query = image.get_eval_query()
    results_df = con.sql(eval_query).df()
    con.execute("COMMIT")

    return results_df


with st.expander("Running the query"):
    st.markdown(
        """
    We can run the query on a single image:
    """
    )

    eval_random_image()
    st.button("Randomize")


with st.expander("Multiple inputs"):
    st.markdown(
        """
    We can also evaluate multiple input images at once. Image we have scanned
    a zipcode as separate digits and we want to parse it.
    """
    )

    images = [random_image(dataset) for _ in range(0, 5)]
    fig, axes = plt.subplots(1, 5, figsize=(5, 1))

    for ax, (img, label) in zip(axes, images):
        image_np = img.squeeze().numpy()
        ax.imshow(image_np, cmap="gray")
        ax.axis("off")
        ax.set_adjustable("box")

    fig.subplots_adjust(wspace=0, hspace=0)

    buf = BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight", pad_inches=0)
    st.image(buf)

    imgs = [x[0] for x in images]
    results = eval_multiple_images(imgs)

    st.markdown(
        """
    We fetch the results for all images in one query, and use it to parse the
    zipcode:
    """
    )

    st.dataframe(results)

    results["prediction"] = results.groupby("input_set_id").cumcount()

    max_rows = results.loc[results.groupby("input_set_id")["log_softmax"].idxmax()]
    predictions = max_rows[["input_set_id", "prediction"]]["prediction"].tolist()

    st.text(f"The zipcode is {''.join(map(str, predictions))}")

    st.button("Randomize", key="rand2")
