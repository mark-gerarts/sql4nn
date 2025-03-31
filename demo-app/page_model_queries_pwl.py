import streamlit as st
import settings
from model import ReLUFNN
import torch
import duckdb as db
import math
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches


@st.cache_resource
def get_model():
    model = ReLUFNN(input_size=1, output_size=1, hidden_size=1000, num_hidden_layers=1)
    model.load_state_dict(torch.load(settings.PWL_MODEL_PATH, weights_only=True))
    model.eval()

    return model


@st.cache_data
def get_query():
    with open(settings.PWL_QUERY_PATH) as file:
        query = file.read()

    return query


@st.cache_resource
def connect_to_db():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_PWL}'")

    return con


model = get_model()
con = connect_to_db()
query = get_query()


st.title("Piecewise Linear Functions")

with st.expander("Intro", expanded=True):
    st.markdown(
        """
        ReLU-FNNs output piecewise linear functions (PWLs) that can
        approximate any function they are trained on, given enough hidden neurons.
        For a ReLU-FNN with only one hidden layer, each hidden node contributes at
        most one unique breakpoint of the PWL.

        We have created a query that transforms the neural network in its
        geometric representations (i.e. a list of its breakpoints and slopes).
        This query only works for ReLU-FNNs with a single hidden layer, but the
        same can be done for any ReLU-FNN.
    """
    )

x_train = np.linspace(-2 * math.pi, 2 * math.pi, 10000)
y_train = np.array([math.sin(x) for x in x_train])

with torch.no_grad():
    predicted = (
        model(torch.tensor(x_train, dtype=torch.float32).unsqueeze(1)).detach().numpy()
    )

with st.expander("The model"):
    st.markdown(
        """
        We have trained a model to learn the function $f(x) = sin(x)$ on
        [$-2\pi..2\pi$]:
    """
    )

    fig, ax = plt.subplots()
    ax.plot(x_train, y_train, "b", label="sin(x)")
    ax.plot(x_train, predicted, "r", label="Neural Network approximation")
    ax.legend()
    st.pyplot(fig)

with st.expander("The query"):
    st.markdown(
        "We have constructed the following query, which extracts the breakpoints and the slopes to the next breakpoint. This can be used to reconstruct the PWL."
    )

    st.code(query, language="sql")


with st.expander("Running the query"):
    st.markdown(
        """
    The query returns the (x,y) coordinate of each breakpoint, together with the
    slope towards the next breakpoint.
    """
    )

    st.code(con.sql(query))


with st.expander("Visualizing the result"):
    st.markdown(
        """
    If we plot the results, we can reconstruct the neural network's output.
    """
    )

    result_df = con.execute(query).df()

    x_values = result_df["x"].values
    y_values = result_df["y"].values
    slopes = result_df["slope"].values

    x_plot = [x_values[0]]
    y_plot = [y_values[0]]

    for i in range(len(slopes) - 1):
        next_x = x_values[i + 1]
        delta_x = next_x - x_plot[-1]
        delta_y = slopes[i] * delta_x
        y_next = y_plot[-1] + delta_y

        x_plot.append(next_x)
        y_plot.append(y_next)

    fig, ax = plt.subplots()
    ax.plot(
        x_plot, y_plot, marker="o", linestyle="-", color="b", label="Reconstruction"
    )
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_title("Reconstruction from breakpoints and slopes")
    ax.grid(True)
    ax.set_xlim(-2 * math.pi, 2 * math.pi)
    ax.set_ylim(-1.5, 1.5)
    st.pyplot(fig)


with st.expander("Integral query"):
    st.markdown(
        """
    With the output of this query, it is also trivial to calculate the integral
    of the neural network's output function. We only need to adapt the last part
    of the query:
    """
    )

    st.code(
        """
    points_and_slopes_with_next AS (
    SELECT
        x,
        y,
        slope,
        LEAD(x) OVER (ORDER BY x) AS next_x
    FROM points_and_slopes
)
SELECT
    SUM(((y + (y + slope * (next_x - x))) / 2) * (next_x - x)) AS integral
FROM
    points_and_slopes_with_next
WHERE next_x IS NOT NULL AND x >= ? and x <= ?;
    """,
        language="sql",
    )


with st.expander("Integral"):
    (start, end) = st.slider(
        "Calculate integral between these x-values:",
        -2 * math.pi,
        2 * math.pi,
        (-math.pi, math.pi),
    )

    fig, ax = plt.subplots()
    ax.plot(
        x_plot, y_plot, marker="o", linestyle="-", color="b", label="Reconstruction"
    )
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_title("Reconstruction from breakpoints and slopes")
    ax.grid(True)
    rect = patches.Rectangle(
        (start, -1.1), (end - start), 2.2, linewidth=1, edgecolor="r", facecolor="none"
    )
    ax.add_patch(rect)
    ax.set_xlim(-2 * math.pi - 0.1, 2 * math.pi + 0.1)
    ax.set_ylim(-1.5, 1.5)
    st.pyplot(fig)

    with open("queries/integral.sql") as file:
        integral_query = file.read()

    st.text("Query result:")
    st.dataframe(con.execute(integral_query, [start, end]).df())

    st.markdown(
        """
        The query result is slightly off. For example, between $-\pi$ and $\pi$
        we would expect the integral to be 0. This difference is expected
        because the network is only an approximation of $sin(x)$.
"""
    )
