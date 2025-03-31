import streamlit as st
import settings
import numpy as np
import pandas as pd
import duckdb as db


@st.cache_resource
def connect_to_db_multiple_epochs():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_MULTIPLE_EPOCHS}'")

    return con


@st.cache_resource
def connect_to_db_multiple_sizes():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_MULTIPLE_SIZES}'")

    return con


@st.cache_data
def get_eval_query():
    with open(settings.EVAL_MULTI_QUERY_PATH) as file:
        return file.read()


# We do the logmax in python for convenience.
def log_softmax(values):
    max_val = np.max(values)
    log_sum_exp = np.log(np.sum(np.exp(values - max_val)))
    return np.log(np.exp(values - max_val)) - log_sum_exp


def eval_image_sql(con, image):
    con.execute("TRUNCATE input")

    rows = []
    for i, pixel in enumerate(image.flatten()):
        rows.append([0, i + 1, pixel.item()])

    df = pd.DataFrame(rows)
    con.execute("INSERT INTO input SELECT * FROM df")

    eval_query = get_eval_query()
    results_df = con.sql(eval_query).df()

    # predicted_digit = results_df["log_softmax"].idxmax()
    predicted_digit = -1

    results_df["log_softmax"] = results_df.groupby("name")["output_value"].transform(
        log_softmax
    )

    predictions = []
    for df in [group for _, group in results_df.groupby("name")]:
        df = df.reset_index()
        probabilities = np.exp(df["log_softmax"])
        confidence = probabilities.max()

        predicted_digit = df["log_softmax"].idxmax()
        model_name = df.iloc[0]["name"]
        model_id = df.iloc[0]["id"]
        predictions.append([model_id, model_name, predicted_digit, confidence])

    predictions = pd.DataFrame(
        predictions, columns=["Model ID", "Model name", "Prediction", "Confidence"]
    ).sort_values(by="Model ID")

    return results_df, predictions


def pivot(sql_prediction):
    df = sql_prediction.sort_values(by="Model ID")
    reshaped_df = df.melt(
        id_vars=["Model ID", "Model name"],
        value_vars=["Prediction", "Confidence"],
        var_name="Metric",
        value_name="Value",
    )
    final_df = reshaped_df.pivot(
        index="Metric", columns="Model ID", values="Value"
    )
    final_df.columns = df.sort_values("Model ID")["Model name"].values
    final_df.columns.name = None

    return final_df
